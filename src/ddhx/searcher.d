/// Search module.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module ddhx.searcher;

import std.stdio;
import std.encoding : transcode;
import core.bitop;
import ddhx;

/// Default haystack buffer size.
private enum BUFFER_SIZE = 16 * 1024;

private enum LAST_BUFFER_SIZE = 128;
private __gshared ubyte[LAST_BUFFER_SIZE] lastItem;
private __gshared size_t lastSize;
private __gshared string lastType;
private __gshared bool hasLast;

/// Search last item.
/// Returns: Error code if set.
int searchLast() {
	return hasLast ?
		search2(lastItem.ptr, lastSize, lastType) :
		errorSet(ErrorCode.noLastItem);
}

/// Binary search.
/// Params:
/// 	data = Needle pointer.
/// 	len = Needle length.
/// 	type = Needle name.
/// Returns: Error code if set.
int search(const(void) *data, size_t len, string type) {
	import core.stdc.string : memcpy;
	
	debug assert(len, "len="~len.stringof);
	
	lastType = type;
	lastSize = len;
	//TODO: Check length again LAST_BUFFER_SIZE
	memcpy(lastItem.ptr, data, len);
	hasLast = true;
	
	return search2(data, len, type);
}

private int search2(const(void) *data, size_t len, string type) {
	msgBottom(" Searching %s...", type);
	long pos = void;
	const int e = searchInternal(data, len, pos);
	if (e) {
		msgBottom(" Type %s not found", type);
	} else {
		if (pos + input.bufferSize > input.size)
			pos = input.size - input.bufferSize;
		input.seek(pos);
		input.read();
		displayRenderTop();
		displayRenderMainRaw();
		//TODO: Format depending on current offset format
		msgBottom(" Found at 0x%x", pos);
	}
	return e;
}

//TODO: Add direction
//      bool backward
//TODO: Add comparer
//      We're already 'wasting' a call to memcpy, so might as well have
//      comparer functions.
//      struct Comparer
//      - needle data
//      - lots of unions for needle samples (first cmp)
//      - support SIMD when possible (D_SIMD)
//      sample(ref Comparer,ubyte[]) (via function pointer)
//      compare(ref Comparer,ubyte[]) (via function pointer)
//      - haystack slice vs. needle
//      - 1,2,4,8 bytes -> direct
//      - 16,32 bytes   -> simd
//      - default       -> memcmp
/// (Internal) Binary search.
/// Params:
/// 	data = Data pointer.
/// 	len = Data length.
/// 	pos = Absolute position in file.
/// Returns: Error code if set
private
int searchInternal(const(void) *data, size_t len, out long newPos) {
	import std.array : uninitializedArray;
	import core.stdc.string : memcmp;
	alias compare = memcmp; // avoids confusion with memcpy/memcmp
	
	ubyte *needle = cast(ubyte*)data;
	/// First byte for data to compare with haystack.
	const ubyte firstByte = needle[0];
	const bool firstByteOnly = len == 1;
	/// File buffer.
	ubyte[] fileBuffer = uninitializedArray!(ubyte[])(BUFFER_SIZE);
	/// Allocated if size is higher than one.
	/// Used to read file data to compare with needle if needle extends
	/// across haystack chunks.
	ubyte[] needleBuffer;
	
	if (firstByteOnly == false)
		needleBuffer = uninitializedArray!(ubyte[])(len);
	
	/// Current search position
	const long oldPos = input.position;
	long pos = input.position + 1;
	input.seek(pos);
	
	size_t haystackIndex = void;
	
L_CONTINUE:
	ubyte[] haystack = input.readBuffer(fileBuffer);
	const size_t haystackLen = haystack.length;
	
	// For every byte
	for (haystackIndex = 0; haystackIndex < haystackLen; ++haystackIndex) {
		// Check first byte
		if (haystack[haystackIndex] != firstByte) continue;
		
		// If first byte is indifferent and length is of 1, then
		// we're done.
		if (firstByteOnly)
			goto L_FOUND;
		
		// In-haystack or out-haystack check
		// Determined if needle fits within haystack
		if (haystackIndex + len < haystackLen) // fits inside haystack
		{
			if (compare(haystack.ptr + haystackIndex, needle, len) == 0)
				goto L_FOUND;
		}
		else // needle spans across haystacks
		{
			const long t = pos + haystackIndex; // temporary seek
			input.seek(t); // Go at chunk index
			//TODO: Check length in case of EOF
			input.readBuffer(needleBuffer); // Read needle length
			if (compare(needleBuffer.ptr, needle, len) == 0)
				goto L_FOUND;
			input.seek(pos); // Go back where we read
		}
	}
	
	// Increase (search) position with chunk length.
	pos += haystackLen;
	
	// Check if last haystack.
	// If haystack length is lower than the default size,
	// this simply means it's the last haystack since it reached
	// OEF (by having read less data).
	if (haystackLen == BUFFER_SIZE) goto L_CONTINUE;
	
	// Not found
	input.seek(oldPos); // Revert to old position before search
	return errorSet(ErrorCode.notFound);
L_FOUND: // Found
	newPos = pos + haystackIndex; // Position + Chunk index = Found position
	return 0;
}

/// Finds the next position indifferent to specified byte.
/// Params:
/// 	data = Byte.
/// Returns: Error code.
int skipByte(ubyte data) {
	msgBottom(" Skipping 0x%x...", data);
	long pos = void;
	const int e = skipByte(data, pos);
	if (e) {
		msgBottom(" Couldn't skip byte 0x%x", data);
	} else {
		if (pos + input.bufferSize > input.size)
			pos = input.size - input.bufferSize;
		input.seek(pos);
		input.read();
		displayRenderTop();
		displayRenderMainRaw();
		//TODO: Format depending on current offset format
		msgBottom(" Found at 0x%x", pos);
	}
	return e;
}

private
int skipByte(ubyte data, out long newPos) {
	import std.array : uninitializedArray;
	
	/// Current search position
	const long oldPos = input.position;
	long pos = input.position + 1;
	
	/// File buffer.
	ubyte[] fileBuffer = uninitializedArray!(ubyte[])(BUFFER_SIZE);
	size_t haystackIndex = void;
	
L_CONTINUE:
	input.seek(pos); // Fix for mmfile
	ubyte[] haystack = input.readBuffer(fileBuffer);
	const size_t haystackLen = haystack.length;
	
	// For every byte
	for (haystackIndex = 0; haystackIndex < haystackLen; ++haystackIndex) {
		if (haystack[haystackIndex] != data)
			goto L_FOUND;
	}
	
	// Increase (search) position with chunk length.
	pos += haystackLen;
	
	// Check if last haystack.
	// If haystack length is lower than the default size,
	// this simply means it's the last haystack since it reached
	// OEF (by having read less data).
	if (haystackLen == BUFFER_SIZE) goto L_CONTINUE;
	
	// Not found
	input.seek(oldPos); // Revert to old position before search
	return errorSet(ErrorCode.notFound);
L_FOUND: // Found
	newPos = pos + haystackIndex; // Position + Chunk index = Found position
	return 0;
}
