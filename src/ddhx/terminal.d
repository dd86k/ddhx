/// Terminal/console handling.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module ddhx.terminal;

// NOTE: Useful links for escape codes
//       https://man7.org/linux/man-pages/man0/termios.h.0p.html
//       https://man7.org/linux/man-pages/man3/tcsetattr.3.html
//       https://man7.org/linux/man-pages/man4/console_codes.4.html

///
private extern (C) int getchar();

private import std.stdio;
private import core.stdc.stdlib : system, atexit;
import ddhx;

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
		//TODO: Get active (or default) colors
	} else version (Posix) {
		stat_t s = void;
		fstat(STDIN_FILENO, &s);
		if (S_ISFIFO(s.st_mode))
			stdin.reopen("/dev/tty", "r");
		tcgetattr(STDIN_FILENO, &old_tio);
		new_tio = old_tio;
		// NOTE: input modes
		// - IXON enables ^S and ^Q
		// - ICRNL enables ^M
		// - BRKINT causes SIGINT (^C) on break conditions
		// - INPCK enables parity checking
		// - ISTRIP strips the 8th bit
		new_tio.c_iflag &= ~(IXON | ICRNL | BRKINT | INPCK | ISTRIP);
		// NOTE: output modes
		// - OPOST turns on output post-processing
		//new_tio.c_oflag &= ~(OPOST);
		// NOTE: local modes
		// - ICANON turns on canonical mode (per-line instead of per-byte)
		// - ECHO turns on character echo
		// - ISIG enables ^C and ^Z signals
		// - IEXTEN enables ^V
		new_tio.c_lflag &= ~(ICANON | ECHO | IEXTEN);
		// NOTE: control modes
		// - CS8 sets Character Size to 8-bit
		new_tio.c_cflag |= CS8;
		// minimum amount of bytes to read,
		// 0 being return as soon as there is data
		//new_tio.c_cc[VMIN] = 0;
		// maximum amount of time to wait for input,
		// 1 being 1/10 of a second (100 milliseconds)
		//new_tio.c_cc[VTIME] = 0;
		tcsetattr(STDIN_FILENO, TCSAFLUSH, &new_tio);
	}
	
	atexit(&terminalRestore);
}

/// Restore CP and other settings
extern(C)
void terminalRestore() {
	version (Windows) {
		SetConsoleOutputCP(oldCP);
	} else version (Posix) {
		tcsetattr(STDIN_FILENO, TCSAFLUSH, &old_tio);
	}
}

void terminalPauseInput() {
	version (Posix) {
		tcsetattr(STDIN_FILENO, TCSAFLUSH, &old_tio);
	}
}

