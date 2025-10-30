/// Editor backend implemention using a Piece List to ease insertion and
/// deletion operations.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module patterns; // plural not to mess with pattern function

import transcoder : CharacterSet;
import std.conv : text;

/// Pattern prefix type.
enum PatternType
{
    unknown,
    hex,
    dec,
    oct,
    string_,
}
/// Detect pattern prefix.
/// Params: input = String input. Sliced from prefix.
/// Returns: Pattern type, unknown if it can't be detected.
PatternType patternpfx(ref string input)
{
    import std.string : startsWith;
    
    // Prefixes
    static immutable string pfxHex0 = `x:`, pfxHex1 = `0x`;
    static immutable string pfxStr0 = `s:`, pfxStr1 = `"`;
    static immutable string pfxDec0 = `d:`;
    static immutable string pfxOct0 = `o:`;
    if (startsWith(input, pfxHex0) || startsWith(input, pfxHex1))
    {
        input = input[pfxHex1.length..$];
        return PatternType.hex;
    }
    else if (startsWith(input, pfxStr0))
    {
        input = input[pfxStr0.length..$];
        return PatternType.string_;
    }
    else if (startsWith(input, pfxStr1))
    {
        if (input.length < 2 || input[$-1] != '"')
            return PatternType.unknown;
        input = input[pfxStr1.length..$-1];
        return PatternType.string_;
    }
    else if (startsWith(input, pfxDec0))
    {
        input = input[pfxDec0.length..$];
        return PatternType.dec;
    }
    else if (startsWith(input, pfxOct0))
    {
        input = input[pfxOct0.length..$];
        return PatternType.oct;
    }
    
    return PatternType.unknown;
}
unittest
{
    string p0 = "0x00";
    assert(patternpfx(p0) == PatternType.hex);
    assert(p0 == "00");
    
    p0 = `x:00`;
    assert(patternpfx(p0) == PatternType.hex);
    assert(p0 == "00");
    
    p0 = `x:ff`;
    assert(patternpfx(p0) == PatternType.hex);
    assert(p0 == "ff");
    
    p0 = `o:377`;
    assert(patternpfx(p0) == PatternType.oct);
    assert(p0 == "377");
    
    p0 = `s:hello`;
    assert(patternpfx(p0) == PatternType.string_);
    assert(p0 == "hello");
    
    p0 = `"hello"`;
    assert(patternpfx(p0) == PatternType.string_);
    assert(p0 == "hello");
    
    p0 = `""`;
    assert(patternpfx(p0) == PatternType.string_);
    assert(p0 == "");
    p0 = `"a`;
    assert(patternpfx(p0) == PatternType.unknown);
    p0 = `"`;
    assert(patternpfx(p0) == PatternType.unknown);
}

// Slice up a 64-bit integer natively
private
ubyte[] slice64(ulong *x)
{
    import core.bitop : bsr, bsf;
    
    assert(x, "fuck you");
    
    if (*x == 0) return [ 0 ];
    
    int i = (bsr(*x) / 8) + 1; // highest bit and round up to nearest byte
    version(LittleEndian)
        return (cast(ubyte*)x)[0..i]; // little: ok order
    else // BigEndian
        return (cast(ubyte*)x)[ulong.sizeof - i..ulong.sizeof]; // big: skip leading zeros
}
unittest
{
    ulong a;
    assert(slice64(&a) == [ 0 ]);
    a = 1;
    assert(slice64(&a) == [ 1 ]);
    a = 0xff;
    assert(slice64(&a) == [ 0xff ]);
    a = 0xffff;
    assert(slice64(&a) == [ 0xff, 0xff ]);
    
    a = 0x1122;
    version (LittleEndian)
        assert(slice64(&a) == [ 0x22, 0x11 ]);
    else
        assert(slice64(&a) == [ 0x11, 0x22 ]);
}

/// Transform a pattern into an array of bytes, useful as a needle.
/// Exceptions: Unknown prefix, empty values, etc.
/// Params:
///     charset = Current character set if string patterns used.
///     args... = Array of arguments (e.g., "x:00","00").
/// Returns: Byte array.
ubyte[] pattern(CharacterSet charset, string[] args...)
{
    import std.format : unformatValue, singleSpec;
    ubyte[] needle;
    PatternType last;
    foreach (string arg; args)
    {
        string orig = arg;
        PatternType next = patternpfx(arg);
    Lretry:
        final switch (next) {
        case PatternType.hex:
            static immutable auto xspec = singleSpec("%x");
            ulong b = unformatValue!ulong(arg, xspec);
            needle ~= slice64(cast(ulong*)&b);
            break;
        case PatternType.dec:
            static immutable auto dspec = singleSpec("%u");
            long b = unformatValue!long(arg, dspec);
            needle ~= slice64(cast(ulong*)&b);
            break;
        case PatternType.oct:
            static immutable auto ospec = singleSpec("%o");
            long b = unformatValue!long(arg, ospec);
            needle ~= slice64(cast(ulong*)&b);
            break;
        case PatternType.string_:
            if (arg.length == 0)
                throw new Exception("String is empty");
            // TODO: Transcode
            needle ~= arg;
            break;
        case PatternType.unknown:
            if (last)
            {
                next = last;
                goto Lretry;
            }
            throw new Exception(text("Unknown pattern prefix: ", orig));
        }
        last = next;
    }
    return needle;
}
unittest
{
    // Official prefixes
    assert(pattern(CharacterSet.ascii, "x:00")          == [ 0 ]);
    assert(pattern(CharacterSet.ascii, "d:255")         == [ 0xff ]);
    assert(pattern(CharacterSet.ascii, "o:377")         == [ 0xff ]);
    assert(pattern(CharacterSet.ascii, "x:00","00")     == [ 0, 0 ]);
    assert(pattern(CharacterSet.ascii, "s:test")        == "test");
    assert(pattern(CharacterSet.ascii, "x:0","s:test")  == "\0test");
    assert(pattern(CharacterSet.ascii, "x:0","0","s:test") == "\0\0test");
    
    // Alias prefixes
    assert(pattern(CharacterSet.ascii, "0xff")            == [ 0xff ]);
    assert(pattern(CharacterSet.ascii, "0x01")            == [ 1 ]);
    assert(pattern(CharacterSet.ascii, "0x0101")          == [ 1, 1 ]);
    assert(pattern(CharacterSet.ascii, "0x010101")        == [ 1, 1, 1 ]);
    assert(pattern(CharacterSet.ascii, "0x01010101")      == [ 1, 1, 1, 1 ]);
    assert(pattern(CharacterSet.ascii, "0x0101010101")    == [ 1, 1, 1, 1, 1 ]);
    
    // Invalid and needs to throw
    try { cast(void)pattern(CharacterSet.ascii, "");   assert(false); } catch (Exception) {}
    try { cast(void)pattern(CharacterSet.ascii, "x:"); assert(false); } catch (Exception) {}
    try { cast(void)pattern(CharacterSet.ascii, "s:"); assert(false); } catch (Exception) {}
}