/**
 * Search module.
 * 
 * As crappy as it may be written, this is actually "sort of" of an extension
 * to the menu module, being an extension of the ddhx module.
 */
module ddhx.searcher;

import std.stdio;
import std.encoding : transcode;
import core.bitop;
import ddhx.ddhx, ddhx.utils;

// NOTE: core.bitop.byteswap only appeared recently
pragma(inline, true)
private ushort bswap16(ushort v) pure nothrow @nogc @safe {
	return cast(ushort)((v << 8) | (v >> 8));
}

void search(T)(string v, bool invert = false) {
	static if (is(T == ubyte)) {
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
		searchInternal(&data, byte.sizeof, "u8");
	} else static if (is(T == ushort)) {
		long l = void;
		if (unformat(v, l) == false) {
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
		searchInternal(&data, short.sizeof, "u16");
	} else static if (is(T == uint)) {
		long l = void;
		if (unformat(v, l) == false) {
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
		searchInternal(&data, int.sizeof, "u32");
	} else static if (is(T == ulong)) {
		long l = void;
		if (unformat(v, l) == false) {
			ddhxMsgLow("Could not parse number");
			return;
		}
		if (invert)
			l = bswap(l);
		searchInternal(&l, long.sizeof, "u64");
	} else static if (is(T == ubyte[])) {
		searchInternal(v.ptr, v.length, "u8[]");
	} else static if (is(T == string)) {
		searchInternal(cast(void*)v.ptr, v.length, "utf-8 string");
	} else static if (is(T == wstring)) {
		wstring ws;
		transcode(v, ws);
		searchInternal(cast(void*)ws.ptr, ws.length, "utf-16 string");
	} else static if (is(T == dstring)) {
		dstring ds;
		transcode(v, ds);
		searchInternal(cast(void*)ds.ptr, ds.length, "utf-32 string");
	}
}

//TODO: Consider converting this to a ubyte[]
//      Calling memcmp may be inlined with this
private void searchInternal(void *data, size_t len, const(char) *type) {
	import core.stdc.string : memcmp;
	
	if (len == 0) {
		ddhxMsgLow("Empty input, cancelled");
		return;
	}
	
	ddhxMsgLow(" Searching %s...", type);
	
	//TODO: Redo search
	/*enum CHUNK_SIZE = 64 * 1024;
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
	}*/
	
	// not found
	ddhxMsgLow("Not found (%s)", type);
}
