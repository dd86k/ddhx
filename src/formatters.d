/// This module used to host the document editor code, before it was moved
/// to backend.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module formatters;

// TODO: Could be renamed to "formatting"

import platform : assertion;
import std.format;
import transcoder : CharacterSet;
import platform : NotImplementedException;
import list;

/// Indicates which writing mode is active when entering data.
enum WritingMode
{
    readonly,   /// Read-only restricts any edits to be performed.
    overwrite,  /// Overwrite replaces currently selected elements.
    insert,     /// Insert inserts new data in-between elements.
}
/// Get label for this writing mode.
/// Params: mode = WritingMode.
/// Returns: Label string.
string writingModeToString(WritingMode mode)
{
    // Noticed most (GUI) text editors have these in caps
    final switch (mode) {
    case WritingMode.readonly:  return "R/O";
    case WritingMode.overwrite: return "OVR";
    case WritingMode.insert:    return "INS";
    }
}

//
// Address specifications
//

/// Address type used for displaying offsets.
enum AddressType // short names to avoid name conflicts
{
    hex,    /// Hexadecimal.
    dec,    /// Decimal.
    oct,    /// Octal.
}

/// Get label for this address type.
/// Params: type = AddressType.
/// Returns: Short name.
string addressTypeToString(AddressType type)
{
    final switch (type) {
    case AddressType.hex: return "hex";
    case AddressType.dec: return "dec";
    case AddressType.oct: return "oct";
    }
}

/// Does not represent an address, but is a utility to help with formatting.
///
/// Because an address is frequency formatted, and often with different values,
/// this helps with "set up once and fire often" issue with the older
/// formatAddress function.
struct AddressFormatter
{
    this(AddressType newtype, bool zeroes = false) { change(newtype, zeroes); }
    
    void change(AddressType newtype, bool zeroes = false)
    {
        // FormatSpec & al sucks.
        final switch (newtype) {
        case AddressType.hex: spec = zeroes ? s_hex0 : s_hex; break;
        case AddressType.dec: spec = zeroes ? s_dec0 : s_dec; break;
        case AddressType.oct: spec = zeroes ? s_oct0 : s_oct; break;
        }
        type = newtype;
    }
    string format(long value, int spacing)
    {
        debug assertion(spec);
        debug assertion(spacing <= buffer.sizeof);
        return cast(string)sformat(buffer, spec, spacing, value);
    }
    void opAssign(AddressFormatter fmt)
    {
        // Only copy type and spec
        type = fmt.type;
        spec = fmt.spec;
    }
private:
    static immutable string s_hex  = "%*x";
    static immutable string s_hex0 = "%0*x";
    static immutable string s_dec  = "%*d";
    static immutable string s_dec0 = "%0*d";
    static immutable string s_oct  = "%*o";
    static immutable string s_oct0 = "%0*o";
    AddressType type = AddressType.hex;
    string spec = s_hex;
    // worst offender is long.min %o: 1000000000000000000000 (22 chars)
    char[24] buffer = void;
}
unittest
{
    AddressFormatter address;
    
    // Address offset in column
    address.change(AddressType.hex, false);
    assert(address.format(0x00, 2)  == " 0");
    assert(address.format(0x01, 2)  == " 1");
    assert(address.format(0x80, 2)  == "80");
    assert(address.format(0xff, 2)  == "ff");
    
    address.change(AddressType.hex, true);
    assert(address.format(0xf,  3)  == "00f");
    
    address.change(AddressType.dec, false);
    assert(address.format(0,    2)  ==  " 0");
    assert(address.format(0,    3)  == "  0");
    assert(address.format(0xff, 2)  == "255");
    assert(address.format(0xff, 3)  == "255");
    
    address.change(AddressType.dec, true);
    assert(address.format(0xf, 3)   == "015");
    
    address.change(AddressType.oct, true);
    assert(address.format(0xff, 2) == "377");
    
    // Test opAssign
    AddressFormatter add2 = address;
    assert(address.format(0xff, 2) == "377");
    
    address.change(AddressType.oct, false);
    assert(address.format(0xf, 3) == " 17");
    
    // Address offset in left panel
    address.change(AddressType.hex, false);
    assert(address.format(        0x00, 10) == "         0");
    assert(address.format(        0x01, 10) == "         1");
    assert(address.format(        0x80, 10) == "        80");
    assert(address.format(        0xff, 10) == "        ff");
    assert(address.format(       0x100, 10) == "       100");
    assert(address.format(      0x1000, 10) == "      1000");
    assert(address.format(     0x10000, 10) == "     10000");
    assert(address.format(    0x100000, 10) == "    100000");
    assert(address.format(   0x1000000, 10) == "   1000000");
    assert(address.format(  0x10000000, 10) == "  10000000");
    assert(address.format( 0x100000000, 10) == " 100000000");
    assert(address.format(0x1000000000, 10) == "1000000000");
    assert(address.format(   ulong.max, 10) == "ffffffffffffffff");
}

