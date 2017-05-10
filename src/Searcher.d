module Searcher;

import std.stdio;
import Utils;
import ddhx;

private enum CHUNK_SIZE = MB / 2;

void SearchByte(const ubyte b)
{
    MessageAlt("Searching byte...");
    long pos = CurrentPosition + 1;
    CurrentFile.seek(pos);
    foreach (const ubyte[] buf; CurrentFile.byChunk(CHUNK_SIZE)) {
        foreach (i; buf) {
            if (b == i) {
                import std.format : format;
                GotoC(pos);
                MessageAlt(format(" Found byte %02XH at %XH", b, pos));
                return;
            }
            ++pos;
        }
    }
    MessageAlt("Not found");
}

void SearchUTF8String(const char[] s)
{
    // Hopefully this gets the first byte out of the lot.
    // Usually, since this is in UTF-8, it's likely it'll also be an ASCII
    // character.
    const char b = s[0];
    const size_t len = s.length;
    MessageAlt("Searching string...");
    long pos = CurrentPosition + 1;
    CurrentFile.seek(pos);
    //TODO: String compare between chunks
    foreach (const ubyte[] buf; CurrentFile.byChunk(CHUNK_SIZE)) {
        for (int i; i < buf.length; ++i) {
            if (b == buf[i]) {
                if (buf[i..i+len] == s) {
                    import std.format : format;
                    GotoC(pos);
                    MessageAlt(format(` Found string "%s" at %XH`, s, pos));
                    return;
                }
            }
            ++pos;
        }
    }
    MessageAlt("Not found");
}