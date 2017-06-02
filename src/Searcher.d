module Searcher;

import std.stdio;
import std.format : format;
import ddhx, Utils : MB, unformat;

private enum CHUNK_SIZE = MB;

//TODO: Progress bar
//TODO: String REGEX (will require a new function entirely for searching)

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
 * Params:
 *   s = string
 *   invert = Invert endianness
 */
void SearchUTF16String(const char[] s, bool invert = false)
{
    const size_t l = s.length;
    ubyte[] buf = new ubyte[l * 2];
//TODO: Richer UTF-8 to UTF-16 transformation
    for (int i = invert ? 0 : 1, e = 0; e < l; i += 2, ++e)
        buf[i] = s[e];
    SearchArray(buf, "wstring");
}

/**
 * Search an UTF-32 string
 * Params:
 *   s = string
 *   invert = Invert endianness
 */
void SearchUTF32String(const char[] s, bool invert = false)
{
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
 * Params:
 *   s = Input
 *   invert = Invert endianness
 */
void SearchUInt16(string s, bool invert = false)
{
    long l;
    if (unformat(s, l)) {
        ubyte[2] la;
        itoa(&la[0], 2, l, invert);
        SearchArray(la, "short");
    } else {
		MessageAlt("Could not parse number");
    }
}

/**
 * Search for a 32-bit value.
 * Params:
 *   s = Input
 *   invert = Invert endianness
 */
void SearchUInt32(string s, bool invert = false)
{
    long l;
    if (unformat(s, l)) {
        ubyte[4] la;
        itoa(&la[0], 4, l, invert);
        SearchArray(la, "int");
    } else {
		MessageAlt("Could not parse number");
    }
}

/**
 * Search for a 64-bit value.
 * Params:
 *   s = Input
 *   invert = Invert endianness
 */
void SearchUInt64(string s, bool invert = false)
{
    long l;
    if (unformat(s, l)) {
        ubyte[8] la;
        itoa(&la[0], 8, l, invert);
        SearchArray(la, "long");
    } else {
		MessageAlt("Could not parse number");
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
    if (l) {
        import Utils : bswap;
        import core.stdc.string : memcpy;
        if (invert)
            switch (size) {
                case 2: l = bswap(l & 0xFFFF); break;
                case 4: l = bswap(l & 0xFFFF_FFFF); break;
                default: l = bswap(l); break;
            }
        //ubyte* lp = cast(ubyte*)&l;
        //for (const void* i = ap + size; ap < i; ++lp, ++ap)
        //    *ap = *lp;
        memcpy(ap, &l, size);
    }
}

private void SearchArray(ubyte[] a, string type)
{
    MessageAlt(format(" Searching %s...", type));
    const char b = a[0];
    const size_t len = a.length;
    long pos = CurrentPosition + 1;
    CurrentFile.seek(pos);
    //TODO: array compare between chunks
    foreach (const ubyte[] buf; CurrentFile.byChunk(CHUNK_SIZE)) {
        const size_t bufl = buf.length;
        for (size_t i; i < bufl; ++i) {
            if (buf[i] == b) {
                if (i + len < bufl)
                if (buf[i..i+len] == a) {
                    const long npos = pos + i;
                    GotoC(npos);
                    MessageAlt(format(" Found %s value at %XH", type, npos));
                    return;
                }
            }
        }
        pos += CHUNK_SIZE;
    }
    MessageAlt(format(" Type %s not found", type));
}