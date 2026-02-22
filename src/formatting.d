/// This module used to host the document editor code, before it was moved
/// to backend.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module formatting;

import list;
import os.terminal : TermColor; // For color schemes
import platform : assertion, NotImplementedException;
import std.format;
import transcoder : CharacterSet;

// This alias exists because more recent compilers complain about local
// static buffers being escape despite that's exactly what I want...
// Oh well, so much for locality.
// 24 chars because worst offender is long.min %o: 1000000000000000000000 (22 chars)
/// Buffer alias
alias ElementText = char[24];

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
    void opAssign(AddressFormatter fmt)
    {
        // Only copy type and spec
        type = fmt.type;
        spec = fmt.spec;
    }
    string textual(char[] buf, long value, int spacing) // avoid .text/.format clash
    {
        return cast(string)sformat(buf, spec, spacing, value);
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
}
unittest
{
    ElementText buf = void;
    
    AddressFormatter address;
    
    // Address offset in column
    address.change(AddressType.hex, false);
    assert(address.textual(buf, 0x00, 2)  == " 0");
    assert(address.textual(buf, 0x01, 2)  == " 1");
    assert(address.textual(buf, 0x80, 2)  == "80");
    assert(address.textual(buf, 0xff, 2)  == "ff");
    
    address.change(AddressType.hex, true);
    assert(address.textual(buf, 0xf,  3)  == "00f");
    
    address.change(AddressType.dec, false);
    assert(address.textual(buf, 0,    2)  ==  " 0");
    assert(address.textual(buf, 0,    3)  == "  0");
    assert(address.textual(buf, 0xff, 2)  == "255");
    assert(address.textual(buf, 0xff, 3)  == "255");
    
    address.change(AddressType.dec, true);
    assert(address.textual(buf, 0xf, 3)   == "015");
    
    address.change(AddressType.oct, true);
    assert(address.textual(buf, 0xff, 2) == "377");
    
    // Test opAssign
    AddressFormatter add2 = address;
    assert(add2.textual(buf, 0xff, 2) == "377");
    
    add2.change(AddressType.oct, false);
    assert(add2.textual(buf, 0xf, 3) == " 17");
    
    // Address offset in left panel
    add2.change(AddressType.hex, false);
    assert(add2.textual(buf,         0x00, 10) == "         0");
    assert(add2.textual(buf,         0x01, 10) == "         1");
    assert(add2.textual(buf,         0x80, 10) == "        80");
    assert(add2.textual(buf,         0xff, 10) == "        ff");
    assert(add2.textual(buf,        0x100, 10) == "       100");
    assert(add2.textual(buf,       0x1000, 10) == "      1000");
    assert(add2.textual(buf,      0x10000, 10) == "     10000");
    assert(add2.textual(buf,     0x100000, 10) == "    100000");
    assert(add2.textual(buf,    0x1000000, 10) == "   1000000");
    assert(add2.textual(buf,   0x10000000, 10) == "  10000000");
    assert(add2.textual(buf,  0x100000000, 10) == " 100000000");
    assert(add2.textual(buf, 0x1000000000, 10) == "1000000000");
    assert(add2.textual(buf,    ulong.max, 10) == "ffffffffffffffff");
}

//
// Data handling
//

/// Data representation.
enum DataType
{
    x8,     /// 8-bit hexadecimal (e.g., 0xff -> ff)
    x16,    /// 16-bit hexadecimal
    x32,    /// 32-bit hexadecimal
    d8,     /// 8-bit unsigned decimal (0xff -> 255)
    d16,    /// 16-bit unsigned decimal
    d32,    /// 32-bit unsigned decimal
    o8,     /// 8-bit unsigned octal (0xff -> 377)
    o16,    /// 16-bit unsigned octal
    o32,    /// 32-bit unsigned octal
}
import std.traits : EnumMembers;
import std.path;
/// Data type count.
enum TYPES = EnumMembers!DataType.length;

