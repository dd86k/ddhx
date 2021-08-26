/**
 * Main rendering engine.
 */
module ddhx;

import std.stdio : File, write, writeln, writef, writefln;
import std.file : getSize;
import std.mmfile;
import std.path : baseName;
import core.stdc.stdio : printf, fflush, puts, snprintf;
import core.stdc.string : memset;
import menu, ddcon;
import utils : formatsize, unformat;
import settings, error;

/// Copyright string
enum DDHX_COPYRIGHT = "Copyright (c) dd86k <dd@dax.moe> 2017-2021";

/// App version
enum DDHX_VERSION = "0.2.2-1";

/// Character table for header row
private immutable char[] offsetTable = [
	'h', 'd', 'o'
];
/// Character table for the main panel for printf
private immutable char[] formatTable = [
	'x', 'u', 'o'
];

//
// User settings
//

/// Global definitions and default values
struct Globals {
	// Settings
	long position;	/// Current file position
	ushort rowWidth = 16;	/// How many bytes are shown per row
	OffsetType offset;	/// Current offset view type
	DisplayMode display;	/// Current display view type
	union {
		File fileHandle;	/// Current File handle
		MmFile mmHandle;	/// Current mmFile handle
	}
	/// On-screen buffer
	/// File: Data buffer
	/// mmFile: Address buffer
	ubyte *buffer;
	uint bufferSize;	/// 
	string fileName;	/// filename
	long fileSize;	/// File size
	char defaultChar = '.';	/// Default character to use for non-ascii characters
	// Internals
	short termHeight;	///TODO: Last known terminal height
	short termWidth;	///TODO: Last known terminal width
	char[] fileSizeString;	/// Formatted binary size
}
/// Single-instance of globals.
__gshared Globals globals;

//TODO: bool mmfile
int ddhxLoad(string path) {
	try {
		// NOTE: zero-length file errors are weird so manual check here
		if ((globals.fileSize = getSize(path)) == 0)
			return ddhxError(DdhxError.fileEmpty);
		
		with (globals) mmHandle = new MmFile(
			(fileName = path), MmFile.Mode.read, 0, buffer);
	} catch (Exception ex) {
		return ddhxError(ex);
	}
	
	return false;
}

/// Main app entry point
void ddhxStart(ulong skip = 0) {
	__gshared char[32] fs = void;
	with (globals) {
		position = skip;
		fileSizeString = formatsize(fs, fileSize);
	}
	
	conclear;
	ddhxPrepBuffer;
	ddhxUpdateOffsetbar;
	
	if (ddhxDrawRaw < conheight - 2)
		ddhxUpdateInfobar;
	else
		ddhxUpdateInfobarRaw;

	InputInfo k;
KEY:
	coninput(k);
	with (globals) switch (k.value) {

	//
	// Navigation
	//

	case Key.UpArrow, Key.K:
		if (position - rowWidth >= 0)
			ddhxSeek(position - rowWidth);
		else
			ddhxSeek(0);
		break;
	case Key.DownArrow, Key.J:
		if (position + bufferSize + rowWidth <= fileSize)
			ddhxSeek(position + rowWidth);
		else
			ddhxSeek(fileSize - bufferSize);
		break;
	case Key.LeftArrow, Key.H:
		if (position - 1 >= 0) // Else already at 0
			ddhxSeek(position - 1);
		break;
	case Key.RightArrow, Key.L:
		if (position + bufferSize + 1 <= fileSize)
			ddhxSeek(position + 1);
		else
			ddhxSeek(fileSize - bufferSize);
		break;
	case Key.PageUp, Mouse.ScrollUp:
		if (position - cast(long)bufferSize >= 0)
			ddhxSeek(position - bufferSize);
		else
			ddhxSeek(0);
		break;
	case Key.PageDown, Mouse.ScrollDown:
		if (position + bufferSize + bufferSize <= fileSize)
			ddhxSeek(position + bufferSize);
		else
			ddhxSeek(fileSize - bufferSize);
		break;
	case Key.Home:
		ddhxSeek(k.key.ctrl ? 0 : position - (position % rowWidth));
		break;
	case Key.End:
		if (k.key.ctrl) {
			ddhxSeek(fileSize - bufferSize);
		} else {
			const long np = position + (rowWidth - position % rowWidth);
			ddhxSeek(np + bufferSize <= fileSize ? np : fileSize - bufferSize);
		}
		break;

	//
	// Actions/Shortcuts
	//

	case Key.Escape, Key.Enter, Key.Colon:
		hxmenu;
		break;
	case Key.G:
		hxmenu("g ");
		ddhxUpdateOffsetbar;
		break;
	case Key.I:
		ddhxShowFileInfo;
		break;
	case Key.R, Key.F5:
		ddhxRefresh;
		break;
	case Key.A:
		optionWidth("a");
		ddhxRefresh;
		break;
	case Key.Q: ddhx_exit; break;
	default:
	}
	goto KEY;
}

