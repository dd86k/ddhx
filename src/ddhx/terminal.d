/// Terminal/console handling.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module ddhx.terminal;

//TODO: Make stdout stream to avoid disrupting screen before app.

///
private extern (C) int getchar();

private import std.stdio;
private import core.stdc.stdlib : system;

version (Windows) {
	private import core.sys.windows.windows;
	private import std.windows.syserror : WindowsException;
	private enum ALT_PRESSED =  RIGHT_ALT_PRESSED  | LEFT_ALT_PRESSED;
	private enum CTRL_PRESSED = RIGHT_CTRL_PRESSED | LEFT_CTRL_PRESSED;
	private enum DEFAULT_COLOR =
		FOREGROUND_BLUE | FOREGROUND_GREEN | FOREGROUND_RED;
	private enum CP_UTF16LE = 1200;
	private enum CP_UTF16BE = 1201;
	private enum CP_UTF7 = 65000;
	private enum CP_UTF8 = 65001;
	private __gshared HANDLE hIn, hOut;
	private __gshared USHORT defaultColor = DEFAULT_COLOR;
	private __gshared DWORD oldCP;
}
version (Posix) {
	private import core.sys.posix.sys.stat;
	private import core.sys.posix.sys.ioctl;
	private import core.sys.posix.unistd;
	private import core.sys.posix.termios;
	version (CRuntime_Musl) {
		alias uint tcflag_t;
		alias uint speed_t;
		alias char cc_t;
		private enum TCSANOW	= 0;
		private enum NCCS	= 32;
		private enum ICANON	= 2;
		private enum ECHO	= 10;
		private enum TIOCGWINSZ	= 0x5413;
		private struct termios {
			tcflag_t c_iflag;
			tcflag_t c_oflag;
			tcflag_t c_cflag;
			tcflag_t c_lflag;
			cc_t c_line;
			cc_t[NCCS] c_cc;
			speed_t __c_ispeed;
			speed_t __c_ospeed;
		}
		private struct winsize {
			ushort ws_row;
			ushort ws_col;
			ushort ws_xpixel;
			ushort ws_ypixel;
		}
		private extern (C) int tcgetattr(int fd, termios *termios_p);
		private extern (C) int tcsetattr(int fd, int a, termios *termios_p);
		private extern (C) int ioctl(int fd, ulong request, ...);
	}
	private enum TERM_ATTR = ~(ICANON | ECHO);
	private __gshared termios old_tio, new_tio;
}

/// Initiate ddcon
void terminalInit() {
	import std.format : format;
	version (Windows) {
		hOut = GetStdHandle(STD_OUTPUT_HANDLE);
		hIn  = GetStdHandle(STD_INPUT_HANDLE);
		if (GetFileType(hIn) == FILE_TYPE_PIPE) {
			version (Trace) trace("stdin is pipe");
			hIn = CreateFileA("CONIN$", GENERIC_READ, 0, null, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, null);
			if (hIn == INVALID_HANDLE_VALUE)
				throw new WindowsException(GetLastError);
			stdin.windowsHandleOpen(hIn, "r");
		}
		SetConsoleMode(hIn, ENABLE_EXTENDED_FLAGS | ENABLE_WINDOW_INPUT | ENABLE_MOUSE_INPUT);
		oldCP = GetConsoleOutputCP();
		// NOTE: While Windows supports UTF-16LE (1200) and UTF-32LE,
		//       it's only for "managed applications" (.NET).
		// LINK: https://docs.microsoft.com/en-us/windows/win32/intl/code-page-identifiers
		BOOL cpr = SetConsoleOutputCP(CP_UTF8);
		version (Trace) trace("SetConsoleOutputCP=%d", cpr);
		//TODO: Get default/active colors
	}
	version (Posix) {
		stat_t s = void;
		fstat(STDIN_FILENO, &s);
		if (S_ISFIFO(s.st_mode))
			stdin.reopen("/dev/tty", "r");
		tcgetattr(STDIN_FILENO, &old_tio);
		new_tio = old_tio;
		new_tio.c_lflag &= TERM_ATTR;
	}
}

/// Restore CP and other settings
void terminalRestore() {
	version (Windows) {
		SetConsoleOutputCP(oldCP);
	}
}

