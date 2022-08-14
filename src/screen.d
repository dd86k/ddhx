/// Terminal screen handling.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module screen;

import std.range : chunks;
import ddhx; // for setting, NumberType
import os.terminal, os.file;
import core.stdc.string : memset;
import core.stdc.stdlib : malloc, free;

//TODO: Data viewer groups
//      hex: h8, h16, h32, h64
//      signed decimal: i8, i16, i32, i64
//      unsigned decimal: u8, u16, u32, u64
//      signed octal: oi8, oi16, oi32, oi64
//      unsigned octal: ou8, ou16, ou32, ou64
//      float: f32, f64
//TODO: Group endianness (when >1)
//      native (default), little, big
//TODO: View display mode (data+text, data, text)
//      Currently very low priority
//TODO: Unaligned rendering.
//      Rendering engine should be capable to take off whereever it stopped
//      or be able to specify/toggle seperate regardless of column length.
//      Probably useful for dump app.

private struct NumberFormatter {
	string name;	/// Short offset name
	char fmtchar;	/// Format character for printf-like functions
	ubyte size;	/// Size for formatted byte (excluding space)
	size_t function(char*,long) offset;	/// Function to format offset
	size_t function(char*,ubyte) data;	/// Function to format data
}

private immutable NumberFormatter[3] formatters = [
	{ "hex", 'x', 2, &format11x, &format02x },
	{ "dec", 'u', 3, &format11d, &format03d },
	{ "oct", 'o', 3, &format11o, &format03o },
];

/// Last known terminal size.
__gshared TerminalSize termSize;

//TODO: Have single __gshared Formatter format instance
//      .offset(long)
//      .data()...

__gshared NumberFormatter offsetFormatter = formatters[0];
__gshared NumberFormatter binaryFormatter = formatters[0];

int initiate() {
	terminalInit(TermFeat.all);
	
	updateTermSize;
	
	if (termSize.height < 3)
		return errorSet(ErrorCode.screenMinimumRows);
	if (termSize.width < 20)
		return errorSet(ErrorCode.screenMinimumColumns);
	
	return 0;
}

void updateTermSize() {
	termSize = terminalSize;
}

void onResize(void function() func) {
	terminalOnResize(func);
}

void setOffsetFormat(NumberType type) {
	offsetFormatter = formatters[type];
}
void setBinaryFormat(NumberType type) {
	binaryFormatter = formatters[type];
}

/// Update cursor position on the terminal screen
void cursor(uint pos, uint nibble) {
	uint y = pos / setting.columns;
	uint x = pos % setting.columns;
	int  d = binaryFormatter.size + 1;
	terminalPos(13 + (x * d) + nibble, 1 + y);
}

/// Clear entire terminal screen
void clear() {
	terminalClear;
}

/*void clearStatusBar() {
	screen.cwritefAt(0,0,"%*s", termSize.width - 1, " ");
}*/

/// Display a formatted message at the bottom of the screen.
/// Params:
///   fmt = Formatting message string.
///   args = Arguments.
void message(A...)(const(char)[] fmt, A args) {
	//TODO: Consider using a scoped outbuffer + private message(outbuf)
	import std.format : format;
	message(format(fmt, args));
}
/// Display a message at the bottom of the screen.
/// Params: str = Message.
void message(const(char)[] str) {
	terminalPos(0, termSize.height - 1);
	cwritef("%-*s", termSize.width - 1, str);
}

string prompt(string prefix, string include) {
	import std.stdio : readln;
	import std.string : chomp;
	
	scope (exit) {
		cursorOffset;
		renderOffset;
	}
	
	clearOffsetBar;
	
	terminalPos(0, 0);
	
	cwrite(prefix);
	if (include) cwrite(include);
	
	terminalPauseInput;
	
	string line = include ~ chomp(readln());
	
	terminalResumeInput;
	
	return line;
}

//
// SECTION Rendering
//

//TODO: Move formatting stuff to module format.

private immutable string hexMap = "0123456789abcdef";

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

