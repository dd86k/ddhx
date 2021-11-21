/**
 * Search module.
 */
module ddhx.searcher;

import std.stdio;
import std.encoding : transcode;
import core.bitop;
import ddhx.ddhx, ddhx.utils, ddhx.error;

private enum LAST_BUFFER_SIZE = 128;
private __gshared ubyte[128] lastItem;
private __gshared size_t lastSize;
private __gshared string lastType;
private __gshared bool hasLast;

// NOTE: core.bitop.byteswap only appeared recently
pragma(inline, true)
private ushort bswap16(ushort v) pure nothrow @nogc @safe {
	return cast(ushort)((v << 8) | (v >> 8));
}

int search(T)(string v) {
	static if (is(T == ubyte)) {
		long l = void;
		if (unformat(v, l) == false)
			return ddhxError(DdhxError.unparsable);
		if (l < byte.min || l > ubyte.max)
			return ddhxError(DdhxError.overflow);
		ubyte data = cast(ubyte)l;
		return search(&data, ubyte.sizeof, "u8");
	} else static if (is(T == ushort)) {
		long l = void;
		if (unformat(v, l) == false)
			return ddhxError(DdhxError.unparsable);
		if (l < short.min || l > ushort.max)
			return ddhxError(DdhxError.overflow);
		ushort data = cast(ushort)l;
//		if (invert)
//			data = bswap16(data);
		return search(&data, ushort.sizeof, "u16");
	} else static if (is(T == uint)) {
		long l = void;
		if (unformat(v, l) == false)
			return ddhxError(DdhxError.unparsable);
		if (l < int.min || l > uint.max)
			return ddhxError(DdhxError.overflow);
		uint data = cast(uint)l;
//		if (invert)
//			data = bswap(data);
		return search(&data, uint.sizeof, "u32");
	} else static if (is(T == ulong)) {
		long l = void;
		if (unformat(v, l) == false)
			return ddhxError(DdhxError.unparsable);
//		if (invert)
//			l = bswap(l);
		return search(&l, ulong.sizeof, "u64");
	} /*else static if (is(T == ubyte[])) {
		return search(v.ptr, v.length, "u8[]");
	}*/ else static if (is(T == string)) {
		return search(v.ptr, v.length, "utf-8 string");
	} else static if (is(T == wstring)) {
		wstring ws;
		transcode(v, ws);
		return search(ws.ptr, ws.length, "utf-16 string");
	} else static if (is(T == dstring)) {
		dstring ds;
		transcode(v, ds);
		return search(ds.ptr, ds.length, "utf-32 string");
	}
}

int searchLast() {
	if (hasLast)
		return search2(lastItem.ptr, lastSize, lastType);
	else
		return ddhxError(DdhxError.noLastItem);
}

private int search(const(void) *data, size_t len, string type) {
	import ddhx.terminal : conheight;
	import core.stdc.string : memcpy;
	debug import std.conv : text;
	
	debug assert(len, "len="~len.text);
	
	lastType = type;
	lastSize = len;
	memcpy(lastItem.ptr, data, len);
	hasLast = true;
	
	return search2(data, len, type);
}

private int search2(const(void) *data, size_t len, string type) {
	ddhxMsgLow(" Searching %s...", type);
	long pos = void;
	const int e = searchInternal(data, len, pos);
	if (e == 0) {
		if (pos + input.bufferSize > input.size)
			pos = input.size - input.bufferSize;
		input.seek(pos);
		globals.buffer = input.read();
		ddhxUpdateOffsetbar();
		ddhxDrawRaw();
		ddhxMsgLow(" Found at 0x%x", pos);
	}
	return e;
}

//TODO: Add direction
//      bool backward
private int searchInternal(const(void) *data, size_t len, out long pos) {
	enum BUFFER_SIZE = 16 * 1024;
	import core.stdc.string : memcmp;
	
	ubyte *ptr = cast(ubyte*)data;
	const ubyte mark = ptr[0];
	const bool byteSearch = len == 1;
	ubyte[] inputBuffer = new ubyte[BUFFER_SIZE];
	ubyte[] dataBuffer;
	
	if (byteSearch == false)
		dataBuffer = new ubyte[len];
	
	ubyte[] in_ = void;
	long p = input.position + 1;
	input.seek(p);
	do {
		in_ = input.readBuffer(inputBuffer);
		
		for (size_t i_; i_ < in_.length; ++i_, ++p) {
			if (in_[i_] != mark) continue;
			
			if (byteSearch)
				goto L_FOUND;
			
			// in buffer?
			if (i_ + len < in_.length) { // in-buffer check
				if (memcmp(in_.ptr + i_, ptr, len) == 0)
					goto L_FOUND;
			} else { // out-buffer check
				input.seek(p);
				input.readBuffer(dataBuffer);
				if (memcmp(dataBuffer.ptr, ptr, len) == 0)
					goto L_FOUND;
				input.seek(p);
			}
		}
	} while (in_.length == BUFFER_SIZE);
	
	input.seek(input.position);
	return ddhxError(DdhxError.notFound);
L_FOUND:
	pos = p;
	return 0;
}
