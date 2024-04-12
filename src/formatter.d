/// Handles data formatting.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module formatter;

//TODO: format function for int

size_t format8hex(char *buffer, ubyte v)
{
    buffer[1] = hexMap[v & 15];
    buffer[0] = hexMap[v >> 4];
    return 2;
}
@system unittest
{
    char[2] c = void;
    format02x(c.ptr, 0x01);
    assert(c[] == "01", c);
    format02x(c.ptr, 0x20);
    assert(c[] == "20", c);
    format02x(c.ptr, 0xff);
    assert(c[] == "ff", c);
}

size_t format64hex(char *buffer, ulong v)
{
    size_t pos;
    bool pad = true;
    for (int shift = 60; shift >= 0; shift -= 4)
    {
        const ubyte b = (v >> shift) & 15;
        if (b == 0)
        {
            if (pad && shift >= 44)
            {
                continue; // cut
            }
            else if (pad && shift >= 4)
            {
                buffer[pos++] = pad ? ' ' : '0';
                continue; // pad
            }
        }
        else // Padding no longer acceptable
            pad = false;
        buffer[pos++] = hexMap[b];
    }
    return pos;
}
@system unittest
{
    char[32] b = void;
    char *p = b.ptr;
    assert(b[0..format64hex(p, 0)]                  ==      "          0");
    assert(b[0..format64hex(p, 1)]                  ==      "          1");
    assert(b[0..format64hex(p, 0x10)]               ==      "         10");
    assert(b[0..format64hex(p, 0x100)]              ==      "        100");
    assert(b[0..format64hex(p, 0x1000)]             ==      "       1000");
    assert(b[0..format64hex(p, 0x10000)]            ==      "      10000");
    assert(b[0..format64hex(p, 0x100000)]           ==      "     100000");
    assert(b[0..format64hex(p, 0x1000000)]          ==      "    1000000");
    assert(b[0..format64hex(p, 0x10000000)]         ==      "   10000000");
    assert(b[0..format64hex(p, 0x100000000)]        ==      "  100000000");
    assert(b[0..format64hex(p, 0x1000000000)]       ==      " 1000000000");
    assert(b[0..format64hex(p, 0x10000000000)]      ==      "10000000000");
    assert(b[0..format64hex(p, 0x100000000000)]     ==     "100000000000");
    assert(b[0..format64hex(p, 0x1000000000000)]    ==    "1000000000000");
    assert(b[0..format64hex(p, ubyte.max)]          ==      "         ff");
    assert(b[0..format64hex(p, ushort.max)]         ==      "       ffff");
    assert(b[0..format64hex(p, uint.max)]           ==      "   ffffffff");
    assert(b[0..format64hex(p, ulong.max)]          == "ffffffffffffffff");
    assert(b[0..format64hex(p, 0x1010)]             ==      "       1010");
    assert(b[0..format64hex(p, 0x10101010)]         ==      "   10101010");
    assert(b[0..format64hex(p, 0x1010101010101010)] == "1010101010101010");
}

private:

immutable string hexMap = "0123456789abcdef";

size_t format02x(char *buffer, ubyte v)
{
    buffer[1] = hexMap[v & 15];
    buffer[0] = hexMap[v >> 4];
    return 2;
}
@system unittest
{
    char[2] c = void;
    format02x(c.ptr, 0x01);
    assert(c[] == "01", c);
    format02x(c.ptr, 0x20);
    assert(c[] == "20", c);
    format02x(c.ptr, 0xff);
    assert(c[] == "ff", c);
}