// Connects data types to definitions
private immutable static DataSpec[] data_specs = [
    // hex
    { DataType.x8,  DataType.x8.stringof,   "%0*x", 2,  ubyte.sizeof },
    { DataType.x16, DataType.x16.stringof,  "%0*x", 4,  ushort.sizeof },
    { DataType.x32, DataType.x32.stringof,  "%0*x", 8,  uint.sizeof },
    // dec
    { DataType.d8,  DataType.d8.stringof,   "%0*d", 3,  ubyte.sizeof },
    { DataType.d16, DataType.d16.stringof,  "%0*d", 5,  ushort.sizeof },
    { DataType.d32, DataType.d32.stringof,  "%0*d", 10, uint.sizeof },
    // oct
    { DataType.o8,  DataType.o8.stringof,   "%0*o", 3,  ubyte.sizeof },
    { DataType.o16, DataType.o16.stringof,  "%0*o", 6,  ushort.sizeof },
    { DataType.o32, DataType.o32.stringof,  "%0*o", 11, uint.sizeof },
];
unittest
{
    // Check array aligns with DataType members
    foreach (i, type; EnumMembers!DataType)
    {
        assert(type == data_specs[i].type);
    }
}

// string alias -> data type enum
DataType selectDataType(string type)
{
    foreach (ref spec; data_specs)
    {
        if (spec.name == type)
            return spec.type;
    }
    throw new Exception("Unknown data type");
}
// data type enum -> data specifications
DataSpec selectDataSpec(DataType type)
{
    size_t i = cast(size_t)type;
    version (D_NoBoundsChecks)
    {
        assertion(i < data_specs.length, "selectDataSpec: OOB");
    }
    return data_specs[i];
}
unittest
{
    foreach (i, type; EnumMembers!DataType)
    {
        assert(selectDataSpec(type).type == data_specs[i].type);
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
private
int keydata_dec(int keychar) @safe
{
    if (keychar >= '0' && keychar <= '9')
        return keychar - '0';
    
    return -1;
}
@safe unittest
{
    assert(keydata_dec('a') < 0);
    assert(keydata_dec('b') < 0);
    assert(keydata_dec('A') < 0);
    assert(keydata_dec('B') < 0);
    assert(keydata_dec('0') == 0);
    assert(keydata_dec('3') == 3);
    assert(keydata_dec('9') == 9);
    assert(keydata_dec('j') < 0);
}
private
int keydata_oct(int keychar) @safe
{
    if (keychar >= '0' && keychar <= '7')
        return keychar - '0';
    
    return -1;
}
@safe unittest
{
    assert(keydata_oct('a') < 0);
    assert(keydata_oct('b') < 0);
    assert(keydata_oct('A') < 0);
    assert(keydata_oct('B') < 0);
    assert(keydata_oct('0') == 0);
    assert(keydata_oct('3') == 3);
    assert(keydata_oct('9') < 0);
    assert(keydata_oct('j') < 0);
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
        // Right now, we only support integer types
        u64 = 0;
    }
    
    bool parse(DataType type, inout(char)[] input)
    {
        import std.conv : to; // lazy, but convenient
        import std.string : strip;

        DataSpec spec = selectDataSpec(type);

        if (input.length == 0)
            return false;
        if (input.length > spec.spacing)
            return false;

        auto stripped = strip(input);
        if (stripped.length == 0)
            return false;

        try final switch (type) {
        case DataType.x8:   u8  = to!ubyte(stripped, 16); return true;
        case DataType.x16:  u16 = to!ushort(stripped, 16); return true;
        case DataType.x32:  u32 = to!uint(stripped, 16); return true;
        case DataType.d8:   u8  = to!ubyte(stripped, 10); return true;
        case DataType.d16:  u16 = to!ushort(stripped, 10); return true;
        case DataType.d32:  u32 = to!uint(stripped, 10); return true;
        case DataType.o8:   u8  = to!ubyte(stripped, 8); return true;
        case DataType.o16:  u16 = to!ushort(stripped, 8); return true;
        case DataType.o32:  u32 = to!uint(stripped, 8); return true;
        }
        catch (Exception ex) {}
        return false;
    }
}
unittest
{
    Element elem;
    
    // Hexadecimal
    assert(elem.parse(DataType.x8, "0") == true);
    assert(elem.u8 == 0);
    assert(elem.parse(DataType.x8, "1") == true);
    assert(elem.u8 == 1);
    assert(elem.parse(DataType.x8, "01") == true);
    assert(elem.u8 == 1);
    assert(elem.parse(DataType.x8, " 1") == true);
    assert(elem.u8 == 1);
    assert(elem.parse(DataType.x8, "10") == true);
    assert(elem.u8 == 0x10);

    assert(elem.parse(DataType.x16, "0") == true);
    assert(elem.u16 == 0);
    assert(elem.parse(DataType.x16, "0101") == true);
    assert(elem.u16 == 0x0101);
    assert(elem.parse(DataType.x16, " 101") == true);
    assert(elem.u16 == 0x0101);
    assert(elem.parse(DataType.x16, "1010") == true);
    assert(elem.u16 == 0x1010);

    // Decimal
    assert(elem.parse(DataType.d8, "0") == true);
    assert(elem.u8 == 0);
    assert(elem.parse(DataType.d8, "025") == true);
    assert(elem.u8 == 25);
    assert(elem.parse(DataType.d8, " 25") == true);
    assert(elem.u8 == 25);
    assert(elem.parse(DataType.d8, "255") == true);
    assert(elem.u8 == 255);
    
    // Octal
    assert(elem.parse(DataType.o32, "37777777777") == true);
    assert(elem.u32 == 0xffffffff);
}

// Size of a data type in bytes.
//
// Mostly used by view module.
int size_of(DataType type)
{
    return selectDataSpec(type).size_of;
}
unittest
{
    assert(size_of(DataType.x8)  == ubyte.sizeof);
    assert(size_of(DataType.x16) == ushort.sizeof);
}

/// Data specification for this data type.
struct DataSpec
{
    /// Data type associated
    DataType type;
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
    case DataType.x8:   return DataType.x8.stringof;
    case DataType.x16:  return DataType.x16.stringof;
    case DataType.x32:  return DataType.x32.stringof;
    case DataType.d8:   return DataType.d8.stringof;
    case DataType.d16:  return DataType.d16.stringof;
    case DataType.d32:  return DataType.d32.stringof;
    case DataType.o8:   return DataType.o8.stringof;
    case DataType.o16:  return DataType.o16.stringof;
    case DataType.o32:  return DataType.o32.stringof;
    }
}
unittest
{
    assert(dataTypeToString(DataType.x8) == "x8");
}

