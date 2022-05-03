/// Module handling screen.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module screen;

import std.range : chunks;
import std.stdio : stdout; // for cwrite family
import all;
import os.terminal, os.file;

//TODO: Data grouping (1, 2, 4, 8, 16)
//      e.g., cd ab -> abcd
//      cast(uint[]) is probably possible on a ubyte[] range
//TODO: Group endianness (when >1)
//      native (default), little, big
//TODO: View display mode (data+text, data, text)
//      Currently very low priority
//TODO: Consider hiding cursor when drawing
//      + save/restore position
//      terminalCursorHide()
//        windows: SetConsoleCursorInfo
//                 https://docs.microsoft.com/en-us/windows/console/setconsolecursorinfo
//        posix: \033[?25l
//      terminalCursorShow()
//        windows: SetConsoleCursorInfo
//        posix: \033[?25h
//TODO: Unaligned rendering.
//      Rendering engine should be capable to take off whereever it stopped
//      or be able to specify/toggle seperate regardless of column length.
//      Probably useful for dump app.

void clearOffsetBar() {
	screen.cwritefAt(0,0,"%*s", terminalSize.width - 1, " ");
}
/*void clearStatusBar() {
	screen.cwritefAt(0,0,"%*s", terminalSize.width - 1, " ");
}*/
void message(A...)(const(char)[] fmt, A args) {
	import std.format : format;
	message(format(fmt, args));
}
void message(const(char)[] str) {
	TerminalSize termsize = terminalSize;
	terminalPos(0, termsize.height - 1);
	cwritef("%-*s", termsize.width - 1, str);
}

private struct NumberFormatter {
	immutable(char)[] name;	/// Short offset name
	align(2) char fmtchar;	/// Format character for printf-like functions
	uint size;	/// Size for formatted byte
	size_t function(char*,long) offset;	/// Function to format offset
	size_t function(char*,ubyte) data;	/// Function to format data
}

private immutable NumberFormatter[3] numbers = [
	{ "hex", 'x', 2, &format11x, &format02x },
	{ "dec", 'u', 3, &format11d, &format03d },
	{ "oct", 'o', 3, &format11o, &format03o },
];

//
// SECTION Formatting
//

private immutable static string hexMap = "0123456789abcdef";

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
// SECTION Rendering
//

/// 
void renderOffsetBar(bool cursor = true) {
	import std.outbuffer : OutBuffer;
	import std.typecons : scoped;
	import std.conv : octal;
	
	__gshared size_t last;
	
	if (cursor)
		terminalPos(0, 0);
	
	const int offsetType = settings.offset;
	const int dataType = settings.data;
	const ushort rowWidth = settings.width;
	
	// Setup index formatting
	//TODO: Consider SingleSpec
	__gshared char[4] offsetFmt = " %__";
	offsetFmt[2] = cast(char)(numbers[dataType].size + '0');
	offsetFmt[3] = numbers[offsetType].fmtchar;
	
	// Recommended to use 'auto' due to struct Scoped
	auto outbuf = scoped!OutBuffer();
	outbuf.reserve(256); // e.g. 8 + 2 + (16 * 3) + 2 + 8 = 68
	outbuf.write("Offset(");
	outbuf.write(numbers[offsetType].name);
	outbuf.write(") ");
	
	// Print column values
	for (ushort i; i < rowWidth; ++i)
		outbuf.writef(offsetFmt, i);
	
	// Fill out remains since this is damage-based
	if (last > outbuf.offset + 1) { // +null
		const size_t c = cast(size_t)(last - outbuf.offset);
		for (size_t i; i < c; ++i)
			outbuf.put(' ');
	}
	
	last = outbuf.offset;
	// OutBuffer.toString duplicates it, what a waste!
	cwriteln(cast(const(char)[])outbuf.toBytes);
}

/// 
void renderStatusBar(bool cursor = true) {
	import std.format : sformat;
	
	//TODO: [0.5] Include editing mode (insert/overwrite)
	//            INS/OVR
	__gshared size_t last;
	char[32] c1 = void, c3 = void;
	char[128] buf = void;
	
	if (cursor)
		terminalPos(0, terminalSize.height - 1);
	
	const double fpos = ddhx.io.position;
	char[] f = sformat!" %s | %s | %s | %s (%f%%)"(buf,
		numbers[settings.data].name,
		transcoder.name,
		formatSize(c1, ddhx.io.readSize, settings.si), // Buffer size
		formatSize(c3, ddhx.io.position + ddhx.io.readSize, settings.si), // Formatted position
		((fpos + ddhx.io.readSize) / ddhx.io.size) * 100, // Pos/input.size%
	);
	
	const size_t flen = f.length;
	
	if (last > flen) { // Fill by blanks
		cwritef("%*s", -cast(int)(flen + (last - flen)), f);
	} else { // Overwrites by default
		cwrite(f);
	}
	
	last = flen;
}

