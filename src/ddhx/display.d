/// Handle display operations using the terminal functions.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.display;

import std.range : chunks;
import std.conv : text;
import core.stdc.string : memset, memcpy;
import core.stdc.stdlib;
import ddhx.os.terminal;
import ddhx.formatter;
import ddhx.transcoder;
import ddhx.utils.math;
import ddhx.logger;

// 
struct ELEMENT
{
    union
    {
        ubyte[8] orig_buffer;
        ulong orig_u64;
        ubyte orig_u8;
    }
    
    // rendered size
    size_t data_length;
    // rendered value
    char[24] data_buffer;
    // 
    size_t text_length;
    //
    char[4] text_buffer;
    
    pragma(inline, true)
    const(char)[] formatted()
    {
        return data_buffer[0..data_length];
    }
    
    pragma(inline, true)
    const(char)[] character()
    {
        return text_buffer[0..text_length];
    }
}

struct BUFFER
{
    int flags;
    
    int dataflags;  /// Formatting flags for data
    int groupsize;  /// Number of bytes for one element
    
    int addrflags;  /// Formatting flags for addresses
    int addrpadding;    /// Max width 
    
    int srcencoding;    /// Source text encoding
    int defaultchar;    /// Default character
    string function(ubyte) transcoder;  /// Text transcoding function
    
    int elemwidth;  /// Element width with padding, spaces or zeros
    
    size_t elementcount;    /// Number of elements in buffer
    ELEMENT *elements;  /// Points to element array
}

/// Initiate the display.
/// Params: tui = TUI mode. If set, turn on the alternative screen and the input system.
void disp_init(bool tui)
{
    terminalInit(tui ? TermFeat.altScreen | TermFeat.inputSys : 0);
}

/// Configure a new, or existing, buffer with a new count of elements.
/// Params:
///     buffer = If null, creates a new buffer. If set, reallocate buffer.
///     count = Element count.
///     flags = Flags.
/// Returns: Allocated buffer.
BUFFER* disp_configure(BUFFER *buffer, int count,
    int datafmt, int groupsize,
    int addrfmt, int addrpad,
    int defaultchar, int encoding)
{
    assert(count);
    
    size_t esize = count * ELEMENT.sizeof;  /// Total size of elements
    size_t bsize = esize + BUFFER.sizeof;   /// Total size of buffer structure with elements
    
    if (buffer == null) // First alloc
    {
        buffer = cast(BUFFER*)malloc(bsize);
        buffer.elements = cast(ELEMENT*)(cast(void*)buffer + BUFFER.sizeof);
    }
    else // Resizing
    {
        buffer = cast(BUFFER*)realloc(buffer, bsize);
    }
    
    if (buffer == null) // TODO: Include strerror
        throw new Exception("CRuntime exception");
    
    buffer.elementcount = count;
    
    // Set info for data formatting
    FormatInfo info = formatInfo(datafmt);
    buffer.elemwidth = info.size1;
    buffer.dataflags = datafmt | F_ZEROPAD;
    buffer.groupsize = groupsize;
    
    // Set info for address formatting
    buffer.addrflags = addrfmt;
    buffer.addrpadding = addrpad;
    
    // Set info for text formatting
    buffer.srcencoding = encoding ? encoding : CharacterSet.ascii;
    buffer.defaultchar = defaultchar ? defaultchar : '.';
    buffer.transcoder = getTranscoder(encoding);
    
    return buffer;
}
unittest
{
    trace("test=disp_configure");
    
    BUFFER *buffer = disp_configure(null, 352,
        Format.hex, 1,
        Format.hex, 11,
        '.', CharacterSet.ascii);
    assert(buffer);
    
    ELEMENT element = void;
    disp_render_element(buffer, &element, 0x21);
    assert(element.data_length == 2);
    assert(element.formatted() == "21");
    assert(element.text_length == 1);
    assert(element.character() == "!");
    
    disp_render_element(buffer, &element, 0x2a);
    assert(element.data_length == 2);
    assert(element.formatted() == "2a");
    assert(element.text_length == 1);
    assert(element.character() == "*");
    
    disp_render_element(buffer, &element, 'a');
    assert(element.formatted() == "61");
    assert(element.character() == "a");
    
    disp_render_element(buffer, &element, 0);
    assert(element.formatted() == "00");
    assert(element.character() == ".");
}

struct RECOMMENDATION
{
    int columns;
    int viewsize;
}

// With the given options, return recommended options.
RECOMMENDATION disp_recommend_values(int columns, int addressPadding, int maxdigits)
{
    trace("cols=%d addrpad=%d mdigits=%d", columns, addressPadding, maxdigits);
    
    version (unittest)
        TerminalSize termsize = TerminalSize(80, 24);
    else
        TerminalSize termsize = terminalSize();
    
    RECOMMENDATION rec;
    
    // Before division: terminal columns - (padding chars + data spacer)
    // After division: max digits by one element + data spacer per elem + 1 text char
    // NOTE: If returned columns smaller than given columns, caller should error
    rec.columns = (termsize.columns - (addressPadding + 2)) / (maxdigits + 2);

    //     
    rec.viewsize = (columns ? columns : rec.columns) * (termsize.rows - 2);
    
    return rec;
}
unittest
{
    trace("test=disp_recommend_values");
    
    // Auto columns, 11 chars for address spacing, 2 chars (hex2)
    RECOMMENDATION rec = disp_recommend_values(0, 11, 2);
    assert(rec.columns == 16);
    assert(rec.viewsize == 352);
}

