/*
 * Search 
 */

module searcher;

import std.stdio;
import core.stdc.string : memcpy;
import std.encoding : transcode;
import ddhx;
import std.format : format;
import utils : unformat;
import std.range : chunks;

/// File search chunk buffer size
private enum CHUNK_SIZE = 4096;

/**
 * Search an UTF-8/ASCII string
 * Params: s = string
 */
void SearchUTF8String(const char[] s) {
	SearchArray(cast(ubyte[])s, "string");
}

/**
 * Search an UTF-16 string
 * Params:
 *   s = string
 *   invert = Invert endianness
 */
void SearchUTF16String(const char[] s, bool invert = false) {
	//TODO: See if we can use proper UTF-16 conversion
	wstring ws;
	transcode(s, ws);
	size_t l;
	wchar* wp = cast(wchar*)ws;
	while (*wp != 0xFFFF) { ++wp; ++l; }
	l *= 2;
	debug MessageAlt(format("WS LENGTH: %d", l));
	ubyte[] buf = new ubyte[l];
	memcpy(cast(byte*)buf, cast(byte*)ws, l);
	//TODO: invert
	SearchArray(buf, "wstring");
}

/**
 * Search an UTF-32 string
 * Params:
 *   s = string
 *   invert = Invert endianness
 */
void SearchUTF32String(const char[] s, bool invert = false) {
	//TODO: See if we can use proper UTF-32 conversion
	dstring ds;
	transcode(s, ds);
	size_t l;
	wchar* dp = cast(wchar*)ds;
	while (*dp != 0xFFFF) { ++dp; ++l; }
	l *= 4;
	debug MessageAlt(format("DS LENGTH: %d", l));
	ubyte[] buf = new ubyte[l];
	memcpy(cast(byte*)buf, cast(byte*)ds, l);
	//TODO: invert
	SearchArray(buf, "dstring");
}

/**
 * Search a byte
 * Params: b = ubyte
 */
void SearchByte(const ubyte b) {
	MessageAlt("Searching byte...");
	long pos = fpos + 1;
	foreach (const ubyte[] buf; (cast(ubyte[])MMFile[]).chunks(CHUNK_SIZE)) {
		foreach (i; buf) {
			if (b == i) {
				GotoC(pos);
				return;
			}
			++pos;
		}
	}
	MessageAlt("Byte not found");
}

/**
 * Search for a 16-bit value.
 * Params:
 *   s = Input
 *   invert = Invert endianness
 */
void SearchUInt16(string s, bool invert = false) {
	long l = void;
	if (unformat(s, l)) {
		__gshared ubyte[2] la;
		itoa(&la[0], 2, l, invert);
		SearchArray(la, "short");
	} else
		MessageAlt("Could not parse number");
}

/**
 * Search for a 32-bit value.
 * Params:
 *   s = Input
 *   invert = Invert endianness
 */
void SearchUInt32(string s, bool invert = false) {
	long l = void;
	if (unformat(s, l)) {
		__gshared ubyte[4] la;
		itoa(&la[0], 4, l, invert);
		SearchArray(la, "int");
	} else
		MessageAlt("Could not parse number");
}

/**
 * Search for a 64-bit value.
 * Params:
 *   s = Input
 *   invert = Invert endianness
 */
void SearchUInt64(string s, bool invert = false) {
	long l = void;
	if (unformat(s, l)) {
		__gshared ubyte[8] la;
		itoa(&la[0], 8, l, invert);
		SearchArray(la, "long");
	} else
		MessageAlt("Could not parse number");
}

/**
 * Converts a number into an array. Endian can be swapped.
 * Params:
 *   ap = Destination array pointer
 *   size = Size of the operation (usually 2, 4, and 8)
 *   l = Reference number
 *   invert = Invert endianness
 */
private void itoa(ubyte* ap, size_t size, long l, bool invert = false) {
	//TODO: template for "size" with TYPE
	if (l) {
		import utils : bswap16, bswap32, bswap64;
		if (invert) switch (size) {
			case 2:  l = bswap16(cast(ushort)l); break;
			case 4:  l = bswap32(cast(uint)l); break;
			default: l = bswap64(l); break;
		}
		memcpy(ap, &l, size);
	}
}

private void SearchArray(ubyte[] input, string type) {
	MessageAlt(" Searching %s", type);
	const ubyte b = input[0];
	const size_t len = input.length;
	long pos = fpos + 1; // To not affect CurrentPosition itself
	foreach (const ubyte[] buf; (cast(ubyte[])MMFile[]).chunks(CHUNK_SIZE)) {
		const size_t bufl = buf.length;
		for (size_t i; i < bufl; ++i) {
			if (buf[i] == b) {
				const size_t ilen = i + len;
				if (ilen < bufl) { // Within CHUNK
					if (buf[i..i+len] == input) {
S_FOUND:                			GotoC(pos + i);
						return;
					}
				} else if (ilen < fsize) { // Out-of-chunk
				//TODO:
					/*CurrentFile.seek(pos + i);
					if (CurrentFile.byChunk(len).front == input) {
						goto S_FOUND;
					}*/
				} else goto S_END; // EOF otherwise, can't continue
			}
		}
		pos += CHUNK_SIZE;
	}
S_END:
	MessageAlt(" Type not found: %s", type);
}