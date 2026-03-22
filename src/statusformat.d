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

    case 'P': // document size in current address
        AddressFormatter af = void;
        af.change(session.rc.address_type);
        return af.textual(abuf0, session.editor.size(), 1);

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

// Test helpers - lightweight stand-ins for Session/Selection to avoid
// circular imports with ddhx module.
version(unittest)
{
    private struct TestEditor
    {
        long _size;
        bool _edited;
        long size() { return _size; }
        bool edited() { return _edited; }
    }

    private struct TestRC
    {
        AddressType address_type = AddressType.hex;
        DataType data_type = DataType.x8;
        CharacterSet charset = CharacterSet.ascii;
        WritingMode writemode = WritingMode.overwrite;
    }

    private struct TestSession
    {
        TestRC rc;
        TestEditor editor;
        string target;
        long position_cursor;
    }

    private struct TestSelection
    {
        long start, end, length;
    }

    private string sliceResult(ref SliceWriter sw)
    {
        return cast(string)sw.buf[0 .. sw.pos];
    }
}

// Literal text passthrough
unittest
{
    char[128] buf;
    SliceWriter sw = SliceWriter(buf);
    TestSession session;
    session.editor = TestEditor(100, false);
    TestSelection sel;

    formatStatus(sw, "hello world", &session, sel, 80);
    assert(sliceResult(sw) == "hello world");
}

// Percent escape
unittest
{
    char[128] buf;
    SliceWriter sw = SliceWriter(buf);
    TestSession session;
    session.editor = TestEditor(100, false);
    TestSelection sel;

    formatStatus(sw, "100%%", &session, sel, 80);
    assert(sliceResult(sw) == "100%");
}

// Unknown specifier passes through
unittest
{
    char[128] buf;
    SliceWriter sw = SliceWriter(buf);
    TestSession session;
    session.editor = TestEditor(100, false);
    TestSelection sel;

    formatStatus(sw, "%z", &session, sel, 80);
    assert(sliceResult(sw) == "%z");
}

// File info specifiers
unittest
{
    char[128] buf;
    SliceWriter sw;
    TestSession session;
    session.editor = TestEditor(1536, false);
    session.target = "/home/user/test.bin";
    TestSelection sel;

    // %f - basename
    sw = SliceWriter(buf);
    formatStatus(sw, "%f", &session, sel, 80);
    assert(sliceResult(sw) == "test.bin");

    // %F - full path
    sw = SliceWriter(buf);
    formatStatus(sw, "%F", &session, sel, 80);
    assert(sliceResult(sw) == "/home/user/test.bin");

    // %s - size in bytes
    sw = SliceWriter(buf);
    formatStatus(sw, "%s", &session, sel, 80);
    assert(sliceResult(sw) == "1536");

    // %S - human size
    sw = SliceWriter(buf);
    formatStatus(sw, "%S", &session, sel, 80);
    assert(sliceResult(sw) == "1.5K");
}

// %f/%F with no target
unittest
{
    char[128] buf;
    SliceWriter sw;
    TestSession session;
    session.editor = TestEditor(0, false);
    TestSelection sel;

    sw = SliceWriter(buf);
    formatStatus(sw, "%f", &session, sel, 80);
    assert(sliceResult(sw) == "(new buffer)");

    sw = SliceWriter(buf);
    formatStatus(sw, "%F", &session, sel, 80);
    assert(sliceResult(sw) == "(new buffer)");
}

// Editor state specifiers
unittest
{
    char[128] buf;
    SliceWriter sw;
    TestSession session;
    session.editor = TestEditor(100, false);
    TestSelection sel;

    // %e - not edited
    sw = SliceWriter(buf);
    formatStatus(sw, "%e", &session, sel, 80);
    assert(sliceResult(sw) == " ");

    // %e - edited
    session.editor._edited = true;
    sw = SliceWriter(buf);
    formatStatus(sw, "%e", &session, sel, 80);
    assert(sliceResult(sw) == "*");

    // %m - writing mode
    sw = SliceWriter(buf);
    formatStatus(sw, "%m", &session, sel, 80);
    assert(sliceResult(sw) == "OVR");

    session.rc.writemode = WritingMode.readonly;
    sw = SliceWriter(buf);
    formatStatus(sw, "%m", &session, sel, 80);
    assert(sliceResult(sw) == "R/O");
}

