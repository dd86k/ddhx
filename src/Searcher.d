module Searcher;

import std.stdio;
import Utils;
import ddhx;

private enum CHUNK_SIZE = MB / 2;

void SearchByte(const ubyte b)
{
    MessageAlt("Searching byte...");
    long pos = CurrentPosition;
    foreach (const ubyte[] buf; CurrentFile.byChunk(CHUNK_SIZE))
    {
        for (int i; i < buf.length; ++i)
            if (b == buf[i]) {
                import std.format : format;
                long l = pos + i + Buffer.length;
                Goto(l);
                MessageAlt(format(" Found byte %02XH at %XH", b, l));
                return;
            }
        pos += CHUNK_SIZE;
    }
    MessageAlt("Not found");
}

void SearchUTF8String(const char[] s)
{
    const ubyte b = cast(ubyte)s[0];
}