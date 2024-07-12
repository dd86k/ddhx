/// Handles formatting.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.formatter;

import core.stdc.string : memset;
import std.conv : text;

// TODO: Add hex upper?
enum Format
{
    hex,
    dec,
    oct,
}

int selectFormat(string format)
{
    switch (format) with (Format) {
    case "hex": return hex;
    case "dec": return dec;
    case "oct": return oct;
    default:
        throw new Exception(text("Invalid format: ", format));
    }
}

struct FormatInfo
{
    string name;
    int size1;
}

FormatInfo formatInfo(int format)
{
    switch (format) with (Format) {
    case hex: return FormatInfo("hex", 2);
    case dec: return FormatInfo("dec", 3);
    case oct: return FormatInfo("oct", 3);
    default:
        throw new Exception(text("Invalid format: ", format));
    }
}

enum
{
    // NOTE: lowest byte is format type
    F_ZEROPAD = 0x100,
    // Add "0x", "0", or nothing to format
    //F_PREPEND = 0x200,
}

int getdigit16lsb(ref long value)
{
    int ret = value & 0xf;
    value >>= 4;
    return ret;
}
unittest
{
    long test = 0x1234_5678_90ab_cdef;
    assert(getdigit16lsb(test) == 0xf);
    assert(getdigit16lsb(test) == 0xe);
    assert(getdigit16lsb(test) == 0xd);
    assert(getdigit16lsb(test) == 0xc);
    assert(getdigit16lsb(test) == 0xb);
    assert(getdigit16lsb(test) == 0xa);
    assert(getdigit16lsb(test) == 0);
    assert(getdigit16lsb(test) == 9);
    assert(getdigit16lsb(test) == 8);
    assert(getdigit16lsb(test) == 7);
    assert(getdigit16lsb(test) == 6);
    assert(getdigit16lsb(test) == 5);
    assert(getdigit16lsb(test) == 4);
    assert(getdigit16lsb(test) == 3);
    assert(getdigit16lsb(test) == 2);
    assert(getdigit16lsb(test) == 1);
}

private immutable char[16] hexmap = "0123456789abcdef";

private
char formatdigit16(int digit) { return hexmap[digit]; }
unittest
{
    assert(formatdigit16(0) == '0');
    assert(formatdigit16(1) == '1');
    assert(formatdigit16(2) == '2');
    assert(formatdigit16(3) == '3');
    assert(formatdigit16(4) == '4');
    assert(formatdigit16(5) == '5');
    assert(formatdigit16(6) == '6');
    assert(formatdigit16(7) == '7');
    assert(formatdigit16(8) == '8');
    assert(formatdigit16(9) == '9');
    assert(formatdigit16(0xa) == 'a');
    assert(formatdigit16(0xb) == 'b');
    assert(formatdigit16(0xc) == 'c');
    assert(formatdigit16(0xd) == 'd');
    assert(formatdigit16(0xe) == 'e');
    assert(formatdigit16(0xf) == 'f');
}

// Input : 0x123 with 11 padding (size=char count, e.g., the num of characters to fulfill)
// Output: "        123"
size_t formatval(char *buffer, size_t buffersize, int width, long value, int options)
{
    assert(buffer);
    assert(buffersize);
    assert(width);
    assert(width <= buffersize);
    
    // Setup
    int format = options & 0xf;
    int function(ref long) getdigit = void;
    char function(int) formatdigit = void;
    final switch (format) with (Format) {
    case hex:
        getdigit = &getdigit16lsb;
        formatdigit = &formatdigit16;
        break;
    case dec:
    case oct: assert(0, "implement");
    }
    
    // Example:  0x0000_0000_0000_1200 with a width of 10 characters
    // Expected:           "      1200" or
    //                     "0000001200"
    // 1. While formatting, record position of last non-zero 'digit' (one-based)
    //    0x0000_0000_0000_1200
    //                     ^
    //                     i=4
    // 2. Substract width with position
    //    width(10) - i(4) = 6 Number of padding chars
    // 3. Fill padding with the number of characters from string[0]
    
    int b; // Position of highest non-zero digit
    int i; // Number of characters written
    for (; i < width; ++i)
    {
        int digit = getdigit(value);
        buffer[width - i - 1] = formatdigit16(digit);
        if (digit) b = i; // Save position
    }
    
    // If we want space padding and more than one characters written
    if ((options & F_ZEROPAD) == 0 && i > 1)
        memset(buffer, ' ', width - (b + 1));
    
    return width;
}
unittest
{
    char[16] b;
    
    void testformat(string result, int size, long value, int options)
    {
        char[] t = b[0..formatval(b.ptr, 16, size, value, options)];
        //import std.stdio : writeln, stderr;
        //writeln(`test: "`, result, `", result: "`, t, `"`);
        if (t != result)
            assert(false);
    }
    
    testformat("0",  1, 0,        Format.hex);
    testformat("00", 2, 0,        Format.hex | F_ZEROPAD);
    testformat(" 0", 2, 0,        Format.hex);
    testformat("dd", 2, 0xdd,     Format.hex);
    testformat("c0ffee", 6, 0xc0ffee, Format.hex);
    testformat("  c0ffee", 8, 0xc0ffee, Format.hex);
    testformat("00c0ffee", 8, 0xc0ffee, Format.hex | F_ZEROPAD);
    testformat("        123", 11, 0x123, Format.hex);
    testformat("00000000123", 11, 0x123, Format.hex | F_ZEROPAD);
}