size_t format11x(char *buffer, long v)
{
    size_t pos;
    bool pad = true;
    for (int shift = 60; shift >= 0; shift -= 4)
    {
        const ubyte b = (v >> shift) & 15;
        if (b == 0)
        {
            if (pad && shift >= 44)
            {
                continue; // cut
            }
            else if (pad && shift >= 4)
            {
                buffer[pos++] = pad ? ' ' : '0';
                continue; // pad
            }
        } else pad = false;
        buffer[pos++] = hexMap[b];
    }
    return pos;
}
/// 
@system unittest
{
    char[32] b = void;
    char *p = b.ptr;
    assert(b[0..format11x(p, 0)]                  ==      "          0");
    assert(b[0..format11x(p, 1)]                  ==      "          1");
    assert(b[0..format11x(p, 0x10)]               ==      "         10");
    assert(b[0..format11x(p, 0x100)]              ==      "        100");
    assert(b[0..format11x(p, 0x1000)]             ==      "       1000");
    assert(b[0..format11x(p, 0x10000)]            ==      "      10000");
    assert(b[0..format11x(p, 0x100000)]           ==      "     100000");
    assert(b[0..format11x(p, 0x1000000)]          ==      "    1000000");
    assert(b[0..format11x(p, 0x10000000)]         ==      "   10000000");
    assert(b[0..format11x(p, 0x100000000)]        ==      "  100000000");
    assert(b[0..format11x(p, 0x1000000000)]       ==      " 1000000000");
    assert(b[0..format11x(p, 0x10000000000)]      ==      "10000000000");
    assert(b[0..format11x(p, 0x100000000000)]     ==     "100000000000");
    assert(b[0..format11x(p, 0x1000000000000)]    ==    "1000000000000");
    assert(b[0..format11x(p, ubyte.max)]          ==      "         ff");
    assert(b[0..format11x(p, ushort.max)]         ==      "       ffff");
    assert(b[0..format11x(p, uint.max)]           ==      "   ffffffff");
    assert(b[0..format11x(p, ulong.max)]          == "ffffffffffffffff");
    assert(b[0..format11x(p, 0x1010)]             ==      "       1010");
    assert(b[0..format11x(p, 0x10101010)]         ==      "   10101010");
    assert(b[0..format11x(p, 0x1010101010101010)] == "1010101010101010");
}

immutable static string decMap = "0123456789";
size_t format03d(char *buffer, ubyte v)
{
    buffer[2] = (v % 10) + '0';
    buffer[1] = (v / 10 % 10) + '0';
    buffer[0] = (v / 100 % 10) + '0';
    return 3;
}
@system unittest
{
    char[3] c = void;
    format03d(c.ptr, 1);
    assert(c[] == "001", c);
    format03d(c.ptr, 10);
    assert(c[] == "010", c);
    format03d(c.ptr, 111);
    assert(c[] == "111", c);
}

size_t format11d(char *buffer, long v)
{
    debug import std.conv : text;
    enum ulong I64MAX = 10_000_000_000_000_000_000UL;
    size_t pos;
    bool pad = true;
    for (ulong d = I64MAX; d > 0; d /= 10)
    {
        const long r = (v / d) % 10;
        if (r == 0)
        {
            if (pad && d >= 100_000_000_000)
            {
                continue; // cut
            }
            else if (pad && d >= 10)
            {
                buffer[pos++] = pad ? ' ' : '0';
                continue;
            }
        } else pad = false;
        debug assert(r >= 0 && r < 10, "r="~r.text);
        buffer[pos++] = decMap[r];
    }
    return pos;
}
/// 
@system unittest
{
    char[32] b = void;
    char *p = b.ptr;
    assert(b[0..format11d(p, 0)]                 ==   "          0");
    assert(b[0..format11d(p, 1)]                 ==   "          1");
    assert(b[0..format11d(p, 10)]                ==   "         10");
    assert(b[0..format11d(p, 100)]               ==   "        100");
    assert(b[0..format11d(p, 1000)]              ==   "       1000");
    assert(b[0..format11d(p, 10_000)]            ==   "      10000");
    assert(b[0..format11d(p, 100_000)]           ==   "     100000");
    assert(b[0..format11d(p, 1000_000)]          ==   "    1000000");
    assert(b[0..format11d(p, 10_000_000)]        ==   "   10000000");
    assert(b[0..format11d(p, 100_000_000)]       ==   "  100000000");
    assert(b[0..format11d(p, 1000_000_000)]      ==   " 1000000000");
    assert(b[0..format11d(p, 10_000_000_000)]    ==   "10000000000");
    assert(b[0..format11d(p, 100_000_000_000)]   ==  "100000000000");
    assert(b[0..format11d(p, 1000_000_000_000)]  == "1000000000000");
    assert(b[0..format11d(p, ubyte.max)]  ==          "        255");
    assert(b[0..format11d(p, ushort.max)] ==          "      65535");
    assert(b[0..format11d(p, uint.max)]   ==          " 4294967295");
    assert(b[0..format11d(p, ulong.max)]  == "18446744073709551615");
    assert(b[0..format11d(p, 1010)]       ==          "       1010");
}

size_t format03o(char *buffer, ubyte v)
{
    buffer[2] = (v % 8) + '0';
    buffer[1] = (v / 8 % 8) + '0';
    buffer[0] = (v / 64 % 8) + '0';
    return 3;
}
@system unittest
{
    import std.conv : octal;
    char[3] c = void;
    format03o(c.ptr, 1);
    assert(c[] == "001", c);
    format03o(c.ptr, octal!20);
    assert(c[] == "020", c);
    format03o(c.ptr, octal!133);
    assert(c[] == "133", c);
}