void cursorOffset() {
	terminalPos(0, 0);
}
void cursorContent() {
	terminalPos(0, 1);
}
void cursorStatusbar() {
	terminalPos(0, termSize.height - 1);
}

void clearOffsetBar() {
	screen.cwritefAt(0, 0, "%*s", termSize.width - 1, " ");
}
/// 
//TODO: Add "edited" or '*' to end if file edited
void renderOffset() {
	import std.outbuffer : OutBuffer;
	import std.typecons : scoped;
	import std.conv : octal;
	
	version (Trace) {
		StopWatch sw = StopWatch(AutoStart.yes);
	}
	
	// Setup index formatting
	int datasize = binaryFormatter.size;
	__gshared char[4] offsetFmt = " %__";
	offsetFmt[2] = cast(char)(datasize + '0');
	offsetFmt[3] = formatters[setting.offsetType].fmtchar;
	
	auto outbuf = scoped!OutBuffer();
	outbuf.reserve(16 + (setting.columns * datasize));
	outbuf.write("Offset(");
	outbuf.write(formatters[setting.offsetType].name);
	outbuf.write(") ");
	
	// Add offsets
	uint i;
	for (; i < setting.columns; ++i)
		outbuf.writef(offsetFmt, i);
	// Fill rest of terminal width if in interactive mode
	if (termSize.width) {
		for (i = cast(uint)outbuf.offset; i < termSize.width; ++i)
			outbuf.put(' ');
	}
	
	version (Trace) {
		Duration a = sw.peek;
	}
	
	// OutBuffer.toString duplicates it, what a waste!
	cwriteln(cast(const(char)[])outbuf.toBytes);
	
	version (Trace) {
		Duration b = sw.peek;
		trace("gen='%s µs' print='%s µs'",
			a.total!"usecs",
			(b - a).total!"usecs");
	}
}

/// 
void renderStatusBar(const(char)[][] items ...) {
	import std.outbuffer : OutBuffer;
	import std.typecons : scoped;
	
	version (Trace) {
		StopWatch sw = StopWatch(AutoStart.yes);
	}
	
	int w = termSize.width;
	
	auto outbuf = scoped!OutBuffer();
	outbuf.reserve(w);
	outbuf.put(' ');
	foreach (item; items) {
		if (outbuf.offset > 1) outbuf.put(" | ");
		outbuf.put(item);
		if (outbuf.offset >= w) {
			
		}
	}
	// Fill rest by space
	outbuf.data[outbuf.offset..w] = ' ';
	outbuf.offset = w; // used in .toBytes
	
	version (Trace) {
		Duration a = sw.peek;
	}
	
	cwrite(cast(const(char)[])outbuf.toBytes);
	
	version (Trace) {
		sw.stop;
		Duration b = sw.peek;
		trace("gen='%s µs' print='%s µs'",
			a.total!"usecs",
			(b - a).total!"usecs");
	}
}

/// Update display from buffer.
/// Params:
/// 	position = Base position.
/// 	data = Data chunk.
/// 	limit = Maximum number of lines to print.
/// Returns: Numbers of row written.
int renderContent(long position, ubyte[] data, int limit) {
	version (Trace) {
		trace("position=%u data.len=%u", position, data.length);
		StopWatch sw = StopWatch(AutoStart.yes);
	}
	
	if (limit == 0) limit = limit.max;
	
	// print lines in bulk (for entirety of view buffer)
	//TODO: Output to scoped OutBuffer
	//auto outbuf = scoped!OutBuffer();
	int line;
	foreach (chunk; chunks(data, setting.columns)) {
		//outbuf.put(renderRow(chunk, position));
		cwriteln(renderRow(chunk, position));
		position += setting.columns;
		if (++line == limit) break;
	}
	
	//cwriteln(cast(const(char)[])outbuf.toBytes);
	
	version (Trace) {
		sw.stop;
		trace("time='%s µs'", sw.peek.total!"usecs");
	}
	
	return line;
}
void renderEmpty(int lines) {
	debug assert(termSize.rows);
	debug assert(termSize.columns);
	
	version (Trace) {
		trace("lines=%u rows=%u cols=%u", lines, termSize.rows, termSize.columns);
		StopWatch sw = StopWatch(AutoStart.yes);
	}
	
	char *p = cast(char*)malloc(termSize.columns);
	debug assert(p);
	int w = termSize.columns;
	memset(p, ' ', w);
	
	//TODO: Output to scoped OutBuffer
	for (int i; i < lines; ++i)
		cwriteln(p, w);
	
	free(p);
	
	version (Trace) {
		sw.stop;
		trace("time='%s µs'", sw.peek.total!"usecs");
	}
}

