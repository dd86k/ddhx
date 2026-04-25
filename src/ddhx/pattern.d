/// Pattern subsystem.
///
/// Used for creating patterns for searching and insertions.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.patterns; // plural not to mess with pattern function

import std.conv : text;
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
private struct Prefix { string str; PatternType type; }
/// Detect pattern prefix.
/// Params: input = String input. Sliced from prefix.
/// Returns: Pattern type, unknown if it can't be detected.
private
Prefix patternpfx(string input)
{
    Prefix pfx;
    
    if (input is null || input.length == 0)
        return pfx;

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
            pfx.str  = input[prefix.str.length..$];
            pfx.type = prefix.type;
            return pfx;
        }
    }
    
    // String quotes
    if (input.length > 2 && input[0] == '"' && input[$-1] == '"')
    {
        pfx.str  = input[1..$-1];
        pfx.type = PatternType.string_;
        return pfx;
    }
    
    // Unknown, give as-is, maybe previous was correct
    pfx.str = input;
    
    return pfx;
}
unittest
{
    assert(patternpfx("0x00") == Prefix("00", PatternType.hex));
    assert(patternpfx("x:00") == Prefix("00", PatternType.hex));
    assert(patternpfx("x:ff") == Prefix("ff", PatternType.hex));
    assert(patternpfx("d:255") == Prefix("255", PatternType.dec));
    assert(patternpfx("o:377") == Prefix("377", PatternType.oct));
    assert(patternpfx("s:hello") == Prefix("hello", PatternType.string_));
    assert(patternpfx(`"hello"`) == Prefix("hello", PatternType.string_));
    
    // Missing end quotes
    assert(patternpfx(`"a`) == Prefix(`"a`, PatternType.unknown));
    assert(patternpfx(`"`)  == Prefix(`"`, PatternType.unknown));
    
    // Empty or null
    assert(patternpfx("")   == Prefix("", PatternType.unknown));
    assert(patternpfx(null) == Prefix(null, PatternType.unknown));
    assert(patternpfx(`""`) == Prefix(`""`, PatternType.unknown));
    
    // Invalid prefixes
    assert(patternpfx("INVALID:") == Prefix("INVALID:", PatternType.unknown));
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
    import std.conv : parse;
    Pattern pat;
    PatternType last;
    foreach (string arg; args)
    {
        Prefix pfx = patternpfx(arg);
        
        // Throwing (after slicing) here makes the behaviour consistent and
        // ensures there is at least one or more characters
        if (pfx.str.length == 0)
            throw new Exception("Missing data for pattern");
        
    Lretry:
        final switch (pfx.type) {
        case PatternType.hex:
            // BUG: https://github.com/dlang/phobos/commit/088e55a56a4fd06067165f9a9d9eaf2173a93f73
            static if (__VERSION__ < 2090)
            {
                import ddhx.platform : assertion;
                assertion(
                    (pfx.str[0] >= '0' && pfx.str[0] <= '9') ||
                    (pfx.str[0] >= 'a' && pfx.str[0] <= 'f') ||
                    (pfx.str[0] >= 'A' && pfx.str[0] <= 'F'),
                    text("Not a hex number", pfx.str));
            }
            // NOTE: %x does not support negative numbers
            ulong b = parse!ulong(pfx.str, 16);
            pat ~= slice64(&b);
            break;
        case PatternType.dec:
            static if (__VERSION__ < 2090)
            {
                import ddhx.platform : assertion;
                assertion(
                    (pfx.str[0] >= '0' && pfx.str[0] <= '9'),
                    text("Not a hex number", pfx.str));
            }
            // NOTE: We don't yet support negative numbers
            //       Sadly that would require a very messy hack
            ulong b = parse!ulong(pfx.str, 10);
            pat ~= slice64(&b);
            break;
        case PatternType.oct:
            static if (__VERSION__ < 2090)
            {
                import ddhx.platform : assertion;
                assertion(
                    (pfx.str[0] >= '0' && pfx.str[0] <= '7'),
                    text("Not a hex number", pfx.str));
            }
            // NOTE: %o does not support negative numbers
            ulong b = parse!ulong(pfx.str, 8);
            pat ~= slice64(&b);
            break;
        case PatternType.string_:
            // TODO: Transcode
            pat ~= pfx.str;
            break;
        case PatternType.unknown:
            // If last pattern is correct ("x:00"), retry with that pattern,
            // since this pattern could just be "00" for example.
            if (last)
            {
                pfx.type = last;
                goto Lretry;
            }
            throw new Exception(text("Unknown pattern prefix: ", arg));
        }
        last = pfx.type;
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
        ubyte[] r;
        try { r = pattern(CharacterSet.ascii, input); } catch (Exception) { return; }
        
        import std.stdio : stderr, writeln;
        stderr.writeln("Failed to throw with: ", input, " it produced: ", r);
        assert(false, "test_throw test failed");
    }
    string[][] invalids = [
        // Missing prefix
        [""], ["00"], ["00", "0x00"],
        // Empty data
        ["x:"], ["o:"], ["d:"], ["s:"], ["0x"], ["\""],
        // Too long
        ["0x010101010101010101"], // 64+8 bits
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