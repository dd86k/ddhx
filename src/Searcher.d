module Searcher;

import std.stdio;
import std.format : format;
import ddhx, Utils;

private enum CHUNK_SIZE = MB / 2;

//TODO: Progress bar
//TODO: One main function with an ubyte[] parameter

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

//TODO: ONE function that translate any strings to a byte array

void SearchUTF8String(const char[] s)
{
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

void SearchUTF16String(const char[] s)
{
    //TODO: UTF-16 string searching
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
                    GotoC(pos);
                    MessageAlt(format(` Found wstring "%s" at %XH`, s, pos));
                    return;
                }
            }
            ++pos;
        }
    }
    MessageAlt("Not found");
}