void terminalResumeInput() {
	version (Posix) {
		tcsetattr(STDIN_FILENO, TCSAFLUSH, &new_tio);
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
		// \033c is a Reset
		// \033[2J is "Erase whole display"
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
	version (Windows) { // 0-based, like us
		COORD c = void;
		c.X = cast(short)x;
		c.Y = cast(short)y;
		SetConsoleCursorPosition(hOut, c);
	} else version (Posix) { // we're 0-based but posix is 1-based
		printf("\033[%d;%dH", ++y, ++x);
	}
}

/**
 * Read an input event. This function is blocking.
 * Params:
 *   k = TerminalInfo struct
 */
void terminalInput(ref TerminalInput event) {
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
			event.alt   = (state & ALT_PRESSED)   != 0;
			event.ctrl  = (state & CTRL_PRESSED)  != 0;
			event.shift = (state & SHIFT_PRESSED) != 0;
			event.value = ir.KeyEvent.wVirtualKeyCode;
			return;
		case MOUSE_EVENT:
			switch (ir.MouseEvent.dwEventFlags) {
			case MOUSE_WHEELED:
				// Up=0x00780000 Down=0xFF880000
				event.value = ir.MouseEvent.dwButtonState > 0xFF_0000 ?
					Mouse.ScrollDown : Mouse.ScrollUp;
				return;
			default: goto L_READ;
			}
		default: goto L_READ;
		}
	} else version (Posix) {
		tcsetattr(STDIN_FILENO, TCSAFLUSH, &new_tio);
		scope (exit) tcsetattr(STDIN_FILENO, TCSAFLUSH, &old_tio);
		
		//TODO: Mouse reporting in Posix terminals
		//      * X10 compatbility mode (mouse-down only)
		//      Enable: ESC [ ? 9 h
		//      Disable: ESC [ ? 9 l
		//      "sends ESC [ M bxy (6 characters)"
		//      - ESC [ M button column row (1-based)
		//      - 0,0 click: ESC [ M   ! !
		//        ! is 0x21, so '!' - 0x21 = 0
		//      - end,end click: ESC [ M   q ;
		//        q is 0x71, so 'q' - 0x21 = 0x50 (column 80)
		//        ; is 0x3b, so ';' - 0x21 = 0x1a (row 26)
		//      - button left:   ' '
		//      - button right:  '"'
		//      - button middle: '!'
		//      * Normal tracking mode
		//      Enable: ESC [ ? 1000 h
		//      Disable: ESC [ ? 1000 l
		//      b bits[1:0] 0=MB1 pressed, 1=MB2 pressed, 2=MB3 pressed, 3=release
		//      b bits[7:2] 4=Shift, 8=Meta, 16=Control
		//TODO: Faster scanning
		//      So we have a few choices:
		//      - string table (current, works alright)
		//      - string[string]
		//      - string decoding
		//        [ -> escape
		//        1;2 -> shift (optional)
		//        B -> right arrow
		
		struct KeyInfo {
			string text;
			ushort value;
			bool ctrl, alt, shift;
		}
		static immutable KeyInfo[] keyInputs = [
			// text		Key value	ctrl	alt	shift
			{ "\033[A",	Key.UpArrow,	false,	false,	false },
			{ "\033[1;2A",	Key.UpArrow,	false,	false,	true },
			{ "\033[1;3A",	Key.UpArrow,	false,	true,	false },
			{ "\033[1;5A",	Key.UpArrow,	true,	false,	false },
			{ "\033[B",	Key.DownArrow,	false,	false,	false },
			{ "\033[1;2B",	Key.DownArrow,	false,	false,	true },
			{ "\033[1;3B",	Key.DownArrow,	false,	true,	false },
			{ "\033[1;5B",	Key.DownArrow,	true,	false,	false },
			{ "\033[C",	Key.RightArrow,	false,	false,	false },
			{ "\033[1;2C",	Key.RightArrow,	false,	false,	true },
			{ "\033[1;3C",	Key.RightArrow,	false,	true,	false },
			{ "\033[1;5C",	Key.RightArrow,	true,	false,	false },
			{ "\033[D",	Key.LeftArrow,	false,	false,	false },
			{ "\033[1;2D",	Key.LeftArrow,	false,	false,	true },
			{ "\033[1;3D",	Key.LeftArrow,	false,	true,	false },
			{ "\033[1;5D",	Key.LeftArrow,	true,	false,	false },
			{ "\033[2~",	Key.Insert,	false,	false,	false },
			{ "\033[3~",	Key.Delete,	false,	false,	false },
			{ "\033[3;5~",	Key.Delete,	true,	false,	false },
			{ "\033[H",	Key.Home,	false,	false,	false },
			{ "\033[1;5H",	Key.Home,	true,	false,	false },
			{ "\033[F",	Key.End,	false,	false,	false },
			{ "\033[1;5F",	Key.End,	true,	false,	false },
			{ "\033[5~",	Key.PageUp,	false,	false,	false },
			{ "\033[5;5~",	Key.PageUp,	true,	false,	false },
			{ "\033[6~",	Key.PageDown,	false,	false,	false },
			{ "\033[6;5~",	Key.PageDown,	true,	false,	false },
			{ "\033OP",	Key.F1,	false,	false,	false },
			{ "\033[1;2P",	Key.F1,	false,	false,	true },
			{ "\033[1;3R",	Key.F1,	false,	true,	false },
			{ "\033[1;5P",	Key.F1,	true,	false,	false },
			{ "\033OQ",	Key.F2,	false,	false,	false },
			{ "\033[1;2Q",	Key.F2,	false,	false,	true },
			{ "\033OR",	Key.F3,	false,	false,	false },
			{ "\033[1;2R",	Key.F3,	false,	false,	true },
			{ "\033OS",	Key.F4,	false,	false,	false },
			{ "\033[1;2S",	Key.F4,	false,	false,	true },
			{ "\033[15~",	Key.F5,	false,	false,	false },
			{ "\033[15;2~",	Key.F5,	false,	false,	true },
			{ "\033[17~",	Key.F6,	false,	false,	false },
			{ "\033[17;2~",	Key.F6,	false,	false,	true },
			{ "\033[18~",	Key.F7,	false,	false,	false },
			{ "\033[18;2~",	Key.F7,	false,	false,	true },
			{ "\033[19~",	Key.F8,	false,	false,	false },
			{ "\033[19;2~",	Key.F8,	false,	false,	true },
			{ "\033[20~",	Key.F9,	false,	false,	false },
			{ "\033[20;2~",	Key.F9,	false,	false,	true },
			{ "\033[21~",	Key.F10,	false,	false,	false },
			{ "\033[21;2~",	Key.F10,	false,	false,	true },
			{ "\033[23~",	Key.F11,	false,	false,	false },
			{ "\033[23;2~",	Key.F11,	false,	false,	true },
			{ "\033[24~",	Key.F12,	false,	false,	false },
			{ "\033[24;2~",	Key.F12,	false,	false,	true },
			
		];
		
		event.ctrl = event.alt = event.shift = false;
		
		enum BLEN = 8;
		char[BLEN] b = void;
	L_READ:
		ssize_t r = read(STDIN_FILENO, &b, BLEN);
		
		switch (r) {
		case -1: assert(0, "read failed");
		case 0:  goto L_READ; // HOW
		case 1:
			char c = b[0];
			if (c < 32) { // Control character
				switch (c) {
				case 0: goto L_READ; // Invalid
				case 8: // ^H
					event.value = Key.Backspace;
					event.ctrl = true;
					return;
				case 9: // \t
					event.value = Key.Tab;
					return;
				case 13: // '\r'
					event.value = Key.Enter;
					return;
				case 20: // ' '
					event.value = Key.Enter;
					return;
				case 27: // \033
					event.value = Key.Escape;
					return;
				default:
				}
				event.value = cast(ushort)(c + 64);
				event.ctrl = true;
			} else if (c == 127) {
				event.value = Key.Backspace;
			} else if (c >= 'a' && c <= 'z') {
				event.value = cast(ushort)(c - 32);
			} else if (c >= 'A' && c <= 'Z') {
				event.value = c;
				event.shift = true;
			} else if (c >= '0' && c <= '9') {
				event.value = c; // D0-D9
			}
			return;
		default:
		}
		
		//TODO: Checking for mouse inputs
		//      Starts with \033[M
		
		// Checking for key inputs
		const(char)[] text = b[0..r];
		for (size_t i; i < keyInputs.length; ++i) {
			immutable(KeyInfo) *ki = &keyInputs[i];
			if (r != ki.text.length) continue;
			if (text != ki.text) continue;
			event.value = ki.value;
			event.ctrl  = ki.ctrl;
			event.alt   = ki.alt;
			event.shift = ki.shift;
			return;
		}
		
		// Matched to nothing
		goto L_READ;
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
	ushort value;
	union {
		struct {
			bool ctrl, alt, shift;
		}
		struct {
			ushort mouseX, mouseY;
		}
	}
}

/// 
struct TerminalSize {
	/// 
	int width, height;
}
