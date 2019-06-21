/**
 * Main rendering engine.
 */
module ddhx;

import std.stdio : write, writef, writeln;
import std.mmfile;
import core.stdc.stdio : printf, puts;
import core.stdc.stdlib;
import core.stdc.string : memset;
import menu, ddcon;
import utils : formatsize, unformat;

//TODO: retain window dimensions until a new size event or something

/// App version
enum APP_VERSION = "0.2.0";

/// Offset type (hex, dec, etc.)
enum OffsetType : size_t {
	Hexadecimal, Decimal, Octal
}

/// 
enum DisplayMode : ubyte {
	Default, Text, Data
}

/// Default character for non-displayable characters
enum DEFAULT_CHAR = '.';

/// Preferred table over computing the same values again$(BR)
/// Hint: Fast
private __gshared const char[] hexTable = [
	'0', '1', '2', '3', '4', '5', '6', '7',
	'8', '9', 'A', 'B', 'C', 'D', 'E', 'F',
];

/// For header
private __gshared const char[] offsetTable = [
	'h', 'd', 'o'
];
/// For formatting
private __gshared const char[] formatTable = [
	'X', 'u', 'o'
];

//
// User settings
//

/// Bytes shown per row
__gshared ushort BytesPerRow = 16;
/// Current offset view type
__gshared OffsetType CurrentOffsetType = void;
/// Current display view type
__gshared DisplayMode CurrentDisplayMode = void;

//
// Internal
//

__gshared MmFile MMFile = void;
__gshared ubyte* mmbuf = void;
__gshared uint screenl = void; // screen size

__gshared string fname = void;
__gshared long fpos = void; /// Current file position
__gshared long fsize = void; /// File size

private __gshared char[30] tfsizebuf; /// total formatted size buffer
private __gshared char[] tfsize; /// total formatted size (pointer)

/// Main app entry point
void Start() {
	fpos = 0;
	tfsize = formatsize(tfsizebuf, fsize);
	InitConsole;
	PrepBuffer;
	Clear;
	UpdateOffsetBar;
	UpdateDisplayRawMM;
	UpdateInfoBarRaw;

	KeyInfo k = void;
KEY:
	ReadKey(k);
	//TODO: Handle resize event
	if (k.keyCode)
		HandleKey(k);
	goto KEY;
}

/*void HandleMouse(const MouseInfo* mi)
{
	size_t bs = BufferLength;

	switch (mi.Type) {
	case MouseEventType.Wheel:
		if (mi.ButtonState > 0) { // Up
			if (CurrentPosition - BytesPerRow >= 0)
				Goto(CurrentPosition - BytesPerRow);
			else
				Goto(0);
		} else { // Down
			if (CurrentPosition + bs + BytesPerRow <= fs)
				Goto(CurrentPosition + BytesPerRow);
			else
				Goto(fs - bs);
		}
		break;
	default:
	}
}*/

/**
 * Handles a user key-stroke
 * Params: k = KeyInfo (ddcon)
 */
extern (C)
void HandleKey(const ref KeyInfo k) {
	import settings : HandleWidth;

	switch (k.keyCode) {

	//
	// Navigation
	//

	case Key.UpArrow:
		if (fpos - BytesPerRow >= 0)
			Goto(fpos - BytesPerRow);
		else
			Goto(0);
		break;
	case Key.DownArrow:
		if (fpos + screenl + BytesPerRow <= fsize)
			Goto(fpos + BytesPerRow);
		else
			Goto(fsize - screenl);
		break;
	case Key.LeftArrow:
		if (fpos - 1 >= 0) // Else already at 0
			Goto(fpos - 1);
		break;
	case Key.RightArrow:
		if (fpos + screenl + 1 <= fsize)
			Goto(fpos + 1);
		else
			Goto(fsize - screenl);
		break;
	case Key.PageUp:
		if (fpos - cast(long)screenl >= 0)
			Goto(fpos - screenl);
		else
			Goto(0);
		break;
	case Key.PageDown:
		if (fpos + screenl + screenl <= fsize)
			Goto(fpos + screenl);
		else
			Goto(fsize - screenl);
		break;
	case Key.Home:
		if (k.ctrl)
			Goto(0);
		else
			Goto(fpos - (fpos % BytesPerRow));
		break;
	case Key.End:
		if (k.ctrl)
			Goto(fsize - screenl);
		else {
			const long np = fpos +
				(BytesPerRow - fpos % BytesPerRow);

			if (np + screenl <= fsize)
				Goto(np);
			else
				Goto(fsize - screenl);
		}
		break;

	//
	// Actions/Shortcuts
	//

	case Key.Escape, Key.Enter:
		Menu;
		break;
	case Key.G:
		Menu("g ");
		UpdateOffsetBar();
		break;
	case Key.I:
		PrintFileInfo;
		break;
	case Key.R, Key.F5:
		RefreshAll;
		break;
	case Key.A:
		HandleWidth("a");
		RefreshAll;
		break;
	case Key.Q: Exit; break;
	default:
	}
}

/// Refresh the entire screen
extern (C)
void RefreshAll() {
	PrepBuffer;
	Clear;
	UpdateOffsetBar;
	UpdateDisplayRawMM;
	UpdateInfoBarRaw;
}

/**
 * Update the upper offset bar.
 */
extern (C)
void UpdateOffsetBar() {
	char [8]format = cast(char[8])" %02X"; // default
	format[4] = formatTable[CurrentOffsetType];
	SetPos(0, 0);
	printf("Offset %c ", offsetTable[CurrentOffsetType]);
	for (ushort i; i < BytesPerRow; ++i)
		printf(cast(char*)format, i);
	putchar('\n');
}