//
// Data handling
//

/// Data representation.
enum DataType
{
    x8,     /// 8-bit hexadecimal (e.g., 0xff -> "ff")
    x16,    /// 16-bit hexadecimal
    //x32,
    //x64,
    //u8,     /// 8-bit unsigned decimal (0xff -> 255)
    //o8,     /// 8-bit unsigned octal (0xff -> 377)
    //s8,     /// 8-bit signal decimal
    //i8,     /// 8-bit signal octal
}
import std.traits : EnumMembers;
import os.terminal;
/// Data type count.
enum TYPES = EnumMembers!DataType.length;

DataType selectDataType(string type)
{
    switch (type) {
    case "x8":      return DataType.x8;
    case "x16":     return DataType.x16;
    default:        throw new Exception("Unknown data type");
    }
}

// Given the data type (hex, dec, oct) return the value
// of the keychar to a digit/nibble.
//
// For example, 'a' will return 0xa, and 'r' will return -1, an error.
private
int keydata_hex(int keychar) @safe
{
    if (keychar >= '0' && keychar <= '9')
        return keychar - '0';
    if (keychar >= 'A' && keychar <= 'F')
        return (keychar - 'A') + 10;
    if (keychar >= 'a' && keychar <= 'f')
        return (keychar - 'a') + 10;
    
    return -1;
}
@safe unittest
{
    assert(keydata_hex('a') == 0xa);
    assert(keydata_hex('b') == 0xb);
    assert(keydata_hex('A') == 0xa);
    assert(keydata_hex('B') == 0xb);
    assert(keydata_hex('0') == 0);
    assert(keydata_hex('3') == 3);
    assert(keydata_hex('9') == 9);
    assert(keydata_hex('j') < 0);
}

/// Can represent a single "element"
///
/// Used in "goto", "skip-forward", etc. to select a single "element"
union Element
{
    ubyte[8] raw;
    long    u64;
    uint    u32;
    ushort  u16;
    ubyte   u8;
    float   f32;
    double  f64;
    
    // Could make this structure "richer" by giving it data type,
    // but there aren't any actual needs at the moment.
    
    void reset(DataType type)
    {
        final switch (type) {
        case DataType.x8:
        case DataType.x16:
            u64 = 0;
            break;
        }
    }
    
