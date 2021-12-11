/**
 * Main rendering engine.
 */
module ddhx.ddhx;

import std.stdio;
import std.file : getSize;
import core.stdc.stdio : printf, fflush, puts, snprintf;
import core.stdc.string : memset;
import ddhx.utils : formatSize, unformat;
import ddhx.input, ddhx.menu, ddhx.terminal, ddhx.settings, ddhx.error;
import ddhx.searcher : searchLast;

//TODO: View display mode (hex+ascii, hex, ascii)
//TODO: Data display mode (hex, octal, dec)

/// Copyright string
enum DDHX_COPYRIGHT = "Copyright (c) 2017-2021 dd86k <dd@dax.moe>";

/// App version
enum DDHX_VERSION = "0.3.3";

/// Version line
enum DDHX_VERSION_LINE = "ddhx " ~ DDHX_VERSION ~ " (built: " ~ __TIMESTAMP__~")";

private extern (C) int putchar(int);

/// Character table for header row
private immutable char[3] offsetTable = [ 'h', 'd', 'o' ];
/// Character table for the main panel for printf
private immutable char[3] formatTable = [ 'x', 'u', 'o' ];
/// Offset format functions
private immutable size_t function(char*,long)[3] offsetFuncs =
	[ &format8lux, &format8lud, &format8luo ];
/// Data format functions
//private immutable size_t function(char*,long)[] dataFuncs =
//	[ &format2x, &format3d, &format3o ];


//
// User settings
//

//TODO: --no-header: bool
//TODO: --no-offset: bool
//TODO: --no-status: bool
/// Global definitions and default values
struct Globals {
	// Settings
	ushort rowWidth = 16;	/// How many bytes are shown per row
	OffsetType offset;	/// Current offset view type
	DisplayMode display;	/// Current display view type
	char defaultChar = '.';	/// Default character to use for non-ascii characters
	// File
	string fileName;	/// 
	const(ubyte)[] buffer;	/// 
//	bool omitHeader;	/// 
//	bool omitOffsetBar;	/// 
//	bool omitOffset;	/// 
	// Internals
	int termHeight;	/// Last known terminal height
	int termWidth;	/// Last known terminal width
	const(char)[] fileSizeString;	/// Formatted binary size
}

__gshared Globals globals; /// Single-instance of globals.
__gshared Input   input;   /// Input file/stream

int printError(A...)(int code, string fmt, A args) {
	stderr.write("error: ");
	stderr.writefln(fmt, args);
	return code;
}

int ddhxOpenFile(string path) {
	version (Trace) trace("path=%s", path);
	
	import std.path : baseName;
	globals.fileName = baseName(path);
	return input.openFile(path);
}
int ddhxOpenMmfile(string path) {
	version (Trace) trace("path=%s", path);
	
	import std.path : baseName;
	globals.fileName = baseName(path);
	return input.openMmfile(path);
}
int ddhxOpenStdin() {
	version (Trace) trace("-");
	
	globals.fileName = "-";
	return input.openStdin();
}

