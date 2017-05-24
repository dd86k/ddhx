module Searcher;

import std.stdio;
import std.format : format;
import ddhx, Utils : MB;

private enum CHUNK_SIZE = MB / 2;

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
 * Search an UTF-16LE string
 * Params: s = string
 */
void SearchUTF16String(const char[] s)
{//TODO: bool bigendian
    const size_t l = s.length;
    ubyte[] buf = new ubyte[l * 2];
    for (int i = 1, e = 0; e < l; i += 2, ++e) buf[i] = s[e];
    SearchArray(buf, "wstring");
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

private void SearchArray(const ubyte[] a, string type)
{
    MessageAlt(format("Searching %s...", type));
    const char b = a[0];
    const size_t len = a.length;
    long pos = CurrentPosition + 1;
    CurrentFile.seek(pos);
    //TODO: array compare between chunks
    foreach (const ubyte[] buf; CurrentFile.byChunk(CHUNK_SIZE)) {
        for (int i; i < buf.length; ++i) {
            if (b == buf[i]) {
                if (buf[i..i+len] == a) {
                    GotoC(pos);
                    MessageAlt(format(" Found %s value at %XH", type, pos));
                    return;
                }
            }
            ++pos;
        }
    }
    MessageAlt("Not found");
}