    bool parse(DataType type, inout(char)[] input)
    {
        DataSpec spec = DataSpec(type);
        
        if (input.length == 0)
            return false;
        if (input.length > spec.spacing)
            return false;
        
        enum SHIFTX = 4;
        final switch (type) {
        case DataType.x8:
            int d = keydata_hex(input[0]);
            if (d < 0)
                return false;
            
            u8 = cast(ubyte)(d << 4);
            
            if (input.length <= 1)
                return true;
            
            d = keydata_hex(input[1]);
            if (d < 0)
                return false;
            
            u8 |= d;
            return true;
        case DataType.x16:
            u16 = 0;
            int s = 12;
            for (int i; i < input.length && spec.spacing; i++, s -= SHIFTX)
            {
                u16 |= keydata_hex(input[i]) << s;
            }
            return true;
        }
    }
}
unittest
{
    Element elem;
    assert(elem.parse(DataType.x8, "0") == true);
    assert(elem.u8 == 0);
    assert(elem.parse(DataType.x8, "10") == true);
    assert(elem.u8 == 0x10);
    assert(elem.parse(DataType.x16, "0") == true);
    assert(elem.u16 == 0);
    assert(elem.parse(DataType.x16, "1010") == true);
    assert(elem.u16 == 0x1010);
}

// Size of a data type in bytes.
//
// This exists since there are a lot of places we only need data type size and
// DataType(...) keeps recreating structure instance (wasteful).
// Optimized for View system, returns int to make it easier to calculate with
// terminal size.
int size_of(DataType type)
{
    static immutable int[TYPES] sizes = [ ubyte.sizeof, ushort.sizeof ];
    size_t i = cast(size_t)type;
    assert(i < sizes.sizeof);
    return sizes[i];
}
unittest
{
    assert(size_of(DataType.x8)  == ubyte.sizeof);
    assert(size_of(DataType.x16) == ushort.sizeof);
    
    // Test all
    for (int i; i < TYPES; i++)
        cast(void)size_of(cast(DataType)i);
}

/// Data specification for this data type.
struct DataSpec
{
    // Construct from DataType enum
    this(DataType type)
    {
        final switch (type) {
        case DataType.x8:  this = DataSpec("x8",  "%0*x", 2, ubyte.sizeof); break;
        case DataType.x16: this = DataSpec("x16", "%0*x", 4, ushort.sizeof); break;
        }
    }
    
    // Manual configuration
    this(string shortname, string fmt, int chars, int sizeof)
    {
        name = shortname;
        fmtspec = fmt;
        spacing = chars;
        size_of = sizeof;
    }
    
    /// Name (e.g., "x8").
    string name;
    /// Format specifier for format/sformat/printf.
    string fmtspec;
    /// Number of characters it occupies at maximum. Used for text alignment.
    int spacing;
    /// Size of data type in bytes.
    int size_of; // Avoids conflict with .sizeof
}

/// Get label for this data type.
/// Params: type = Data type.
/// Returns: Label.
string dataTypeToString(DataType type) // Only used in statusbar code
{
    final switch (type) {
    case DataType.x8:  return "x8";
    case DataType.x16: return "x16";
    }
}

/// Helper structure that walks over a buffer and formats every element.
struct DataFormatter
{
    // NOTE: Endianness setting could be here, too
    /// Make a new instance with data and byte length
    this(DataType dtype, const(void) *data, size_t len)
    {
        datatype = dtype;
        spec = DataSpec(dtype);
        buffer = data;
        size = len;
    }
    
    void step() { i += spec.size_of; }
    
