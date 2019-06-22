/**
 * Search module.
 */
module searcher;

import std.stdio;
import core.stdc.string : memcpy;
import std.encoding : transcode;
import ddhx;
import utils : unformat;
import std.range : chunks;
import utils;

/// File search chunk buffer size
private enum CHUNK_SIZE = 4096;

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
	//TODO: See if we can use proper UTF-32 conversion
	dstring ds;
	transcode(s, ds);
	ubyte[1024] buf = void;
	wchar* p = cast(wchar*)buf;
	size_t l;
	foreach (const wchar c; ds) {
		p[l++] = c;
	}
	search_arr(buf[0..l], "dstring");
}

/**
 * Search a byte
 * Params: b = ubyte
 */
void search_u8(const ubyte b) {
	msgalt("Searching byte...");
	ubyte[1] a = [ b ];
	search_arr(a, "byte");
	msgalt("Byte not found");
}

/**
 * Search for a 16-bit value.
 * Params:
 *   s = Input
 *   invert = Invert endianness
 */
void search_u16(string s, bool invert = false) {
	long l = void;
	if (unformat(s, l) == false) {
		msgalt("Could not parse number");
		return;
	}
	const ushort u16 = invert ? bswap16(cast(ushort)l) : cast(ushort)l;
	ubyte[2] la = void;
	*(cast(ushort*)la) = u16;
	search_arr(la, "u16");
}

/**
 * Search for a 32-bit value.
 * Params:
 *   s = Input
 *   invert = Invert endianness
 */
void search_u32(string s, bool invert = false) {
	long l = void;
	if (unformat(s, l) == false) {
		msgalt("Could not parse number");
		return;
	}
	const uint u32 = invert ? bswap32(cast(uint)l) : cast(uint)l;
	ubyte[4] la = void;
	*(cast(uint*)la) = u32;
	search_arr(la, "u32");
}

/**
 * Search for a 64-bit value.
 * Params:
 *   s = Input
 *   invert = Invert endianness
 */
void search_u64(string s, bool invert = false) {
	long l = void;
	if (unformat(s, l)) {
		if (invert) l = bswap64(l);
		ubyte[8] la = void;
		*(cast(long*)la) = l;
		search_arr(la, "u64");
	} else
		msgalt("Could not parse number");
}

private void search_arr(ubyte[] data, string type) {
	msgalt(" Searching %s", type);
	const ubyte firstbyte = data[0];
	const size_t datal = data.length;
	long pos = fpos + 1; // To not affect file position itself

	outer: foreach (const ubyte[] buf; (cast(ubyte[])CFile[]).chunks(CHUNK_SIZE)) {
		const size_t bufl = buf.length;
		inner: for (size_t i; i < bufl; ++i) {
			if (buf[i] != firstbyte) break inner;

			const size_t ilen = i + datal;
			if (ilen < bufl) { // Within CHUNK
				if (buf[i..i+datal] == data) {
					hxgoto_c(pos + i);
					return;
				}
			} else if (ilen < fsize) { // Out-of-chunk
			//TODO:
				/*CurrentFile.seek(pos + i);
				if (CurrentFile.byChunk(len).front == input) {
					goto S_FOUND;
				}*/
			} else
				break outer; // EOF otherwise, can't continue
		}
		pos += CHUNK_SIZE;
	}
	msgalt(" Not found (%s)", type);
}