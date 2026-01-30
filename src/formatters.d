/// This module used to host the document editor code, before it was moved
/// to backend.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module formatters;

// TODO: Could be renamed to "formatters"

import platform : assertion;
import std.format;
import transcoder : CharacterSet;
import platform : NotImplementedException;

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
    assert(address.format(       0x00, 10) == "         0");
    assert(address.format(       0x01, 10) == "         1");
    assert(address.format(       0x80, 10) == "        80");
    assert(address.format(       0xff, 10) == "        ff");
    assert(address.format(      0x100, 10) == "       100");
    assert(address.format(     0x1000, 10) == "      1000");
    assert(address.format(    0x10000, 10) == "     10000");
    assert(address.format(   0x100000, 10) == "    100000");
    assert(address.format(  0x1000000, 10) == "   1000000");
    assert(address.format(0x10000000,  10) == "  10000000");
    assert(address.format(0x100000000, 10) == " 100000000");
    assert(address.format(0x100000000, 10) == " 100000000");
    assert(address.format(ulong.max,   10) == "ffffffffffffffff");
}

//
// Data handling
//

/// Describes how a single element should be formatted.
enum DataType
{
    x8,     /// 8-bit hexadecimal (e.g., 0xff will be ff)
    x16,
    //x32,
    //x64,
    //u8,     /// 8-bit unsigned decimal (0xff -> 255)
    //o8,     /// 8-bit unsigned octal (0xff -> 377)
    //s8,     /// 8-bit signal decimal
    //i8,     /// 8-bit signal octal
}
/// Data specification for this data type.
struct DataSpec
{
    /// Name (e.g., "x8").
    string name;
    /// Number of characters it occupies at maximum. Used for alignment.
    int spacing;
    /// Size of data type in bytes.
    int size_of;
}
/// Get specification for this data type.
/// Params: type = Data type.
/// Returns: Data specification.
DataSpec dataSpec(DataType type)
{
    final switch (type) {
    case DataType.x8:  return DataSpec("x8",  2, ubyte.sizeof);
    case DataType.x16: return DataSpec("x16", 4, ushort.sizeof);
    //case DataType.u8: return DataSpec("u8", 3);
    //case DataType.o8: return DataSpec("o8", 3);
    }
}
/// Get label for this data type.
/// Params: type = Data type.
/// Returns: Label.
string dataTypeToString(DataType type)
{
    final switch (type) {
    case DataType.x8:  return "x8";
    case DataType.x16: return "x16";
    }
}

/// Format element as x8.
/// Params:
///     buf = Character buffer.
///     v = Element value.
///     zeros = If true, prepend with zeros.
/// Returns: String slice.
string formatx8(char[] buf, ubyte v, bool zeros) // DataFormatter uses this...
{
    return cast(string)sformat(buf, zeros ? "%02x" : "%2x", v);
}
unittest
{
    char[32] buf = void;
    assert(formatx8(buf, 0x00, true)  == "00");
    assert(formatx8(buf, 0x01, true)  == "01");
    assert(formatx8(buf, 0xff, true)  == "ff");
    assert(formatx8(buf, 0x00, false) == " 0");
    assert(formatx8(buf, 0x01, false) == " 1");
    assert(formatx8(buf, 0xff, false) == "ff");
}
string formatx16(char[] buf, ushort v, bool zeros)
{
    return cast(string)sformat(buf, zeros ? "%04x" : "%4x", v);
}
unittest
{
    char[32] buf = void;
    assert(formatx16(buf, 0x0001, true)  == "0001");
    assert(formatx16(buf, 0x0101, true)  == "0101");
    assert(formatx16(buf, 0xff01, true)  == "ff01");
    assert(formatx16(buf, 0x0001, false) == "   1");
    assert(formatx16(buf, 0x0101, false) == " 101");
    assert(formatx16(buf, 0xff01, false) == "ff01");
}

/// Helper structure that walks over a buffer and formats every element.
struct DataFormatter
{
    /// New instance
    this(DataType dtype, const(void) *data, size_t len)
    {
        // TODO: Partial formatting
        final switch (dtype) {
        case DataType.x8:
            size = ubyte.sizeof;
            formatdata = () {
                if (i >= max)
                    return null;
                return formatx8(textbuf, (cast(ubyte*)buffer)[i], true);
            };
            break;
        case DataType.x16:
            // TODO: Fix formatting for x16
            size = ushort.sizeof;
            formatdata = () {
                if (i >= max)
                    return null;
                return formatx16(textbuf, (cast(ushort*)buffer)[i], true);
            };
            break;
        }
        
        buffer = data;
        //max = buffer + (len * size);
        max = len;
    }
    
    void step()
    {
        //buffer += size;
        i++;
    }
    
    /// Format an element.
    ///
    /// Returns null when done.
    ///
    /// Set in ctor.
    string delegate() formatdata;
    
    ubyte[] data()
    {
        return (cast(ubyte*)(buffer + (i * size)))[0..size];
    }
    
private:
    size_t size;    /// Size of one element
    size_t i;
    size_t max;
    const(void) *buffer;
    char[24] textbuf = void;
}
unittest
{
    immutable ubyte[] data = [ 0x00, 0x01, 0xa0, 0xff ];
    DataFormatter formatter = DataFormatter(DataType.x8, data.ptr, data.length);
    assert(formatter.formatdata() == "00"); formatter.step();
    assert(formatter.formatdata() == "01"); formatter.step();
    assert(formatter.formatdata() == "a0"); formatter.step();
    assert(formatter.formatdata() == "ff"); formatter.step();
    assert(formatter.formatdata() == null);
    
    // TODO: Fix position issue
    /*
    immutable ushort[] data16 = [ 0x0101, 0xf0f0 ];
    formatter = DataFormatter(DataType.x16, data16.ptr, data16.length);
    assert(formatter.formatdata() == "0101"); formatter.step();
    import std.stdio : writeln;
    writeln("d==========->", formatter.formatdata());
    assert(formatter.formatdata() == "f0f0"); formatter.step();
    assert(formatter.formatdata() == null);
    */
}

/// Helps inputting data and formatting said input
///
/// They act like relays, clat clat
struct InputFormatter
{
    void change(DataType newtype)
    {
        type = newtype;
        spec = dataSpec(newtype);
        final switch (newtype) {
        case DataType.x8:
            fmtspec = spec_x8;
            break;
        case DataType.x16:
            fmtspec = spec_x16;
            break;
        }
        reset();
    }
    
    void reset()
    {
        d = b = t = 0;
        buffer[] = 0;
    }
    
    size_t index() // digit index
    {
        return t;
    }
    
    // Add digit, goes left to right
    bool add(int digit)
    {
        //   +---- d=0
        //   |+--- d=1
        // 0x12
        //   ||
        //   ++-- b=0
        
        int dp = (spec.spacing - 1 - t);
        final switch (type) {
        case DataType.x8:
            // t=0 -> digit << 4
            // t=1 -> digit << 0
            u8 |= digit << (dp * XSHIFT);
            break;
        case DataType.x16:
            // t=0 -> digit << 12
            // t=1 -> digit << 8
            // t=2 -> digit << 4
            // t=3 -> digit << 0
            u16 |= digit << (dp * XSHIFT);
            break;
        }
        
        t++;
        
        // completed data type (x8=2 chars, x16=4 chars, etc.)
        if (++d >= spec.spacing)
        {
            b = spec.size_of;
            d = 0; // reset digit index
            return true;
        }
        
        return false;
    }
    
    // Format what's in the buffer
    string format()
    {
        final switch (type) {
        case DataType.x8:
            return cast(string)sformat(txtbuffer, fmtspec, spec.spacing, u8);
        case DataType.x16:
            return cast(string)sformat(txtbuffer, fmtspec, spec.spacing, u16);
        }
    }
    alias toString = format;
    
    // Return data because entering numbers from left to right
    ubyte[] data()
    {
        version (LittleEndian)
        {
            int r = spec.size_of - 1;
            for (int i; i < spec.size_of; i++, r--)
            {
                outbuffer[i] = buffer[r];
            }
            
            return outbuffer[0..spec.size_of];
        }
        else return buffer[0..spec.size_of]; // BigEndian :-)
    }
    
private:
    enum XSHIFT = 4;  // << 4
    enum DSHIFT = 10; // * 10
    enum OSHIFT = 8;  // * 8
    
    static immutable string spec_x8 =  "%0*x";
    static immutable string spec_x16 = spec_x8;
    string fmtspec = spec_x8;
    
    DataType type = DataType.x8;
    DataSpec spec;
    int d; /// digit index
    int b; /// buffer index
    int t; /// total digits
    
    union // NOTE: Using integers for math is easier
    {
        ubyte[8] buffer = void;
        ubyte   u8 = void;
        ushort u16 = void;
        uint   u32 = void;
        ulong  u64 = void;
    }
    version (LittleEndian) ubyte[8] outbuffer = void;
    char[24] txtbuffer = void;
}
unittest
{
    InputFormatter input;
    
    input.change(DataType.x8);
    
    assert(input.data   == [ 0 ]);
    
    assert(input.add(1) == false);
    assert(input.data   == [ 0x10 ]);
    assert(input.format == "10");
    
    assert(input.add(2) == true);
    assert(input.data   == [ 0x12 ]);
    assert(input.format == "12");
    
    // TODO: Fix endianness
    //       Bad if we want to print as x16
    //       0xffaa
    //       Little: [ 0xaa, 0xff ]
    //       Big   : [ 0xff, 0xaa ]
    input.change(DataType.x16);
    
    assert(input.data   == [ 0, 0 ]);
    
    assert(input.add(0xf) == false);
    assert(input.data   == [ 0xf0, 0x00 ]);
    assert(input.format == "f000");
    
    assert(input.add(2) == false);
    assert(input.data   == [ 0xf2, 0x00 ]);
    assert(input.format == "f200");
    
    assert(input.add(0xa) == false);
    assert(input.data   == [ 0xf2, 0xa0 ]);
    assert(input.format == "f2a0");
    
    assert(input.add(4) == true);
    assert(input.data   == [ 0xf2, 0xa4 ]);
    assert(input.format == "f2a4");
}
