/**
 * Main rendering engine.
 */
module ddhx;

import std.stdio : write, writeln, writef, writefln;
import std.file : getSize;
import std.mmfile;
import core.stdc.stdio : printf, fflush, puts, snprintf;
import core.stdc.string : memset;
import menu, ddcon;
import utils : formatsize, unformat;

__gshared:

/// Copyright string
enum COPYRIGHT = "Copyright (c) dd86k <dd@dax.moe> 2017-2021";

/// App version
enum APP_VERSION = "0.2.2";

/// Offset type (hex, dec, etc.)
enum OffsetType {
	Hex, Decimal, Octal
}

/// 
enum DisplayMode {
	Default, Text, Data
}

/// Default character for non-displayable characters
enum DEFAULT_CHAR = '.';

/// Character table for header row
private immutable char[] offsetTable = [
	'h', 'd', 'o'
];
/// Character table for the main panel for printf
private immutable char[] formatTable = [
	'X', 'u', 'o'
];

//
// User settings
//

//TODO: Mark these as private and have a function to set them

/// How many bytes are shown per row
ushort g_rowwidth = 16;
/// Current offset view type
OffsetType g_offsettype = void;
/// Current display view type
DisplayMode g_displaymode = void;

MmFile g_fhandle;	/// Current file handle
ubyte* g_fmmbuf;	/// mmfile buffer address
uint g_screenl;	/// screen size in bytes, 1 dimensional buffer
string g_fname;	/// filename
long g_fpos;	/// Current file position
long g_fsize;	/// File size

private char[32] g_fsizebuf;	/// total formatted size buffer
private char[] g_fsizeout;	/// total formatted size (slice)
private Exception lastEx;	/// Last exception

/// Load file
/// Params: path = Path of file to open
/// Returns: true on error
bool ddhx_file(string path) {
	try {
		// NOTE: zero-length file errors are weird so manual check here
		if ((g_fsize = getSize(path)) == 0)
			throw new Exception("Empty file");
		
		g_fhandle = new MmFile((g_fname = path), MmFile.Mode.read, 0, g_fmmbuf);
	} catch (Exception ex) {
		lastEx = ex;
		return true;
	}
	
	return false;
}

/// Print lastException to stderr. Useful for command-line.
/// Params: mod = Module or function name
void ddhx_error(string mod) {
	import std.stdio : stderr;
	debug stderr.writefln("%s: (%s L%d) %s",
		mod, lastEx.file, lastEx.line, lastEx.msg);
	else  stderr.writefln("%s: %s",
		mod, lastEx.msg);
}

/// Get last exception.
/// Returns: Last exception
Exception ddhx_exception() {
	return lastEx;
}

