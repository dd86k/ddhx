module Searcher;

import std.stdio;
import Utils;
import ddhx;

private enum CHUNK_SIZE = 2 * MB;

void SearchByte(const ubyte b)
{
    //TODO: Fix byte searching
    MessageAlt("Searching byte...");
    long pos = CurrentPosition;
    foreach (buf; CurrentFile.byChunk(CHUNK_SIZE)) {
        for (int i; i < buf.length; ++i) {
            if (b == buf[i]) {
                import std.format : format;
                long l = pos + Buffer.length;
                Goto(l);
                MessageAlt(format(" Found byte %02XH at %XH", b, l));
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
    //import core.stdc.string;
    const char b = s[0];
    const size_t len = s.length;
    MessageAlt("Searching string...");
    long pos = CurrentPosition;
    //TODO: Fix string searching
    //TODO: String compare if between chunks
    foreach (buf; CurrentFile.byChunk(CHUNK_SIZE)) {
        for (int i; i < buf.length; ++i) {
            if (b == buf[i]) { // OK
                if (buf[i..i+len+1] == s) { // Doesn't work
                    import std.format : format;
                    const long l = pos + Buffer.length;
                    Goto(l);
                    MessageAlt(format(` Found string "%s" at %XH`, s, l));
                    return;
                }
            }
            ++pos;
        }
    }
    MessageAlt("Not found");
}