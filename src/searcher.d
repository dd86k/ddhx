/// Search module.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module searcher;

import std.array : uninitializedArray;
import core.stdc.string : memcmp;
import editor, error;

alias compare = memcmp; // avoids confusion with memcpy/memcmp

/// Search buffer size.
private enum BUFFER_SIZE = 4 * 1024;

/*int data(ref Editor editor, out long pos, const(void) *data, size_t len, bool dir) {
}*/

/// Binary search.
/// Params:
///     pos = Found position.
///     data = Needle pointer.
///     len = Needle length.
///     dir = Search direction. If set, forwards. If unset, backwards.
/// Returns: Error code if set.
int searchData(out long pos, const(void) *data, size_t len, bool dir) {
    int function(out long, const(void)*, size_t) F = dir ? &forward : &backward;
    return F(pos, data, len);
}

/// Search for binary data forward.
/// Params:
///     pos = Found position in file.
///     data = Data pointer.
///     len = Data length.
/// Returns: Error code if set.
private
int forward(out long newPos, const(void) *data, size_t len) {
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
    const long oldPos = editor.position;
    long pos = oldPos + 1; /// New haystack position
    editor.seek(pos);
    
    version (Trace) trace("start=%u", pos);
    
    size_t haystackIndex = void; /// haystack chunk index
    
L_CONTINUE:
    ubyte[] haystack = editor.read(fileBuffer);
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
            editor.seek(t);    // Go at chunk start + index
            ubyte[] tc = editor.read(needleBuffer); // Read needle length
            if (editor.eof) // Already hit past the end with needle length
                goto L_NOTFOUND; // No more chunks
            if (compare(tc.ptr, needle, len) == 0)
                goto L_FOUND;
            editor.seek(pos); // Negative, return to chunk start
        }
    }
    
    // Increase (search) position with chunk length.
    pos += haystackLen;
    
    // Check if last haystack.
    if (editor.eof == false) goto L_CONTINUE;
    
    // Not found
L_NOTFOUND:
    editor.seek(oldPos);
    return errorSet(ErrorCode.notFound);

L_FOUND: // Found
    newPos = pos + haystackIndex; // Position + Chunk index = Found position
    return 0;
}

/// Search for binary data backward.
/// Params:
///     pos = Found position in file.
///     data = Data pointer.
///     len = Data length.
/// Returns: Error code if set.
private
int backward(out long newPos, const(void) *data, size_t len) {
    version (Trace) trace("data=%s len=%u", data, len);
    
    if (editor.position < 2)
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
    
    if (lastByteOnly == false) // No need for buffer if needle is a byte
        needleBuffer = uninitializedArray!(ubyte[])(len);
    
    // Setup
    const long oldPos = editor.position;
    long pos = oldPos - 1; /// Chunk position
    editor.seek(pos);
    
    version (Trace) trace("start=%u", pos);
    
    size_t haystackIndex = void;
    size_t haystackLen = BUFFER_SIZE;
    ptrdiff_t diff = void;
    
L_CONTINUE:
    pos -= haystackLen;
    
    // Adjusts buffer size to read chunk if it goes past start of haystack.
    if (pos < 0) {
        haystackLen += pos;
        fileBuffer = uninitializedArray!(ubyte[])(haystackLen);
        pos = 0;
    }
    
    editor.seek(pos);
    ubyte[] haystack = editor.read;
    
    // For every byte
    for (haystackIndex = haystackLen; haystackIndex-- > 0;) {
        // Check last byte
        if (haystack[haystackIndex] != lastByte) continue;
        
        // Fix when needle is one byte
        diff = 0;
        
        // If first byte is indifferent and length is of 1, then
        // we're done.
        if (lastByteOnly) goto L_FOUND;
        
        // Go at needle
        diff = haystackIndex - len + 1; // Go at needle[0]
        
        // In-haystack or out-haystack check
        // Determined if needle fits within haystack (chunk)
        if (diff >= 0) { // fits inside haystack
            if (compare(haystack.ptr + diff, needle, len) == 0)
                goto L_FOUND;
        } else { // needle spans across haystacks
            editor.seek(pos + diff); // temporary seek
            ubyte[] tc = editor.read(needleBuffer); // Read needle length
            if (compare(tc.ptr, needle, len) == 0)
                goto L_FOUND;
            editor.seek(pos); // Go back we where last
        }
    }
    
    // Acts like EOF.
    if (pos > 0) goto L_CONTINUE;
    
    // Not found
    editor.seek(oldPos);
    return errorSet(ErrorCode.notFound);

L_FOUND: // Found
    newPos = pos + diff; // Position + Chunk index = Found position
    return 0;
}

/// Finds the next position indifferent to specified byte.
/// Params:
///     data = Byte.
///     newPos = Found position.
/// Returns: Error code.
int searchSkip(ubyte data, out long newPos) {
    version (Trace) trace("data=0x%x", data);
    
    /// File buffer.
    ubyte[] fileBuffer = uninitializedArray!(ubyte[])(BUFFER_SIZE);
    size_t haystackIndex = void;
    
    const long oldPos = editor.position;
    long pos = oldPos + 1;
    
L_CONTINUE:
    editor.seek(pos);
    ubyte[] haystack = editor.read(fileBuffer);
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
    editor.seek(oldPos);
    return errorSet(ErrorCode.notFound);

L_FOUND: // Found
    newPos = pos + haystackIndex; // Position + Chunk index = Found position
    return 0;
}