// TODO: Make DataWalker that modifies Element instances
//       Because then, Element can has iszero() more consistently
//       And have its own format function.
/// Helper structure that walks over a buffer and formats every element.
struct DataFormatter
{
    // NOTE: Endianness setting could be here, too
    /// Make a new instance with data and byte length
    this(DataType dtype, const(void) *data, size_t len)
    {
        spec = selectDataSpec(dtype);
        buffer = data;
        size = len;
    }
    
    void step() { i += spec.size_of; }
    
    /// Format an element.
    /// Params: buf = Buffer.
    /// Returns: Formatted data or null when end of data.
    string textual(char[] buf)
    {
        if (i >= size)
            return cast(string)sformat(buf, "%*s", spec.spacing, "");
        
        import core.stdc.string : memcpy;
        
        final switch (spec.type) {
        case DataType.x8:
        case DataType.d8:
        case DataType.o8:
            ubyte v = *cast(ubyte*)(buffer + i);
            return cast(string)sformat(buf, spec.fmtspec, spec.spacing, v);
        case DataType.x16:
        case DataType.d16:
        case DataType.o16:
            ushort v;
            ptrdiff_t left = size - i;
            memcpy(&v, buffer + i, left >= ushort.sizeof ? ushort.sizeof : left);
            return cast(string)sformat(buf, spec.fmtspec, spec.spacing, v);
        case DataType.x32:
        case DataType.d32:
        case DataType.o32:
            uint v;
            ptrdiff_t left = size - i;
            memcpy(&v, buffer + i, left >= uint.sizeof ? uint.sizeof : left);
            return cast(string)sformat(buf, spec.fmtspec, spec.spacing, v);
        }
    }
    
