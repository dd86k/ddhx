module Searcher;

import std.stdio;
import ddhx;
import std.format : format;
import Utils : unformat;

private enum CHUNK_SIZE = 512;

//TODO: Progress bar (only after first chunk, updates per-chunk)
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
    for (int i = invert ? 0 : 1, e; e < l; i += 2, ++e)
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
    for (int i = invert ? 0 : 3, e; e < l; i += 4, ++e)
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
                switch (CurrentOffsetType) {
                default:
                    MessageAlt(format(" Found byte %02XH at %X", b, pos));
                    break;
                case OffsetType.Decimal:
                    MessageAlt(format(" Found byte %02XH at %d", b, pos));
                    break;
                case OffsetType.Octal:
                    MessageAlt(format(" Found byte %02XH at %o", b, pos));
                    break;
                }
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
void SearchUInt16(string s, bool invert = false)
{
    long l;
    if (unformat(s, l)) {
        ubyte[2] la;
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
void SearchUInt32(string s, bool invert = false)
{
    long l;
    if (unformat(s, l)) {
        ubyte[4] la;
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
void SearchUInt64(string s, bool invert = false)
{
    long l;
    if (unformat(s, l)) {
        ubyte[8] la;
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
    if (l) {
        import Utils : bswap;
        import core.stdc.string : memcpy;
        if (invert)
        switch (size) {
            case 2:  l = bswap(l & 0xFFFF); break;
            case 4:  l = bswap(l & 0xFFFF_FFFF); break;
            default: l = bswap(l); break;
        }
        memcpy(ap, &l, size);
    }
}

private void SearchArray(ubyte[] input, string type)
{
    MessageAlt(format(" Searching %s...", type));
    const long fsize = CurrentFile.size;
    const char b = input[0];
    const size_t len = input.length;
    long pos = CurrentPosition + 1; // To not affect CurrentPosition itself
    CurrentFile.seek(pos);
    foreach (const ubyte[] buf; CurrentFile.byChunk(CHUNK_SIZE)) {
        const size_t bufl = buf.length;
        for (size_t i; i < bufl; ++i) {
            if (buf[i] == b) {
                const size_t ilen = i + len;
                if (ilen < bufl) { // Within CHUNK
                    if (buf[i..i+len] == input) {
S_FOUND:
                        const long n = pos + i; // New position
                        switch (CurrentOffsetType) {
                        default:
                            MessageAlt(format(" Found %s value at %X", type, n));
                            break;
                        case OffsetType.Decimal:
                            MessageAlt(format(" Found %s value at %d", type, n));
                            break;
                        case OffsetType.Octal:
                            MessageAlt(format(" Found %s value at %o", type, n));
                            break;
                        }
                        GotoC(n);
                        return;
                    }
                } else if (ilen < fsize) { // Out-of-chunk
                    CurrentFile.seek(pos + i);
                    if (CurrentFile.byChunk(len).front == input) {
                        goto S_FOUND;
                    }
                } else goto S_END; // EOF otherwise, can't continue
            }
        }
        pos += CHUNK_SIZE;
    }
S_END:
    MessageAlt(format(" Type %s was not found", type));
}