/// Main app entry point
void ddhx_main() {
	g_fsizeout = formatsize(g_fsizebuf, g_fsize);
	conclear;
	ddhx_prep;
	ddhx_update_offsetbar;
	
	if (ddhx_render_raw < conheight - 2)
		ddhx_update_infobar;
	else
		ddhx_update_infobar_raw;

	InputInfo k;
KEY:
	coninput(k);
	switch (k.value) {

	//
	// Navigation
	//

	case Key.UpArrow, Key.K:
		if (g_fpos - g_rowwidth >= 0)
			ddhx_seek_unsafe(g_fpos - g_rowwidth);
		else
			ddhx_seek_unsafe(0);
		break;
	case Key.DownArrow, Key.J:
		if (g_fpos + g_screenl + g_rowwidth <= g_fsize)
			ddhx_seek_unsafe(g_fpos + g_rowwidth);
		else
			ddhx_seek_unsafe(g_fsize - g_screenl);
		break;
	case Key.LeftArrow, Key.H:
		if (g_fpos - 1 >= 0) // Else already at 0
			ddhx_seek_unsafe(g_fpos - 1);
		break;
	case Key.RightArrow, Key.L:
		if (g_fpos + g_screenl + 1 <= g_fsize)
			ddhx_seek_unsafe(g_fpos + 1);
		else
			ddhx_seek_unsafe(g_fsize - g_screenl);
		break;
	case Key.PageUp, Mouse.ScrollUp:
		if (g_fpos - cast(long)g_screenl >= 0)
			ddhx_seek_unsafe(g_fpos - g_screenl);
		else
			ddhx_seek_unsafe(0);
		break;
	case Key.PageDown, Mouse.ScrollDown:
		if (g_fpos + g_screenl + g_screenl <= g_fsize)
			ddhx_seek_unsafe(g_fpos + g_screenl);
		else
			ddhx_seek_unsafe(g_fsize - g_screenl);
		break;
	case Key.Home:
		ddhx_seek_unsafe(k.key.ctrl ? 0 : g_fpos - (g_fpos % g_rowwidth));
		break;
	case Key.End:
		if (k.key.ctrl) {
			ddhx_seek_unsafe(g_fsize - g_screenl);
		} else {
			const long np = g_fpos +
				(g_rowwidth - g_fpos % g_rowwidth);
			ddhx_seek_unsafe(np + g_screenl <= g_fsize ? np : g_fsize - g_screenl);
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
		ddhx_update_offsetbar();
		break;
	case Key.I:
		ddhx_fileinfo;
		break;
	case Key.R, Key.F5:
		ddhx_refresh;
		break;
	case Key.A:
		ddhx_setting_width("a");
		ddhx_refresh;
		break;
	case Key.Q: ddhx_exit; break;
	default:
	}
	goto KEY;
}

/// Set the ouput mode.
/// Params: v = Setting value
/// Returns: true on error
bool ddhx_setting_output(string v) {
	switch (v[0]) {
	case 'o', 'O': g_offsettype = OffsetType.Octal; break;
	case 'd', 'D': g_offsettype = OffsetType.Decimal; break;
	case 'h', 'H': g_offsettype = OffsetType.Hex; break;
	default: return true;
	}
	return false;
}

/// Set the column width in bytes
/// Params: v = Value
/// Returns: true on error
bool ddhx_setting_width(string v) {
	switch (v[0]) {
	case 'a': // Automatic
		final switch (g_displaymode)
		{
		case DisplayMode.Default:
			g_rowwidth = cast(ushort)((conwidth - 11) / 4);
			break;
		case DisplayMode.Text, DisplayMode.Data:
			g_rowwidth = cast(ushort)((conwidth - 11) / 3);
			break;
		}
		break;
	case 'd': // Default
		g_rowwidth = 16;
		break;
	default:
		long l;
		if (unformat(v, l) == false) {
			lastEx = new Exception("width: Number could not be formatted");
			return true;
		}
		if (l < 1 || l > ushort.max) {
			lastEx = new Exception("width: Number out of range");
			return true;
		}
		g_rowwidth = cast(ushort)l;
	}
	return false;
}

/// Refresh the entire screen
void ddhx_refresh() {
	ddhx_prep;
	conclear;
	ddhx_update_offsetbar;
	if (ddhx_render_raw < conheight - 2)
		ddhx_update_infobar;
	else
		ddhx_update_infobar_raw;
}

/**
 * Update the upper offset bar.
 */
void ddhx_update_offsetbar() {
	char [8]format = cast(char[8])" %02X"; // default
	format[4] = formatTable[g_offsettype];
	conpos(0, 0);
	printf("Offset %c ", offsetTable[g_offsettype]);
	for (ushort i; i < g_rowwidth; ++i)
		printf(cast(char*)format, i);
	putchar('\n');
}

/// Update the bottom current information bar.
void ddhx_update_infobar() {
	conpos(0, conheight - 1);
	ddhx_update_infobar_raw;
}

/// Updates information bar without cursor position call.
void ddhx_update_infobar_raw() {
	char[32] bl = void, cp = void;
	writef(" %*s | %*s/%*s | %7.3f%%",
		7,  formatsize(bl, g_screenl), // Buffer size
		10, formatsize(cp, g_fpos), // Formatted position
		10, g_fsizeout, // Total file size
		((cast(float)g_fpos + g_screenl) / g_fsize) * 100 // Pos/filesize%
	);
}

/// Determine screensize
void ddhx_prep() {
	const int bufs = (conheight - 2) * g_rowwidth; // Proposed buffer size
	g_screenl = g_fsize >= bufs ? bufs : cast(uint)g_fsize;
}

/**
 * Goes to the specified position in the file.
 * Ignores bounds checking for performance reasons.
 * Sets CurrentPosition.
 * Params: pos = New position
 */
void ddhx_seek_unsafe(long pos) {
	if (g_screenl < g_fsize) {
		g_fpos = pos;
		if (ddhx_render < conheight - 2)
			ddhx_update_infobar;
		else
			ddhx_update_infobar_raw;
	} else
		ddhx_msglow("Navigation disabled, buffer too small");
}

/**
 * Goes to the specified position in the file.
 * Checks bounds and calls Goto.
 * Params: pos = New position
 */
void ddhx_seek(long pos) {
	if (pos + g_screenl > g_fsize)
		ddhx_seek_unsafe(g_fsize - g_screenl);
	else
		ddhx_seek_unsafe(pos);
}

/**
 * Parses the string as a long and navigates to the file location.
 * Includes offset checking (+/- notation).
 * Params: str = String as a number
 */
void ddhx_seek(string str) {
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
		ddhx_msglow("Could not parse number");
		return;
	}
	switch (rel) {
	case 1:
		if (g_fpos + l - g_screenl < g_fsize)
			ddhx_seek_unsafe(g_fpos + l);
		break;
	case 2:
		if (g_fpos - l >= 0)
			ddhx_seek_unsafe(g_fpos - l);
		break;
	default:
		if (l >= 0 && l < g_fsize - g_screenl) {
			ddhx_seek_unsafe(l);
		} else {
			import std.format : format;
			ddhx_msglow(format("Range too far or negative: %d (%XH)", l, l));
		}
	}
}