/// Clear screen
void terminalClear() {
	version (Windows) {
		CONSOLE_SCREEN_BUFFER_INFO csbi = void;
		COORD c;
		GetConsoleScreenBufferInfo(hOut, &csbi);
		const int size = csbi.dwSize.X * csbi.dwSize.Y;
		DWORD num;
		if (FillConsoleOutputCharacterA(hOut, ' ', size, c, &num) == 0
			/*|| // .NET uses this but no idea why yet.
			FillConsoleOutputAttribute(hOut, csbi.wAttributes, size, c, &num) == 0*/) {
			terminalPos(0, 0);
		} else // If that fails, run cls.
			system("cls");
	} else version (Posix) {
		printf("\033c");
	}
	else static assert(0, "Clear: Not implemented");
}

/// Get terminal window size in characters.
/// Returns: Size
TerminalSize terminalSize() {
	TerminalSize size = void;
	version (Windows) {
		CONSOLE_SCREEN_BUFFER_INFO c = void;
		GetConsoleScreenBufferInfo(hOut, &c);
		size.height = c.srWindow.Bottom - c.srWindow.Top + 1;
		size.width  = c.srWindow.Right - c.srWindow.Left + 1;
	} else version (Posix) {
		winsize ws = void;
		ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws);
		size.height = ws.ws_row;
		size.width  = ws.ws_col;
	} else {
		static assert(0, "WindowHeight : Not implemented");
	}
	return size;
}

/**
 * Set cursor position x and y position respectively from the top left corner,
 * 0-based.
 * Params:
 *   x = X position (horizontal)
 *   y = Y position (vertical)
 */
void terminalPos(int x, int y) {
	version (Windows) { // 0-based
		COORD c = void;
		c.X = cast(short)x;
		c.Y = cast(short)y;
		SetConsoleCursorPosition(hOut, c);
	} else version (Posix) { // 1-based
		printf("\033[%d;%dH", ++y, ++x);
	}
}

/**
 * Read an input event. This function is blocking.
 * Params:
 *   k = TerminalInfo struct
 */
void terminalInput(ref TerminalInput k) {
	version (Windows) {
		INPUT_RECORD ir = void;
		DWORD num = void;
		char i = void;
L_READ:
		if (ReadConsoleInputA(hIn, &ir, 1, &num) == 0)
			throw new WindowsException(GetLastError);
		if (num == 0)
			goto L_READ;
		switch (ir.EventType) {
		case KEY_EVENT:
			if (ir.KeyEvent.bKeyDown == FALSE)
				goto L_READ;
			const DWORD state = ir.KeyEvent.dwControlKeyState;
			k.key.alt   = (state & ALT_PRESSED)   != 0;
			k.key.ctrl  = (state & CTRL_PRESSED)  != 0;
			k.key.shift = (state & SHIFT_PRESSED) != 0;
			k.value = ir.KeyEvent.wVirtualKeyCode;
			return;
		case MOUSE_EVENT:
			switch (ir.MouseEvent.dwEventFlags) {
			case MOUSE_WHEELED:
				// Up=0x00780000 Down=0xFF880000
				k.value = ir.MouseEvent.dwButtonState > 0xFF_0000 ?
					Mouse.ScrollDown : Mouse.ScrollUp;
				return;
			default: goto L_READ;
			}
		default: goto L_READ;
		}
	} else version (Posix) {
		//TODO: Get modifier keys states
		
		// Commenting this section will echo the character and make
		// getchar unusable
		tcsetattr(STDIN_FILENO, TCSANOW, &new_tio);
		
		int c = getchar;
		
		with (k) switch (c) {
		case '\n': // \n (ENTER)
			value = Key.Enter;
			goto _READKEY_END;
		case 27: // ESC
			switch (c = getchar) {
			case '[':
				switch (c = getchar) {
				case 'A': value = Key.UpArrow; goto _READKEY_END;
				case 'B': value = Key.DownArrow; goto _READKEY_END;
				case 'C': value = Key.RightArrow; goto _READKEY_END;
				case 'D': value = Key.LeftArrow; goto _READKEY_END;
				case 'F': value = Key.End; goto _READKEY_END;
				case 'H': value = Key.Home; goto _READKEY_END;
				// There is an additional getchar due to the pending '~'
				case '2': value = Key.Insert; getchar; goto _READKEY_END;
				case '3': value = Key.Delete; getchar; goto _READKEY_END;
				case '5': value = Key.PageUp; getchar; goto _READKEY_END;
				case '6': value = Key.PageDown; getchar; goto _READKEY_END;
				default: goto _READKEY_DEFAULT;
				} // [
			default: goto _READKEY_DEFAULT;
			} // ESC
		default:
			if (c >= 'a' && c <= 'z') {
				k.value = cast(Key)(c - 32);
				goto _READKEY_END;
			}
		}

_READKEY_DEFAULT:
		k.value = cast(ushort)c;
		
_READKEY_END:
		tcsetattr(STDIN_FILENO, TCSANOW, &old_tio);
	} // version posix
}

