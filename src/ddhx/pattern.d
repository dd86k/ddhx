/// Pattern subsystem.
///
/// Used for creating patterns for searching and insertions.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.patterns; // plural not to mess with pattern function

import std.conv : text;
import std.format : unformatValue, singleSpec;
import std.string : startsWith;

import ddhx.transcoder : CharacterSet;

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
private
PatternType patternpfx(ref string input)
{
    if (input is null || input.length == 0)
        return PatternType.unknown;

    // TODO: "xle:"/"xbe:" prefixes to force Little or Big Endianness
    //       Or could be some form of modifier because otherwise that's
    //       potentially adding one million types.
    // TODO: "re:" for Regular Expressions
    // TODO: Scalar types (or just length delimiter)
    //       Decimal: "u8:","u16:","u32:","u64:","f32:","f64:"
    //       Hex    : "x8:","x16:","x32:","x64:"
    //       Octal  : "o8:","o16:","o32:","o64:"
    // TODO: Exotic types: "f24:", "f48:"
    //       These will require reading a few file specs and see if they are
    //       exact in value interpretation.
    // Regular prefixes, in order of importance
    // 1. test prefix
    // 2. if prefix match, trim input by its length
    struct Prefix { string str; PatternType type; }
    static immutable Prefix[] prefixes = [
        { "x:", PatternType.hex },
        { "0x", PatternType.hex },
        { "d:", PatternType.dec },
        { "o:", PatternType.oct },
        { "s:", PatternType.string_ },
    ];
    foreach (prefix; prefixes)
    {
        if (startsWith(input, prefix.str))
        {
            input = input[prefix.str.length..$];
            return prefix.type;
        }
    }
    
    // String quotes
    if (input.length >= 2 && input[0] == '"' && input[$-1] == '"')
    {
        input = input[1..$-1];
        return PatternType.string_;
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
    
    p0 = `d:255`;
    assert(patternpfx(p0) == PatternType.dec);
    assert(p0 == "255");
    
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
    
    p0 = `"a`; // missing end quote
    assert(patternpfx(p0) == PatternType.unknown);
    p0 = `"`;
    assert(patternpfx(p0) == PatternType.unknown);
}

// Slice up a 64-bit integer natively
private
ubyte[] slice64(ulong *x)
{
    import core.bitop : bsr;
    
    assert(x);
    
    if (*x == 0) return [ 0 ];
    
    int i = (bsr(*x) / 8) + 1; // highest bit and round up to nearest byte
    
    version(LittleEndian)
        return (cast(ubyte*)x)[0..i];
    else // On big endian, we skip leading zeros
        return (cast(ubyte*)x)[ulong.sizeof - i..ulong.sizeof];
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

struct Pattern
{
    ubyte[] data;
    alias data this;
}
/// Transform a pattern into an array of bytes, useful as a needle.
/// Throws: FormatException or Exception for unknown prefix, empty values, etc.
/// Params:
///     charset = Current character set if string patterns used.
///     args... = Array of arguments (e.g., "x:00","00").
/// Returns: Byte array.
ubyte[] pattern(CharacterSet charset, string[] args...)
{
    Pattern pat;
    PatternType last;
    foreach (string arg; args)
    {
        PatternType current = patternpfx(arg);
        
        // Throwing here makes the behaviour consistent and ensures there is at
        // least one or more characters
        if (arg.length == 0)
            throw new Exception("Missing data for pattern");
        
    Lretry:
        final switch (current) {
        case PatternType.hex:
            // NOTE: %x does not support negative numbers
            static immutable auto xspec = singleSpec("%x");
            ulong b = unformatValue!ulong(arg, xspec);
            pat ~= slice64(&b);
            break;
        case PatternType.dec:
            // NOTE: We don't yet support negative numbers
            //       Sadly that would require a very messy hack
            static immutable auto uspec = singleSpec("%u");
            ulong b = unformatValue!ulong(arg, uspec);
            pat ~= slice64(&b);
            break;
        case PatternType.oct:
            // NOTE: %o does not support negative numbers
            static immutable auto ospec = singleSpec("%o");
            ulong b = unformatValue!ulong(arg, ospec);
            pat ~= slice64(&b);
            break;
        case PatternType.string_:
            // TODO: Transcode
            pat ~= arg;
            break;
        case PatternType.unknown:
            // If last pattern is correct ("x:00"), retry with that pattern,
            // since this pattern could just be "00" for example.
            if (last)
            {
                current = last;
                goto Lretry;
            }
            throw new Exception(text("Unknown pattern prefix: ", arg));
        }
        last = current;
    }
    return pat;
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
    assert(pattern(CharacterSet.ascii, "0x0")             == [ 0 ]);
    assert(pattern(CharacterSet.ascii, "0x00")            == [ 0 ]);
    assert(pattern(CharacterSet.ascii, "0xff")            == [ 0xff ]);
    assert(pattern(CharacterSet.ascii, `"yes"`)           == "yes");
    
    // Non-string multibyte patterns
    assert(pattern(CharacterSet.ascii, "0x01")            == [ 1 ]);
    assert(pattern(CharacterSet.ascii, "0x0101")          == [ 1, 1 ]);
    assert(pattern(CharacterSet.ascii, "0x010101")        == [ 1, 1, 1 ]);
    assert(pattern(CharacterSet.ascii, "0x01010101")      == [ 1, 1, 1, 1 ]); // 32bit
    assert(pattern(CharacterSet.ascii, "0x0101010101")      == [ 1, 1, 1, 1, 1 ]);
    assert(pattern(CharacterSet.ascii, "0x010101010101")    == [ 1, 1, 1, 1, 1, 1 ]);
    assert(pattern(CharacterSet.ascii, "0x01010101010101")  == [ 1, 1, 1, 1, 1, 1, 1 ]);
    assert(pattern(CharacterSet.ascii, "0x0101010101010101")== [ 1, 1, 1, 1, 1, 1, 1, 1 ]);
    
    // Invalid tests that need to throw
    void test_throw(string[] input)
    {
        try { cast(void)pattern(CharacterSet.ascii, input); } catch (Exception) { return; }
        
        import std.stdio : stderr, writeln;
        stderr.writeln("Failed to throw with: ", input);
        assert(false, "test_throw test failed");
    }
    string[][] invalids = [
        // Empty
        [""], ["x:"], ["o:"], ["d:"], ["s:"], ["0x"], ["\""], ["00"],
        // Unknown prefixes
        ["INVALID:ff"], ["INVALID:"],
        // Tests last known good prefix
        ["x:00", "INVALID:ff"],
        // Negative numbers not yet supported....... sorry
        ["d:-1"], ["x:-1"], ["o:-1"],
    ];
    foreach (inv; invalids)
        test_throw(inv);
}