    /// Format an element.
    /// Returns: Formatted data or null when end of data.
    string print()
    {
        if (i >= size)
            return cast(string)sformat(textbuf, "%*s", spec.spacing, "");
        
        final switch (datatype) {
        case DataType.x8:
            ubyte v = *cast(ubyte*)(buffer + i);
            return cast(string)sformat(textbuf, spec.fmtspec, spec.spacing, v);
        case DataType.x16:
            ushort v = void;
            switch (size - i) { // left
            case 1:
                v = *cast(ubyte*)(buffer + i);
                break;
            default:
                v = *cast(ushort*)(buffer + i);
            }
            return cast(string)sformat(textbuf, spec.fmtspec, spec.spacing, v);
        }
    }
    
private:
    size_t i;       /// Byte index
    size_t size;    /// Size of input data in bytes
    const(void) *buffer;
    DataType datatype;
    DataSpec spec;
    char[24] textbuf = void;
}
unittest
{
    DataFormatter formatter;
    
    immutable ubyte[] data = [ 0x00, 0x01, 0xa0, 0xff ];
    formatter = DataFormatter(DataType.x8, data.ptr, data.length);
    assert(formatter.print() == "00"); formatter.step();
    assert(formatter.print() == "01"); formatter.step();
    assert(formatter.print() == "a0"); formatter.step();
    assert(formatter.print() == "ff"); formatter.step();
    assert(formatter.print() == "  ");
    
    immutable ushort[] data16 = [ 0x0101, 0xf0f0 ];
    formatter = DataFormatter(DataType.x16, data16.ptr, data16.length * ushort.sizeof);
    assert(formatter.print() == "0101"); formatter.step();
    assert(formatter.print() == "f0f0"); formatter.step();
    assert(formatter.print() == "    ");
    
    // Test partial data formatting
    immutable ubyte[] data16p = [ 0xab, 0xab, 0xab ];
    formatter = DataFormatter(DataType.x16, data16p.ptr, data16p.length);
    assert(formatter.print() == "abab"); formatter.step();
    assert(formatter.print() == "00ab"); formatter.step();
    assert(formatter.print() == "    ");
}

/// Helps inputting data and formatting said input
///
/// They act like relays, clat clat
struct InputFormatter
{
    void change(DataType newtype)
    {
        type = newtype;
        spec = DataSpec(newtype);
        reset();
    }
    
    void reset()
    {
        d = 0;
        txtbuffer[] = ' ';
        element.reset(type);
    }
    
    size_t index() // digit index
    {
        return d;
    }
    
    bool add(char character)
    {
        return replace(character, d);
    }
    bool replace(char character, size_t idx)
    {
        if (idx >= spec.spacing) return false;
        
        final switch (type) {
        case DataType.x8, DataType.x16:
            if (keydata_hex(character) < 0) return false;
            break;
        }
        
        txtbuffer[idx] = character;
        d = idx + 1;
        return true;
    }
    bool full()
    {
        return d >= spec.spacing;
    }
    
    // Format what's in the buffer
    string format()
    {
        return cast(string)txtbuffer[0..spec.spacing];
    }
    alias toString = format;
    
    /// Return raw data, useful to be parsed later.
    /// Warning: Inverted in LittleEndian builds.
    /// Returns: Buffer slice.
    ubyte[] data()
    {
        if (d)
            assertion(element.parse(type, txtbuffer[0..d]));
        return element.raw[0..spec.size_of];
    }
    
private:
    DataType type;
    DataSpec spec;
    size_t d; /// digit index
    
    char[24] txtbuffer = void;
    Element element = void;
}
unittest
{
    InputFormatter input;
    
    input.change(DataType.x8);
    
    assert(input.data       == [ 0 ]);
    
    assert(input.add('1')   == true);
    assert(input.data       == [ 0x10 ]);
    assert(input.format     == "1 ");
    assert(input.full()     == false);
    
    assert(input.add('2')   == true);
    assert(input.data       == [ 0x12 ]);
    assert(input.format     == "12");
    
    assert(input.full()     == true);
    assert(input.add('3')   == false);
    
    input.change(DataType.x16);
    
    assert(input.data       == [ 0, 0 ]);
    assert(input.full()     == false);
    
    assert(input.add('f')   == true);
    assert(input.format     == "f   ");
    version (LittleEndian)
        assert(input.data   == [ 0x00, 0xf0 ]);
    else
        assert(input.data   == [ 0xf0, 0x00 ]);
    assert(input.full()     == false);
    
    assert(input.add('2')   == true);
    assert(input.format     == "f2  ");
    version (LittleEndian)
        assert(input.data   == [ 0x00, 0xf2 ]);
    else
        assert(input.data   == [ 0xf2, 0x00 ]);
    assert(input.full()     == false);
    
    assert(input.add('a')   == true);
    assert(input.format     == "f2a ");
    version (LittleEndian)
        assert(input.data   == [ 0xa0, 0xf2 ]);
    else
        assert(input.data   == [ 0xf2, 0xa0 ]);
    assert(input.full()     == false);
    
    assert(input.add('4')   == true);
    assert(input.format     == "f2a4");
    version (LittleEndian)
        assert(input.data   == [ 0xa4, 0xf2 ]);
    else
        assert(input.data   == [ 0xf2, 0xa4 ]);
    
    assert(input.add('5')   == false);
    assert(input.full()     == true);
}