/// Main app entry point
int ddhxInteractive(long skip = 0) {
	//TODO: Consider hiding terminal cursor
	//TODO: Consider changing the buffering strategy
	//      e.g., flush+setvbuf/puts+flush
	
	//TODO: negative should be starting from end of file (if not stdin)
	if (skip < 0)
		skip = +skip;
	
	if (input.mode == InputMode.stdin) {
		version (Trace) trace("slurp skip=%u", skip);
		input.slurpStdin(skip);
	}
	
	input.position = skip;
	globals.fileSizeString = input.binarySize();
	
	version (Trace) trace("coninit");
	coninit;
	version (Trace) trace("conclear");
	conclear;
	version (Trace) trace("conheight");
	globals.termHeight = conheight;
	ddhxPrepBuffer(true);
	globals.buffer = input.read();
	version (Trace) trace("buffer+read=%u", globals.buffer.length);
	ddhxRender();
	
	InputInfo k;
	version (Trace) trace("loop");
L_KEY:
	coninput(k);
	version (Trace) trace("key=%d", k.value);
	
	with (globals) switch (k.value) {
	
	//
	// Navigation
	//
	
	case Key.UpArrow, Key.K:
		if (input.position - rowWidth >= 0)
			ddhxSeek(input.position - rowWidth);
		else
			ddhxSeek(0);
		break;
	case Key.DownArrow, Key.J:
		if (input.position + input.bufferSize + rowWidth <= input.size)
			ddhxSeek(input.position + rowWidth);
		else
			ddhxSeek(input.size - input.bufferSize);
		break;
	case Key.LeftArrow, Key.H:
		if (input.position - 1 >= 0) // Else already at 0
			ddhxSeek(input.position - 1);
		break;
	case Key.RightArrow, Key.L:
		if (input.position + input.bufferSize + 1 <= input.size)
			ddhxSeek(input.position + 1);
		else
			ddhxSeek(input.size - input.bufferSize);
		break;
	case Key.PageUp, Mouse.ScrollUp:
		if (input.position - cast(long)input.bufferSize >= 0)
			ddhxSeek(input.position - input.bufferSize);
		else
			ddhxSeek(0);
		break;
	case Key.PageDown, Mouse.ScrollDown:
		if (input.position + input.bufferSize + input.bufferSize <= input.size)
			ddhxSeek(input.position + input.bufferSize);
		else
			ddhxSeek(input.size - input.bufferSize);
		break;
	case Key.Home:
		ddhxSeek(k.key.ctrl ? 0 : input.position - (input.position % rowWidth));
		break;
	case Key.End:
		if (k.key.ctrl) {
			ddhxSeek(input.size - input.bufferSize);
		} else {
			const long np = input.position + (rowWidth - input.position % rowWidth);
			ddhxSeek(np + input.bufferSize <= input.size ? np : input.size - input.bufferSize);
		}
		break;

	//
	// Actions/Shortcuts
	//

	case Key.N:
		if (searchLast())
			ddhxMsgLow(ddhxErrorMsg);
		break;
	case Key.Escape, Key.Enter, Key.Colon:
		hxmenu;
		break;
	case Key.G:
		hxmenu("g ");
		ddhxUpdateOffsetbar;
		break;
	case Key.I:
		ddhxMsgFileInfo;
		break;
	case Key.R, Key.F5:
		ddhxRefresh;
		break;
	case Key.A:
		optionWidth("a");
		ddhxRefresh;
		break;
	case Key.Q: ddhxExit; break;
	default:
		version (Trace) trace("unknown key=%u", k.value);
	}
	goto L_KEY;
}

/// 
int ddhxDump(long skip, long length) {
	if (length < 0)
		return printError(2, "length negative");
	
	version (Trace) trace("skip=%d length=%d", skip, length);
	
	final switch (input.mode) {
	case InputMode.file, InputMode.mmfile:
		if (skip < 0) {
			skip = input.size + skip;
		}
		if (skip + length > input.size)
			return printError(3, "length overflow");
		if (length == 0)
			length = input.size - skip;
		if (skip)
			input.seek(skip);
		
		ddhxUpdateOffsetbarRaw;
		
		if (length >= DEFAULT_BUFFER_SIZE) {
			input.adjust(DEFAULT_BUFFER_SIZE);
			do {
				globals.buffer = input.read();
				ddhxDrawRaw;
				input.position += DEFAULT_BUFFER_SIZE;
			} while (length -= DEFAULT_BUFFER_SIZE > 0);
		}
		
		if (length > 0) {
			input.adjust(cast(uint)length);
			globals.buffer = input.read();
			ddhxDrawRaw;
		}
	
		break;
	case InputMode.stdin:
		if (skip < 0)
			return printError(4, "skip value negative in stdin mode");
		
		size_t l = void;
		if (skip) {
			if (skip > DEFAULT_BUFFER_SIZE) {
				input.adjust(DEFAULT_BUFFER_SIZE);
			} else {
				input.adjust(cast(uint)(skip));
			}
			do {
				l = input.read().length;
			} while (l >= DEFAULT_BUFFER_SIZE);
		}
		
		input.adjust(DEFAULT_BUFFER_SIZE);
		ddhxUpdateOffsetbarRaw;
		
		do {
			globals.buffer = input.read();
			ddhxDrawRaw;
			input.position += DEFAULT_BUFFER_SIZE;
			l = globals.buffer.length;
		} while (l);
		break;
	}
	return 0;
}

