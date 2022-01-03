/// The heart of the machine, the rendering display.
/// 
/// This accommodates all functions related to rendering elements on screen,
/// which includes the upper offset bar, data view (offsets, data, and text),
/// and bottom message bar.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module ddhx.display;

import std.stdio : stdout;
import core.stdc.stdio : printf, puts;
import core.stdc.wchar_ : wchar_t;
import ddhx;

//TODO: Engine struct settings
//      Pre-assign formatting functions when changing options
//      Maybe have setXXX functions?
//TODO: Groups
//      e.g., cd ab -> abcd
//TODO: Group endianness
//TODO: View display mode (hex+ascii, hex, ascii)
//TODO: Data display mode (hex, octal, dec)

private extern (C) int putchar(int);

/// Character table for header row
private immutable char[3] offsetTable = [ 'h', 'd', 'o' ];
/// Character table for the main panel for printf
private immutable char[3] formatTable = [ 'x', 'u', 'o' ];

// For offset views

/// Offset format functions
private immutable size_t function(char*,long)[3] offsetFuncs =
	[ &format8lux, &format8lud, &format8luo ];
//
//private immutable size_t function(char*,ushort) offsetUpFuncs =


// For main data panel

// Data format functions
//private immutable size_t function(char*,long)[] dataFuncs =
//	[ &format2x, &format3d, &format3o ];
/// Character translations functions
private immutable dchar function(ubyte)[4] charFuncs = [
	&translateASCII,
	&translateCP437,
	&translateEBCDIC,
//	&translateGSM
];

//
// SECTION Formatting
//

