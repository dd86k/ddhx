module Searcher;

import std.stdio;
import std.format : format;
import ddhx, Utils : MB, unformat;

private enum CHUNK_SIZE = 2 * MB;

//TODO: Progress bar
//TODO: String REGEX

/**
 * Search an UTF-8/ASCII string
 * Params: s = string
 */
void SearchUTF8String(const char[] s)
{
    SearchArray(cast(ubyte[])s, "string");
}

/**
 * Search an UTF-16 string
 * Params: s = string
 */
void SearchUTF16String(const char[] s, bool invert = false)
{//TODO: bool bigendian
    const size_t l = s.length;
    ubyte[] buf = new ubyte[l * 2];
//TODO: Richer UTF-8 to UTF-16 transformation
    for (int i = invert ? 0 : 1, e = 0; e < l; i += 2, ++e)
        buf[i] = s[e];
    SearchArray(buf, "wstring");
}

/**
 * Search an UTF-32 string
 * Params: s = string
 */
void SearchUTF32String(const char[] s, bool invert = false)
{//TODO: bool bigendian
    const size_t l = s.length;
    ubyte[] buf = new ubyte[l * 4];
//TODO: Richer UTF-8 to UTF-16 transformation
    for (int i = invert ? 0 : 3, e = 0; e < l; i += 4, ++e)
        buf[i] = s[e];
    SearchArray(buf, "dstring");
}

/**
 * Search a byte
 * Params: b = ubyte
 */
void SearchByte(const ubyte b)
{
    MessageAlt("Searching byte...");
    long pos = CurrentPosition + 1;
    CurrentFile.seek(pos);
    foreach (const ubyte[] buf; CurrentFile.byChunk(CHUNK_SIZE)) {
        foreach (i; buf) {
            if (b == i) {
                GotoC(pos);
                MessageAlt(format(" Found byte %02XH at %XH", b, pos));
                return;
            }
            ++pos;
        }
    }
    MessageAlt("Not found");
}

/**
 * Search for a 16-bit value.
 * Params: s = Input
 */
void SearchUInt16(string s, bool invert = false)
{
    long l;
    if (unformat(s, l)) {
        ubyte[2] la;
        itoa(&la[0], 2, l, invert);
        SearchArray(la, "short");
    }
}

/**
 * Search for a 32-bit value.
 * Params: s = Input
 */
void SearchUInt32(string s, bool invert = false)
{
    long l;
    if (unformat(s, l)) {
        ubyte[4] la;
        itoa(&la[0], 4, l, invert);
        SearchArray(la, "int");
    }
}

/**
 * Search for a 64-bit value.
 * Params: s = Input
 */
void SearchUInt64(string s, bool invert = false)
{
    long l;
    if (unformat(s, l)) {
        ubyte[8] la;
        itoa(&la[0], 8, l, invert);
        SearchArray(la, "long");
    }
}

/**
 * Converts a number into an array.
 * Params:
 *   ap = Destination array pointer
 *   size = Size of the operation (usually 2, 4, and 8)
 *   l = Reference number
 *   invert = Invert endianness
 */
private void itoa(ubyte* ap, size_t size, long l, bool invert = false) {
    import Utils : bswap;
    if (l) {
        if (invert)
        switch (size) {
            case 2: l = bswap(l & 0xFFFF); break;
            case 4: l = bswap(l & 0xFFFF_FFFF); break;
            default: l = bswap(l); break;
        }
        ubyte* lp = cast(ubyte*)&l;
        for (int i = 0; i < size; ++i, ++lp, ++ap)
            *ap = *lp;
    }
}

private void SearchArray(ubyte[] a, string type)
{
    MessageAlt(format("Searching %s...", type));
    const char b = a[0];
    const size_t len = a.length;
    long pos = CurrentPosition + 1;
    CurrentFile.seek(pos);
    //TODO: array compare between chunks
    //TODO: Fix when at end of file and 0s
    foreach (const ubyte[] buf; CurrentFile.byChunk(CHUNK_SIZE)) {
        for (int i; i < CHUNK_SIZE; ++i) {
            if (buf[i] == b) {
                if (i + len < CHUNK_SIZE)
                if (buf[i..i+len] == a) {
                    GotoC(pos);
                    MessageAlt(format(" Found %s value at %XH", type, pos));
                    return;
                }
            }
            ++pos;
        }
    }
    MessageAlt(format(" Type %s not found", type));
}