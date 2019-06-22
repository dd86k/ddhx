/**
 * Main rendering engine.
 */
module ddhx;

import std.stdio : write, writeln, writef, writefln;
import std.mmfile;
import core.stdc.stdio : printf;
import menu, ddcon;
import utils : formatsize, unformat;

//TODO: retain window dimensions until a new size event or something

/// Copyright string
enum COPYRIGHT = "Copyright (c) dd86k 2017-2019";

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

__gshared MmFile CFile = void;	/// Current file
__gshared ubyte* mmbuf = void;	/// mmfile buffer address
__gshared uint screenl = void;	/// screen size in bytes, 1 dimensional buffer

__gshared string fname = void;	/// filename
__gshared long fpos = void;	/// Current file position
__gshared long fsize = void;	/// File size

private __gshared char[30] tfsizebuf;	/// total formatted size buffer
private __gshared char[] tfsize;	/// total formatted size (pointer)

/// Main app entry point
/// Params: pos = File position to start with
extern (C)
void Start(long pos) {
	fpos = pos;
	tfsize = formatsize(tfsizebuf, fsize);
	screeninit;
	hxprep;
	screenclear;
	hxoffsetbar;
	hxrender_r;
	hxinfobar_r;

	KeyInfo k = void;
KEY:
	screenkey(k);
	//TODO: Handle resize event
	if (k.keyCode)
		hxkey(k);
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
void hxkey(const ref KeyInfo k) {
	import settings : HandleWidth;

	switch (k.keyCode) {

	//
	// Navigation
	//

	case Key.UpArrow:
		if (fpos - BytesPerRow >= 0)
			hxgoto(fpos - BytesPerRow);
		else
			hxgoto(0);
		break;
	case Key.DownArrow:
		if (fpos + screenl + BytesPerRow <= fsize)
			hxgoto(fpos + BytesPerRow);
		else
			hxgoto(fsize - screenl);
		break;
	case Key.LeftArrow:
		if (fpos - 1 >= 0) // Else already at 0
			hxgoto(fpos - 1);
		break;
	case Key.RightArrow:
		if (fpos + screenl + 1 <= fsize)
			hxgoto(fpos + 1);
		else
			hxgoto(fsize - screenl);
		break;
	case Key.PageUp:
		if (fpos - cast(long)screenl >= 0)
			hxgoto(fpos - screenl);
		else
			hxgoto(0);
		break;
	case Key.PageDown:
		if (fpos + screenl + screenl <= fsize)
			hxgoto(fpos + screenl);
		else
			hxgoto(fsize - screenl);
		break;
	case Key.Home:
		if (k.ctrl)
			hxgoto(0);
		else
			hxgoto(fpos - (fpos % BytesPerRow));
		break;
	case Key.End:
		if (k.ctrl)
			hxgoto(fsize - screenl);
		else {
			const long np = fpos +
				(BytesPerRow - fpos % BytesPerRow);

			if (np + screenl <= fsize)
				hxgoto(np);
			else
				hxgoto(fsize - screenl);
		}
		break;

	//
	// Actions/Shortcuts
	//

	case Key.Escape, Key.Enter:
		hxmenu;
		break;
	case Key.G:
		hxmenu("g ");
		hxoffsetbar();
		break;
	case Key.I:
		hxfileinfo;
		break;
	case Key.R, Key.F5:
		hxrefresh_a;
		break;
	case Key.A:
		HandleWidth("a");
		hxrefresh_a;
		break;
	case Key.Q: hxexit; break;
	default:
	}
}

/// Refresh the entire screen
extern (C)
void hxrefresh_a() {
	hxprep;
	screenclear;
	hxoffsetbar;
	hxrender_r;
	hxinfobar_r;
}

/**
 * Update the upper offset bar.
 */
extern (C)
void hxoffsetbar() {
	char [8]format = cast(char[8])" %02X"; // default
	format[4] = formatTable[CurrentOffsetType];
	screenpos(0, 0);
	printf("Offset %c ", offsetTable[CurrentOffsetType]);
	for (ushort i; i < BytesPerRow; ++i)
		printf(cast(char*)format, i);
	putchar('\n');
}

/// Update the bottom current information bar.
extern (C)
void hxinfobar() {
	screenpos(0, screenheight - 1);
	hxinfobar_r;
}

/// Updates information bar without cursor position call.
extern (C)
void hxinfobar_r() {
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
void hxprep() {
	const int bufs = (screenheight - 2) * BytesPerRow; // Proposed buffer size
	screenl = fsize >= bufs ? bufs : cast(uint)fsize;
}

/**
 * Goes to the specified position in the file.
 * Ignores bounds checking for performance reasons.
 * Sets CurrentPosition.
 * Params: pos = New position
 */
extern (C)
void hxgoto(long pos) {
	if (screenl < fsize) {
		fpos = pos;
		hxrender;
		hxinfobar_r;
	} else
		msgalt("Navigation disabled, buffer too small.");
}

/**
 * Goes to the specified position in the file.
 * Checks bounds and calls Goto.
 * Params: pos = New position
 */
extern (C)
void hxgoto_c(long pos) {
	if (pos + screenl > fsize)
		hxgoto(fsize - screenl);
	else
		hxgoto(pos);
}

/**
 * Parses the string as a long and navigates to the file location.
 * Includes offset checking (+/- notation).
 * Params: str = String as a number
 */
void gotostr(string str) {
	byte rel = void; // Lazy code
	if (str[0] == '+') { // relative position
		rel = 1;
		str = str[1..$];
	} else if (str[0] == '-') {
		rel = 2;
		str = str[1..$];
	}
	long l = void;
	if (unformat(str, l) == false) {
		msgalt("Could not parse number");
		return;
	}
	switch (rel) {
	case 1:
		if (fpos + l - screenl < fsize)
			hxgoto(fpos + l);
		break;
	case 2:
		if (fpos - l >= 0)
			hxgoto(fpos - l);
		break;
	default:
		if (l >= 0 && l < fsize - screenl) {
			hxgoto(l);
		} else {
			import std.format : format;
			msgalt(format("Range too far or negative: %d (%XH)", l, l));
		}
	}
}

/// Update display from buffer
extern (C)
void hxrender() {
	screenpos(0, 1);
	hxrender_r;
}

/// Update display from buffer without setting cursor
extern (C)
void hxrender_r() {
	__gshared char[] hexTable = [
		'0', '1', '2', '3', '4', '5', '6', '7',
		'8', '9', 'A', 'B', 'C', 'D', 'E', 'F',
	];

	char[1024] a = void, d = void;
	
	size_t brow = BytesPerRow; /// bytes per row
	size_t minw = cast(int)brow * 3;

	a[brow] = d[minw] = '\0';

	size_t p = cast(size_t)fpos, wlen = p + screenl; /// window length

	//TODO: if wlen>fsize, then slice differently
	// range, does not allocate
	const ubyte[] fbuf = cast(ubyte[])CFile[p..wlen];

	char[12] bytef = cast(char[12])"%08X %s  %s\n";
	bytef[3] = formatTable[CurrentOffsetType];

	for (size_t bi; p < wlen; p += brow) {
		const bool over = p + brow > fsize;

		if (over) {
			brow = cast(uint)(fsize - p);
			minw = brow * 3;
		}

		for (size_t di, ai; ai < brow; ++ai) {
			const ubyte b = fbuf[bi++];
			d[di++] = ' ';
			d[di++] = hexTable[b >> 4];
			d[di++] = hexTable[b & 15];
			a[ai] = b > 0x7E || b < 0x20 ? DEFAULT_CHAR : b;
		}

		writef(bytef, p, d[0..minw], a[0..brow]);

		if (over) return;
	}
}

/**
 * Message once (upper bar)
 * Params: msg = Message string
 */
void msg(string msg) {
	screenpos(0, 0);
	writef("%s%*s", msg, (screenwidth - 1) - msg.length, " ");
}

/**
 * Message once (bottom bar)
 * Params: msg = Message string
 */
void msgalt(string msg) {
	screenpos(0, screenheight - 1);
	writef("%s%*s", msg, (screenwidth - 1) - msg.length, " ");
}

/**
 * Bottom bar message.
 * Params:
 *   f = Format
 *   arg = String argument
 */
void msgalt(string f, string arg) {
	import std.format : format;
	msgalt(format(f, arg));
}

/// Print some file information at the bottom bar
extern (C)
void hxfileinfo() {
	import std.format : sformat;
	import std.path : baseName;
	char[256] b = void;
	msgalt(cast(string)b.sformat!"%s  %s"(tfsize, fname.baseName));
}

/// Exits ddhx
extern (C)
void hxexit() {
	import core.stdc.stdlib : exit;
	screenclear;
	exit(0);
}