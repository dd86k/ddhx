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

//TODO: Data grouping
//      e.g., cd ab -> abcd
//TODO: Group endianness
//TODO: View display mode (data+text, data, text)
//TODO: Consider hiding cursor when drawing
//      + save/restore position
//      terminalHideCursor()
//        windows: SetConsoleCursorInfo
//                 https://docs.microsoft.com/en-us/windows/console/setconsolecursorinfo
//        posix: \033[?25l
//      terminalShowCursor()
//        windows: SetConsoleCursorInfo
//        posix: \033[?25h
//TODO: Redo offset formatting functions
//      e.g. size_t formatOctal(char* buffer, long v, ubyte pad)
//      Why?

private enum LBUF_SIZE = 2048;

private extern (C) int putchar(int);

/// Data modes for upper row (display purposes)
private static immutable(char)[][3] offsetNames = [ "Hex", "Dec", "Oct" ];
/// Character table for header row (display purposes)
private deprecated immutable char[3] offsetTable = [ 'h', 'd', 'o' ];
/// Character table for the main panel for printf (formatting purposes)
private immutable char[3] formatTable = [ 'x', 'u', 'o' ];
/// Offset format functions
private immutable size_t function(char*,long)[3] offsetFuncs = [
	&format11x, &format11d, &format11o
];
/// Data format functions
private immutable size_t function(char*,ubyte)[3] dataFuncs = [
	&format02x, &format03d, &format03o
];
/// Data formatted size
private immutable size_t[3] dataSizes = [ 2, 3, 3 ];
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

private immutable static string hexMap  = "0123456789abcdef";

