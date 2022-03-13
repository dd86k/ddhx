/// Search module.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module ddhx.searcher;

import ddhx;

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

/// Default haystack buffer size.
private enum BUFFER_SIZE = 16 * 1024;

private enum LAST_BUFFER_SIZE = 128;
private __gshared ubyte[LAST_BUFFER_SIZE] lastItem;
private __gshared size_t lastSize;
private __gshared string lastType;
private __gshared bool wasBackward;
private __gshared bool hasLast;

/// Search last item.
/// Returns: Error code if set.
int searchLast() {
	return hasLast ?
		search2(lastItem.ptr, lastSize, lastType, wasBackward) :
		errorSet(ErrorCode.noLastItem);
}

/// Binary search. Saves last item data, length, and search direction.
/// Params:
/// 	data = Needle pointer.
/// 	len = Needle length.
/// 	type = Needle name for the type.
/// 	backward = Search direction. If set, searches backwards.
/// Returns: Error code if set.
int search(const(void) *data, size_t len, string type, bool backward) {
	import core.stdc.string : memcpy;
	
	version (Trace) trace("data=%s len=%u type=%s", data, len, type);
	
	debug assert(len, "len="~len.stringof);
	
	wasBackward = backward;
	lastType = type;
	lastSize = len;
	//TODO: Check length against LAST_BUFFER_SIZE
	memcpy(lastItem.ptr, data, len);
	hasLast = true;
	
	return search2(data, len, type, backward);
}

private
int search2(const(void) *data, size_t len, string type, bool backward) {
	msgBottom(" Searching %s...", type);
	long pos = void;
	const int e = backward ?
		searchBackward(pos, data, len) :
		searchForward(pos, data, len);
	if (e == 0) {
		appSafeSeek(pos);
		//TODO: Format position depending on current offset format
		msgBottom(" Found at 0x%x", pos);
	}
	return e;
}

/// Search for binary data forward.
/// Params:
/// 	pos = Found position in file.
/// 	data = Data pointer.
/// 	len = Data length.
/// Returns: Error code if set.
private
int searchForward(out long newPos, const(void) *data, size_t len) {
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
	OSFileState state = void;
	io.save(state);
	long pos = io.position + 1; /// New haystack position
	io.seek(Seek.start, pos);
	
	version (Trace) trace("start=%u", pos);
	
	size_t haystackIndex = void;
	ubyte[] haystack = void;
	
L_CONTINUE:
	io.read2(fileBuffer, haystack);
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
			io.seek(Seek.start, t); // Go at chunk index
			//TODO: Check length in case of EOF
			ubyte[] n = void;
			io.read2(needleBuffer, n); // Read needle length
			if (compare(n.ptr, needle, len) == 0)
				goto L_FOUND;
			io.seek(Seek.start, pos); // Not found, go back where we last read
		}
	}
	
	// Increase (search) position with chunk length.
	pos += haystackLen;
	
	// Check if last haystack.
	if (io.eof == false) goto L_CONTINUE;
	
	// Not found
	io.seek(Seek.start, state.position);
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
int searchBackward(out long newPos, const(void) *data, size_t len) {
	import std.array : uninitializedArray;
	import core.stdc.string : memcmp;
	alias compare = memcmp; // avoids confusion with memcpy/memcmp
	
	version (Trace) trace("data=%s len=%u", data, len);
	
	if (io.position < 2)
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
	OSFileState state = void;
	io.save(state);
	long pos = io.position - 1; /// Chunk position
	
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
	
	io.seek(Seek.start, pos);
	io.read2(fileBuffer, haystack);
	
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
			io.seek(Seek.start, pos + diff); // temporary seek
			ubyte[] n = void;
			io.read2(needleBuffer, n); // Read needle length
			if (compare(n.ptr, needle, len) == 0)
				goto L_FOUND;
			io.seek(Seek.start, pos); // Go back we where last
		}
	}
	
	// Acts like EOF.
	if (pos > 0) goto L_CONTINUE;
	
	// Not found
	io.seek(Seek.start, state.position);
	return errorSet(ErrorCode.notFound);

L_FOUND: // Found
	newPos = pos + diff; // Position + Chunk index = Found position
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
		if (pos + io.readSize > io.size)
			pos = io.size - io.readSize;
		io.seek(Seek.start, pos);
		io.read();
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
	
	/// File buffer.
	ubyte[] fileBuffer = uninitializedArray!(ubyte[])(BUFFER_SIZE);
	size_t haystackIndex = void;
	
	OSFileState state = void;
	io.save(state);
	long pos = io.position + 1;
	ubyte[] haystack = void;
	
L_CONTINUE:
	io.seek(Seek.start, pos); // Fix for mmfile
	io.read2(fileBuffer, haystack);
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
//	io.restore(state); // Revert to old position before search
	io.seek(Seek.start, state.position);
	return errorSet(ErrorCode.notFound);
L_FOUND: // Found
	newPos = pos + haystackIndex; // Position + Chunk index = Found position
	return 0;
}