/// Refresh the entire screen
void ddhxRefresh() {
	ddhxPrepBuffer();
	input.seek(input.position);
	globals.buffer = input.read();
	conclear();
	ddhxRender();
}

/// Render all
void ddhxRender() {
	ddhxUpdateOffsetbar();
	if (ddhxDrawRaw() < conheight - 2)
		ddhxUpdateStatusbar;
	else
		ddhxUpdateStatusbarRaw;
}

/// Update the upper offset bar.
void ddhxUpdateOffsetbar() {
	conpos(0, 0);
	ddhxUpdateOffsetbarRaw;
}

/// 
void ddhxUpdateOffsetbarRaw() {
	//TODO: Redo ddhxUpdateOffsetbarRaw
	/*enum OFFSET = "Offset ";
	__gshared char[512] line = "Offset ";
	size_t lineindex = OFFSET.sizeof;
	
	line[lineindex] = offsetTable[globals.offset];
	line[lineindex+1] = ' ';
	lineindex += 2;
	
	for (ushort i; i < globals.rowWidth; ++i) {
		line[lineindex] = ' ';
	}*/
	
	static char[8] fmt = " %02x";
	fmt[4] = formatTable[globals.offset];
	printf("Offset %c ", offsetTable[globals.offset]);
	//TODO: Better rendering for large positions
	if (input.position > 0xffff_ffff) putchar(' ');
	for (ushort i; i < globals.rowWidth; ++i)
		printf(cast(char*)fmt, i);
	putchar('\n');
}

/// Update the bottom current information bar.
void ddhxUpdateStatusbar() {
	conpos(0, conheight - 1);
	ddhxUpdateStatusbarRaw;
}

/// Updates information bar without cursor position call.
void ddhxUpdateStatusbarRaw() {
	import std.format : sformat;
	__gshared size_t last;
	char[32] c = void, t = void;
	char[128] b = void;
	char[] f = sformat!" %*s | %*s/%*s | %7.4f%%"(b,
		7,  formatSize(c, input.bufferSize), // Buffer size
		10, formatSize(t, input.position), // Formatted position
		10, globals.fileSizeString, // Total file size
		((cast(float)input.position + input.bufferSize) / input.size) * 100 // Pos/input.size%
	);
	if (last > f.length) {
		int p = cast(int)(f.length + (last - f.length));
		writef("%*s", -p, f);
	} else {
		write(f);
	}
	last = f.length;
	version (CRuntime_DigitalMars) stdout.flush();
	version (CRuntime_Musl) stdout.flush();
}

/// Determine input.bufferSize and buffer size
void ddhxPrepBuffer(bool skipTerm = false) {
	version (Trace) trace("skip=%s", skipTerm);
	
	debug import std.conv : text;
	const int h = (skipTerm ? globals.termHeight : conheight) - 2;
	debug assert(h > 0);
	debug assert(h < conheight, "h="~h.text~" >= conheight="~conheight.text);
	int newSize = h * globals.rowWidth; // Proposed buffer size
	if (newSize >= input.size)
		newSize = cast(uint)(input.size - input.position);
	version (Trace) trace("newSize=%u", newSize);
	input.adjust(newSize);
}

/**
 * Goes to the specified position in the file.
 * Ignores bounds checking for performance reasons.
 * Sets CurrentPosition.
 * Params: pos = New position
 */
