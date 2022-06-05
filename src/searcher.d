/// Search module.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module searcher;

import ddhx;
import os.file;

/// Search buffer size.
private enum BUFFER_SIZE = 4 * 1024;

/*int data(ref Editor editor, out long pos, const(void) *data, size_t len, bool dir) {
}*/

/// Binary search.
/// Params:
/// 	pos = Found position.
/// 	data = Needle pointer.
/// 	len = Needle length.
/// 	dir = Search direction. If set, forwards. If unset, backwards.
/// Returns: Error code if set.
int searchData(out long pos, const(void) *data, size_t len, bool dir) {
	int function(out long, const(void)*, size_t) F = dir ? &forward : &backward;
	return F(pos, data, len);
}

/// Search for binary data forward.
/// Params:
/// 	pos = Found position in file.
/// 	data = Data pointer.
/// 	len = Data length.
/// Returns: Error code if set.
private
int forward(out long newPos, const(void) *data, size_t len) {
	import std.array : uninitializedArray;
	import core.stdc.string : memcmp;
	alias compare = memcmp; // avoids confusion with memcpy/memcmp
	
	version (Trace) trace("data=%s len=%u", data, len);
	
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
	
	// Setup
	IoState state = void;
	ddhx.io.save(state);
	long pos = ddhx.io.position + 1; /// New haystack position
	ddhx.io.seek(Seek.start, pos);
	
	version (Trace) trace("start=%u", pos);
	
	size_t haystackIndex = void;
	ubyte[] haystack = void;
	
L_CONTINUE:
	ddhx.io.read2(fileBuffer, haystack);
	const size_t haystackLen = haystack.length;
	
	// For every byte
	for (haystackIndex = 0; haystackIndex < haystackLen; ++haystackIndex) {
		// Check first byte
		if (haystack[haystackIndex] != firstByte) continue;
		
		// If first byte is indifferent and length is of 1, then
		// we're done.
		if (firstByteOnly) goto L_FOUND;
		
		// In-haystack or out-haystack check
		// Determined if needle fits within haystack (chunk)
		if (haystackIndex + len < haystackLen) { // fits inside haystack
			if (compare(haystack.ptr + haystackIndex, needle, len) == 0)
				goto L_FOUND;
		} else { // needle spans across haystacks
			const long t = pos + haystackIndex; // temporary seek
			ddhx.io.seek(Seek.start, t); // Go at chunk index
			//TODO: Check length in case of EOF
			ubyte[] n = void;
			ddhx.io.read2(needleBuffer, n); // Read needle length
			if (compare(n.ptr, needle, len) == 0)
				goto L_FOUND;
			ddhx.io.seek(Seek.start, pos); // Not found, go back where we last read
		}
	}
	
	// Increase (search) position with chunk length.
	pos += haystackLen;
	
	// Check if last haystack.
	if (ddhx.io.eof == false) goto L_CONTINUE;
	
	// Not found
	ddhx.io.seek(Seek.start, state.position);
	return errorSet(ErrorCode.notFound);

L_FOUND: // Found
	newPos = pos + haystackIndex; // Position + Chunk index = Found position
	return 0;
}

/// Search for binary data backward.
/// Params:
/// 	pos = Found position in file.
/// 	data = Data pointer.
/// 	len = Data length.
/// Returns: Error code if set.
private
int backward(out long newPos, const(void) *data, size_t len) {
	import std.array : uninitializedArray;
	import core.stdc.string : memcmp;
	alias compare = memcmp; // avoids confusion with memcpy/memcmp
	
	version (Trace) trace("data=%s len=%u", data, len);
	
	if (ddhx.io.position < 2)
		return errorSet(ErrorCode.insufficientSpace);
	
	ubyte *needle = cast(ubyte*)data;
	/// First byte for data to compare with haystack.
	const ubyte lastByte = needle[len - 1];
	const bool lastByteOnly = len == 1;
	/// File buffer.
	ubyte[] fileBuffer = uninitializedArray!(ubyte[])(BUFFER_SIZE);
	/// Allocated if size is higher than one.
	/// Used to read file data to compare with needle if needle extends
	/// across haystack chunks.
	ubyte[] needleBuffer;
	
	if (lastByteOnly == false)
		needleBuffer = uninitializedArray!(ubyte[])(len);
	
	// Setup
	IoState state = void;
	ddhx.io.save(state);
	long pos = ddhx.io.position - 1; /// Chunk position
	
	version (Trace) trace("start=%u", pos);
	
	size_t haystackIndex = void;
	ubyte[] haystack = void;
	size_t haystackLen = BUFFER_SIZE;
	ptrdiff_t diff = void;
	
L_CONTINUE:
	pos -= haystackLen;
	
	// Adjusts buffer size to read [0..]
	if (pos < 0) {
		haystackLen += pos;
		fileBuffer = uninitializedArray!(ubyte[])(haystackLen);
		pos = 0;
	}
	
	ddhx.io.seek(Seek.start, pos);
	ddhx.io.read2(fileBuffer, haystack);
	
	// For every byte
	for (haystackIndex = haystackLen; haystackIndex-- > 0;) {
		// Check last byte
		if (haystack[haystackIndex] != lastByte) continue;
		
		diff = 0; // fix for only byte
		
		// If first byte is indifferent and length is of 1, then
		// we're done.
		if (lastByteOnly) goto L_FOUND;
		
		diff = haystackIndex - len + 1; // Go at needle[0]
		
		// In-haystack or out-haystack check
		// Determined if needle fits within haystack (chunk)
		if (diff >= 0) { // fits inside haystack
			if (compare(haystack.ptr + diff, needle, len) == 0)
				goto L_FOUND;
		} else { // needle spans across haystacks
			ddhx.io.seek(Seek.start, pos + diff); // temporary seek
			ubyte[] n = void;
			ddhx.io.read2(needleBuffer, n); // Read needle length
			if (compare(n.ptr, needle, len) == 0)
				goto L_FOUND;
			ddhx.io.seek(Seek.start, pos); // Go back we where last
		}
	}
	
	// Acts like EOF.
	if (pos > 0) goto L_CONTINUE;
	
	// Not found
	ddhx.io.seek(Seek.start, state.position);
	return errorSet(ErrorCode.notFound);

L_FOUND: // Found
	newPos = pos + diff; // Position + Chunk index = Found position
	return 0;
}

/// Finds the next position indifferent to specified byte.
/// Params:
/// 	data = Byte.
/// 	newPos = Found position.
/// Returns: Error code.
int searchSkip(ubyte data, out long newPos) {
	import std.array : uninitializedArray;
	
	/// File buffer.
	ubyte[] fileBuffer = uninitializedArray!(ubyte[])(BUFFER_SIZE);
	size_t haystackIndex = void;
	
	IoState state = void;
	ddhx.io.save(state);
	long pos = ddhx.io.position + 1;
	ubyte[] haystack = void;
	
L_CONTINUE:
	ddhx.io.seek(Seek.start, pos); // Fix for mmfile
	ddhx.io.read2(fileBuffer, haystack);
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
//	ddhx.io.restore(state); // Revert to old position before search
	ddhx.io.seek(Seek.start, state.position);
	return errorSet(ErrorCode.notFound);
L_FOUND: // Found
	newPos = pos + haystackIndex; // Position + Chunk index = Found position
	return 0;
}