/// Update the bottom current information bar.
extern (C)
void UpdateInfoBar() {
	SetPos(0, WindowHeight - 1);
	UpdateInfoBarRaw;
}

/// Updates information bar without cursor position call.
extern (C)
void UpdateInfoBarRaw() {
	char[30] bl = void, cp = void;
	writef(" %*s | %*s/%*s | %7.3f%%",
		7,  formatsize(bl, screenl), // Buffer size
		10, formatsize(cp, fpos), // Formatted position
		10, tfsize, // Total file size
		((cast(float)fpos + screenl) / fsize) * 100 // Pos/filesize%
	);
}

/// Determine screensize
extern (C)
void PrepBuffer() {
	const int bufs = (WindowHeight - 2) * BytesPerRow; // Proposed buffer size
	screenl = fsize >= bufs ? bufs : cast(uint)fsize;
}

/**
 * Goes to the specified position in the file.
 * Ignores bounds checking for performance reasons.
 * Sets CurrentPosition.
 * Params: pos = New position
 */
extern (C)
void Goto(long pos) {
	if (screenl < fsize) {
		fpos = pos;
		UpdateDisplay;
		UpdateInfoBarRaw;
	} else
		MessageAlt("Navigation disabled, buffer too small.");
}

/**
 * Goes to the specified position in the file.
 * Checks bounds and calls Goto.
 * Params: pos = New position
 */
extern (C)
void GotoC(long pos) {
	if (pos + screenl > fsize)
		Goto(fsize - screenl);//Buffer.length);
	else
		Goto(pos);
}

/**
 * Parses the string as a long and navigates to the file location.
 * Includes offset checking (+/- notation).
 * Params: str = String as a number
 */
void GotoStr(string str) {
	byte rel; // Lazy code
	if (str[0] == '+') {
		rel = 1;
		str = str[1..$];
	} else if (str[0] == '-') {
		rel = 2;
		str = str[1..$];
	}
	long l = void;
	if (unformat(str, l)) {
		switch (rel) {
		case 1:
			if (fpos + l - screenl < fsize)
				Goto(fpos + l);
			break;
		case 2:
			if (fpos - l >= 0)
				Goto(fpos - l);
			break;
		default:
			if (l >= 0 && l < fsize - screenl) {
				Goto(l);
			} else {
				import std.format : format;
				MessageAlt(format("Range too far or negative: %d (%XH)", l, l));
			}
		}
	} else {
		MessageAlt("Could not parse number");
	}
}

/// Update display from buffer
extern (C)
void UpdateDisplay() {
	SetPos(0, 1);
	UpdateDisplayRawMM;
}

/// Update display from buffer without setting cursor
extern (C)
void UpdateDisplayRawMM() {
	import core.stdc.string : memset;
	char [1024]a = void;
	char [1024]d = void;
	
	size_t brow = BytesPerRow; /// bytes per row
	int minw = cast(int)brow * 3;

	a[brow] = '\0';
	d[minw] = '\0';

	long p = fpos;
	const long blen = p + screenl;

	//TODO: if >fsize, then slice differently
	ubyte[] fbuf = cast(ubyte[])MMFile[p..blen];

	char [16]bytef = cast(char[16])"%08X %s  %s\n";
	bytef[3] = formatTable[CurrentOffsetType];

	for (size_t bi; p < blen; p += brow) {
		const bool over = p + brow > fsize;

		if (over) {
			brow = cast(uint)(fsize - p);
			memset(cast(char*)a, ' ', BytesPerRow);
			memset(cast(char*)d, ' ', minw);
		}

		for (size_t di, ai; ai < brow; ++ai) {
			const ubyte b = fbuf[bi++];
			d[di++] = ' ';
			d[di++] = hexTable[b >> 4];
			d[di++] = hexTable[b & 15];
			a[ai] = FormatChar(b);
		}

		printf(cast(char*)bytef, p, cast(char*)d, cast(char*)a);

		if (over) return;
	}
}

/**
 * Message once (upper bar)
 * Params: msg = Message string
 */
void Message(string msg) {
	ClearMsg;
	SetPos(0, 0);
	write(msg);
}

/// Clear upper bar
extern (C)
void ClearMsg() {
	SetPos(0, 0);
	writef("%*s", WindowWidth - 1, " ");
}

/**
 * Message once (bottom bar)
 * Params: msg = Message string
 */
void MessageAlt(string msg) {
	ClearMsgAlt;
	SetPos(0, WindowHeight - 1);
	write(msg);
}

void MessageAlt(string f, string arg) {
	import std.format : format;
	MessageAlt(format(f, arg));
}

/// Clear bottom bar
extern (C)
void ClearMsgAlt() {
	SetPos(0, WindowHeight - 1);
	writef("%*s", WindowWidth - 1, " ");
}

/// Print some file information at the bottom bar
extern (C)
void PrintFileInfo() {
	import std.format : sformat;
	import std.path : baseName;

	char[512] b = void;

	ClearMsgAlt;
	MessageAlt(cast(string)b.sformat!"%s  %s"(tfsize, fname.baseName));
}

/// Exits ddhx
extern (C)
void Exit() {
	import core.stdc.stdlib : exit;
	Clear;
	exit(0);
}

/**
 * Converts an unsigned byte to an ASCII character. If the byte is outside of
 * the ASCII range, $(D DEFAULT_CHAR) will be returned.
 * Params: c = Unsigned byte
 * Returns: ASCII character
 */
extern (C)
char FormatChar(ubyte c) pure @safe @nogc nothrow { //TODO: EIBEC?
	return c > 0x7E || c < 0x20 ? DEFAULT_CHAR : c;
}