/// Key codes mapping.
enum Key : ushort {
	Undefined = 0,
	Backspace = 8,
	Tab = 9,
	Clear = 12,
	Enter = 13,
	Pause = 19,
	Escape = 27,
	Spacebar = 32,
	PageUp = 33,
	PageDown = 34,
	End = 35,
	Home = 36,
	LeftArrow = 37,
	UpArrow = 38,
	RightArrow = 39,
	DownArrow = 40,
	Select = 41,
	Print = 42,
	Execute = 43,
	PrintScreen = 44,
	Insert = 45,
	Delete = 46,
	Help = 47,
	D0 = 48,
	D1 = 49,
	D2 = 50,
	D3 = 51,
	D4 = 52,
	D5 = 53,
	D6 = 54,
	D7 = 55,
	D8 = 56,
	D9 = 57,
	Colon = 58,
	A = 65,
	B = 66,
	C = 67,
	D = 68,
	E = 69,
	F = 70,
	G = 71,
	H = 72,
	I = 73,
	J = 74,
	K = 75,
	L = 76,
	M = 77,
	N = 78,
	O = 79,
	P = 80,
	Q = 81,
	R = 82,
	S = 83,
	T = 84,
	U = 85,
	V = 86,
	W = 87,
	X = 88,
	Y = 89,
	Z = 90,
	LeftMeta = 91,
	RightMeta = 92,
	Applications = 93,
	Sleep = 95,
	NumPad0 = 96,
	NumPad1 = 97,
	NumPad2 = 98,
	NumPad3 = 99,
	NumPad4 = 100,
	NumPad5 = 101,
	NumPad6 = 102,
	NumPad7 = 103,
	NumPad8 = 104,
	NumPad9 = 105,
	Multiply = 106,
	Add = 107,
	Separator = 108,
	Subtract = 109,
	Decimal = 110,
	Divide = 111,
	F1 = 112,
	F2 = 113,
	F3 = 114,
	F4 = 115,
	F5 = 116,
	F6 = 117,
	F7 = 118,
	F8 = 119,
	F9 = 120,
	F10 = 121,
	F11 = 122,
	F12 = 123,
	F13 = 124,
	F14 = 125,
	F15 = 126,
	F16 = 127,
	F17 = 128,
	F18 = 129,
	F19 = 130,
	F20 = 131,
	F21 = 132,
	F22 = 133,
	F23 = 134,
	F24 = 135,
	BrowserBack = 166,
	BrowserForward = 167,
	BrowserRefresh = 168,
	BrowserStop = 169,
	BrowserSearch = 170,
	BrowserFavorites = 171,
	BrowserHome = 172,
	VolumeMute = 173,
	VolumeDown = 174,
	VolumeUp = 175,
	MediaNext = 176,
	MediaPrevious = 177,
	MediaStop = 178,
	MediaPlay = 179,
	LaunchMail = 180,
	LaunchMediaSelect = 181,
	LaunchApp1 = 182,
	LaunchApp2 = 183,
	Oem1 = 186,
	OemPlus = 187,
	OemComma = 188,
	OemMinus = 189,
	OemPeriod = 190,
	Oem2 = 191,
	Oem3 = 192,
	Oem4 = 219,
	Oem5 = 220,
	Oem6 = 221,
	Oem7 = 222,
	Oem8 = 223,
	Oem102 = 226,
	Process = 229,
	Packet = 231,
	Attention = 246,
	CrSel = 247,
	ExSel = 248,
	EraseEndOfFile = 249,
	Play = 250,
	Zoom = 251,
	NoName = 252,
	Pa1 = 253,
	OemClear = 254
}
enum Mouse : ushort {
	Click	= 0x1000,
	ScrollUp	= 0x2000,
	ScrollDown	= 0x3000,
}

/*******************************************************************
 * Structs
 *******************************************************************/

/// Key information structure
struct TerminalInput {
	ushort value;	/// Character or mouse event
	union {
		struct key_t {
			ubyte ctrl;	/// If either CTRL was held down.
			ubyte alt;	/// If either ALT was held down.
			ubyte shift;	/// If SHIFT was held down.
		} key_t key;
		struct mouse_t {
			ushort x, y;
		} mouse_t mouse;
	}
}

/// 
struct TerminalSize {
	/// 
	int width, height;
}
