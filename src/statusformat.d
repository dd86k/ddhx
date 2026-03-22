/// Status bar format string expander.
///
/// Provides printf-like format specifiers for customizable status bars.
/// The formatter operates in a single left-to-right pass, writing directly
/// to a writer to avoid allocation.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module statusformat;

import formatting;
import std.format : sformat;
import std.path : baseName;
import transcoder : CharacterSet, charsetID;

/// Buffer-backed writer for formatting into a char[] slice, it's "write-and-forget".
/// This is used by report_position to format into g_messagebuf, it's "write-and-retain".
struct SliceWriter
{
    char[] buf;
    size_t pos;
    
    void put(char c)
    {
        if (pos < buf.length)
            buf[pos++] = c;
    }
    
    void put(scope const(char)[] s)
    {
        foreach (ch; s)
            put(ch);
    }
    
    void repeat(char c, size_t n)
    {
        foreach (_; 0 .. n)
            put(c);
    }
    
    size_t length() const { return pos; }
}

/// Expand a status format string into a writer, stopping at maxCols.
///
/// Params:
///   writer   = Writer to output into (by ref)
///   fmt      = The format string (e.g., "%e %m | %t | %c | %p")
///   session  = Session pointer for accessing all state
///   sel      = Pre-computed selection
///   maxCols  = Terminal width; stop writing when reached
/// Returns: Number of columns written.
int formatStatus(Writer, Session, Selection)(ref Writer writer, const(char)[] fmt,
    Session* session, Selection sel, int maxCols)
{
    int col;
    size_t i;
    while (i < fmt.length && col < maxCols)
    {
        if (fmt[i] != '%')
        {
            writer.put(fmt[i]);
            col++;
            i++;
            continue;
        }

        // '%' found
        if (++i >= fmt.length)
        {
            // Trailing '%', output literally
            writer.put('%');
            col++;
            break;
        }

        const(char)[] result = resolveSpecifier(fmt, i, session, sel);

        // Write result characters, respecting maxCols
        foreach (ch; result)
        {
            if (col >= maxCols)
                break;
            writer.put(ch);
            col++;
        }
    }

    return col;
}

private const(char)[] resolveSpecifier(Session, Selection)(const(char)[] fmt, ref size_t i,
    Session* session, Selection sel)
{
    __gshared char[64] tmpbuf;
    __gshared ElementText abuf0;
    __gshared ElementText abuf1;
    
    char c = fmt[i++];
    
    switch (c) {
    case '%': // literal '%'
        return "%";

    case 'f': // target basename
        string target = session.target;
        if (target is null || target.length == 0)
            return "(new buffer)";
        return baseName(target);

    case 'F': // target path
        string target = session.target;
        if (target is null || target.length == 0)
            return "(new buffer)";
        return target;

    case 's': // document size in decimal
        return sformat(tmpbuf, "%d", session.editor.size());

    case 'S': // document size in human binary size
        return humanSize(tmpbuf, session.editor.size());

    case 'm': // current writing mode
        return writingModeToString(session.rc.writemode);

    case 'e': // edited indicator
        return session.editor.edited() ? "*" : " ";

    case 'p': // current address position in current address type
        AddressFormatter af = void;
        af.change(session.rc.address_type);
        return af.textual(abuf0, session.position_cursor, 1);

    case 'd': // current address position in decimal
        AddressFormatter af = void;
        af.change(AddressType.dec);
        return af.textual(abuf0, session.position_cursor, 1);

    case 'h': // current address position in hexadecimal
        AddressFormatter af = void;
        af.change(AddressType.hex);
        return af.textual(abuf0, session.position_cursor, 1);

    case 'o': // current address position in octal
        AddressFormatter af = void;
        af.change(AddressType.oct);
        return af.textual(abuf0, session.position_cursor, 1);

    case 'v': // selection length in bytes
        return sformat(tmpbuf, "%d", sel.length);

    case 'V': // selection range formatted in current address type
        AddressFormatter af = void;
        af.change(session.rc.address_type);
        auto s = af.textual(abuf0, sel.start, 1);
        auto e = af.textual(abuf1, sel.end, 1);
        return sformat(tmpbuf, "%s-%s", s, e);

    case 'c': // character set
        return charsetID(session.rc.charset);

    case 't': // data type
        return dataTypeToString(session.rc.data_type);

    default:
        // Unknown specifier: pass through literally
        tmpbuf[0] = '%';
        tmpbuf[1] = c;
        return cast(const(char)[])tmpbuf[0 .. 2];
    }
}

private const(char)[] humanSize(char[] buf, long size)
{
    static immutable string[] suffixes = ["B", "K", "M", "G", "T", "P"];

    if (size < 0)
        return sformat(buf, "%d", size);

    double val = cast(double)size;
    size_t si = 0;

    while (val >= 1024.0 && si + 1 < suffixes.length)
    {
        val /= 1024.0;
        si++;
    }

    if (si == 0)
        return sformat(buf, "%d%s", size, suffixes[0]);

    // Show one decimal place
    return sformat(buf, "%.1f%s", val, suffixes[si]);
}
unittest
{
    char[64] buf;

    assert(humanSize(buf, 0) == "0B");
    assert(humanSize(buf, 512) == "512B");
    assert(humanSize(buf, 1024) == "1.0K");
    assert(humanSize(buf, 1536) == "1.5K");
    assert(humanSize(buf, 1048576) == "1.0M");
    assert(humanSize(buf, 1572864) == "1.5M");
    assert(humanSize(buf, 1073741824) == "1.0G");
}