//TODO: [0.5] Possibility to only redraw a specific byte.
//      renderContentByte(size_t bufpos, ubyte newData)

uint renderContent(bool cursor = true) {
	if (cursor)
		terminalPos(0, 1);
	
	return renderContent(ddhx.io.position, ddhx.io.buffer);
}

/// Update display from buffer.
/// Returns: Numbers of row written.
uint renderContent(long position, ubyte[] data) {
	// Setup formatting related stuff
	initRow;
	
	// print lines in bulk (for entirety of view buffer)
	uint lines;
	foreach (chunk; chunks(data, settings.width)) {
		cwriteln(renderRow(chunk, position));
		position += settings.width;
		++lines;
	}
	
	return lines;
}

private void initRow(NumberType offset = settings.offset,
	NumberType data = settings.data) {
	offsetFmt = &numbers[offset];
	dataFmt = &numbers[data];
}

private __gshared immutable(NumberFormatter) *offsetFmt;
private __gshared immutable(NumberFormatter) *dataFmt;

//TODO: insertPosition?
//TODO: insertData?
//TODO: insertText?
private char[] renderRow(ubyte[] chunk, long pos) {
	import core.stdc.string : memset;
	
	enum BUFFER_SIZE = 2048;
	__gshared char[BUFFER_SIZE] buffer;
	__gshared char *bufferptr = buffer.ptr;
	
	// Insert OFFSET
	size_t indexData = offsetFmt.offset(bufferptr, pos);
	bufferptr[indexData++] = ' '; // index: OFFSET + space
	
	const uint dataLen = (settings.width * (dataFmt.size + 1)); /// data row character count
	size_t indexChar = indexData + dataLen; // Position for character column
	*(cast(ushort*)(bufferptr + indexChar)) = 0x2020; // DATA-CHAR spacer
	indexChar += 2; // indexChar: indexData + dataLen + spacer
	
	// Format DATA and CHAR
	// NOTE: Smaller loops could fit in cache...
	//       And would separate data/text logic
	foreach (data; chunk) {
//	for (size_t i; i < chunk.length; ++i) {
//		const ubyte data = chunk[i]; /// byte data
		// Data translation
		bufferptr[indexData++] = ' ';
		indexData += dataFmt.data(bufferptr + indexData, data);
		// Character translation
		immutable(char)[] units = transcoder.transform(data);
		if (units.length) { // Has utf-8 codepoints
			foreach (codeunit; units)
				bufferptr[indexChar++] = codeunit;
		} else // Invalid character, insert default character
			bufferptr[indexChar++] = settings.defaultChar;
	}
	// data length < minimum row requirement = pad DATA
	if (chunk.length < settings.width) {
		size_t left =
			(settings.width - chunk.length) // Bytes left
			* (dataFmt.size + 1);  // space + 1x data size
		memset(bufferptr + indexData, ' ', left);
	}
	
	return buffer[0..indexChar];
}

//TODO: More renderRow unittests
unittest {
	// With defaults
	initRow;
	//	 Offset(hex)   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
	assert(renderRow([ 0 ], 0) ==
		"          0  00                                               .");
	assert(renderRow([ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf ], 0x10) ==
		"         10  00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f  ................");
	
}

// !SECTION

// SECTION Console Write functions

size_t cwriteAt(int x, int y, const(char)[] str) {
	terminalPos(x, y);
	return cwrite(str);
}
size_t cwritelnAt(int x, int y, const(char)[] str) {
	terminalPos(x, y);
	return cwriteln(str);
}
size_t cwritefAt(A...)(int x, int y, const(char)[] fmt, A args) {
	terminalPos(x, y);
	return cwritef(fmt, args);
}
size_t cwriteflnAt(A...)(int x, int y, const(char)[] fmt, A args) {
	terminalPos(x, y);
	return cwritefln(fmt, args);
}
size_t cwrite(const(char)[] _str) {
	import std.stdio : stdout;
	import core.stdc.stdio : fwrite, FILE;
	
	return fwrite(_str.ptr, 1, _str.length, stdout.getFP);
}
size_t cwriteln(const(char)[] _str) {
	size_t c = cwrite(_str);
	cwrite("\n");
	return ++c;
}
size_t cwritef(A...)(const(char)[] fmt, A args) {
	import std.format : sformat;
	char[128] buf = void;
	return cwrite(sformat(buf, fmt, args));
}
size_t cwritefln(A...)(const(char)[] fmt, A args) {
	size_t c = cwritef(fmt, args);
	cwrite("\n");
	return ++c;
}

// !SECTION