    // 
    bool iszero()
    {
        if (i >= size)
            return false;
        
        import core.stdc.string : memcpy;
        
        // lazy lol
        final switch (spec.type) {
        case DataType.x8:
        case DataType.d8:
        case DataType.o8:
            return *cast(ubyte*)(buffer + i) == 0;
        case DataType.x16:
        case DataType.d16:
        case DataType.o16:
            ushort v;
            ptrdiff_t left = size - i;
            memcpy(&v, buffer + i, left >= ushort.sizeof ? ushort.sizeof : left);
            return v == 0;
        case DataType.x32:
        case DataType.d32:
        case DataType.o32:
            uint v;
            ptrdiff_t left = size - i;
            memcpy(&v, buffer + i, left >= uint.sizeof ? uint.sizeof : left);
            return v == 0;
        }
    }
    
private:
    ptrdiff_t i;       /// Byte index
    ptrdiff_t size;    /// Size of input data in bytes
    const(void) *buffer;
    DataSpec spec;
}
unittest
{
    ElementText buf = void;
    
    DataFormatter formatter;
    
    // Test x8
    immutable ubyte[] data = [ 0x00, 0x01, 0xa0, 0xff ];
    formatter = DataFormatter(DataType.x8, data.ptr, data.length);
    assert(formatter.textual(buf) == "00"); assert( formatter.iszero()); formatter.step();
    assert(formatter.textual(buf) == "01"); assert(!formatter.iszero()); formatter.step();
    assert(formatter.textual(buf) == "a0"); assert(!formatter.iszero()); formatter.step();
    assert(formatter.textual(buf) == "ff"); assert(!formatter.iszero()); formatter.step();
    assert(formatter.textual(buf) == "  ");
    
    // Test x16
    immutable ushort[] data16 = [ 0x0101, 0xf0f0 ];
    formatter = DataFormatter(DataType.x16, data16.ptr, data16.length * ushort.sizeof);
    assert(formatter.textual(buf) == "0101"); assert(!formatter.iszero()); formatter.step();
    assert(formatter.textual(buf) == "f0f0"); assert(!formatter.iszero()); formatter.step();
    assert(formatter.textual(buf) == "    ");
    
    // Test partial data formatting
    immutable ubyte[] data16p = [ 0xab, 0xab, 0xab ];
    formatter = DataFormatter(DataType.x16, data16p.ptr, data16p.length);
    assert(formatter.textual(buf) == "abab"); assert(!formatter.iszero()); formatter.step();
    assert(formatter.textual(buf) == "00ab"); assert(!formatter.iszero()); formatter.step();
    assert(formatter.textual(buf) == "    ");
    
    // Test decimal
    formatter = DataFormatter(DataType.d8, data.ptr, data.length);
    assert(formatter.textual(buf) == "000"); assert( formatter.iszero()); formatter.step();
    assert(formatter.textual(buf) == "001"); assert(!formatter.iszero()); formatter.step();
    assert(formatter.textual(buf) == "160"); assert(!formatter.iszero()); formatter.step();
    assert(formatter.textual(buf) == "255"); assert(!formatter.iszero()); formatter.step();
    assert(formatter.textual(buf) == "   ");
}

// NOTE: class is a cheap hack to deal with escapes
class InputFormatter
{
    void change(DataType newtype)
    {
        spec = selectDataSpec(newtype);
        reset();
    }
    