/// Update display from buffer
/// Returns: See ddhx_render_raw
uint ddhx_render() {
	conpos(0, 1);
	return ddhx_render_raw;
}

/// Update display from buffer without setting cursor
/// Returns: The number of lines printed on screen
uint ddhx_render_raw() {
	__gshared char[] hexTable = [
		'0', '1', '2', '3', '4', '5', '6', '7',
		'8', '9', 'A', 'B', 'C', 'D', 'E', 'F',
	];

	uint linesp; /// Lines printed
	char[2048] buf = void;

	size_t viewpos = cast(size_t)g_fpos;
	size_t viewend = viewpos + g_screenl; /// window length
	ubyte *filebuf = cast(ubyte*)g_fhandle[viewpos..viewend].ptr;

	const(char) *fposfmt = void;
	with (OffsetType)
	final switch (g_offsettype) {
	case Hex:	fposfmt = "%8zX "; break;
	case Octal:	fposfmt = "%8zo "; break;
	case Decimal:	fposfmt = "%8zd "; break;
	}

	// vi: view index
	for (size_t vi; vi < g_screenl; viewpos += g_rowwidth) {
		// Offset column: Cannot be negative since the buffer will
		// always be large enough
		size_t bufindex = snprintf(buf.ptr, 32, fposfmt, viewpos);

		// data bytes left to be treated for the row
		size_t left = g_screenl - vi;

		if (left >= g_rowwidth) {
			left = g_rowwidth;
		} else { // left < g_rowwidth
			memset(buf.ptr + bufindex, ' ', 2048);
		}

		// Data buffering (hexadecimal and ascii)
		// hi: hex buffer offset
		// ai: ascii buffer offset
		size_t hi = bufindex;
		size_t ai = bufindex + (g_rowwidth * 3);
		buf[ai] = ' ';
		buf[ai+1] = ' ';
		for (ai += 2; left > 0; --left, hi += 3, ++ai) {
			ubyte b = filebuf[vi++];
			buf[hi] = ' ';
			buf[hi+1] = hexTable[b >> 4];
			buf[hi+2] = hexTable[b & 15];
			buf[ai] = b > 0x7E || b < 0x20 ? DEFAULT_CHAR : b;
		}

		// null terminator
		buf[ai] = 0;

		// Output
		puts(buf.ptr);
		++linesp;
	}

	return linesp;
}

/**
 * Message once (upper bar)
 * Params: msg = Message string
 */
void ddhx_msgtop(string msg) {
	conpos(0, 0);
	writef("%s%*s", msg, (conwidth - 1) - msg.length, " ");
}

/**
 * Message once (bottom bar)
 * Params: msg = Message string
 */
void ddhx_msglow(string msg) {
	conpos(0, conheight - 1);
	writef("%s%*s", msg, (conwidth - 1) - msg.length, " ");
}

/**
 * Bottom bar message.
 * Params:
 *   f = Format
 *   arg = String argument
 */
void ddhx_msglow(string f, string arg) {
	//TODO: (string format, ...) format, remove other (string) func
	import std.format : format;
	ddhx_msglow(format(f, arg));
}

/// Print some file information at the bottom bar
void ddhx_fileinfo() {
	import std.format : sformat;
	import std.path : baseName;
	char[256] b = void;
	//TODO: Use ddhx_msglow(string fmt, ...) whenever available
	ddhx_msglow(cast(string)b.sformat!"%s  %s"(g_fsizeout, g_fname.baseName));
}

/// Exits ddhx
void ddhx_exit() {
	import core.stdc.stdlib : exit;
	conclear;
	exit(0);
}
