/// Formatting utilities for data and address elements.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.formatting;

import core.stdc.string : memcpy;

import std.conv : to; // lazy, but convenient
import std.format;
import std.path;
import std.string : strip;
import std.traits : EnumMembers;

import ddhx.platform : assertion;
import ddhx.transcoder : CharacterSet;

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
    digit,      /// Digit edits individual digits/nibbles within elements.
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
    case WritingMode.digit:     return "DIG";
    }
}

//
// Address specifications
//

// TODO: re-use enum Format for Address
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

// NOTE: Splitting Base and Format means higher combo count
//       N bases * M formats while only defining N + M.
//       Also, makes certain operations cleaner (ie, fetching n bytes).

/// Underlying interpretation of the raw bytes (size + signedness/float).
enum BaseType : ubyte
{
    u8,     /// 8-bit unsigned integer.
    u16,    /// 16-bit unsigned integer.
    u32,    /// 32-bit unsigned integer.
}

/// How a value is rendered for display and parsing.
enum Format : ubyte
{
    hex,    /// Hexadecimal digits.
    dec,    /// Unsigned decimal digits.
    oct,    /// Unsigned octal digits.
}

// Size in bytes per base type, indexed by BaseType.
private immutable static int[] base_sizes = [
    ubyte.sizeof,
    ushort.sizeof,
    uint.sizeof,
];

// printf-family conversion character per format, indexed by Format.
private immutable static char[] format_chars = [ 'x', 'd', 'o' ];

// Precomputed printf-family format specifier per format, indexed by Format.
private immutable static string[] format_specs = [ "%0*x", "%0*d", "%0*o" ];

// Maximum display width in characters for (base, format).
// Rows: BaseType (u8, u16, u32); Cols: Format (hex, dec, oct).
private immutable static int[3][3] spacing_table = [
    [  2,  3,  3 ], // u8:  ff,        255,        377
    [  4,  5,  6 ], // u16: ffff,      65535,      177777
    [  8, 10, 11 ], // u32: ffffffff,  4294967295, 37777777777
];

/// Size in bytes of a base type.
/// Params: base = BaseType base.
/// Returns: Size of a base type in Bytes.
int size_of(BaseType base)
{
    size_t i = cast(size_t)base;
    version (D_NoBoundsChecks)
        assertion(i < base_sizes.length, "size_of(BaseType): OOB");
    return base_sizes[i];
}

/// Maximum display width in characters for the (base, format) pair.
/// Params:
///     base = BaseType base.
///     format = Formatting.
/// Returns: Size of a base type in characters.
int spacing_of(BaseType base, Format format)
{
    size_t b = cast(size_t)base, f = cast(size_t)format;
    version (D_NoBoundsChecks)
    {
        assertion(b < spacing_table.length, "spacing_of: base OOB");
        assertion(f < spacing_table[0].length, "spacing_of: format OOB");
    }
    return spacing_table[b][f];
}

/// Whether the (base, format) pair is meaningful.
///
/// Currently all integer bases accept all integer formats, so every pair is
/// valid. Float and char formats will narrow this when those land.
/// Params:
///     base = BaseType base.
///     format = Formatting.
/// Returns: True if it is a valid pair.
bool valid(BaseType base, Format format)
{
    return true;
}

/// Data representation: a (base, format) pair.
///
/// Construct with `DataType(BaseType.u8, Format.hex)` or parse a legacy
/// shorthand string ("x8", "d16", ...) via `selectDataType`.
struct DataType
{
    BaseType base;
    Format format;
}
/// Count of named legacy shorthand combos (x8..o32).
enum TYPES = type_pairs.length;

