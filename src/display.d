/// Handles complex terminal operations.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module display;

import std.range : chunks;
import std.conv : text;
import core.stdc.string : memset, memcpy;
import os.terminal;
import formatter;
import transcoder;
import utils.math;
import logger;

enum Format
{
    hex,
    dec,
    oct,
}

int selectFormat(string fmt)
{
    switch (fmt) with (Format)
    {
    case "hex": return hex;
    case "dec": return dec;
    case "oct": return oct;
    default:
        throw new Exception(text("Invalid format: ", fmt));
    }
}

//TODO: cache rendered (data) lines
//      dedicated char buffers

private enum
{
    TUIMODE = 0x1,
}

private __gshared
{
    /// Capabilities
    int caps;
}

void disp_init(bool tui)
{
    caps |= tui;
    terminalInit(tui ? TermFeat.altScreen | TermFeat.inputSys : 0);
}

int disp_readkey()
{
Lread:
    TermInput i = terminalRead();
    if (i.type != InputType.keyDown) goto Lread;
    return i.key;
}

// Given n columns, hint the optimal buffer size for the "view".
// If 0, calculated automatically
int disp_hint_cols()
{
    enum hexsize = 2;
    enum decsize = 3;
    enum octsize = 3;
    TerminalSize w = terminalSize();
    return (w.columns - /*gofflen*/ 16) / (hexsize + 2);
}
int disp_hint_view(int cols)
{
    TerminalSize w = terminalSize();
    
    enum hexsize = 2;
    enum decsize = 3;
    enum octsize = 3;
    
    // 16 - for text section?
    return ((w.columns - cols /* 16 */) / (hexsize + 2)) * (w.rows - 2);
}

void disp_enable_cursor()
{
    
}

void disp_disable_cursor()
{
    
}

void disp_cursor(int row, int col)
{
    terminalPos(col, row);
}
void disp_write(char* stuff, size_t sz)
{
    terminalWrite(stuff, sz);
}

/// 
void disp_header(int columns,
    int addrfmt = Format.hex)
{
    //int max = int.max;
    
    if (caps & TUIMODE)
    {
        //max = terminalSize().columns;
        disp_cursor(0, 0);
    }
    
    enum BUFSZ = 2048;
    __gshared char[BUFSZ] buffer;
    
    static immutable string prefix = "Offset(";
    
    string soff = void;
    size_t function(char*, ubyte) format;
    switch (addrfmt) with (Format)
    {
    case hex:
        soff = "hex";
        format = &format8hex;
        break;
    case dec:
        soff = "dec";
        //format = &;
        break;
    case oct:
        soff = "oct";
        //format = &;
        break;
    default:
        assert(false);
    }
    
    memcpy(buffer.ptr, prefix.ptr, prefix.length);
    memcpy(buffer.ptr + prefix.length, soff.ptr, soff.length);
    
    size_t i = prefix.length + 3;
    buffer[i++] = ')';
    buffer[i++] = ' ';
    
    for (int col; col < columns; ++col)
    {
        buffer[i++] = ' ';
        i += format(&buffer.ptr[i], cast(ubyte)col);
    }
    
    buffer[i++] = '\n';
    
    terminalWrite(buffer.ptr, i);
}

/// 
void disp_message(const(char)* msg, size_t len)
{
    TerminalSize w = terminalSize();
    disp_cursor(w.rows - 1, 0);
    
    //TODO: Invert colors for rest of space
    terminalWrite(msg, min(len, w.columns));
}

// NOTE: Settings could be passed through a structure
/// 
void disp_update(ulong base, ubyte[] data,
    int columns,
    int datafmt = Format.hex, int addrfmt = Format.hex,
    char defaultchar = '.', int textfmt = CharacterSet.ascii,
    int addrpadd = 11, int groupsize = 1)
{
    assert(columns > 0);
    
    enum BUFFERSZ = 1024 * 1024;
    __gshared char[BUFFERSZ] buffer;
    // Buffer size
    size_t bufsz = BUFFERSZ;
    // Buffer index
    size_t bi = void;
    
    // Prepare data formatting functions
    int elemsz = void; // Size of one data element, in characters, plus space
    size_t function(char*, ubyte) formatdata; // Byte formatter
    switch (datafmt) with (Format)
    {
    case hex:
        formatdata = &format8hex;
        elemsz = 3;
        break;
    case dec:
        elemsz = 4;
        break;
    case oct:
        elemsz = 4;
        break;
    default:
        assert(false, "Invalid data format");
    }
    
    // Prepare address formatting functions
    size_t function(char*, ulong) formataddr;
    switch (addrfmt) with (Format)
    {
    case hex:
        formataddr = &format64hex;
        break;
    case dec:
        break;
    case oct:
        break;
    default:
        assert(false, "Invalid address format");
    }
    
    // Prepare transcoder
    string function(ubyte) transcode = void;
    switch (textfmt) with (CharacterSet)
    {
    case ascii:
        transcode = &transcodeASCII;
        break;
    case cp437:
        transcode = &transcodeCP437;
        break;
    case ebcdic:
        transcode = &transcodeEBCDIC;
        break;
    case mac:
        transcode = &transcodeMac;
        break;
    default:
        assert(false, "Invalid character set");
    }
    
    // Starting position of text column
    size_t cstart = addrpadd + 1 + (elemsz * columns) + 2;
    
    if (caps & TUIMODE) disp_cursor(1, 0);

    foreach (chunk; chunks(data, columns))
    {
        // Format address, update address, add space
        bi = formataddr(buffer.ptr, base);
        base += columns;
        buffer[bi++] = ' ';
        
        // Insert data and text bytes
        size_t ci = cstart;
        foreach (b, u8; chunk)
        {
            buffer[bi++] = ' ';
            bi += formatdata(&buffer.ptr[bi], u8);
            
            // Transcode and insert it into buffer
            immutable(char)[] units = transcode(u8);
            if (units.length == 0) // No utf-8 codepoints, insert default char
            {
                buffer[ci++] = defaultchar;
                continue;
            }
            foreach (codeunit; units)
                buffer[ci++] = codeunit;
        }
        
        // If row isn't entirely filled by column requirement
        // NOTE: Text is filled as well to damage the display in TUI mode
        if (chunk.length < columns)
        {
            size_t rem = columns - chunk.length; // remaining bytes
            
            // Fill empty data space
            size_t sz = rem * elemsz;
            memset(&buffer.ptr[bi], ' ', sz); bi += sz;
            
            // Fill empty text space
            memset(&buffer.ptr[cstart + chunk.length], ' ', rem);
        }
        
        // Add spaces between data and text columns
        buffer[bi++] = ' ';
        buffer[bi++] = ' ';
        
        // Add length of text column and terminate with newline
        bi += ci - cstart;  // text index - text start = text size in bytes
        buffer[bi++] = '\n';
        
        trace("out=%d", bi);
        if (chunk.length < columns)
            trace("buffer=%(-%02x%)", cast(ubyte[])buffer[0..bi]);
        
        terminalWrite(buffer.ptr, bi);
    }
}

private:

