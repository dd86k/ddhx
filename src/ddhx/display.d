/// Handles complex terminal operations.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.display;

import std.range : chunks;
import std.conv : text;
import core.stdc.string : memset, memcpy;
import core.stdc.stdlib : malloc, free;
import ddhx.os.terminal;
import ddhx.formatter;
import ddhx.transcoder;
import ddhx.utils.math;
import ddhx.logger;

//TODO: cache rendered (data) lines
//      dedicated char buffers

// Display allocates buffer and returns it
// 

//TODO: ELEMENT
//      union { long _; char[8] data; }
//      int digits;

struct LINE
{
    long base;
    
    int baselen;
    char[24] basestr;
    
    int datalen;    /// Number of characters printed for data section
    char *data;
    
    int textlen;    /// Number of characters printed for text section
    char *text;
}

struct BUFFER
{
    int flags;
    
    int rows;       /// Initial requested row count
    int columns;    /// Initial requested column count
    
    int datacap;    /// Data buffer size (capacity)
    int textcap;    /// Text buffer size (capacity)
    
    int lncount;    /// Number of lines rendered (obviously not over rows count)
    LINE* lines;
}

void disp_init(bool tui)
{
    terminalInit(tui ? TermFeat.altScreen | TermFeat.inputSys : 0);
}

BUFFER* disp_create(int rows, int cols, int flags)
{
    trace("rows=%d cols=%d flags=%x", rows, cols, flags);
    
    // Assuming max oct 377 + 1 space for one LINE of formatted data
    int databfsz = cols * 4;
    // Assuming max 3 bytes per UTF-8 character, no emoji support, for one LINE of text data
    int textbfsz = cols * 3;
    //
    int linesz = cast(int)LINE.sizeof + databfsz + textbfsz;
    // 
    int totalsz = cast(int)BUFFER.sizeof + (rows * linesz);
    
    trace("dsz=%d tsz=%d lsz=%d total=%d", databfsz, textbfsz, linesz, totalsz);
    
    BUFFER* buffer = cast(BUFFER*)malloc(totalsz);
    if (buffer == null)
        return buffer;
    
    // Layout:
    //   BUFFER struct
    //   LINE... structures
    //   Data and text... buffers per-LINE
    
    buffer.flags = flags;
    buffer.rows = rows;
    buffer.columns = cols;
    buffer.datacap = databfsz;
    buffer.textcap = textbfsz;
    buffer.lines = cast(LINE*)(cast(void*)buffer + BUFFER.sizeof);
    char* bp = cast(char*)buffer + BUFFER.sizeof + (cast(int)LINE.sizeof * rows);
    for (int i; i < rows; ++i)
    {
        LINE *line = &buffer.lines[i];
        line.base = 0;
        line.datalen = line.textlen = 0;
        line.data = bp;
        line.text = bp + databfsz;
        bp += databfsz + textbfsz;
    }
    
    return buffer;
}

void disp_set_datafmt(int datafmt)
{
}
void disp_set_addrfmt(int addrfmt)
{
}
void disp_set_character(int charset)
{
}

int disp_readkey()
{
Lread:
    TermInput i = terminalRead();
    if (i.type != InputType.keyDown) goto Lread;
    return i.key;
}

// Get maximum element size in characters
int disp_elem_msize(int fmt) // note: plus space
{
    switch (fmt) with (Format) {
    case hex: return 3; // " ff"
    case dec: return 4; // " 255"
    case oct: return 4; // " 377"
    default: assert(false, "Invalid fmt");
    }
}

void disp_cursor_enable(bool enabled)
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
void disp_size(ref int rows, ref int cols)
{
    TerminalSize ts = terminalSize();
    rows = ts.rows;
    cols = ts.columns;
}

/// 
void disp_header(int columns,
    int addrfmt = Format.hex)
{
    enum BUFSZ = 2048;
    __gshared char[BUFSZ] buffer;
    
    static immutable string prefix = "Offset(";
    
    int elemsize = void;
    string soff = void;
    //size_t function(char*, ubyte) format;
    switch (addrfmt) with (Format)
    {
    case hex:
        elemsize = 2;
        soff = "hex";
        //format = &format8hex;
        break;
    case dec:
        elemsize = 3;
        soff = "dec";
        //format = &;
        break;
    case oct:
        elemsize = 3;
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
        //i += format(&buffer.ptr[i], cast(ubyte)col);
        i += formatval(buffer.ptr + i, 24, elemsize, col, addrfmt);
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

LINE* disp_find_line(long pos)
{
    return null;
}

void disp_render_line(LINE *line,
    long base, ubyte[] data,
    int columns,
    int datafmt, int addrfmt,
    char defaultchar, int textfmt,
    int addrpad, int groupsize)
{
    // Prepare data formatting functions
    int elemsz = void; // Size of one data element, in characters, plus space
    //size_t function(char*, ubyte) formatdata; // Byte formatter
    switch (datafmt) with (Format)
    {
    case hex:
        //formatdata = &format8hex;
        elemsz = 2;
        break;
    case dec:
        elemsz = 3;
        break;
    case oct:
        elemsz = 3;
        break;
    default:
        assert(false, "Invalid data format");
    }
    
    // Prepare address formatting functions
    /*
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
    */
    
    // Prepare transcoder
    string function(ubyte) transcode = getTranscoder(textfmt);

    line.base = base;
    //line.baselen = cast(int)formataddr(line.basestr.ptr, base);
    line.baselen = cast(int)formatval(line.basestr.ptr, 24, addrpad, base, addrfmt);
    
    // Insert data and text bytes
    int di, ci, cnt;
    foreach (u8; data)
    {
        ++cnt; // Number of bytes processed
        
        // Format data element into data buffer
        line.data[di++] = ' ';
        //di += formatdata(&line.data[di], u8);
        //TODO: Fix buffer length
        di += formatval(line.data + di, 24, elemsz, u8, textfmt | F_ZEROPAD);
        
        // Transcode character and insert it into text buffer
        immutable(char)[] units = transcode(u8);
        if (units.length == 0) // No utf-8 codepoints, insert default char
        {
            line.text[ci++] = defaultchar;
            continue;
        }
        foreach (codeunit; units)
            line.text[ci++] = codeunit;
    }
    
    // If row is incomplete, in-fill with spaces
    if (cnt < columns)
    {
        // Remaining length in bytes
        int rem = columns - cnt;
        
        // Fill empty data space and adjust data index
        int datsz = rem * (elemsz + 1);
        memset(line.data + di, ' ', datsz); di += datsz;
        
        // Fill empty text space and adjust text index
        memset(line.text + ci, ' ', rem); ci += rem;
    }
    
    line.datalen = di;
    line.textlen = ci;
}

void disp_render_buffer(BUFFER *buffer,
    long base, ubyte[] data,
    int columns,
    int datafmt, int addrfmt,
    char defaultchar, int textfmt,
    int addrpad, int groupsize)
{
    assert(buffer);
    assert(columns > 0);
    assert(datafmt >= 0);
    assert(addrfmt >= 0);
    assert(defaultchar);
    assert(textfmt >= 0);
    assert(addrpad > 0);
    assert(groupsize > 0);
    
    //TODO: Check columns vs. buffer's?
    
    // Render lines
    int lncnt;
    size_t lnidx;
    foreach (chunk; chunks(data, columns))
    {
        if (lnidx >= buffer.rows)
        {
            trace("Line index exceeded buffer row capacity (%d v. %d)", lnidx, buffer.rows);
            break;
        }
        
        LINE *line = &buffer.lines[lnidx++];
        
        disp_render_line(line, base, chunk,
            columns, datafmt, addrfmt,
            defaultchar, textfmt,
            addrpad, groupsize);
        
        base += columns;
        ++lncnt;
    }
    buffer.lncount = lncnt;
}

void disp_print_buffer(BUFFER *buffer)
{
    assert(buffer, "Buffer pointer null");
    
    for (int l; l < buffer.lncount; ++l)
        disp_print_line(&buffer.lines[l]);
}

void disp_print_line(LINE *line)
{
    assert(line, "Line pointer null");
    
    static immutable string space = "  ";
    static immutable string newln = "\n";
    
    terminalWrite(line.basestr.ptr, line.baselen);
    terminalWrite(space.ptr, space.length - 1);
    terminalWrite(line.data, line.datalen);
    terminalWrite(space.ptr, space.length);
    terminalWrite(line.text, line.textlen);
    terminalWrite(newln.ptr, newln.length);
}