// Cursor position specifiers
unittest
{
    char[128] buf;
    SliceWriter sw;
    TestSession session;
    session.editor = TestEditor(4096, false);
    session.position_cursor = 255;
    TestSelection sel;

    // %p - current address mode (default hex)
    sw = SliceWriter(buf);
    formatStatus(sw, "%p", &session, sel, 80);
    assert(sliceResult(sw) == "ff");

    // %d - decimal
    sw = SliceWriter(buf);
    formatStatus(sw, "%d", &session, sel, 80);
    assert(sliceResult(sw) == "255");

    // %h - hex
    sw = SliceWriter(buf);
    formatStatus(sw, "%h", &session, sel, 80);
    assert(sliceResult(sw) == "ff");

    // %o - octal
    sw = SliceWriter(buf);
    formatStatus(sw, "%o", &session, sel, 80);
    assert(sliceResult(sw) == "377");

    // %p with decimal address mode
    session.rc.address_type = AddressType.dec;
    sw = SliceWriter(buf);
    formatStatus(sw, "%p", &session, sel, 80);
    assert(sliceResult(sw) == "255");
}

// Charset and data type
unittest
{
    char[128] buf;
    SliceWriter sw;
    TestSession session;
    session.editor = TestEditor(100, false);
    TestSelection sel;

    // %c - charset
    sw = SliceWriter(buf);
    formatStatus(sw, "%c", &session, sel, 80);
    assert(sliceResult(sw) == "ascii");

    // %t - data type
    sw = SliceWriter(buf);
    formatStatus(sw, "%t", &session, sel, 80);
    assert(sliceResult(sw) == "x8");
}

// Selection specifiers
unittest
{
    char[128] buf;
    SliceWriter sw;
    TestSession session;
    session.editor = TestEditor(4096, false);
    TestSelection sel = TestSelection(16, 255, 240);

    // %v - selection length
    sw = SliceWriter(buf);
    formatStatus(sw, "%v", &session, sel, 80);
    assert(sliceResult(sw) == "240");

    // %V - selection range (hex by default)
    sw = SliceWriter(buf);
    formatStatus(sw, "%V", &session, sel, 80);
    assert(sliceResult(sw) == "10-ff");
}

// Default format strings replicate current behavior
unittest
{
    char[128] buf;
    SliceWriter sw;
    TestSession session;
    session.editor = TestEditor(65536, false);
    session.position_cursor = 0;
    TestSelection sel;

    // Normal status bar default
    sw = SliceWriter(buf);
    formatStatus(sw, "%e %m | %t | %c | %p", &session, sel, 80);
    assert(sliceResult(sw) == "  OVR | x8 | ascii | 0");

    // Selection default
    sel = TestSelection(0, 255, 256);
    sw = SliceWriter(buf);
    formatStatus(sw, "SEL: %V (%v Bytes)", &session, sel, 80);
    assert(sliceResult(sw) == "SEL: 0-ff (256 Bytes)");

    // Report default
    sw = SliceWriter(buf);
    formatStatus(sw, "%d / %s B", &session, sel, 80);
    assert(sliceResult(sw) == "0 / 65536 B");
}

// maxCols truncation
unittest
{
    char[128] buf;
    SliceWriter sw = SliceWriter(buf);
    TestSession session;
    session.editor = TestEditor(100, false);
    TestSelection sel;

    int written = formatStatus(sw, "hello world", &session, sel, 5);
    assert(sliceResult(sw) == "hello");
    assert(written == 5);
}

// Trailing percent
unittest
{
    char[128] buf;
    SliceWriter sw = SliceWriter(buf);
    TestSession session;
    session.editor = TestEditor(100, false);
    TestSelection sel;

    formatStatus(sw, "test%", &session, sel, 80);
    assert(sliceResult(sw) == "test%");
}