    void reset()
    {
        d = 0;
        txtbuffer[] = ' ';
        element.reset(spec.type);
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
        
        final switch (spec.type) {
        case DataType.x8, DataType.x16, DataType.x32:
            if (keydata_hex(character) < 0) return false;
            break;
        case DataType.d8, DataType.d16, DataType.d32:
            if (keydata_dec(character) < 0) return false;
            break;
        case DataType.o8, DataType.o16, DataType.o32:
            if (keydata_oct(character) < 0) return false;
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
        {
            // Right-padding zeros fixes "f " registering as 0xf
            ElementText buf2 = void;
            buf2[0..d] = txtbuffer[0..d];
            buf2[d..spec.spacing] = '0';
            assertion(element.parse(spec.type, buf2[0..spec.spacing]));
        }
        return element.raw[0..spec.size_of];
    }
    
private:
    DataSpec spec;
    size_t d; /// digit index
    
    ElementText txtbuffer = void;
    Element element = void;
}
unittest
{
    scope InputFormatter input = new InputFormatter; // HACK
    
    input.change(DataType.x8);
    
    assert(input.data       == [ 0 ]);
    
    assert(input.add('1')   == true);
    assert(input.format     == "1 ");
    assert(input.data()     == [ 0x10 ]);
    assert(input.full()     == false);
    
    assert(input.add('2')   == true);
    assert(input.format     == "12");
    
    assert(input.full()     == true);
    assert(input.data()     == [ 0x12 ]);
    assert(input.add('3')   == false);
    
    input.change(DataType.x16);
    
    assert(input.data       == [ 0, 0 ]);
    assert(input.full()     == false);
    
    assert(input.add('f')   == true);
    assert(input.format     == "f   ");
    assert(input.full()     == false);
    
    assert(input.add('2')   == true);
    assert(input.format     == "f2  ");
    assert(input.full()     == false);
    
    assert(input.add('a')   == true);
    assert(input.format     == "f2a ");
    assert(input.full()     == false);
    
    assert(input.add('4')   == true);
    assert(input.format     == "f2a4");
    version (LittleEndian)
        assert(input.data   == [ 0xa4, 0xf2 ]);
    else
        assert(input.data   == [ 0xf2, 0xa4 ]);
    
    assert(input.add('5')   == false);
    assert(input.full()     == true);
    
    input.change(DataType.d8);
    
    assert(input.add('f')   == false);
    assert(input.add('2')   == true);
    assert(input.add('2')   == true);
    assert(input.add('5')   == true);
    assert(input.full()     == true);
    assert(input.add('0')   == false);
    assert(input.format     == "225");
    assert(input.data       == [ 0xe1 ]);
    
    input.change(DataType.o8);
    
    assert(input.add('f')   == false);
    assert(input.add('9')   == false);
    assert(input.add('2')   == true);
    assert(input.add('2')   == true);
    assert(input.add('5')   == true);
    assert(input.full()     == true);
    assert(input.add('0')   == false);
    assert(input.format     == "225");
    assert(input.data       == [ 0x95 ]);
}

/* Remember, we only have 8 usable colors in a 16-color space (fg == bg -> bad).
   And only 6 (excluding "bright" variants) of them can be used for a purpose,
   other than white/black for defaults.
   BUT, a color scheme can always be mapped to something else (by preference).
*/
enum ColorScheme
{
    normal,
    cursor,
    selection,
    mirror,
    unimportant,    // ie, zero
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

ColorScheme getScheme(string name)
{
    // Maps one or more names to a scheme
    switch (name) {
    case "normal":      return ColorScheme.normal;
    case "cursor":      return ColorScheme.cursor;
    case "selection":   return ColorScheme.selection;
    case "mirror":      return ColorScheme.mirror;
    case "unimportant": return ColorScheme.unimportant;
    default:
        import std.conv : text;
        throw new Exception(text("Unknown scheme: ", name));
    }
}

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
    