size_t format11o(char *buffer, long v)
{
    size_t pos;
    if (v >> 63) buffer[pos++] = '1'; // ulong.max coverage
    bool pad = true;
    for (int shift = 60; shift >= 0; shift -= 3)
    {
        const ubyte b = (v >> shift) & 7;
        if (b == 0)
        {
            if (pad && shift >= 33)
            {
                continue; // cut
            }
            else if (pad && shift >= 3)
            {
                buffer[pos++] = pad ? ' ' : '0';
                continue;
            }
        } else pad = false;
        buffer[pos++] = hexMap[b];
    }
    return pos;
}
/// 
@system unittest
{
    import std.conv : octal;
    char[32] b = void;
    char *p = b.ptr;
    assert(b[0..format11o(p, 0)]                     ==  "          0");
    assert(b[0..format11o(p, 1)]                     ==  "          1");
    assert(b[0..format11o(p, octal!10)]              ==  "         10");
    assert(b[0..format11o(p, octal!20)]              ==  "         20");
    assert(b[0..format11o(p, octal!100)]             ==  "        100");
    assert(b[0..format11o(p, octal!1000)]            ==  "       1000");
    assert(b[0..format11o(p, octal!10_000)]          ==  "      10000");
    assert(b[0..format11o(p, octal!100_000)]         ==  "     100000");
    assert(b[0..format11o(p, octal!1000_000)]        ==  "    1000000");
    assert(b[0..format11o(p, octal!10_000_000)]      ==  "   10000000");
    assert(b[0..format11o(p, octal!100_000_000)]     ==  "  100000000");
    assert(b[0..format11o(p, octal!1000_000_000)]    ==  " 1000000000");
    assert(b[0..format11o(p, octal!10_000_000_000)]  ==  "10000000000");
    assert(b[0..format11o(p, octal!100_000_000_000)] == "100000000000");
    assert(b[0..format11o(p, ubyte.max)]   ==            "        377");
    assert(b[0..format11o(p, ushort.max)]  ==            "     177777");
    assert(b[0..format11o(p, uint.max)]    ==            "37777777777");
    assert(b[0..format11o(p, ulong.max)]   == "1777777777777777777777");
    assert(b[0..format11o(p, octal!101_010)] ==          "     101010");
}

// !SECTION

version (none):

//int outputLine(long base, ubyte[] data, int row, int cursor = -1)

//TODO: Add int param for data at cursor (placeholder)
/// Render multiple lines on screen with optional cursor.
/// Params:
///     base = Offset base.
///     data = data to render.
///     cursor = Position of cursor.
/// Returns: Number of rows printed. Negative numbers indicate error.
int output(long base, ubyte[] data, int cursor = -1)
{
    int crow = void, ccol = void;
    
    if (data.length == 0)
        return 0;
    
    if (cursor < 0)
        crow = ccol = -1;
    else
    {
        crow = cursor / setting.columns;
        ccol = cursor % setting.columns;
    }
    
    version (Trace)
    {
        trace("base=%u D=%u crow=%d ccol=%d",
            base, data.length, crow, ccol);
        StopWatch sw = StopWatch(AutoStart.yes);
    }
    
    size_t buffersz = // minimum anyway
        OFFSET_SPACE + 2 + // offset + spacer
        ((binaryFormatter.size + 1) * setting.columns) + // binary + spacer * cols
        (1 + (setting.columns * 3)); // spacer + text (utf-8)
    
    char *buffer = cast(char*)malloc(buffersz);
    if (buffer == null) return -1;
    
    int lines;
    foreach (chunk; chunks(data, setting.columns))
    {
        const bool cur_row = lines == crow;
        
        Row row = makerow(buffer, buffersz, chunk, base, ccol);
        
        if (cur_row)
        {
            version (Trace) trace(
                "row.length=%u cbi=%u cbl=%u cti=%u ctl=%u bl=%u tl=%u",
                row.result.length,
                row.cursorBinaryIndex,
                row.cursorBinaryLength,
                row.cursorTextIndex,
                row.cursorTextLength,
                row.binaryLength,
                row.textLength);
            
            // between binary and text cursors
            size_t distance = row.cursorTextIndex -
                row.cursorBinaryIndex -
                row.cursorBinaryLength;
            
            char *p = buffer;
            // offset + pre-cursor binary
            p += cwrite(p, row.cursorBinaryIndex);
            // binary cursor
            terminalInvertColor;
            p += cwrite(p, row.cursorBinaryLength);
            terminalResetColor;
            // post-cursor binary + pre-cursor text (minus spacer)
            p += cwrite(p, distance);
            // text cursor
            terminalHighlight;
            p += cwrite(p, row.cursorTextLength);
            terminalResetColor;
            // post-cursor text
            size_t rem = row.result.length - (p - buffer);
            p += cwrite(p, rem);
            
            version (Trace) trace("d=%u r=%u l=%u", distance, rem, p - buffer);
        }
        else
            cwrite(row.result.ptr, row.result.length);
        
        cwrite('\n');
        
        ++lines;
        base += setting.columns;
    }
    
    free(buffer);
    
    version (Trace)
    {
        sw.stop;
        trace("time='%s µs'", sw.peek.total!"usecs");
    }
    
    return lines;
}

