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
 *   invert = Invert endianness
 */
void search_utf16(const char[] s, bool invert = false) {
	//TODO: See if we can use proper UTF-16 conversion
	wstring ws;
	transcode(s, ws);
	size_t l;
	wchar* wp = cast(wchar*)ws;
	while (*wp != 0xFFFF) { ++wp; ++l; }
	l *= 2;
	ubyte[] buf = new ubyte[l];
	memcpy(cast(byte*)buf, cast(byte*)ws, l);
	//TODO: invert
	search_arr(buf, "wstring");
}

/**
 * Search an UTF-32 string
 * Params:
 *   s = string
 *   invert = Invert endianness
 */
void search_utf32(const char[] s, bool invert = false) {
	//TODO: See if we can use proper UTF-32 conversion
	dstring ds;
	transcode(s, ds);
	size_t l;
	wchar* dp = cast(wchar*)ds;
	while (*dp != 0xFFFF) { ++dp; ++l; }
	l *= 4;
	ubyte[] buf = new ubyte[l];
	memcpy(cast(byte*)buf, cast(byte*)ds, l);
	//TODO: invert
	search_arr(buf, "dstring");
}

/**
 * Search a byte
 * Params: b = ubyte
 */
void search_u8(const ubyte b) {
	MessageAlt("Searching byte...");
	ubyte[1] a = [ b ];
	search_arr(a, "byte");
	MessageAlt("Byte not found");
}

/**
 * Search for a 16-bit value.
 * Params:
 *   s = Input
 *   invert = Invert endianness
 */
void search_u16(string s, bool invert = false) {
	long l = void;
	if (unformat(s, l)) {
		const ushort u16 = invert ? bswap16(cast(ushort)l) : cast(ushort)l;
		ubyte[2] la = void;
		*(cast(ushort*)la) = u16;
		search_arr(la, "u16");
	} else
		MessageAlt("Could not parse number");
}

/**
 * Search for a 32-bit value.
 * Params:
 *   s = Input
 *   invert = Invert endianness
 */
void search_u32(string s, bool invert = false) {
	long l = void;
	if (unformat(s, l)) {
		const uint u32 = invert ? bswap32(cast(uint)l) : cast(uint)l;
		ubyte[4] la = void;
		*(cast(uint*)la) = u32;
		search_arr(la, "u32");
	} else
		MessageAlt("Could not parse number");
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
		MessageAlt("Could not parse number");
}

private void search_arr(ubyte[] data, string type) {
	MessageAlt(" Searching %s", type);
	const ubyte firstbyte = data[0];
	const size_t datal = data.length;
	long pos = fpos + 1; // To not affect file position itself

	outer: foreach (const ubyte[] buf; (cast(ubyte[])MMFile[]).chunks(CHUNK_SIZE)) {
		const size_t bufl = buf.length;
		inner: for (size_t i; i < bufl; ++i) {
			if (buf[i] != firstbyte) break inner;

			const size_t ilen = i + datal;
			if (ilen < bufl) { // Within CHUNK
				if (buf[i..i+datal] == data) {
					GotoC(pos + i);
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
	MessageAlt(" Not found (%s)", type);
}