// Legacy DataType -> (BaseType, Format) mapping. Order matches DataType.
private struct TypePair { BaseType base; Format format; }
private immutable static TypePair[] type_pairs = [
    { BaseType.u8,  Format.hex }, // x8
    { BaseType.u16, Format.hex }, // x16
    { BaseType.u32, Format.hex }, // x32
    { BaseType.u8,  Format.dec }, // d8
    { BaseType.u16, Format.dec }, // d16
    { BaseType.u32, Format.dec }, // d32
    { BaseType.u8,  Format.oct }, // o8
    { BaseType.u16, Format.oct }, // o16
    { BaseType.u32, Format.oct }, // o32
];
// Shorthand names per legacy combo, indexed alongside type_pairs.
private immutable static string[] type_names = [
    "x8", "x16", "x32",
    "d8", "d16", "d32",
    "o8", "o16", "o32",
];
// Connects data types to definitions, composed at compile time from the
// (base, format) pair table above.
private immutable static DataSpec[] data_specs = () {
    DataSpec[] r;
    foreach (i, ref p; type_pairs)
    {
        DataSpec s;
        s.type    = DataType(p.base, p.format);
        s.name    = type_names[i];
        s.base    = p.base;
        s.format  = p.format;
        s.size_of = base_sizes[cast(size_t)p.base];
        s.spacing = spacing_table[cast(size_t)p.base][cast(size_t)p.format];
        s.fmtspec = format_specs[cast(size_t)p.format];
        r ~= s;
    }
    return r;
}();
unittest
{
    // Check each spec round-trips through DataType.
    foreach (i, ref p; type_pairs)
    {
        DataType t = DataType(p.base, p.format);
        assert(data_specs[i].type == t);
        assert(data_specs[i].base == p.base);
        assert(data_specs[i].format == p.format);
    }
}
unittest
{
    // Lock the (BaseType, Format) tables against the composed data_specs
    // entries so future edits cannot silently drift sizes or widths.
    foreach (ref p; type_pairs)
    {
        DataSpec spec = selectDataSpec(DataType(p.base, p.format));
        assert(size_of(p.base)              == spec.size_of);
        assert(spacing_of(p.base, p.format) == spec.spacing);
        assert(format_chars[p.format]       == spec.fmtspec[$ - 1]);
        assert(valid(p.base, p.format));
    }
}

// string alias -> data type bundle. Only known shorthands are accepted, so
// the returned pair is always `valid()` by construction.
DataType selectDataType(string type)
{
    foreach (ref spec; data_specs)
    {
        if (spec.name == type)
        {
            assert(valid(spec.type.base, spec.type.format));
            return spec.type;
        }
    }
    throw new Exception("Unknown data type");
}
// data type -> data specifications, composed from the (base, format) pair.
DataSpec selectDataSpec(DataType type)
{
    return makeSpec(type.base, type.format);
}
unittest
{
    foreach (i, ref p; type_pairs)
    {
        DataType t = DataType(p.base, p.format);
        assert(selectDataSpec(t).type == data_specs[i].type);
    }
}

// Size of a data type in bytes.
//
// Mostly used by view module.
int size_of(DataType type)
{
    return size_of(type.base);
}
unittest
{
    assert(size_of(DataType(BaseType.u8, Format.hex))  == ubyte.sizeof);
    assert(size_of(DataType(BaseType.u16, Format.hex)) == ushort.sizeof);
}

// Spacing of a data type in characters.
//
// Cheap function used by view module.
int spacing_of(DataType type)
{
    return spacing_of(type.base, type.format);
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
        DataSpec spec = selectDataSpec(type);

        if (input.length == 0)
            return false;
        if (input.length > spec.spacing)
            return false;

        auto stripped = strip(input);
        if (stripped.length == 0)
            return false;

        uint radix;
        final switch (spec.format) {
        case Format.hex: radix = 16; break;
        case Format.dec: radix = 10; break;
        case Format.oct: radix = 8;  break;
        }
        try final switch (spec.base) {
        case BaseType.u8:  u8  = to!ubyte (stripped, radix); return true;
        case BaseType.u16: u16 = to!ushort(stripped, radix); return true;
        case BaseType.u32: u32 = to!uint  (stripped, radix); return true;
        }
        catch (Exception ex) {}
        return false;
    }
}
unittest
{
    Element elem;
    
    // Hexadecimal
    assert(elem.parse(DataType(BaseType.u8, Format.hex), "0") == true);
    assert(elem.u8 == 0);
    assert(elem.parse(DataType(BaseType.u8, Format.hex), "1") == true);
    assert(elem.u8 == 1);
    assert(elem.parse(DataType(BaseType.u8, Format.hex), "01") == true);
    assert(elem.u8 == 1);
    assert(elem.parse(DataType(BaseType.u8, Format.hex), " 1") == true);
    assert(elem.u8 == 1);
    assert(elem.parse(DataType(BaseType.u8, Format.hex), "10") == true);
    assert(elem.u8 == 0x10);

    assert(elem.parse(DataType(BaseType.u16, Format.hex), "0") == true);
    assert(elem.u16 == 0);
    assert(elem.parse(DataType(BaseType.u16, Format.hex), "0101") == true);
    assert(elem.u16 == 0x0101);
    assert(elem.parse(DataType(BaseType.u16, Format.hex), " 101") == true);
    assert(elem.u16 == 0x0101);
    assert(elem.parse(DataType(BaseType.u16, Format.hex), "1010") == true);
    assert(elem.u16 == 0x1010);

    // Decimal
    assert(elem.parse(DataType(BaseType.u8, Format.dec), "0") == true);
    assert(elem.u8 == 0);
    assert(elem.parse(DataType(BaseType.u8, Format.dec), "025") == true);
    assert(elem.u8 == 25);
    assert(elem.parse(DataType(BaseType.u8, Format.dec), " 25") == true);
    assert(elem.u8 == 25);
    assert(elem.parse(DataType(BaseType.u8, Format.dec), "255") == true);
    assert(elem.u8 == 255);
    
    // Octal
    assert(elem.parse(DataType(BaseType.u32, Format.oct), "37777777777") == true);
    assert(elem.u32 == 0xffffffff);
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
    /// Underlying base interpretation.
    BaseType base;
    /// Display/parse format.
    Format format;
}

/// Build a DataSpec from a (base, format) pair.
///
/// `type` is populated when the pair matches one of the named DataType
/// presets, otherwise left at its `.init` value.
/// Returns: Data specification from base and format.
DataSpec makeSpec(BaseType base, Format format)
{
    assert(valid(base, format), "makeSpec: invalid (base, format) pair");
    DataSpec s;
    s.base    = base;
    s.format  = format;
    s.size_of = size_of(base);
    s.spacing = spacing_of(base, format);
    s.fmtspec = format_specs[cast(size_t)format];
    // Best-effort back-map to a legacy DataType for callers still keyed on it.
    foreach (i, ref p; type_pairs)
    {
        if (p.base == base && p.format == format)
        {
            s.type = DataType(base, format);
            s.name = type_names[i];
            break;
        }
    }
    return s;
}

/// Get label for this data type.
/// Params: type = Data type.
/// Returns: Label.
string dataTypeToString(DataType type) // Only used in statusbar code
{
    foreach (i, ref p; type_pairs)
    {
        if (p.base == type.base && p.format == type.format)
            return type_names[i];
    }
    return null; // unnamed (base, format) combination
}
unittest
{
    assert(dataTypeToString(DataType(BaseType.u8, Format.hex)) == "x8");
}

// TODO: Make DataWalker that modifies Element instances
//       Because then, Element can has iszero() more consistently
//       And have its own format function.
/// Helper structure that walks over a buffer and formats every element.
struct DataFormatter
{
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
        
        final switch (spec.base) {
        case BaseType.u8:
            ubyte v = *cast(ubyte*)(buffer + i);
            return cast(string)sformat(buf, spec.fmtspec, spec.spacing, v);
        case BaseType.u16:
            ushort v;
            ptrdiff_t left = size - i;
            memcpy(&v, buffer + i, left >= ushort.sizeof ? ushort.sizeof : left);
            return cast(string)sformat(buf, spec.fmtspec, spec.spacing, v);
        case BaseType.u32:
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

        // lazy lol
        final switch (spec.base) {
        case BaseType.u8:
            return *cast(ubyte*)(buffer + i) == 0;
        case BaseType.u16:
            ushort v;
            ptrdiff_t left = size - i;
            memcpy(&v, buffer + i, left >= ushort.sizeof ? ushort.sizeof : left);
            return v == 0;
        case BaseType.u32:
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
    formatter = DataFormatter(DataType(BaseType.u8, Format.hex), data.ptr, data.length);
    assert(formatter.textual(buf) == "00"); assert( formatter.iszero()); formatter.step();
    assert(formatter.textual(buf) == "01"); assert(!formatter.iszero()); formatter.step();
    assert(formatter.textual(buf) == "a0"); assert(!formatter.iszero()); formatter.step();
    assert(formatter.textual(buf) == "ff"); assert(!formatter.iszero()); formatter.step();
    assert(formatter.textual(buf) == "  ");
    
    // Test x16
    immutable ushort[] data16 = [ 0x0101, 0xf0f0 ];
    formatter = DataFormatter(DataType(BaseType.u16, Format.hex), data16.ptr, data16.length * ushort.sizeof);
    assert(formatter.textual(buf) == "0101"); assert(!formatter.iszero()); formatter.step();
    assert(formatter.textual(buf) == "f0f0"); assert(!formatter.iszero()); formatter.step();
    assert(formatter.textual(buf) == "    ");
    
    // Test partial data formatting
    immutable ubyte[] data16p = [ 0xab, 0xab, 0xab ];
    formatter = DataFormatter(DataType(BaseType.u16, Format.hex), data16p.ptr, data16p.length);
    assert(formatter.textual(buf) == "abab"); assert(!formatter.iszero()); formatter.step();
    assert(formatter.textual(buf) == "00ab"); assert(!formatter.iszero()); formatter.step();
    assert(formatter.textual(buf) == "    ");
    
    // Test decimal
    formatter = DataFormatter(DataType(BaseType.u8, Format.dec), data.ptr, data.length);
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
    
    // Validate character is valid for current DataType
    bool validate(char character)
    {
        final switch (spec.format) {
        case Format.hex:
            if (keydata_hex(character) < 0) return false;
            break;
        case Format.dec:
            if (keydata_dec(character) < 0) return false;
            break;
        case Format.oct:
            if (keydata_oct(character) < 0) return false;
            break;
        }
        return true;
    }
    
    // Add character to input buffer at current offset
    bool add(char character)
    {
        return replace(character, d);
    }
    // Replace character to input buffer at this offset
    bool replace(char character, size_t idx)
    {
        if (idx >= spec.spacing) return false;
        
        if (validate(character) == false)
            return false;
        
        txtbuffer[idx] = character;
        d = idx + 1;
        return true;
    }
    bool full()
    {
        return d >= spec.spacing;
    }
    
    // Format a single element from raw bytes using the current spec
    // Used for digit mode
    string formatRaw(char[] buf, const(void)* raw, size_t len)
    {
        final switch (spec.base) {
        case BaseType.u8:
            ubyte v = *cast(ubyte*) raw;
            return cast(string) sformat(buf, spec.fmtspec, spec.spacing, v);
        case BaseType.u16:
            ushort v;
            memcpy(&v, raw, len >= ushort.sizeof ? ushort.sizeof : len);
            return cast(string) sformat(buf, spec.fmtspec, spec.spacing, v);
        case BaseType.u32:
            uint v;
            memcpy(&v, raw, len >= uint.sizeof ? uint.sizeof : len);
            return cast(string) sformat(buf, spec.fmtspec, spec.spacing, v);
        }
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
    
    input.change(DataType(BaseType.u8, Format.hex));
    
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
    
    input.change(DataType(BaseType.u16, Format.hex));
    
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
    
    input.change(DataType(BaseType.u8, Format.dec));
    
    assert(input.add('f')   == false);
    assert(input.add('2')   == true);
    assert(input.add('2')   == true);
    assert(input.add('5')   == true);
    assert(input.full()     == true);
    assert(input.add('0')   == false);
    assert(input.format     == "225");
    assert(input.data       == [ 0xe1 ]);
    
    input.change(DataType(BaseType.u8, Format.oct));
    
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