//TODO: bool insertPosition?
//TODO: bool insertData?
//TODO: bool insertText?
private char[] renderRow(ubyte[] chunk, long pos) {
	//TODO: Consider realloc on terminal width
	//      In screen.initiate
	enum BUFFER_SIZE = 2048;
	__gshared char[BUFFER_SIZE] buffer;
	__gshared char *bufferptr = buffer.ptr;
	
	// Insert OFFSET
	size_t indexData = offsetFormatter.offset(bufferptr, pos);
	bufferptr[indexData++] = ' '; // index: OFFSET + space
	
	const uint dataLen = (setting.columns * (binaryFormatter.size + 1)); /// data row character count
	size_t indexChar = indexData + dataLen; // Position for character column
	
	*(cast(ushort*)(bufferptr + indexChar)) = 0x2020; // DATA-CHAR spacer
	indexChar += 2; // indexChar: indexData + dataLen + spacer
	
	// Format DATA and CHAR
	// NOTE: Smaller loops could fit in cache...
	//       And would separate data/text logic
	foreach (data; chunk) {
		//TODO: Maybe binary data formatter should include space
		// Data translation
		bufferptr[indexData++] = ' ';
		indexData += binaryFormatter.data(bufferptr + indexData, data);
		// Character translation
		immutable(char)[] units = transcoder.transform(data);
		if (units.length) { // Has utf-8 codepoints
			foreach (codeunit; units)
				bufferptr[indexChar++] = codeunit;
		} else // Invalid character, insert default character
			bufferptr[indexChar++] = setting.defaultChar;
	}
	
	size_t end = indexChar;
	
	// data length < minimum row requirement = in-fill data and text columns
	if (chunk.length < setting.columns) {
		// In-fill characters: left = Columns - ChunkLength
		size_t leftchar = (setting.columns - chunk.length); // Bytes left
		memset(bufferptr + indexChar, ' ', leftchar);
		// In-fill binary data: left = CharactersLeft * (DataSize + 1)
		size_t leftdata = leftchar * (binaryFormatter.size + 1);
		memset(bufferptr + indexData, ' ', leftdata);
		
		end += leftchar;
	}
	
	return buffer[0..end];
}

//TODO: More renderRow unittests
//TODO: Maybe split rendering components?
unittest {
	//	 Offset(hex)   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
	assert(renderRow([ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf ], 0) ==
		"          0  00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f  ................");
	assert(renderRow([ 0 ], 0x10) ==
		"         10  00                                               .               ");
}

// !SECTION

// SECTION Console Write functions

size_t cwrite(char c) {
	return terminalOutput(&c, 1);
}
size_t cwrite(const(char)[] _str) {
	return terminalOutput(_str.ptr, _str.length);
}
size_t cwriteln(char *_str, size_t size) {
	return terminalOutput(_str, size);
}
size_t cwriteln(const(char)[] _str) {
	return cwrite(_str) + cwrite('\n');
}
size_t cwritef(A...)(const(char)[] fmt, A args) {
	import std.format : sformat;
	char[256] buf = void;
	return cwrite(sformat(buf, fmt, args));
}
size_t cwritefln(A...)(const(char)[] fmt, A args) {
	return cwritef(fmt, args) + cwrite('\n');
}
size_t cwriteAt(int x, int y, char c) {
	terminalPos(x, y);
	return cwrite(c);
}
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

// !SECTION