void ddhxSeek(long pos) {
	version (Trace) trace("pos=%d", pos);
	
	if (input.bufferSize < input.size) {
		input.seek(pos);
		globals.buffer = input.read();
		ddhxRender();
	} else
		ddhxMsgLow("Navigation disabled, buffer too small");
}

/**
 * Parses the string as a long and navigates to the file location.
 * Includes offset checking (+/- notation).
 * Params: str = String as a number
 */
void ddhxSeek(string str) {
	version (Trace) trace("str=%s", str);
	
	const char seekmode = str[0];
	if (seekmode == '+' || seekmode == '-') { // relative input.position
		str = str[1..$];
	}
	long newPos = void;
	if (unformat(str, newPos) == false) {
		ddhxMsgLow("Could not parse number");
		return;
	}
	with (globals) switch (seekmode) {
	case '+':
		newPos = input.position + newPos;
		if (newPos - input.bufferSize < input.size)
			ddhxSeek(newPos);
		break;
	case '-':
		newPos = input.position - newPos;
		if (newPos >= 0)
			ddhxSeek(newPos);
		break;
	default:
		if (newPos < 0) {
			ddhxMsgLow("Range underflow: %d (0x%x)", newPos, newPos);
		} else if (newPos >= input.size - input.bufferSize) {
			ddhxMsgLow("Range overflow: %d (0x%x)", newPos, newPos);
		} else {
			ddhxSeek(newPos);
		}
	}
}

/**
 * Goes to the specified position in the file.
 * Checks bounds and calls Goto.
 * Params: pos = New position
 */
void ddhxSeekSafe(long pos) {
	version (Trace) trace("pos=%s", pos);
	
	if (pos + input.bufferSize > input.size)
		ddhxSeek(input.size - input.bufferSize);
	else
		ddhxSeek(pos);
}