private
size_t format02x(char *buffer, ubyte v) {
	buffer[1] = hexMap[v & 15];
	buffer[0] = hexMap[v >> 4];
	return 2;
}
@system unittest {
	char[2] c = void;
	format02x(c.ptr, 0x01);
	assert(c[] == "01", c);
	format02x(c.ptr, 0x20);
	assert(c[] == "20", c);
	format02x(c.ptr, 0xff);
	assert(c[] == "ff", c);
}
private
size_t format11x(char *buffer, long v) {
	size_t pos;
	bool pad = true;
	for (int shift = 60; shift >= 0; shift -= 4) {
		const ubyte b = (v >> shift) & 15;
		if (b == 0) {
			if (pad && shift >= 44) {
				continue; // cut
			} else if (pad && shift >= 4) {
				buffer[pos++] = pad ? ' ' : '0';
				continue; // pad
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
	assert(b[0..format11x(p, 0)]                  ==      "          0");
	assert(b[0..format11x(p, 1)]                  ==      "          1");
	assert(b[0..format11x(p, 0x10)]               ==      "         10");
	assert(b[0..format11x(p, 0x100)]              ==      "        100");
	assert(b[0..format11x(p, 0x1000)]             ==      "       1000");
	assert(b[0..format11x(p, 0x10000)]            ==      "      10000");
	assert(b[0..format11x(p, 0x100000)]           ==      "     100000");
	assert(b[0..format11x(p, 0x1000000)]          ==      "    1000000");
	assert(b[0..format11x(p, 0x10000000)]         ==      "   10000000");
	assert(b[0..format11x(p, 0x100000000)]        ==      "  100000000");
	assert(b[0..format11x(p, 0x1000000000)]       ==      " 1000000000");
	assert(b[0..format11x(p, 0x10000000000)]      ==      "10000000000");
	assert(b[0..format11x(p, 0x100000000000)]     ==     "100000000000");
	assert(b[0..format11x(p, 0x1000000000000)]    ==    "1000000000000");
	assert(b[0..format11x(p, ubyte.max)]          ==      "         ff");
	assert(b[0..format11x(p, ushort.max)]         ==      "       ffff");
	assert(b[0..format11x(p, uint.max)]           ==      "   ffffffff");
	assert(b[0..format11x(p, ulong.max)]          == "ffffffffffffffff");
	assert(b[0..format11x(p, 0x1010)]             ==      "       1010");
	assert(b[0..format11x(p, 0x10101010)]         ==      "   10101010");
	assert(b[0..format11x(p, 0x1010101010101010)] == "1010101010101010");
}

private immutable static string decMap = "0123456789";
private
size_t format03d(char *buffer, ubyte v) {
	buffer[2] = (v % 10) + '0';
	buffer[1] = (v / 10 % 10) + '0';
	buffer[0] = (v / 100 % 10) + '0';
	return 3;
}
@system unittest {
	char[3] c = void;
	format03d(c.ptr, 1);
	assert(c[] == "001", c);
	format03d(c.ptr, 10);
	assert(c[] == "010", c);
	format03d(c.ptr, 111);
	assert(c[] == "111", c);
}
private
size_t format11d(char *buffer, long v) {
	debug import std.conv : text;
	enum ulong I64MAX = 10_000_000_000_000_000_000UL;
	size_t pos;
	bool pad = true;
	for (ulong d = I64MAX; d > 0; d /= 10) {
		const long r = (v / d) % 10;
		if (r == 0) {
			if (pad && d >= 100_000_000_000) {
				continue; // cut
			} else if (pad && d >= 10) {
				buffer[pos++] = pad ? ' ' : '0';
				continue;
			}
		} else pad = false;
		debug assert(r >= 0 && r < 10, "r="~r.text);
		buffer[pos++] = decMap[r];
	}
	return pos;
}
/// 
@system unittest {
	char[32] b = void;
	char *p = b.ptr;
	assert(b[0..format11d(p, 0)]                 ==   "          0");
	assert(b[0..format11d(p, 1)]                 ==   "          1");
	assert(b[0..format11d(p, 10)]                ==   "         10");
	assert(b[0..format11d(p, 100)]               ==   "        100");
	assert(b[0..format11d(p, 1000)]              ==   "       1000");
	assert(b[0..format11d(p, 10_000)]            ==   "      10000");
	assert(b[0..format11d(p, 100_000)]           ==   "     100000");
	assert(b[0..format11d(p, 1000_000)]          ==   "    1000000");
	assert(b[0..format11d(p, 10_000_000)]        ==   "   10000000");
	assert(b[0..format11d(p, 100_000_000)]       ==   "  100000000");
	assert(b[0..format11d(p, 1000_000_000)]      ==   " 1000000000");
	assert(b[0..format11d(p, 10_000_000_000)]    ==   "10000000000");
	assert(b[0..format11d(p, 100_000_000_000)]   ==  "100000000000");
	assert(b[0..format11d(p, 1000_000_000_000)]  == "1000000000000");
	assert(b[0..format11d(p, ubyte.max)]  ==          "        255");
	assert(b[0..format11d(p, ushort.max)] ==          "      65535");
	assert(b[0..format11d(p, uint.max)]   ==          " 4294967295");
	assert(b[0..format11d(p, ulong.max)]  == "18446744073709551615");
	assert(b[0..format11d(p, 1010)]       ==          "       1010");
}

private
size_t format03o(char *buffer, ubyte v) {
	buffer[2] = (v % 8) + '0';
	buffer[1] = (v / 8 % 8) + '0';
	buffer[0] = (v / 64 % 8) + '0';
	return 3;
}
@system unittest {
	import std.conv : octal;
	char[3] c = void;
	format03o(c.ptr, 1);
	assert(c[] == "001", c);
	format03o(c.ptr, octal!20);
	assert(c[] == "020", c);
	format03o(c.ptr, octal!133);
	assert(c[] == "133", c);
}
private
size_t format11o(char *buffer, long v) {
	size_t pos;
	if (v >> 63) buffer[pos++] = '1'; // ulong.max coverage
	bool pad = true;
	for (int shift = 60; shift >= 0; shift -= 3) {
		const ubyte b = (v >> shift) & 7;
		if (b == 0) {
			if (pad && shift >= 33) {
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
	assert(b[0..format11o(p, 0)]                     ==  "          0");
	assert(b[0..format11o(p, 1)]                     ==  "          1");
	assert(b[0..format11o(p, octal!10)]              ==  "         10");
	assert(b[0..format11o(p, octal!20)]              ==  "         20");
	assert(b[0..format11o(p, octal!100)]             ==  "        100");
	assert(b[0..format11o(p, octal!1000)]            ==  "       1000");
	assert(b[0..format11o(p, octal!10_000)]          ==  "      10000");
	assert(b[0..format11o(p, octal!100_000)]         ==  "     100000");
	assert(b[0..format11o(p, octal!1000_000)]        ==  "    1000000");
	assert(b[0..format11o(p, octal!10_000_000)]      ==  "   10000000");
	assert(b[0..format11o(p, octal!100_000_000)]     ==  "  100000000");
	assert(b[0..format11o(p, octal!1000_000_000)]    ==  " 1000000000");
	assert(b[0..format11o(p, octal!10_000_000_000)]  ==  "10000000000");
	assert(b[0..format11o(p, octal!100_000_000_000)] == "100000000000");
	assert(b[0..format11o(p, ubyte.max)]   ==            "        377");
	assert(b[0..format11o(p, ushort.max)]  ==            "     177777");
	assert(b[0..format11o(p, uint.max)]    ==            "37777777777");
	assert(b[0..format11o(p, ulong.max)]   == "1777777777777777777777");
	assert(b[0..format11o(p, octal!101_010)] ==          "     101010");
}

// !SECTION

//
// SECTION Character translation
//

//TODO: Possibly redo character transcoding functions
//      e.g. size_t insertCP437(char *data, size_t left);
//TODO: Other character sets
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
/*20*/	C!' ', C!'!', C!'"', C!'#', C!'$', C!'%', C!'&',C!'\'',
/*28*/	C!'(', C!')', C!'*', C!'+', C!',', C!'-', C!'.', C!'/',
/*30*/	C!'0', C!'1', C!'2', C!'3', C!'4', C!'5', C!'6', C!'7',
/*38*/	C!'8', C!'9', C!':', C!';', C!'<', C!'>', C!'=', C!'?',
/*40*/	C!'@', C!'A', C!'B', C!'C', C!'D', C!'E', C!'F', C!'G',
/*48*/	C!'H', C!'I', C!'J', C!'K', C!'M', C!'N', C!'L', C!'O',
/*50*/	C!'P', C!'Q', C!'R', C!'S', C!'T', C!'U', C!'V', C!'W',
/*58*/	C!'X', C!'Y', C!'Z', C!'[',C!'\\', C!']', C!'^', C!'_',
/*60*/	C!'`', C!'a', C!'b', C!'c', C!'d', C!'e', C!'f', C!'g',
/*68*/	C!'h', C!'i', C!'j', C!'k', C!'l', C!'m', C!'n', C!'o',
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
/*f8*/	C!'°', C!'∙', C!'·', C!'√', C!'ⁿ', C!'²', C!'■', C!' '
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

/// Returns the number of characters that gets past the 8-character limit
/// for the current offset + buffer size.
/// Returns: Number of spaces for column alignment.
int getOverfill() {
	return 0;
}

/// Update the upper offset bar.
void displayRenderTop() {
	terminalPos(0, 0);
	displayRenderTopRaw();
}

/// 
void displayRenderTopRaw() {
	import std.outbuffer : OutBuffer;
	import std.typecons : scoped;
	import std.conv : octal;
	
	enum ubyte ZERO = 0;
	enum char SPACE = ' ';
	__gshared size_t last;
	
	const int offsetType = globals.offsetType;
	const int dataType = globals.dataType;
	const ushort rowWidth = globals.rowWidth;
	
	// Setup index formatting
	//TODO: Consider SingleSpec
	__gshared char[4] offsetFmt = " %__";
	offsetFmt[2] = cast(char)(dataSizes[dataType] + '0');
	offsetFmt[3]  = formatTable[offsetType];
	
	auto outbuf = scoped!OutBuffer(); // Recommended to use 'auto' due to struct Scoped
	outbuf.reserve(256); // e.g. 8 + 2 + (16 * 3) + 2 + 8 = 68
	outbuf.write("Offset(");
	outbuf.write(offsetNames[offsetType]);
	outbuf.write(") ");
	
	// Print column values
	//TODO: Consider %(%) syntax
	for (ushort i; i < rowWidth; ++i)
		outbuf.writef(offsetFmt, i);
	
	// Fill out remains since this is damage-based
	if (last > outbuf.offset + 1) { // +null
		const size_t c = cast(size_t)(last - outbuf.offset);
		for (size_t i; i < c; ++i)
			outbuf.put(SPACE);
	}
	
	// Zero-terminate and print
	outbuf.put(ZERO);
	last = puts(cast(char*)outbuf.data.ptr);
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
	//TODO: [0.5] Include editing mode (insert/overwrite)
	__gshared size_t last;
	char[32] c1 = void, c2 = void, c3 = void;
	char[128] buf = void;
	char[] f = sformat!" %s | %s | %s - %s | %f%% - %f%%"(buf,
		offsetNames[globals.dataType],
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

/// Update display from buffer.
/// Returns: Numbers of row written.
uint displayRenderMainRaw() {
	//TODO: Consider redoing buffer management with an OutBuffer.
	//      Or std.array.appender + std.format.spec.SingleSpec
	//TODO: Remember length of last printed line for damaged-based display
	//TODO: [0.5] Possibility to only redraw a specific line.
	
	// data
	const(ubyte) *b    = input.result.ptr;	/// data buffer pointer
	int           bsz  = cast(int)input.result.length;	/// data buffer size
	size_t        bpos;	// data buffer position index
	
	// line buffer
	size_t          lpos = void;	/// line buffer index position
	char[LBUF_SIZE] lbuf = void;	/// line buffer
	char           *lptr = lbuf.ptr;
	uint            ls;	/// lines printed
	
	// setup
	const int rowMax = globals.rowWidth;
	const char defaultChar = globals.defaultChar;
	const int offsetType = globals.offsetType;
	const int dataType = globals.dataType;
	const int charset = globals.charType;
	size_t function(char*, long) formatOffset = offsetFuncs[offsetType];
	size_t function(char*, ubyte) formatData = dataFuncs[dataType];
	const size_t dataSize = dataSizes[dataType];
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
		size_t cpos = (lpos + (rowMax * (dataSize + 1))) + 2;
		for (ushort r; r < bytesLeft; ++r, ++bpos) {
			const ubyte byteData = b[bpos];
			// Data translation
			lbuf[lpos] = ' ';
			lpos += formatData(lptr + lpos + 1, byteData) + 1;
			// Character translation
			char[] units = transcodeChar(byteData);
			if (units.length)
				for (size_t i; i < units.length; ++i, ++cpos)
					lbuf[cpos] = units[i];
			else
				lbuf[cpos++] = defaultChar;
		}
		
		// Spacer between DATA and CHAR panels
		*(cast(ushort*)(lptr + lpos)) = 0x2020;
		lpos += 2;
		
		// Line DATA leftovers
		if (leftOvers) {
			import core.stdc.string : memset;
			bytesLeft = rowMax - left;
			memset(lptr + lpos, ' ', bytesLeft);
			/*do {
				lbuf[lpos]   = ' ';
				lbuf[lpos+1] = ' ';
				lbuf[lpos+2] = ' ';
				lpos += 3;
			} while (--bytesLeft > 0);*/
			left = 0;
		}
		
		// Terminate line and send
		lbuf[cpos] = 0;
		puts(lptr);	// print line result + newline
	}
	
	return ls;
}