/// Refresh the entire screen
void ddhxRefresh() {
	ddhxPrepBuffer;
	conclear;
	ddhxUpdateOffsetbar;
	if (ddhxDrawRaw < conheight - 2)
		ddhxUpdateInfobar;
	else
		ddhxUpdateInfobarRaw;
}

/**
 * Update the upper offset bar.
 */
void ddhxUpdateOffsetbar() {
	static char[8] fmt = " %02x";
	fmt[4] = formatTable[globals.offset];
	conpos(0, 0);
	printf("Offset %c ", offsetTable[globals.offset]);
	for (ushort i; i < globals.rowWidth; ++i)
		printf(cast(char*)fmt, i);
	putchar('\n');
}

/// Update the bottom current information bar.
void ddhxUpdateInfobar() {
	conpos(0, conheight - 1);
	ddhxUpdateInfobarRaw;
}

/// Updates information bar without cursor position call.
void ddhxUpdateInfobarRaw() {
	char[32] bf = void, po = void;
	with (globals) writef(" %*s | %*s/%*s | %7.3f%%",
		7,  formatsize(bf, bufferSize), // Buffer size
		10, formatsize(po, position), // Formatted position
		10, fileSizeString, // Total file size
		((cast(float)position + bufferSize) / fileSize) * 100 // Pos/filesize%
	);
}

/// Determine screensize and buffer size
void ddhxPrepBuffer() {
	with (globals) {
		const int newSize = (conheight - 2) * rowWidth; // Proposed buffer size
		bufferSize = fileSize >= newSize ? newSize : cast(uint)fileSize;
	}
}

/**
 * Goes to the specified position in the file.
 * Ignores bounds checking for performance reasons.
 * Sets CurrentPosition.
 * Params: pos = New position
 */
void ddhxSeek(long pos) {
	if (globals.bufferSize < globals.fileSize) {
		globals.position = pos;
		if (ddhxDraw < conheight - 2)
			ddhxUpdateInfobar;
		else
			ddhxUpdateInfobarRaw;
	} else
		ddhxMsgLow("Navigation disabled, buffer too small");
}

/**
 * Goes to the specified position in the file.
 * Checks bounds and calls Goto.
 * Params: pos = New position
 */
void ddhxSeekSafe(long pos) {
	if (pos + globals.bufferSize > globals.fileSize)
		ddhxSeek(globals.fileSize - globals.bufferSize);
	else
		ddhxSeek(pos);
}

/**
 * Parses the string as a long and navigates to the file location.
 * Includes offset checking (+/- notation).
 * Params: str = String as a number
 */