private immutable static string hexMap = "0123456789abcdef";

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
		buffer[pos++] = hexMap[b];
	}
	return pos;
}
/// 
@system unittest {
	char[32] b = void;
	char *p = b.ptr;
	assert(b[0..format8lux(p, 0)]                  ==         "       0");
	assert(b[0..format8lux(p, 1)]                  ==         "       1");
	assert(b[0..format8lux(p, 0x10)]               ==         "      10");
	assert(b[0..format8lux(p, 0x100)]              ==         "     100");
	assert(b[0..format8lux(p, 0x1000)]             ==         "    1000");
	assert(b[0..format8lux(p, 0x10000)]            ==         "   10000");
	assert(b[0..format8lux(p, 0x100000)]           ==         "  100000");
	assert(b[0..format8lux(p, 0x1000000)]          ==         " 1000000");
	assert(b[0..format8lux(p, 0x10000000)]         ==         "10000000");
	assert(b[0..format8lux(p, 0x100000000)]        ==        "100000000");
	assert(b[0..format8lux(p, 0x1000000000)]       ==       "1000000000");
	assert(b[0..format8lux(p, 0x10000000000)]      ==      "10000000000");
	assert(b[0..format8lux(p, 0x100000000000)]     ==     "100000000000");
	assert(b[0..format8lux(p, 0x1000000000000)]    ==    "1000000000000");
	assert(b[0..format8lux(p, ubyte.max)]          ==         "      ff");
	assert(b[0..format8lux(p, ushort.max)]         ==         "    ffff");
	assert(b[0..format8lux(p, uint.max)]           ==         "ffffffff");
	assert(b[0..format8lux(p, ulong.max)]          == "ffffffffffffffff");
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
		buffer[pos++] = hexMap[b];
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

// !SECTION

//
// SECTION Character translation
//

//TODO: Directly encode utf-8 into tables
//      In theory should be a little faster than transcoding from wchar/dchar
//      Could be:
//      - uint
//      - char[3]
//      - char[] (length embedded) + codeUnits!char('.')
//      - a custom structure (how?)
//TODO: size_t insertCP437(char *data, size_t left);
//TODO: Other translations
//      - Mac OS Roman (Windows-10000) "mac"
//        https://en.wikipedia.org/wiki/Mac_OS_Roman
//      - Windows-1251 "win1251"
//        https://en.wikipedia.org/wiki/Windows-1251
//      - Windows-932 "win932"
//        https://en.wikipedia.org/wiki/Code_page_932_(Microsoft_Windows)
//      - ITU T.61 "t61"
//        https://en.wikipedia.org/wiki/ITU_T.61
//      - GSM 03.38 "gsm"
//        https://www.unicode.org/Public/MAPPINGS/ETSI/GSM0338.TXT

private immutable dchar[256] charsCP437 = [
//       00   01   02   03   04   05   06   07   08   09   0a   0b   0c   0d   0e   0f
/*0x*/	  0, '☺', '☻', '♥', '♦', '♣', '♠', '•', '◘', '○', '◙', '♂', '♀', '♪', '♫', '☼',
/*1x*/	'►', '◄', '↕', '‼', '¶', '§', '▬', '↨', '↑', '↓', '→', '←', '∟', '↔', '▲', '▼',
/*2x*/	' ', '!', '"', '#', '$', '%', '&','\'', '(', ')', '*', '+', ',', '-', '.', '/',
/*3x*/	'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '>', '=', '?',
/*4x*/	'@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'M', 'N', 'L', 'O',
/*5x*/	'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[','\\', ']', '^', '_',
/*6x*/	'`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'm', 'n', 'l', 'o',
/*7x*/	'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~', '⌂',
/*8x*/	'Ç', 'ü', 'é', 'â', 'ä', 'à', 'å', 'ç', 'ê', 'ë', 'è', 'ï', 'î', 'ì', 'Ä', 'Å',
/*9x*/	'É', 'æ', 'Æ', 'ô', 'ö', 'ò', 'û', 'ù', 'ÿ', 'Ö', 'Ü', '¢', '£', '¥', '₧', 'ƒ',
/*Ax*/	'á', 'í', 'ó', 'ú', 'ñ', 'Ñ', 'ª', 'º', '¿', '⌐', '¬', '½', '¼', '¡', '«', '»',
/*Bx*/	'░', '▒', '▓', '│', '┤', '╡', '╢', '╖', '╕', '╣', '║', '╗', '╝', '╜', '╛', '┐',
/*Cx*/	'└', '┴', '┬', '├', '─', '┼', '╞', '╟', '╚', '╔', '╩', '╦', '╠', '═', '╬', '╧',
/*Dx*/	'╨', '╤', '╥', '╙', '╘', '╒', '╓', '╫', '╪', '┘', '┌', '█', '▄', '▌', '▐', '▀',
/*Ex*/	'α', 'β', 'Γ', 'π', 'Σ', 'σ', 'µ', 'τ', 'Φ', 'Θ', 'Ω', 'δ', '∞', 'φ', 'ε', '∩',
/*Fx*/	'≡', '±', '≥', '≤', '⌠', '⌡', '÷', '≈', '°', '∙', '·', '√', 'ⁿ', '²', '■',   0
];
private immutable dchar[256] charsEBCDIC = [
//       00   01   02   03   04   05   06   07   08   09   0a   0b   0c   0d   0e   0f
/*0x*/	  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
/*1x*/	  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
/*2x*/	  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
/*3x*/	  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
/*4x*/	' ', ' ', 'â', 'ä', 'à', 'á', 'ã', 'å', 'ç', 'ñ', '¢', '.', '<', '(', '+', '|',
/*5x*/	'&', 'é', 'ê', 'ë', 'è', 'í', 'î', 'ï', 'ì', 'ß', '!', '$', '*', ')', ';', '¬',
/*6x*/	'-', '/', 'Â', 'Ä', 'À', 'Á', 'Ã', 'Å', 'Ç', 'Ñ', '¦', ',', '%', '_', '>', '?',
/*7x*/	'ø', 'É', 'Ê', 'Ë', 'È', 'Í', 'Î', 'Ï', 'Ì', '`', ':', '#', '@','\'', '=', '"',
/*8x*/	'Ø', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', '«', '»', 'ð', 'ý', 'þ', '±',
/*9x*/	'°', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 'ª', 'º', 'æ', '¸', 'Æ', '¤',
/*Ax*/	'µ', '~', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '¡', '¿', 'Ð', 'Ý', 'Þ', '®',
/*Bx*/	'^', '£', '¥', '·', '©', '§', '¶', '¼', '½', '¾', '[', ']', '¯', '¨', '´', '×',
/*Cx*/	'{', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I',   0, 'ô', 'ö', 'ò', 'ó', 'õ',
/*Dx*/	'}', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', '¹', 'û', 'ü', 'ù', 'ú', 'ÿ',
/*Ex*/	'\\','÷', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '²', 'Ô', 'Ö', 'Ò', 'Ó', 'Õ',
/*Fx*/	'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '³', 'Û', 'Ü', 'Ù', 'Ú',   0
];
private
dchar translateASCII(ubyte data) {
	return data > 0x7E || data < 0x20 ? globals.defaultChar : data;
}
private
dchar translateEBCDIC(ubyte data) {
	return charsEBCDIC[data];
}
private
dchar translateCP437(ubyte data) {
	return charsCP437[data];
}

// !SECTION

void displayResizeBuffer(uint size) {
	version (Trace) trace("size=%u", size);
	input.adjust(size);
}

/// Update the upper offset bar.
void displayRenderTop() {
	terminalPos(0, 0);
	displayRenderTopRaw();
}

/// 
void displayRenderTopRaw() {
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
	
	__gshared char[8] fmt = " %2x";
	int type = globals.offsetType;
	fmt[3] = formatTable[type];
	printf("Offset %c ", offsetTable[type]);
	if (input.position > 0xffff_ffff) putchar(' ');
	if (input.position > 0xffff_ffff_f) putchar(' ');
	for (ushort i; i < globals.rowWidth; ++i)
		printf(cast(char*)fmt, i);
	putchar('\n');
}

/// Update the bottom current information bar.
void displayRenderBottom() {
	terminalPos(0, terminalSize.height - 1);
	displayRenderBottomRaw;
}

/// Updates information bar without cursor position call.
void displayRenderBottomRaw() {
	import std.format : sformat;
	import std.stdio : writef, write;
	__gshared size_t last;
	char[32] c = void, t = void;
	char[128] b = void;
	char[] f = sformat!" %*s | %*s/%*s | %7.4f%%-%7.4f%%"(b,
		5,  formatSize(c, input.bufferSize), // Buffer size
		10, formatSize(t, input.position), // Formatted position
		10, input.sizeString, // Total file size
		((cast(float)input.position) / input.size) * 100, // Pos/input.size%
		((cast(float)input.position + input.bufferSize) / input.size) * 100, // Pos/input.size%
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

/// Update display from buffer.
/// Returns: Numbers of row written.
uint displayRenderMain() {
	terminalPos(0, 1);
	return displayRenderMainRaw;
}

//TODO: Possibility to only redraw a specific line.
//      Or just bottom or top.
/// Update display from buffer.
/// Returns: Numbers of row written.
uint displayRenderMainRaw() {
	// data
	const(ubyte) *b    = input.result.ptr;	/// data buffer pointer
	int           bsz  = cast(int)input.result.length;	/// data buffer size
	size_t        bpos;	// data buffer position index
	
	// line buffer
	size_t     lpos = void;	/// line buffer index position
	char[2048] lbuf   = void;	/// line buffer
	char      *lptr      = lbuf.ptr;
	uint       ls;	/// lines printed
	
	// setup
	const int rowMax = globals.rowWidth;
	const char defaultChar = globals.defaultChar;
	const int offsetType = globals.offsetType;
//	const int dataType = globals.dataType;
	const int charset = globals.charType;
	size_t function(char*, long) formatOffset = offsetFuncs[offsetType];
//	size_t function(char*, ubyte) formatData = dataFuncs[globals.dataMode];
	dchar function(ubyte) translateChar = charFuncs[charset];
	
	// print lines in bulk
	long pos = input.position;
	for (int left = bsz; left > 0; left -= rowMax, pos += rowMax, ++ls) {
		// Insert OFFSET
		lpos = formatOffset(lptr, pos);
		lbuf[lpos++] = ' '; //lptr
		
		// Line setup
		const bool leftOvers = left < rowMax;
		int bytesLeft = leftOvers ? left : rowMax;
		
		// Insert DATA and CHAR
		size_t cpos = (lpos + (rowMax * 3)) + 2;
		for (ushort r; r < bytesLeft; ++r, ++cpos, ++bpos) {
			const ubyte byteData = b[bpos];
			// Data translation
			lbuf[lpos] = ' ';
			lbuf[lpos+1] = hexMap[byteData >> 4];
			lbuf[lpos+2] = hexMap[byteData & 15];
			lpos += 3;
			// Character translation
			// NOTE: Translated to UTF-8 for these reasons:
			//       - UTF-16 and UTF-32 on Windows is only supported for .NET.
			//       - Most Linux terminals do UTF-8 by default.
			dchar c = translateChar(byteData);
			if (c) {
				import std.encoding : codeUnits, CodeUnits;
				CodeUnits!char cu = codeUnits!char(c);
				const size_t len = cu.s.length;
				lbuf[cpos] = cu.s[0];
				if (len < 2) continue;
				lbuf[++cpos] = cu.s[1];
				if (len < 3) continue;
				lbuf[++cpos] = cu.s[2];
				if (len < 4) continue;
				lbuf[++cpos] = cu.s[3];
			} else {
				lbuf[cpos] = defaultChar;
			}
		}
		
		// Spacer between DATA and CHAR panels
		lbuf[lpos] = ' ';
		lbuf[lpos+1] = ' ';
		lpos += 2;
		
		// Line DATA leftovers
		if (leftOvers) {
			bytesLeft = rowMax - left;
			do {
				lbuf[lpos]   = ' ';
				lbuf[lpos+1] = ' ';
				lbuf[lpos+2] = ' ';
				lpos += 3;
			} while (--bytesLeft > 0);
			left = 0;
		}
		
		// Terminate line and send
		lbuf[cpos] = 0;
		puts(lptr);	// print line result + newline
	}
	
	return ls;
}