private immutable static string hexTable = "0123456789abcdef";
private
size_t format8lux(char *buffer, long v) {
	size_t pos;
	bool pad = true;
	for (int shift = 60; shift >= 0; shift -= 4) {
		const ubyte b = (v >> shift) & 15;
		if (b == 0) {
			if (pad && shift >= 32) {
				continue; // cut
			} else if (pad && shift >= 4) {
				buffer[pos++] = pad ? ' ' : '0';
				continue;
			}
		} else pad = false;
		buffer[pos++] = hexTable[b];
	}
	return pos;
}
/// 
@system unittest {
	char[32] b = void;
	char *p = b.ptr;
	assert(b[0..format8lux(p, 0)]               ==      "       0");
	assert(b[0..format8lux(p, 1)]               ==      "       1");
	assert(b[0..format8lux(p, 0x10)]            ==      "      10");
	assert(b[0..format8lux(p, 0x100)]           ==      "     100");
	assert(b[0..format8lux(p, 0x1000)]          ==      "    1000");
	assert(b[0..format8lux(p, 0x10000)]         ==      "   10000");
	assert(b[0..format8lux(p, 0x100000)]        ==      "  100000");
	assert(b[0..format8lux(p, 0x1000000)]       ==      " 1000000");
	assert(b[0..format8lux(p, 0x10000000)]      ==      "10000000");
	assert(b[0..format8lux(p, 0x100000000)]     ==     "100000000");
	assert(b[0..format8lux(p, 0x1000000000)]    ==    "1000000000");
	assert(b[0..format8lux(p, 0x10000000000)]   ==   "10000000000");
	assert(b[0..format8lux(p, 0x100000000000)]  ==  "100000000000");
	assert(b[0..format8lux(p, 0x1000000000000)] == "1000000000000");
	assert(b[0..format8lux(p, ubyte.max)]  ==         "      ff");
	assert(b[0..format8lux(p, ushort.max)] ==         "    ffff");
	assert(b[0..format8lux(p, uint.max)]   ==         "ffffffff");
	assert(b[0..format8lux(p, ulong.max)]  == "ffffffffffffffff");
	assert(b[0..format8lux(p, 0x1010)]             ==         "    1010");
	assert(b[0..format8lux(p, 0x10101010)]         ==         "10101010");
	assert(b[0..format8lux(p, 0x1010101010101010)] == "1010101010101010");
}
private
size_t format8lud(char *buffer, long v) {
	debug import std.conv : text;
	enum ulong I64MAX = 10_000_000_000_000_000_000UL;
	immutable static string decTable = "0123456789";
	size_t pos;
	bool pad = true;
	for (ulong d = I64MAX; d > 0; d /= 10) {
		const long r = (v / d) % 10;
		if (r == 0) {
			if (pad && d >= 100_000_000) {
				continue; // cut
			} else if (pad && d >= 10) {
				buffer[pos++] = pad ? ' ' : '0';
				continue;
			}
		} else pad = false;
		debug assert(r >= 0 && r < 10, "r="~r.text);
		buffer[pos++] = decTable[r];
	}
	return pos;
}
/// 
@system unittest {
	char[32] b = void;
	char *p = b.ptr;
	assert(b[0..format8lud(p, 0)]                 ==      "       0");
	assert(b[0..format8lud(p, 1)]                 ==      "       1");
	assert(b[0..format8lud(p, 10)]                ==      "      10");
	assert(b[0..format8lud(p, 100)]               ==      "     100");
	assert(b[0..format8lud(p, 1000)]              ==      "    1000");
	assert(b[0..format8lud(p, 10_000)]            ==      "   10000");
	assert(b[0..format8lud(p, 100_000)]           ==      "  100000");
	assert(b[0..format8lud(p, 1000_000)]          ==      " 1000000");
	assert(b[0..format8lud(p, 10_000_000)]        ==      "10000000");
	assert(b[0..format8lud(p, 100_000_000)]       ==     "100000000");
	assert(b[0..format8lud(p, 1000_000_000)]      ==    "1000000000");
	assert(b[0..format8lud(p, 10_000_000_000)]    ==   "10000000000");
	assert(b[0..format8lud(p, 100_000_000_000)]   ==  "100000000000");
	assert(b[0..format8lud(p, 1000_000_000_000)]  == "1000000000000");
	assert(b[0..format8lud(p, ubyte.max)]  ==             "     255");
	assert(b[0..format8lud(p, ushort.max)] ==             "   65535");
	assert(b[0..format8lud(p, uint.max)]   ==           "4294967295");
	assert(b[0..format8lud(p, ulong.max)]  == "18446744073709551615");
	assert(b[0..format8lud(p, 1010)]       ==             "    1010");
}
private
size_t format8luo(char *buffer, long v) {
	size_t pos;
	if (v >> 63) buffer[pos++] = '1'; // ulong.max coverage
	bool pad = true;
	for (int shift = 60; shift >= 0; shift -= 3) {
		const ubyte b = (v >> shift) & 7;
		if (b == 0) {
			if (pad && shift >= 24) {
				continue; // cut
			} else if (pad && shift >= 3) {
				buffer[pos++] = pad ? ' ' : '0';
				continue;
			}
		} else pad = false;
		buffer[pos++] = hexTable[b];
	}
	return pos;
}
/// 
@system unittest {
	import std.conv : octal;
	char[32] b = void;
	char *p = b.ptr;
	assert(b[0..format8luo(p, 0)]                     ==     "       0");
	assert(b[0..format8luo(p, 1)]                     ==     "       1");
	assert(b[0..format8luo(p, octal!10)]              ==     "      10");
	assert(b[0..format8luo(p, octal!20)]              ==     "      20");
	assert(b[0..format8luo(p, octal!100)]             ==     "     100");
	assert(b[0..format8luo(p, octal!1000)]            ==     "    1000");
	assert(b[0..format8luo(p, octal!10_000)]          ==     "   10000");
	assert(b[0..format8luo(p, octal!100_000)]         ==     "  100000");
	assert(b[0..format8luo(p, octal!1000_000)]        ==     " 1000000");
	assert(b[0..format8luo(p, octal!10_000_000)]      ==     "10000000");
	assert(b[0..format8luo(p, octal!100_000_000)]     ==    "100000000");
	assert(b[0..format8luo(p, octal!1000_000_000)]    ==   "1000000000");
	assert(b[0..format8luo(p, octal!10_000_000_000)]  ==  "10000000000");
	assert(b[0..format8luo(p, octal!100_000_000_000)] == "100000000000");
	assert(b[0..format8luo(p, ubyte.max)]   ==               "     377");
	assert(b[0..format8luo(p, ushort.max)]  ==               "  177777");
	assert(b[0..format8luo(p, uint.max)]    ==            "37777777777");
	assert(b[0..format8luo(p, ulong.max)]   == "1777777777777777777777");
	assert(b[0..format8luo(p, octal!101_010)]             == "  101010");
}