void ddhxSeek(string str) {
	const char mode = str[0];
	if (mode == '+') { // relative position
		str = str[1..$];
	} else if (mode == '-') {
		str = str[1..$];
	}
	long newPos = void;
	if (unformat(str, newPos) == false) {
		ddhxMsgLow("Could not parse number");
		return;
	}
	with (globals) switch (mode) {
	case '+':
		newPos = position + newPos;
		if (newPos - bufferSize < fileSize)
			ddhxSeek(newPos);
		break;
	case '-':
		newPos = position - newPos;
		if (newPos >= 0)
			ddhxSeek(newPos);
		break;
	default:
		if (newPos >= 0 && newPos < fileSize - bufferSize) {
			ddhxSeek(newPos);
		} else {
			import std.format : format;
			ddhxMsgLow("Range too far or negative: %d (%xH)", newPos, newPos);
		}
	}
}

/// Update display from buffer
/// Returns: See ddhx_render_raw
uint ddhxDraw() {
	conpos(0, 1);
	return ddhxDrawRaw;
}

/// Update display from buffer without setting cursor
/// Returns: The number of lines printed on screen
uint ddhxDrawRaw() {
	static immutable string hexTable = "0123456789abcdef";
	static immutable const(char)*[] offTable = [ "%8zx ", "%8zo ", "%8zd " ];
	
	uint linesp; /// Lines printed
	char[2048] buf = void;
	char *bufptr = cast(char*)&buf[0];
	
	size_t viewpos = cast(size_t)globals.position;
	size_t viewend = viewpos + globals.fileSize; /// window length
	ubyte *filebuf = cast(ubyte*)globals.mmHandle[viewpos..viewend].ptr;
	
	const(char) *fposfmt = offTable[globals.offset];
	
	// vi: view index
	for (size_t vi; vi < globals.bufferSize; viewpos += globals.rowWidth) {
		// Offset column: Cannot be negative since the buffer will
		// always be large enough
		size_t bufindex = snprintf(bufptr, 32, fposfmt, viewpos);
		
		// data bytes left to be treated for the row
		size_t left = globals.bufferSize - vi;
		
		if (left >= globals.rowWidth) {
			left = globals.rowWidth;
		} else { // left < g_rowwidth
			memset(bufptr + bufindex, ' ', 2048);
		}
		
		// Data buffering (hexadecimal and ascii)
		size_t hi = bufindex; /// hex buffer offset
		size_t ai = bufindex + (globals.rowWidth * 3); /// ascii buffer offset
		buf[ai] = buf[ai + 1] = ' ';
		for (ai += 2; left > 0; --left, hi += 3, ++ai) {
			const ubyte b = filebuf[vi++];
			buf[hi] = ' ';
			buf[hi+1] = hexTable[b >> 4];
			buf[hi+2] = hexTable[b & 15];
			buf[ai] = b > 0x7E || b < 0x20 ? globals.defaultChar : b;
		}
		
		buf[ai] = 0;	// null it
		puts(bufptr);	// out with it
		++linesp;
	}

	return linesp;
}

/**
 * Message once (upper bar)
 * Params: msg = Message string
 */
void ddhxMsgTop(A ...)(string fmt, A args) {
	import std.format : sformat;
	char[256] outbuf = void;
	char[] outs = outbuf[].sformat(fmt, args);
	conpos(0, 0);
	writef("%s%*s", outs, (conwidth - 1) - outs.length, " ");
}

void ddhxMsgLow(A ...)(string fmt, A args) {
	import std.format : sformat;
	char[256] outbuf = void;
	char[] outs = outbuf[].sformat(fmt, args);
	conpos(0, conheight - 1);
	writef("%s%*s", outs, (conwidth - 1) - outs.length, " ");
}

/// Print some file information at the bottom bar
void ddhxShowFileInfo() {
	with (globals)
	ddhxMsgLow("%s  %s", fileSizeString, baseName(fileName));
}

/// Exits ddhx
void ddhx_exit(int code = 0) {
	import core.stdc.stdlib : exit;
	conclear;
	exit(code);
}
