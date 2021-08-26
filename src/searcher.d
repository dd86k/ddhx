/**
 * Search module.
 * 
 * As crappy as it may be written, this is actually "sort of" of an extension
 * to the menu module, being an extension of the ddhx module.
 */
module searcher;

import std.stdio;
import std.encoding : transcode;
import core.bitop;
import ddhx;
import utils;

// NOTE: core.bitop.byteswap only appeared recently
pragma(inline, true)
private ushort bswap16(ushort v) pure nothrow @nogc @safe {
	return cast(ushort)((v << 8) | (v >> 8));
}

/**
 * Search an UTF-8/ASCII string
 * Params: v = utf-8 string
 */
void search_utf8(immutable(char)[] v) {
	search_internal(cast(void*)v.ptr, v.length, "utf-8 string");
}

/**
 * Search an UTF-16 string
 * Params:
 *   v = utf-16 string
 */
void search_utf16(immutable(char)[] v) {
	wstring ws;
	transcode(v, ws);
	search_internal(cast(void*)ws.ptr, ws.length, "utf-16 string");
}

/**
 * Search an UTF-32 string
 * Params:
 *   v = utf-32 string
 */
void search_utf32(const char[] v) {
	dstring ds;
	transcode(v, ds);
	search_internal(cast(void*)ds.ptr, ds.length, "utf-32 string");
}

/**
 * Search a byte
 * Params: v = ubyte
 */
void search_u8(string v) {
	long l = void;
	if (unformat(v, l) == false) {
		ddhxMsgLow("Could not parse number");
		return;
	}
	if (l < byte.min || l > ubyte.max) {
		ddhxMsgLow("Integer too large for a byte");
		return;
	}
	byte data = cast(byte)l;
	search_internal(&data, byte.sizeof, "u8");
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
		ddhxMsgLow("Could not parse number");
		return;
	}
	if (l < short.min || l > ushort.max) {
		ddhxMsgLow("Integer too large for a u16 value");
		return;
	}
	short data = cast(short)l;
	if (invert)
		data = bswap16(data);
	search_internal(&data, short.sizeof, "u16");
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
		ddhxMsgLow("Could not parse number");
		return;
	}
	if (l < int.min || l > uint.max) {
		ddhxMsgLow("Integer too large for a u16 value");
		return;
	}
	int data = cast(int)l;
	if (invert)
		data = bswap(data);
	search_internal(&data, int.sizeof, "u32");
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
		ddhxMsgLow("Could not parse number");
		return;
	}
	if (invert)
		l = bswap(l);
	search_internal(&l, long.sizeof, "u64");
}

/**
 * Search using raw array of byte data.
 * Params: v = Byte array
 */
void search_array(ubyte[] v) {
	search_internal(v.ptr, v.length, "u8 array");
}

//TODO: Consider converting this to a ubyte[]
//      Calling memcmp may be inlined with this
private void search_internal(void *data, size_t len, const(char) *type) {
	import core.stdc.string : memcmp;
	
	if (len == 0) {
		ddhxMsgLow("Empty input, cancelled");
		return;
	}
	
	ddhxMsgLow(" Searching %s...", type);
	
	enum CHUNK_SIZE = 64 * 1024;
	const ubyte s8 = (cast(ubyte*)data)[0];
	const ulong flimit = globals.fileSize;	/// file size
	const ulong dlimit = flimit - len; 	/// data limit
	const ulong climit = flimit - CHUNK_SIZE;	/// chunk limit
	long pos = globals.position + 1;
	
	// per chunk
	while (pos < climit) {
		const(ubyte)[] chunk = cast(ubyte[])globals.mmHandle[pos..pos+CHUNK_SIZE];
		foreach (size_t o, ubyte b; chunk) {
			// first byte does not correspond
			if (b != s8) continue;
			
			// compare data
			const long npos = pos + o;
			const(ubyte)[] d = cast(ubyte[])globals.mmHandle[npos .. npos + len];
			if (memcmp(d.ptr, data, len) == 0) {
				ddhxSeek(npos);
				return;
			}
		}
		pos += CHUNK_SIZE;
	}
	
	// rest of data
	const(ubyte)[] chunk = cast(ubyte[])globals.mmHandle[pos..$];
	foreach (size_t o, ubyte b; chunk) {
		// first byte does not correspond
		if (b != s8) continue;
		
		// if data still fits within file
		if (pos + o >= dlimit) break;
		
		// compare data
		const long npos = pos + o;
		const(ubyte)[] d = cast(ubyte[])globals.mmHandle[npos .. npos + len];
		if (memcmp(d.ptr, data, len) == 0) {
			ddhxSeek(npos);
			return;
		}
	}
	
	// not found
	ddhxMsgLow("Not found (%s)", type);
}
