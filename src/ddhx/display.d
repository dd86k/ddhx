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
import std.encoding : codeUnits, CodeUnits;
import core.stdc.stdio : printf, puts;
import ddhx;

//TODO: Engine struct settings
//      Pre-assign formatting functions when changing options
//      Maybe have setXXX functions?
//TODO: Groups
//      e.g., cd ab -> abcd
//TODO: Group endianness
//TODO: View display mode (hex+ascii, hex, ascii)
//TODO: Data display mode (hex, octal, dec)
//TODO: Consider hiding cursor when drawing
//      terminalHideCursor()
//        windows: SetConsoleCursorInfo
//                 https://docs.microsoft.com/en-us/windows/console/setconsolecursorinfo
//        posix: \033[?25l
//      terminalShowCursor()
//        windows: SetConsoleCursorInfo
//        posix: \033[?25h

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
/// Character transcoding functions
private immutable char[] function(ubyte)[4] transFuncs = [
	&transcodeASCII,
	&transcodeCP437,
	&transcodeEBCDIC,
//	&transcodeGSM
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

private alias U  = char[];
private alias CU = CodeUnits!char;
private template C(dchar c) {
	enum C = codeUnits!char(c).s;
}

private
char[] transcodeASCII(ubyte data) {
	__gshared char[]  empty;
	__gshared char[1] c;
	if (data > 0x7E || data < 0x20)
		return empty;
	
	c[0] = data;
	return c;
}
private U[256] mapCP437 = [
//          0      1      2      3      4      5      6      7
/*00*/	   [], C!'☺', C!'☻', C!'♥', C!'♦', C!'♣', C!'♠', C!'•',
/*08*/	C!'◘', C!'○', C!'◙', C!'♂', C!'♀', C!'♪', C!'♫', C!'☼',
/*10*/	C!'►', C!'◄', C!'↕', C!'‼', C!'¶', C!'§', C!'▬', C!'↨',
/*18*/	C!'↑', C!'↓', C!'→', C!'←', C!'∟', C!'↔', C!'▲', C!'▼',
/*20*/	C!' ', C!'!', C!'"', C!'#', C!'$', C!'%', C!'&', C!'\'',
/*28*/	C!'(', C!')', C!'*', C!'+', C!',', C!'-', C!'.', C!'/',
/*30*/	C!'0', C!'1', C!'2', C!'3', C!'4', C!'5', C!'6', C!'7',
/*38*/	C!'8', C!'9', C!':', C!';', C!'<', C!'>', C!'=', C!'?',
/*40*/	C!'@', C!'A', C!'B', C!'C', C!'D', C!'E', C!'F', C!'G',
/*48*/	C!'H', C!'I', C!'J', C!'K', C!'M', C!'N', C!'L', C!'O',
/*50*/	C!'P', C!'Q', C!'R', C!'S', C!'T', C!'U', C!'V', C!'W',
/*58*/	C!'X', C!'Y', C!'Z', C!'[',C!'\\', C!']', C!'^', C!'_',
/*60*/	C!'`', C!'a', C!'b', C!'c', C!'d', C!'e', C!'f', C!'g',
/*68*/	C!'h', C!'i', C!'j', C!'k', C!'m', C!'n', C!'l', C!'o',
/*70*/	C!'p', C!'q', C!'r', C!'s', C!'t', C!'u', C!'v', C!'w',
/*78*/	C!'x', C!'y', C!'z', C!'{', C!'|', C!'}', C!'~', C!'⌂',
/*80*/	C!'Ç', C!'ü', C!'é', C!'â', C!'ä', C!'à', C!'å', C!'ç',
/*88*/	C!'ê', C!'ë', C!'è', C!'ï', C!'î', C!'ì', C!'Ä', C!'Å',
/*90*/	C!'É', C!'æ', C!'Æ', C!'ô', C!'ö', C!'ò', C!'û', C!'ù',
/*98*/	C!'ÿ', C!'Ö', C!'Ü', C!'¢', C!'£', C!'¥', C!'₧', C!'ƒ',
/*a0*/	C!'á', C!'í', C!'ó', C!'ú', C!'ñ', C!'Ñ', C!'ª', C!'º',
/*a8*/	C!'¿', C!'⌐', C!'¬', C!'½', C!'¼', C!'¡', C!'«', C!'»',
/*b0*/	C!'░', C!'▒', C!'▓', C!'│', C!'┤', C!'╡', C!'╢', C!'╖',
/*b8*/	C!'╕', C!'╣', C!'║', C!'╗', C!'╝', C!'╜', C!'╛', C!'┐',
/*c0*/	C!'└', C!'┴', C!'┬', C!'├', C!'─', C!'┼', C!'╞', C!'╟',
/*c8*/	C!'╚', C!'╔', C!'╩', C!'╦', C!'╠', C!'═', C!'╬', C!'╧',
/*d0*/	C!'╨', C!'╤', C!'╥', C!'╙', C!'╘', C!'╒', C!'╓', C!'╫',
/*d8*/	C!'╪', C!'┘', C!'┌', C!'█', C!'▄', C!'▌', C!'▐', C!'▀',
/*e0*/	C!'α', C!'β', C!'Γ', C!'π', C!'Σ', C!'σ', C!'µ', C!'τ',
/*e8*/	C!'Φ', C!'Θ', C!'Ω', C!'δ', C!'∞', C!'φ', C!'ε', C!'∩',
/*f0*/	C!'≡', C!'±', C!'≥', C!'≤', C!'⌠', C!'⌡', C!'÷', C!'≈',
/*f8*/	C!'°', C!'∙', C!'·', C!'√', C!'ⁿ', C!'²', C!'■', C!0
];
private
char[] transcodeCP437(ubyte data) {
	return mapCP437[data];
}

private U[256] mapEBCDIC = [
//          0      1      2      3      4      5      6      7 
/*00*/	   [],    [],    [],    [],    [],    [],    [],    [],
/*08*/	   [],    [],    [],    [],    [],    [],    [],    [],
/*10*/	   [],    [],    [],    [],    [],    [],    [],    [],
/*18*/	   [],    [],    [],    [],    [],    [],    [],    [],
/*20*/	   [],    [],    [],    [],    [],    [],    [],    [],
/*28*/	   [],    [],    [],    [],    [],    [],    [],    [],
/*30*/	   [],    [],    [],    [],    [],    [],    [],    [],
/*38*/	   [],    [],    [],    [],    [],    [],    [],    [],
/*40*/	C!' ', C!' ', C!'â', C!'ä', C!'à', C!'á', C!'ã', C!'å',
/*48*/	C!'ç', C!'ñ', C!'¢', C!'.', C!'<', C!'(', C!'+', C!'|',
/*50*/	C!'&', C!'é', C!'ê', C!'ë', C!'è', C!'í', C!'î', C!'ï',
/*58*/	C!'ì', C!'ß', C!'!', C!'$', C!'*', C!')', C!';', C!'¬',
/*60*/	C!'-', C!'/', C!'Â', C!'Ä', C!'À', C!'Á', C!'Ã', C!'Å',
/*68*/	C!'Ç', C!'Ñ', C!'¦', C!',', C!'%', C!'_', C!'>', C!'?',
/*70*/	C!'ø', C!'É', C!'Ê', C!'Ë', C!'È', C!'Í', C!'Î', C!'Ï',
/*78*/	C!'Ì', C!'`', C!':', C!'#', C!'@', C!'\'',C!'=', C!'"',
/*80*/	C!'Ø', C!'a', C!'b', C!'c', C!'d', C!'e', C!'f', C!'g',
/*88*/	C!'h', C!'i', C!'«', C!'»', C!'ð', C!'ý', C!'þ', C!'±',
/*90*/	C!'°', C!'j', C!'k', C!'l', C!'m', C!'n', C!'o', C!'p',
/*98*/	C!'q', C!'r', C!'ª', C!'º', C!'æ', C!'¸', C!'Æ', C!'¤',
/*a0*/	C!'µ', C!'~', C!'s', C!'t', C!'u', C!'v', C!'w', C!'x',
/*a8*/	C!'y', C!'z', C!'¡', C!'¿', C!'Ð', C!'Ý', C!'Þ', C!'®',
/*b0*/	C!'^', C!'£', C!'¥', C!'·', C!'©', C!'§', C!'¶', C!'¼',
/*b8*/	C!'½', C!'¾', C!'[', C!']', C!'¯', C!'¨', C!'´', C!'×',
/*c0*/	C!'{', C!'A', C!'B', C!'C', C!'D', C!'E', C!'F', C!'G',
/*c8*/	C!'H', C!'I',    [], C!'ô', C!'ö', C!'ò', C!'ó', C!'õ',
/*d0*/	C!'}', C!'J', C!'K', C!'L', C!'M', C!'N', C!'O', C!'P',
/*d8*/	C!'Q', C!'R', C!'¹', C!'û', C!'ü', C!'ù', C!'ú', C!'ÿ',
/*e0*/	C!'\\',C!'÷', C!'S', C!'T', C!'U', C!'V', C!'W', C!'X',
/*e8*/	C!'Y', C!'Z', C!'²', C!'Ô', C!'Ö', C!'Ò', C!'Ó', C!'Õ',
/*f0*/	C!'0', C!'1', C!'2', C!'3', C!'4', C!'5', C!'6', C!'7',
/*f8*/	C!'8', C!'9', C!'³', C!'Û', C!'Ü', C!'Ù', C!'Ú',    []
];
private
char[] transcodeEBCDIC(ubyte data) {
	return mapEBCDIC[data];
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
	char[32] c1 = void, c2 = void, c3 = void;
	char[128] buf = void;
	char[] f = sformat!" %s | %s - %s | %g%% - %g%%"(buf,
		formatSize(c1, input.bufferSize), // Buffer size
		formatSize(c2, input.position), // Formatted position
		formatSize(c3, input.position + input.bufferSize), // Formatted position
		((cast(float)input.position) / input.size) * 100, // Pos/input.size%
		((cast(float)input.position + input.bufferSize) / input.size) * 100, // Pos/input.size%
	);
	if (last > f.length) { // Fill by blanks
		int p = cast(int)(f.length + (last - f.length));
		writef("%*s", -p, f);
	} else { // Overwrites by default
		write(f);
	}
	last = f.length;
	stdout.flush();
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
	char[] function(ubyte) transcodeChar = transFuncs[charset];
	
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
		for (ushort r; r < bytesLeft; ++r, ++bpos) {
			const ubyte byteData = b[bpos];
			// Data translation
			lbuf[lpos] = ' ';
			lbuf[lpos+1] = hexMap[byteData >> 4];
			lbuf[lpos+2] = hexMap[byteData & 15];
			lpos += 3;
			// Character translation
			char[] units = transcodeChar(byteData);
			if (units.length)
				for (size_t i; i < units.length; ++i, ++cpos)
					lbuf[cpos] = units[i];
			else
				lbuf[cpos++] = defaultChar;
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