    static ColorMap parse(string colorstr)
    {
        import std.string : indexOf;
        
        /*
        ┌──────────┬─────────┬─────────┬──────────┐
        │  Input   │   fg    │   bg    │  Flags   │
        ├──────────┼─────────┼─────────┼──────────┤
        │ red:blue │ red     │ blue    │ FG+BG    │
        ├──────────┼─────────┼─────────┼──────────┤
        │ red:     │ red     │ default │ FG       │
        ├──────────┼─────────┼─────────┼──────────┤
        │ red      │ red     │ default │ FG       │
        ├──────────┼─────────┼─────────┼──────────┤
        │ :blue    │ default │ blue    │ BG       │
        ├──────────┼─────────┼─────────┼──────────┤
        │ invert   │ -       │ -       │ INVERTED │
        └──────────┴─────────┴─────────┴──────────┘
        */
        // "default:red" -> bg=red
        // ":red"       -> bg=red
        // "red:"       -> fg=red
        // "red"        -> fg=red
        if (colorstr is null || colorstr.length == 0)
            throw new Exception("Color cannot be empty");
        
        ColorMap map;
        string fg = void;
        string bg = void;
        
        ptrdiff_t i = indexOf(colorstr, ':');
        if (i >= 0) // foreground + background
        {
            fg = colorstr[0..i];
            bg = colorstr[i+1..$];
        }
        else
        {
            fg = colorstr;
            bg = null;
        }
        
        ColorMap.mapterm(map, fg, COLORMAP_FOREGROUND);
        ColorMap.mapterm(map, bg, COLORMAP_BACKGROUND);
        
        return map;
    }
    private static void mapterm(ref ColorMap map, string term, int pre)
    {
        // Final switch asserts...
        TermColor color = void;
        switch (term) {
        case "", "default": return; // leave .init default
        case "invert": map.flags |= COLORMAP_INVERTED; return;
        case "black":   color = TermColor.black; break;
        case "blue":    color = TermColor.blue; break;
        case "green":   color = TermColor.green; break;
        case "aqua":    color = TermColor.aqua; break;
        case "red":     color = TermColor.red; break;
        case "purple":  color = TermColor.purple; break;
        case "yellow":  color = TermColor.yellow; break;
        case "gray":    color = TermColor.gray; break;
        case "lightgray":   color = TermColor.lightgray; break;
        case "brightblue":  color = TermColor.brightblue; break;
        case "brightgreen": color = TermColor.brightgreen; break;
        case "brightaqua":  color = TermColor.brightaqua; break;
        case "brightred":   color = TermColor.brightred; break;
        case "brightpurple":color = TermColor.brightpurple; break;
        case "brightyellow":color = TermColor.brightyellow; break;
        case "white":       color = TermColor.white; break;
        default:
            import std.conv : text;
            throw new Exception(text("Unknown color: ", term));
        }
        // No magic here
        map.flags |= pre;
        if (pre & COLORMAP_FOREGROUND)
            map.fg = color;
        else
            map.bg = color;
    }
}
unittest
{
    assert(ColorMap.parse("default:default") == ColorMap(0, TermColor.init, TermColor.init));
    assert(ColorMap.parse("default")        == ColorMap(0, TermColor.init, TermColor.init));
    assert(ColorMap.parse("invert")         == ColorMap(COLORMAP_INVERTED, TermColor.init, TermColor.init));
    
    assert(ColorMap.parse("red:default")    == ColorMap(COLORMAP_FOREGROUND, TermColor.red, TermColor.init));
    assert(ColorMap.parse("red:")           == ColorMap(COLORMAP_FOREGROUND, TermColor.red, TermColor.init));
    assert(ColorMap.parse("red")            == ColorMap(COLORMAP_FOREGROUND, TermColor.red, TermColor.init));
    assert(ColorMap.parse("purple")         == ColorMap(COLORMAP_FOREGROUND, TermColor.purple, TermColor.init));
    
    assert(ColorMap.parse("default:red")    == ColorMap(COLORMAP_BACKGROUND, TermColor.init, TermColor.red));
    assert(ColorMap.parse(":red")           == ColorMap(COLORMAP_BACKGROUND, TermColor.init, TermColor.red));
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
        // unimportant
        { COLORMAP_FOREGROUND,  TermColor.gray, TermColor.init },
    ];
    static assert(maps.length == SCHEMES);
    
    ColorMap get(ColorScheme scheme)
    {
        size_t i = cast(size_t)scheme;
        version (D_NoBoundsChecks)
            if (i < SCHEMES) throw new Exception("assert: i < SCHEMES");
        return maps[i];
    }
    void set(ColorScheme scheme, ColorMap map)
    {
        size_t i = cast(size_t)scheme;
        version (D_NoBoundsChecks)
            if (i < SCHEMES) throw new Exception("assert: i < SCHEMES");
        maps[i] = map;
    }
    
    static immutable ColorMap[SCHEMES] defaults = [
        // normal
        { 0,                    TermColor.init, TermColor.init },
        // cursor
        { COLORMAP_INVERTED,    TermColor.init, TermColor.init },
        // selection
        { COLORMAP_INVERTED,    TermColor.init, TermColor.init },
        // mirror
        { COLORMAP_BACKGROUND,  TermColor.init, TermColor.red },
        // unimportant
        { COLORMAP_FOREGROUND,  TermColor.gray, TermColor.init },
    ];
    static ColorMap default_(ColorScheme scheme)
    {
        size_t i = cast(size_t)scheme;
        version (D_NoBoundsChecks)
            if (i < SCHEMES) throw new Exception("assert: i < SCHEMES");
        return defaults[i];
    }
}