/// Update display from buffer
/// Returns: See ddhx_render_raw
uint ddhxDraw() {
	conpos(0, 1);
	return ddhxDrawRaw;
}

/// Write to stdout from file buffer
/// Returns: The number of lines printed
uint ddhxDrawRaw() {
	// data
	const(ubyte) *b    = globals.buffer.ptr;
	int           bsz  = cast(int)globals.buffer.length;
	size_t        bpos;
	
	// line buffer
	size_t     lpos = void;
	char[2048] lbuf   = void;	/// line buffer
	char      *l      = lbuf.ptr;
	uint       ls;	/// lines printed
	
	// formatting
	const int row = globals.rowWidth;
	size_t function(char*, long) formatOffset = offsetFuncs[globals.offset];
	//size_t function(char*, ubyte) formatData = dataFuncs[globals.dataMode];
	
	// print lines in bulk
	long pos = input.position;
	for (int left = bsz; left > 0; left -= row, pos += row, ++ls) {
		lpos = formatOffset(l, pos);
		l[lpos++] = ' ';
		
		const bool leftOvers = left < row;
		int bytesLeft = leftOvers ? left : row;
		
		size_t apos = (lpos + (row * 3)) + 2;
		for (ushort r; r < bytesLeft; ++r, ++apos, ++bpos) {
			const ubyte bt = b[bpos];
			l[lpos] = ' ';
			l[lpos+1] = hexTable[bt >> 4];
			l[lpos+2] = hexTable[bt & 15];
			lpos += 3; // += formatData(bt);
			l[apos] = bt > 0x7E || bt < 0x20 ? globals.defaultChar : bt;
		}
		
		lbuf[lpos] = ' ';	// hex + ' ' + ascii
		lbuf[lpos+1] = ' ';	// hex + ' ' + ascii
		lpos += 2;
		
		if (leftOvers) {
			bytesLeft = row - left;
			l[apos] = 0;
			do {
				l[lpos]   = ' ';
				l[lpos+1] = ' ';
				l[lpos+2] = ' ';
				lpos += 3;
			} while (--bytesLeft > 0);
			left = 0;
		} else lbuf[lpos + globals.rowWidth] = 0;
		
		puts(l);	// out with it + newline
	}
	
	return ls;
}

/**
 * Message once (upper bar)
 * Params: msg = Message string
 */
void ddhxMsgTop(A...)(string fmt, A args) {
	conpos(0, 0);
	ddhxMsg(fmt, args);
}

void ddhxMsgLow(A...)(string fmt, A args) {
	conpos(0, conheight - 1);
	ddhxMsg(fmt, args);
}

private void ddhxMsg(A...)(string fmt, A args) {
	import std.format : sformat;
	char[256] outbuf = void;
	char[] outs = outbuf[].sformat(fmt, args);
	writef("%s%*s", outs, (conwidth - 1) - outs.length, " ");
	stdout.flush();
}

/// Print some file information at the bottom bar
void ddhxMsgFileInfo() {
	with (globals)
	ddhxMsgLow("%s  %s", fileSizeString, fileName);
}

void ddhxExit(int code = 0) {
	import core.stdc.stdlib : exit;
	conclear;
	exit(code);
}