/* Remember, we only have 8 usable colors in a 16-color space (fg == bg -> bad).
   And only 6 (excluding "bright" variants) of them can be used for a purpose,
   other than white/black for defaults.
   BUT, a color scheme can always be mapped to something else (by preference).
   For now, do hard-coded fg/bg values.
   Should be able to configure "color:normal" to a specific mapping.
*/
enum ColorScheme
{
    normal,
    cursor,
    selection,
    mirror,
    // The following are just future ideas
    //modified,   // edited data
    //address,    // layout: address/offset
    //constant,   // layout: known constant value
    //bookmark,
    //search,     // search result
    //diff_added,     // 
    //diff_removed,   // 
    //diff_changed,   // 
}
enum SCHEMES = EnumMembers!(ColorScheme).length;

enum
{
    COLORMAP_INVERTED    = 1,    /// 
    COLORMAP_FOREGROUND  = 2,    /// 
    COLORMAP_BACKGROUND  = 4,    ///
}
// ColorPair[ColorScheme] mapping;
struct ColorMap
{
    int flags;
    TermColor fg;
    TermColor bg;
}
struct ColorMapper
{
    // Initial color specifications
    ColorMap[SCHEMES] maps = [
        // normal
        { 0,                    TermColor.init, TermColor.init },
        // cursor
        { COLORMAP_INVERTED,    TermColor.init, TermColor.init },
        // selection
        { COLORMAP_INVERTED,    TermColor.init, TermColor.init },
        // mirror
        { COLORMAP_BACKGROUND,  TermColor.init, TermColor.red },
    ];
    
    ColorMap get(ColorScheme scheme)
    {
        size_t i = cast(size_t)scheme;
        assert(i < SCHEMES);
        return maps[i];
    }
    void set(ColorScheme scheme, ColorMap map)
    {
        size_t i = cast(size_t)scheme;
        assert(i < SCHEMES);
        maps[i] = map;
    }
}

struct LineSegment
{
    // NOTE: Don't call this variable "text", it will call std.conv.text.
    // small string optimization because the segment engine is that simple at the moment
    // and bufferedwriter still saves us
    char[32] data;
    size_t sz;
    ColorScheme scheme;
    
    string toString()
    {
        return cast(string)data[0..sz];
    }
}
struct Line
{
    List!LineSegment segments;
    
    // "reserve" is a function in object.d. DO NOT try to collide with it.
    this(size_t segment_count)
    {
        segments = List!LineSegment(segment_count);
    }
    ~this()
    {
        destroy(segments);
    }
    
    void reset() { segments.reset(); }
    
    // Manual add
    void add(string text, ColorScheme scheme)
    {
        import core.stdc.string : memcpy;
        assert(text.length < 32);
        LineSegment segment = void;
        memcpy(segment.data.ptr, text.ptr, text.length);
        segment.sz = text.length;
        segment.scheme = scheme;
        segments ~= segment;
    }
    
    // No color
    void normal(string[] texts...)
    {
        foreach (text; texts)
            add(text, ColorScheme.normal);
    }
    
    void cursor(string text)
    {
        add(text, ColorScheme.cursor);
    }
    
    void selection(string text)
    {
        add(text, ColorScheme.selection);
    }
    
    void mirror(string text)
    {
        add(text, ColorScheme.mirror);
    }
}
unittest
{
    /*
    assert(line.segments[5].inverted == true);
    assert(line.segments[6].text == " ");
    assert(line.segments[6].inverted == true);
    */
}