//TODO: Consider moving to this ddhx
void renderEmpty(uint rows, int w)
{
    version (Trace)
    {
        trace("lines=%u rows=%u cols=%u", lines, rows, w);
        StopWatch sw = StopWatch(AutoStart.yes);
    }
    
    char *p = cast(char*)malloc(w);
    assert(p); //TODO: Soft asserts
    memset(p, ' ', w);
    
    //TODO: Output to scoped OutBuffer
    for (int i; i < rows; ++i)
        cwrite(p, w);
    
    free(p);
    
    version (Trace)
    {
        sw.stop;
        trace("time='%s µs'", sw.peek.total!"usecs");
    }
}

private
struct Row
{
    char[] result;
    
    size_t cursorBinaryIndex;
    size_t cursorBinaryLength;
    size_t cursorTextIndex;
    size_t cursorTextLength;
    
    size_t binaryLength;
    size_t textLength;
}

private
Row makerow(char *buffer, size_t bufferlen,
    ubyte[] chunk, long pos,
    int cursor_col)
{
    Row row = void;
    
    // Insert OFFSET
    size_t indexData = offsetFormatter.offset(buffer, pos);
    buffer[indexData++] = ' '; // index: OFFSET + space
    
    const uint dataLen = (setting.columns * (binaryFormatter.size + 1)); /// data row character count
    size_t indexChar = indexData + dataLen; // Position for character column
    
    *(cast(ushort*)(buffer + indexChar)) = 0x2020; // DATA-CHAR spacer
    indexChar += 2; // indexChar: indexData + dataLen + spacer
    
    // Format DATA and CHAR
    // NOTE: Smaller loops could fit in cache...
    //       And would separate data/text logic
    size_t bi0 = indexData, ti0 = indexChar;
    int currentCol;
    foreach (data; chunk)
    {
        const bool curhit = currentCol == cursor_col; // cursor hit column
        //TODO: Maybe binary data formatter should include space?
        // Data translation
        buffer[indexData++] = ' ';
        if (curhit)
        {
            row.cursorBinaryIndex  = indexData;
            row.cursorBinaryLength = binaryFormatter.size;
        }
        indexData += binaryFormatter.data(buffer + indexData, data);
        // Character translation
        immutable(char)[] units = transcoder.transform(data);
        if (curhit)
        {
            row.cursorTextIndex = indexChar;
            row.cursorTextLength = units.length ? units.length : 1;
        }
        if (units.length) // Has utf-8 codepoints
        {
            foreach (codeunit; units)
                buffer[indexChar++] = codeunit;
        } else // Invalid character, insert default character
            buffer[indexChar++] = setting.defaultChar;
        
        ++currentCol;
    }
    
    row.binaryLength = dataLen - bi0;
    row.textLength   = indexChar - ti0;
    
    size_t end = indexChar;
    
    // data length < minimum row requirement = in-fill data and text columns
    if (chunk.length < setting.columns)
    {
        // In-fill characters: left = Columns - ChunkLength
        size_t leftchar = (setting.columns - chunk.length); // Bytes left
        memset(buffer + indexChar, ' ', leftchar);
        row.textLength += leftchar;
        // In-fill binary data: left = CharactersLeft * (DataSize + 1)
        size_t leftdata = leftchar * (binaryFormatter.size + 1);
        memset(buffer + indexData, ' ', leftdata);
        row.binaryLength += leftdata;
        
        end += leftchar;
    }
    
    row.result = buffer[0..end];
    
    return row;
}