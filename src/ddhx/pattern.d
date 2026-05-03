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

// Slice up any integer pointer as a byte array.
// The array will be sized depending on the number of populated bits.
// For example, 0x01 will be [ 0x01 ], 0x0101 being [ 0x01, 0x01 ].
private
ubyte[] sliceup(T)(T x)
{
    // std.conv.bitCast might be interesting, but shrug
    import core.bitop : bsr;
    
    assert(x);
    
    if (*x == 0) return [ 0 ];
    
    enum S = cast(int) T.sizeof;
    
    int i = (bsr(*x) / S) + 1; // highest bit and round up to nearest byte
    
    version(LittleEndian)
        return (cast(ubyte*)x)[0..i];
    else // On big endian, we skip leading zeros
        return (cast(ubyte*)x)[T.sizeof - i..T.sizeof];
}
unittest
{
    ulong a;
    assert(sliceup(&a) == [ 0 ]);
    a = 1;
    assert(sliceup(&a) == [ 1 ]);
    a = 0xff;
    assert(sliceup(&a) == [ 0xff ]);
    a = 0xffff;
    assert(sliceup(&a) == [ 0xff, 0xff ]);
    a = 0xffff_ff;
    assert(sliceup(&a) == [ 0xff, 0xff, 0xff ]);
    a = 0xffff_ffff;
    assert(sliceup(&a) == [ 0xff, 0xff, 0xff, 0xff ]);
    a = 0xffff_ffff_ff;
    assert(sliceup(&a) == [ 0xff, 0xff, 0xff, 0xff, 0xff ]);
    a = 0xffff_ffff_ffff;
    assert(sliceup(&a) == [ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff ]);
    a = 0xffff_ffff_ffff_ff;
    assert(sliceup(&a) == [ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff ]);
    a = 0xffff_ffff_ffff_ffff;
    assert(sliceup(&a) == [ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff ]);
    
    a = 0x1122;
    version (LittleEndian)
        assert(sliceup(&a) == [ 0x22, 0x11 ]);
    else
        assert(sliceup(&a) == [ 0x11, 0x22 ]);
    
    ubyte b = 0xaa;
    assert(sliceup(&b) == [ 0xaa ]);
    
    ushort c = 0xaaaa;
    assert(sliceup(&c) == [ 0xaa, 0xaa ]);
    
    uint d = 0xaaaa_aaaa;
    assert(sliceup(&d) == [ 0xaa, 0xaa, 0xaa, 0xaa ]);
}

