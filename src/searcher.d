/**
 * Search module.
 */
module searcher;

import std.stdio;
import std.encoding : transcode;
import ddhx;
import utils : unformat;
import utils;

/// File search chunk buffer size
private enum CHUNK_SIZE = 4096;

private struct search_t {
	union {
		ubyte[2] a16;
		short i16;
		ubyte[4] a32;
		int i32;
		ubyte[8] a64;
		long i64;
	}
}

/**
 * Search an UTF-8/ASCII string
 * Params: s = string
 */
void search_utf8(const char[] s) {
	search_arr(cast(ubyte[])s, "string");
}

/**
 * Search an UTF-16 string
 * Params:
 *   s = string
 */
void search_utf16(const char[] s) {
	wstring ws;
	transcode(s, ws);
	ubyte[1024] buf = void;
	wchar* p = cast(wchar*)buf;
	size_t l;
	foreach (const wchar c; ws) {
		p[l++] = c;
	}
	search_arr(buf[0..l], "wstring");
}

/**
 * Search an UTF-32 string
 * Params:
 *   s = string
 */
void search_utf32(const char[] s) {
	dstring ds;
	transcode(s, ds);
	ubyte[1024] buf = void;
	dchar* p = cast(dchar*)buf;
	size_t l;
	foreach (const dchar c; ds) {
		p[l++] = c;
	}
	search_arr(buf[0..l], "dstring");
}

/**
 * Search a byte
 * Params: b = ubyte
 */
void search_u8(const ubyte b) {
	ddhx_msglow("Searching byte...");
	ubyte[1] a = void;
	a[0] = b;
	search_arr(a, "byte");
}

/**
 * Search for a 16-bit value.
 * Params:
 *   input = Input
 *   invert = Invert endianness
 */
void search_u16(string input, bool invert = false) {
	long l = void;
	if (unformat(input, l) == false) {
		ddhx_msglow("Could not parse number");
		return;
	}
	search_t s = void;
	s.i32 = invert ? bswap16(cast(short)l) : cast(short)l;
	search_arr(s.a16, "u16");
}

/**
 * Search for a 32-bit value.
 * Params:
 *   input = Input
 *   invert = Invert endianness
 */
void search_u32(string input, bool invert = false) {
	long l = void;
	if (unformat(input, l) == false) {
		ddhx_msglow("Could not parse number");
		return;
	}
	search_t s = void;
	s.i32 = invert ? bswap32(cast(int)l) : cast(int)l;
	search_arr(s.a32, "u32");
}

/**
 * Search for a 64-bit value.
 * Params:
 *   input = Input
 *   invert = Invert endianness
 */
void search_u64(string input, bool invert = false) {
	long l = void;
	if (unformat(input, l) == false) {
		ddhx_msglow("Could not parse number");
		return;
	}
	search_t s = void;
	s.i64 = invert ? bswap64(l) : l;
	search_arr(s.a64, "u64");
}

private void search_arr(ubyte[] data, string type) {
	ddhx_msglow(" Searching %s...", type);
	const ubyte firstbyte = data[0];
	const size_t datalen = data.length;
	size_t pos = cast(size_t)fpos + 1; // do not affect file position itself
	size_t posmax = pos + CHUNK_SIZE;

	ubyte[] buf = void;
	outer: do {
		buf = cast(ubyte[])CFile[pos..posmax];
		const size_t buflen = buf.length;
		for (size_t i; i < buflen; ++i) {
			if (buf[i] != firstbyte) continue;

			const size_t ilen = i + datalen;
			if (ilen < buflen) { // Within CHUNK
				if (buf[i..i + datalen] == data) {
S_FOUND:
					ddhx_seek(pos + i);
					return;
				}
			} else if (ilen < fsize) { // Out-of-chunk
				if (cast(ubyte[])CFile[i..i+datalen] == data) {
					goto S_FOUND;
				}
			} else break outer;
		}

		pos = posmax; posmax += CHUNK_SIZE;
	} while (pos < fsize);
	ddhx_msglow(" Not found (%s)", type);
}