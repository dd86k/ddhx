/// This module used to host the document editor code, before it was moved
/// to backend.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module doceditor;

import document.base : IDocument;
import logger;
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
enum AddressType
{
    hex,    /// Hexadecimal.
    dec,    /// Decimal.
    oct,    /// Octal.
}
/// Get label for this address type.
/// Params: type = AddressType.
/// Returns: 
string addressTypeToString(AddressType type)
{
    final switch (type) {
    case AddressType.hex: return "hex";
    case AddressType.dec: return "dec";
    case AddressType.oct: return "oct";
    }
}
/// Format an address using this type.
/// Params:
///     buf = Character buffer.
///     v = Address value.
///     spacing = Number of spacing in characters.
///     type = AddressType.
///     zeros = If set, prepend with zeros.
/// Returns: String slice.
string formatAddress(char[] buf, long v, int spacing, AddressType type, bool zeros = false)
{
    string spec = void;
    final switch (type) {
    case AddressType.hex: spec = zeros ? "%0*x" : "%*x"; break;
    case AddressType.dec: spec = zeros ? "%0*d" : "%*d"; break;
    case AddressType.oct: spec = zeros ? "%0*o" : "%*o"; break;
    }
    return cast(string)sformat(buf, spec, spacing, v);
}
unittest
{
    char[32] buf = void;
    // Address offset in column
    assert(formatAddress(buf[], 0x00, 2, AddressType.hex) == " 0");
    assert(formatAddress(buf[], 0x01, 2, AddressType.hex) == " 1");
    assert(formatAddress(buf[], 0x80, 2, AddressType.hex) == "80");
    assert(formatAddress(buf[], 0xff, 2, AddressType.hex) == "ff");
    assert(formatAddress(buf[], 0xff, 2, AddressType.dec) == "255");
    assert(formatAddress(buf[], 0xff, 2, AddressType.oct) == "377");
    assert(formatAddress(buf[], 0xf, 3, AddressType.hex, true) == "00f");
    assert(formatAddress(buf[], 0xf, 3, AddressType.dec, true) == "015");
    assert(formatAddress(buf[], 0xf, 3, AddressType.oct, true) == "017");
    // Address offset in left panel
    assert(formatAddress(buf[], 0x00, 10, AddressType.hex)        == "         0");
    assert(formatAddress(buf[], 0x01, 10, AddressType.hex)        == "         1");
    assert(formatAddress(buf[], 0x80, 10, AddressType.hex)        == "        80");
    assert(formatAddress(buf[], 0xff, 10, AddressType.hex)        == "        ff");
    assert(formatAddress(buf[], 0x100, 10, AddressType.hex)       == "       100");
    assert(formatAddress(buf[], 0x1000, 10, AddressType.hex)      == "      1000");
    assert(formatAddress(buf[], 0x10000, 10, AddressType.hex)     == "     10000");
    assert(formatAddress(buf[], 0x100000, 10, AddressType.hex)    == "    100000");
    assert(formatAddress(buf[], 0x1000000, 10, AddressType.hex)   == "   1000000");
    assert(formatAddress(buf[], 0x10000000, 10, AddressType.hex)  == "  10000000");
    assert(formatAddress(buf[], 0x100000000, 10, AddressType.hex) == " 100000000");
    assert(formatAddress(buf[], 0x100000000, 10, AddressType.hex) == " 100000000");
    assert(formatAddress(buf[], ulong.max, 10, AddressType.hex)   == "ffffffffffffffff");
}

//
// Data handling
//

/// Describes how a single element should be formatted.
enum DataType
{
    x8,     /// 8-bit hexadecimal (e.g., 0xff will be ff)
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
}
/// Get specification for this data type.
/// Params: type = Data type.
/// Returns: Data specification.
DataSpec dataSpec(DataType type)
{
    final switch (type) {
    case DataType.x8: return DataSpec("x8", 2);
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
    case DataType.x8: return "x8";
    }
}
/// Format element depending on editor settings.
/// Params:
///     buf = Character buffer.
///     dat = Pointer to data.
///     len = Length of data.
///     type = Data type.
/// Returns: String slice with formatted data.
/// Throws: An exception when length criteria isn't met.
string formatData(char[] buf, void *dat, size_t len, DataType type)
{
    final switch (type) {
    case DataType.x8:
        assertion(len >= ubyte.sizeof, "length ran out");
        return formatx8(buf, *cast(ubyte*)dat, true);
    }
}
unittest
{
    char[32] buf = void;
    ubyte a = 0x00;
    assert(formatData(buf[], &a, ubyte.sizeof, DataType.x8) == "00");
    ubyte b = 0x01;
    assert(formatData(buf[], &b, ubyte.sizeof, DataType.x8) == "01");
    ubyte c = 0xff;
    assert(formatData(buf[], &c, ubyte.sizeof, DataType.x8) == "ff");
}

/// Format element as x8.
/// Params:
///     buf = Character buffer.
///     v = Element value.
///     zeros = If true, prepend with zeros.
/// Returns: String slice.
string formatx8(char[] buf, ubyte v, bool zeros)
{
    return cast(string)sformat(buf, zeros ? "%02x" : "%2x", v);
}
unittest
{
    char[32] buf = void;
    assert(formatx8(buf[], 0x00, true)  == "00");
    assert(formatx8(buf[], 0x01, true)  == "01");
    assert(formatx8(buf[], 0xff, true)  == "ff");
    assert(formatx8(buf[], 0x00, false) == " 0");
    assert(formatx8(buf[], 0x01, false) == " 1");
    assert(formatx8(buf[], 0xff, false) == "ff");
}

/// Helper structure that walks over a buffer and formats every element.
struct DataFormatter
{
    /// New instance
    this(DataType dtype, const(ubyte) *data, size_t len)
    {
        buffer = data;
        max = buffer + len;
        
        switch (dtype) {
        case DataType.x8:
            formatdata = () {
                if (buffer + size > max)
                    return null;
                return formatx8(textbuf[], *cast(ubyte*)(buffer++), true);
            };
            size = ubyte.sizeof;
            break;
        default:
            throw new NotImplementedException();
        }
    }
    
    /// Skip an element.
    void skip()
    {
        buffer += size;
    }
    
    /// Format an element.
    ///
    /// Returns null when done.
    ///
    /// Set in ctor.
    string delegate() formatdata;
    
private:
    char[32] textbuf = void;
    size_t size;
    const(void) *buffer;
    const(void) *max;
}
unittest
{
    immutable ubyte[] data = [ 0x00, 0x01, 0xa0, 0xff ];
    DataFormatter formatter = DataFormatter(DataType.x8, data.ptr, data.length);
    assert(formatter.formatdata() == "00");
    assert(formatter.formatdata() == "01");
    assert(formatter.formatdata() == "a0");
    assert(formatter.formatdata() == "ff");
    assert(formatter.formatdata() == null);
}