enum
{
    PATTERN_HAS_GLOB  = 1,   /// pattern contains ? or * wildcards
    // Globbing values
    PATTERN_GLOB_ONE  = 256, /// ushort sentinel for '?' (match exactly one byte)
    PATTERN_GLOB_MANY = 257, /// ushort sentinel for '*' (match zero or more bytes)
}
struct Pattern
{
    ushort[] data; /// full pattern; values 0-255 are literal bytes, >=256 being special
    int flags;
    alias data this;
    /// Generate a flat ubyte[] from data on demand. Valid only when there is not globbing.
    ubyte[] toBytes() const
    {
        ubyte[] result = new ubyte[data.length];
        foreach (i, v; data) result[i] = cast(ubyte) v;
        return result;
    }
    // static func avoids ctor fuckery and lvalue requirement
    // this function is mostly used for search()
    /// Generate new pattern exclusively out from raw data. Never implies globbing.
    static Pattern fromBytes(const(ubyte)[] newdata)
    {
        Pattern pat;
        pat.data = new ushort[newdata.length];
        foreach (i, v; newdata) pat.data[i] = v;
        return pat;
    }
}
/// Transform a pattern into an array of bytes, useful as a needle.
/// Throws: FormatException or Exception for unknown prefix, empty values, etc.
/// Params:
///     charset = Current character set if string patterns used.
///     args... = Array of arguments (e.g., "x:00","00").
/// Returns: Byte array.
Pattern pattern(CharacterSet charset, string[] args...)
{
    import std.conv : parse;
    Pattern pat;
    PatternType last;
    foreach (string arg; args)
    {
        switch (arg) {
        case "?": pat.data ~= PATTERN_GLOB_ONE;  pat.flags |= PATTERN_HAS_GLOB; continue;
        case "*": pat.data ~= PATTERN_GLOB_MANY; pat.flags |= PATTERN_HAS_GLOB; continue;
        default:
        }

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
            foreach (v; sliceup(&b)) pat.data ~= v;
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
            //       But, it is accepted with long as a template parameter
            ulong b = parse!ulong(pfx.str, 10);
            foreach (v; sliceup(&b)) pat.data ~= v;
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
            foreach (v; sliceup(&b)) pat.data ~= v;
            break;
        case PatternType.string_:
            // TODO: Transcode
            foreach (v; pfx.str) pat.data ~= v;
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
    assert(pattern(CharacterSet.ascii, "x:00").data          == [ 0 ]);
    assert(pattern(CharacterSet.ascii, "d:255").data         == [ 0xff ]);
    assert(pattern(CharacterSet.ascii, "o:377").data         == [ 0xff ]);
    assert(pattern(CharacterSet.ascii, "x:00","00").data     == [ 0, 0 ]);
    assert(pattern(CharacterSet.ascii, "s:test").data        == [ 't', 'e', 's', 't' ]);
    assert(pattern(CharacterSet.ascii, "x:0","s:test").data  == [ 0, 't', 'e', 's', 't' ]);
    assert(pattern(CharacterSet.ascii, "x:0","0","s:test").data == [ 0, 0, 't', 'e', 's', 't' ]);
    
    // Alias prefixes
    assert(pattern(CharacterSet.ascii, "0x0").data             == [ 0 ]);
    assert(pattern(CharacterSet.ascii, "0x00").data            == [ 0 ]);
    assert(pattern(CharacterSet.ascii, "0xff").data            == [ 0xff ]);
    assert(pattern(CharacterSet.ascii, `"yes"`).data           == [ 'y', 'e', 's' ]);
    
    // Non-string multibyte patterns
    assert(pattern(CharacterSet.ascii, "0x01").data            == [ 1 ]);
    assert(pattern(CharacterSet.ascii, "0x0101").data          == [ 1, 1 ]);
    assert(pattern(CharacterSet.ascii, "0x010101").data        == [ 1, 1, 1 ]);
    assert(pattern(CharacterSet.ascii, "0x01010101").data      == [ 1, 1, 1, 1 ]); // 32bit
    assert(pattern(CharacterSet.ascii, "0x0101010101").data      == [ 1, 1, 1, 1, 1 ]);
    assert(pattern(CharacterSet.ascii, "0x010101010101").data    == [ 1, 1, 1, 1, 1, 1 ]);
    assert(pattern(CharacterSet.ascii, "0x01010101010101").data  == [ 1, 1, 1, 1, 1, 1, 1 ]);
    assert(pattern(CharacterSet.ascii, "0x0101010101010101").data== [ 1, 1, 1, 1, 1, 1, 1, 1 ]);
    
    // Invalid tests that need to throw
    void test_throw(string[] input)
    {
        Pattern r;
        try { r = pattern(CharacterSet.ascii, input); } catch (Exception) { return; }
        
        import std.stdio : stderr, writeln;
        stderr.writeln("Failed to throw with: ", input, " it produced: ", r.data);
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
    
    // Globbers
    assert(pattern(CharacterSet.ascii, "?")                 == [ PATTERN_GLOB_ONE ]);
    assert(pattern(CharacterSet.ascii, "*")                 == [ PATTERN_GLOB_MANY ]);
    assert(pattern(CharacterSet.ascii, "x:00", "?", "x:FF") == [ 0, PATTERN_GLOB_ONE,  0xff ]);
    assert(pattern(CharacterSet.ascii, "x:00", "*", "x:FF") == [ 0, PATTERN_GLOB_MANY, 0xff ]);
}

/// Match a pattern against haystack starting at hPos/nPos.
///
/// It does not scan. That is what the search() function is for, in view.
/// Params:
///     haystack = Data buffer.
///     needle   = Compiled pattern (may contain ? and * wildcards).
///     hPos     = Starting offset in haystack.
///     nPos     = Starting offset in needle (normally 0).
/// Returns: true if the pattern matches at hPos.
bool matchPattern(ubyte[] haystack, Pattern needle, size_t hPos, size_t nPos)
{
    if ((needle.flags & PATTERN_HAS_GLOB) == 0)
    {
        size_t nl = needle.data.length;
        if (hPos + nl > haystack.length) return false;
        foreach (i, nc; needle.data)
            if (haystack[hPos + i] != cast(ubyte) nc) return false;
        return true;
    }

    // Iterative two-pointer glob match: O(n)
    size_t h = hPos, n = nPos;
    size_t starN = size_t.max, starH;

    while (h < haystack.length)
    {
        if (n < needle.data.length)
        {
            ushort nc = needle.data[n];
            if (nc < PATTERN_GLOB_ONE && haystack[h] == cast(ubyte) nc) { h++; n++; continue; }
            switch (nc) {
            case PATTERN_GLOB_ONE: h++; n++; continue;
            case PATTERN_GLOB_MANY: starN = n++; starH = h; continue;
            default:
            }
        }
        else // pattern exhausted, so prefix matches. haystack tail is irrelevant
            return true;
        if (starN != size_t.max) // backtrack to *
        {
            n = starN + 1;
            h = ++starH;
            continue;
        }
        return false;
    }
    // trailing *s match empty
    while (n < needle.data.length && needle.data[n] == PATTERN_GLOB_MANY) n++;
    return n == needle.data.length;
}
unittest
{
    ubyte[] hay = cast(ubyte[]) "ABCDEF";

    Pattern p = pattern(CharacterSet.ascii, "s:ABC");
    assert(matchPattern(hay, p, 0, 0));
    assert(matchPattern(hay, p, 1, 0) == false);
    assert(matchPattern(hay, p, 4, 0) == false); // not enough room

    // ? matches exactly one byte
    p = pattern(CharacterSet.ascii, "?", "s:BC");
    assert(matchPattern(hay, p, 0, 0)); // A matches ?
    assert(matchPattern(hay, p, 2, 0) == false); // CD != BC

    // * matches zero or more
    p = pattern(CharacterSet.ascii, "*", "s:EF");
    assert(matchPattern(hay, p, 0, 0)); // * eats ABCD
    assert(matchPattern(hay, p, 4, 0)); // * matches empty
    assert(matchPattern(hay, p, 5, 0) == false); // only F left

    // Literal on both sides of *
    p = pattern(CharacterSet.ascii, "s:A", "*", "s:F");
    assert(matchPattern(hay, p, 0, 0));
    assert(matchPattern(hay, p, 1, 0) == false);

    // Multiple stars must not exponentially backtrack
    p = pattern(CharacterSet.ascii, "*", "?", "*", "s:F");
    assert(matchPattern(hay, p, 0, 0));
    assert(matchPattern(hay, p, 6, 0) == false); // past end
    
    // Fixed-position match: matchPattern tests AT hPos, not starting from hPos
    p = pattern(CharacterSet.ascii, "s:D", "?", "F");
    assert(matchPattern(hay, p, 3, 0));           // "DEF": D=D, E=?, F=F
    assert(matchPattern(hay, p, 0, 0) == false);  // 'A' != 'D'
    assert(matchPattern(hay, p, 4, 0) == false);  // not enough room
}