struct LineSegment
{
    string data;
    ColorScheme scheme;

    string toString() const { return data; }
}
struct Line
{
    List!LineSegment segments;
    char[4 * 1024] textbuf;
    size_t textpos;

    // "reserve" is a function in object.d. DO NOT try to collide with it.
    this(size_t segment_count)
    {
        segments = List!LineSegment(segment_count);
    }
    ~this()
    {
        destroy(segments);
    }

    LineSegment opIndex(size_t i)
    {
        return segments[i];
    }

    // Setting index=0 is faster than de- and re-allocating
    void reset() { segments.reset(); textpos = 0; }

    size_t add(string text, ColorScheme scheme)
    {
        import core.stdc.string : memcpy;

        assertion(textpos + text.length <= textbuf.length);

        memcpy(textbuf.ptr + textpos, text.ptr, text.length);

        // Coalesce: extend previous segment if same scheme
        if (segments.count > 0 && segments.buffer[segments.count - 1].scheme == scheme)
        {
            auto prev = &segments.buffer[segments.count - 1];
            prev.data = cast(string) textbuf[textpos - prev.data.length .. textpos + text.length];
        }
        else
        {
            LineSegment segment;
            segment.data = cast(string) textbuf[textpos .. textpos + text.length];
            segment.scheme = scheme;
            segments ~= segment;
        }

        textpos += text.length;
        return text.length;
    }
    
    // No color
    size_t normal(string[] texts...)
    {
        size_t r;
        foreach (text; texts)
            r += add(text, ColorScheme.normal);
        return r;
    }
    
    size_t cursor(string text)
    {
        return add(text, ColorScheme.cursor);
    }
    
    size_t selection(string text)
    {
        return add(text, ColorScheme.selection);
    }
    
    size_t mirror(string text)
    {
        return add(text, ColorScheme.mirror);
    }
}
unittest
{
    Line line;

    assert(line.normal("test", "second") == 10);
    assert(line.cursor("ff") == 2);
    assert(line.selection("ffff") == 4);

    // "test" and "second" coalesce into one normal segment
    assert(line[0].toString()   == "testsecond");
    assert(line[0].scheme       == ColorScheme.normal);

    assert(line[1].toString()   == "ff");
    assert(line[1].scheme       == ColorScheme.cursor);

    assert(line[2].toString()   == "ffff");
    assert(line[2].scheme       == ColorScheme.selection);
}
unittest
{
    Line line; // Emulate a line of 4 x8 columns...

    // address
    assert(line.normal("    1000000") == 11);
    assert(line.normal(" ")     == 1);

    // data
    assert(line.normal(" ")     == 1);
    assert(line.normal("ff")    == 2);
    assert(line.normal(" ")     == 1);
    assert(line.normal("ff")    == 2);
    assert(line.normal(" ")     == 1);
    assert(line.selection("ff") == 2);
    assert(line.selection(" ")  == 1);
    assert(line.selection("ff") == 2);

    // data-text spacers
    assert(line.normal("  ")    == 2);

    // text
    assert(line.normal(".")     == 1);
    assert(line.normal(".")     == 1);
    assert(line.normal(".")     == 1);
    assert(line.normal(".")     == 1);

    // Adjacent same-scheme segments coalesce:
    // [0] normal:    "    1000000  ff ff " (address + data before selection)
    // [1] selection: "ff ff"               (selected data)
    // [2] normal:    "  ...."              (spacer + text)
    assert(line.segments.count == 3);

    assert(line[0].toString()   == "    1000000  ff ff ");
    assert(line[0].scheme       == ColorScheme.normal);

    assert(line[1].toString()   == "ff ff");
    assert(line[1].scheme       == ColorScheme.selection);

    assert(line[2].toString()   == "  ....");
    assert(line[2].scheme       == ColorScheme.normal);
}