int disp_readkey()
{
Lread:
    TermInput i = terminalRead();
    if (i.type != InputType.keyDown) goto Lread;
    return i.key;
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
void disp_size(ref int cols, ref int rows)
{
    TerminalSize ts = terminalSize();
    rows = ts.rows;
    cols = ts.columns;
}

// TODO: Address Padding parameter.
// TODO: If we can't fit "Offset" (with address padding), either trim it or remove it
// TODO: Change Offset(hex) to Offset:hex
// TODO: Remove optional values off parameters
/// 
void disp_header(int columns,
    int addrfmt = Format.hex,
    int addrpad = 11)
{
    enum BUFSZ = 2048;
    __gshared char[BUFSZ] buffer;
    
    static immutable string prefix = "Offset(";
    
    FormatInfo finfo = formatInfo(addrfmt);
    
    memcpy(buffer.ptr, prefix.ptr, prefix.length);
    memcpy(buffer.ptr + prefix.length, finfo.name.ptr, finfo.name.length);
    
    size_t i = prefix.length + 3;
    buffer[i++] = ')';
    buffer[i++] = ' ';
    
    for (int col; col < columns; ++col)
    {
        buffer[i++] = ' ';
        i += formatval(buffer.ptr + i, 24, finfo.size1, col, addrfmt);
    }
    
    buffer[i++] = '\n';
    
    terminalWrite(buffer.ptr, i);
}

/// 
void disp_message(const(char)* msg, size_t len)
{
    TerminalSize w = terminalSize();
    disp_cursor(w.rows - 1, 0);
    
    terminalWrite(msg, min(len, w.columns));
}

// 
void disp_render_element(BUFFER *buffer, ELEMENT *element, long value)
{
    // Copy original value
    element.orig_u64 = value;
    
    // Format data element
    element.data_length = formatval(element.data_buffer.ptr, element.data_buffer.sizeof,
        buffer.elemwidth, value, buffer.flags);
    
    // Format text element
    immutable(char)[] c = buffer.transcoder(cast(ubyte)value);
    if (c)
    {
        element.text_length = c.length;
        //element.text[0..c.length] = c[0..c.length];
        memcpy(element.text_buffer.ptr, c.ptr, c.length);
    }
    else
    {
        element.text_buffer[0] = cast(char)buffer.defaultchar;
        element.text_length = 1;
    }
}

void disp_update_element(BUFFER *buffer, size_t i, long value)
{
    assert(0, "todo");
}

void disp_render_elements(BUFFER *buffer, ubyte[] data)
{
    trace("data.length=%d", data.length);
    
    // Render all elements
    for (size_t i; i < buffer.elementcount; ++i)
    {
        // TODO: Obviously, include GROUP of bytes
        long value = data[i];
        
        disp_render_element(buffer, buffer.elements + i, value);
    }
}
unittest
{
    trace("test=disp_render_elements");
    
    BUFFER *buffer = disp_configure(null, 4,
        Format.hex, 1,
        Format.hex, 11,
        '.', CharacterSet.ascii);
    assert(buffer);
    assert(buffer.elementcount == 4);
    
    disp_render_elements(buffer, [ 0x11, 0x22, 0x33, 0x44 ]);
    
    assert(buffer.elements[0].formatted() == "11");
    assert(buffer.elements[0].character() == ".");
    
    assert(buffer.elements[1].formatted() == "22");
    assert(buffer.elements[1].character() == `"`);
    
    assert(buffer.elements[2].formatted() == "33");
    assert(buffer.elements[2].character() == "3");
    
    assert(buffer.elements[3].formatted() == "44");
    assert(buffer.elements[3].character() == "D");
}

/// Print elements to screen.
/// Params:
///     buffer = Buffer instance.
///     base = Memory location base.
///     rows = Row index.
void disp_print_all(BUFFER *buffer, long base, int cols)
{
    /// Size, in bytes, of a row, used to increment base address
    long rowsize = cols; // TODO: cols * groupsize
    
    trace("base=%x cols=%d ecount=%d", base, cols, buffer.elementcount);
    
    static immutable string spaces = "  ";
    
    for (size_t i; i < buffer.elementcount; i += cols, base += rowsize)
    {
        char[24] addrbuf = void;
        size_t asize = formatval(addrbuf.ptr, addrbuf.sizeof,
            buffer.addrpadding, base, buffer.addrflags);
        terminalWrite(addrbuf.ptr, asize);
        terminalWrite(spaces.ptr, 1);
        
        size_t mcols = min(cols, buffer.elementcount - i);
        
        for (size_t c, i2 = i; c < mcols; ++c, ++i2)
        {
            terminalWrite(spaces.ptr, 1);
            terminalWrite(buffer.elements[i2].formatted());
        }
        terminalWrite(spaces.ptr, 2);
        for (size_t c, i2 = i; c < mcols; ++c, ++i2)
        {
            terminalWrite(buffer.elements[i2].character());
        }
        
        static immutable char nl = '\n';
        terminalWrite(&nl, 1);
    }
}
