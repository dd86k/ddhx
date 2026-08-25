/// Pattern subsystem.
///
/// Used for creating patterns for searching and insertions.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module patterns; // plural not to mess with pattern function

import std.conv : text;
import std.string : startsWith;

import ddhx.transcoder : CharacterSet;

import utils : Argument, printable;

import messages;

/// Pattern prefix type.
enum PatternType
{
    unknown,
    hex,
    dec,
    oct,
    string_,
}
private struct Prefix { const(char)[] str; PatternType type; }
/// Detect pattern prefix.
/// Params: input = Argument bytes. Sliced from prefix.
/// Returns: Pattern type, unknown if it can't be detected.
private
Prefix patternpfx(const(char)[] input)
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
    // TODO: String types: "ascii:", etc. Avoids implicit transcoding surprise
    // TODO: Exotic types: "f24:", "f48:"
    //       These will require reading a few file specs and see if they are
    //       exact in value interpretation.
    // TODO: Evaluate "0b" prefix
    // Regular prefixes, in order of importance
    // 1. test prefix
    // 2. if prefix match, trim input by its length
    static immutable Prefix[] prefixes = [
        { "x:", PatternType.hex },
        { "0x", PatternType.hex },
        { "d:", PatternType.dec },
        { "o:", PatternType.oct },
        { "0o", PatternType.oct },
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
    
    // NOTE: There used to be a bare `"STRING"` alias for `s:STRING` here.
    //       It never fired from a command line, because the shell strips
    //       quotes before this sees them, and once quoting became meaningful
    //       (see Argument) it could only fire on `'"quoted"'`, where taking
    //       the quotes as syntax would contradict single quotes being literal.

    // Unknown, give as-is, maybe previous was correct
    pfx.str = input;
    
    return pfx;
}
unittest
{
    assert(patternpfx("0x00") == Prefix("00", PatternType.hex));
    assert(patternpfx("0o00") == Prefix("00", PatternType.oct));
    assert(patternpfx("x:00") == Prefix("00", PatternType.hex));
    assert(patternpfx("x:ff") == Prefix("ff", PatternType.hex));
    assert(patternpfx("d:255") == Prefix("255", PatternType.dec));
    assert(patternpfx("o:377") == Prefix("377", PatternType.oct));
    assert(patternpfx("s:hello") == Prefix("hello", PatternType.string_));
    
    // Quotes are not a prefix, they are the shell's business
    assert(patternpfx(`"hello"`) == Prefix(`"hello"`, PatternType.unknown));
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
///
/// A string pattern is the argument bytes, whatever they are: quoting already
/// decided which parts were raw and which were a C string literal, and escapes
/// are resolved by then (see utils.arguments). Nothing here has to be text.
///
/// ---
/// find s:C:\Users             raw, a path
/// find s:'C:\Program Files'   raw, quoted only for the space
/// find s:"\x1b[0m"            C string, an escape sequence
/// find s:'C:\Users'"\0"       both, concatenated
/// ---
///
/// A whole argument of `?` or `*` is a wildcard; anything with a prefix is
/// data, so `s:*` is already the way to search for one.
///
/// Throws: FormatException or Exception for unknown prefix, empty values,
///         invalid escape sequences, etc.
/// Params:
///     charset = Current character set if string patterns used.
///     args... = Array of arguments (e.g., "x:00","00").
/// Returns: Byte array.
Pattern pattern(CharacterSet charset, Argument[] args)
{
    import std.conv : parse;
    Pattern pat;
    PatternType last;
    foreach (Argument arg; args)
    {
        // Allow malformed text encodings in prefixes
        const(char)[] input = cast(const(char)[])arg.data;

        // A wildcard is a whole argument of its own, so a prefixed one is
        // already data and needs no quoting: `s:*` is a one-byte needle.
        switch (input) {
        case "?": pat.data ~= PATTERN_GLOB_ONE;  pat.flags |= PATTERN_HAS_GLOB; continue;
        case "*": pat.data ~= PATTERN_GLOB_MANY; pat.flags |= PATTERN_HAS_GLOB; continue;
        default:
        }

        Prefix pfx = patternpfx(input);
        
        // Throwing (after slicing) here makes the behaviour consistent and
        // ensures there is at least one or more characters
        if (pfx.str.length == 0)
            throw new Exception(MSG_MISSING_PATTERN_DATA);
        
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
            //       But, parse!long does
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
            // TODO: Possibly replace string pattern type for encoding-specific ones
            foreach (char v; pfx.str) pat.data ~= cast(ubyte)v;
            break;
        case PatternType.unknown:
            // If last pattern is correct ("x:00"), retry with that pattern,
            // since this pattern could just be "00" for example.
            if (last)
            {
                pfx.type = last;
                goto Lretry;
            }
            throw new Exception(text(MSG_UNKNOWN_PATTERN_PREFIX, printable(arg.data)));
        }
        last = pfx.type;
    }
    return pat;
}
/// Ditto
Pattern pattern(CharacterSet charset, string[] args...) // string to Argument
{
    Argument[] wrapped = new Argument[args.length];
    foreach (i, arg; args) wrapped[i] = Argument(arg);
    return pattern(charset, wrapped);
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
    assert(pattern(CharacterSet.ascii, "0o0").data             == [ 0 ]);
    assert(pattern(CharacterSet.ascii, "0o00").data            == [ 0 ]);
    assert(pattern(CharacterSet.ascii, "0xff").data            == [ 0xff ]);

    // Plain strings are raw, so a backslash is a backslash
    assert(pattern(CharacterSet.ascii, `s:a\tb`).data          == [ 'a', '\\', 't', 'b' ]);
    assert(pattern(CharacterSet.ascii, `s:C:\dir`).data        == [ 'C', ':', '\\', 'd', 'i', 'r' ]);
    assert(pattern(CharacterSet.ascii, `s:C:\\`).data          == [ 'C', ':', '\\', '\\' ]);

    // ...and what an escape sequence produced is data like any other, since it
    // arrives here already resolved. Bytes that are not text included: this is
    // the layer that has no opinion on encodings
    ubyte[] bytes(immutable(ubyte)[] data)
    {
        Argument[] argv = [ Argument(data) ];
        ubyte[] result;
        foreach (ushort v; pattern(CharacterSet.ascii, argv).data)
            result ~= cast(ubyte)v;
        return result;
    }
    assert(bytes(cast(immutable(ubyte)[])"s:\0")     == [ 0 ]);
    assert(bytes(cast(immutable(ubyte)[])"s:a\tb")   == [ 'a', '\t', 'b' ]);
    assert(bytes(cast(immutable(ubyte)[])"s:\x1b[0m") == [ 0x1b, '[', '0', 'm' ]);
    assert(bytes(cast(immutable(ubyte)[])[ 's', ':', 0xff, 0xfe ]) == [ 0xff, 0xfe ]);

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
        ["x:"], ["o:"], ["d:"], ["s:"], ["0x"],
        // Quotes are no longer a prefix alias
        ["\""], [`"yes"`],
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

    // Bad escapes are the command line's problem, not this layer's: by the
    // time a pattern is built, a backslash is only ever a backslash
    foreach (string bad; [ `s:\`, `s:\z`, `s:\x`, `s:\400` ])
        assert(pattern(CharacterSet.ascii, bad).data.length);

    // Globbers
    assert(pattern(CharacterSet.ascii, "?")                 == [ PATTERN_GLOB_ONE ]);
    assert(pattern(CharacterSet.ascii, "*")                 == [ PATTERN_GLOB_MANY ]);
    assert(pattern(CharacterSet.ascii, "x:00", "?", "x:FF") == [ 0, PATTERN_GLOB_ONE,  0xff ]);
    assert(pattern(CharacterSet.ascii, "x:00", "*", "x:FF") == [ 0, PATTERN_GLOB_MANY, 0xff ]);
    // A prefix already makes it data, no quoting involved
    assert(pattern(CharacterSet.ascii, "s:*").data == [ '*' ]);
    assert(pattern(CharacterSet.ascii, "s:?").data == [ '?' ]);
    assert(bytes(cast(immutable(ubyte)[])"s:*") == [ '*' ]);
}

// Layer boundary between the command shell (utils.arguments) and pattern
// parsing, pinned down here rather than left to be rediscovered.
//
// Shell  : word splitting, quoting, and escapes. Hands over bytes.
// Pattern: prefixes and wildcards.
//
// Nothing but bytes crosses the boundary, and the two quotes buy two
// independent things:
//
//                 protects whitespace    escape sequences
//     s:text      no                     no
//     s:'text'    yes                    no
//     s:"text"    yes                    yes
//
// Which is the same deal a string literal offers in any language: the quoting
// style says how to read the text. So a Windows path is a Windows path,
//
//      find s:C:\Users                  raw, nothing to escape
//      find s:'C:\Example Space\2'      raw, quoted only for the space
//      find s:"C:\\Example Space\\2"    C string, so the backslashes double
//
// and an escape sequence is something you opt into with double quotes. The two
// forms concatenate, each keeping its own reading, the way string literals do:
//
//      find s:'C:\Users'"\0"            a path with a NUL after it
@system unittest
{
    import utils : arguments;

    // Compile a command line the way the prompt would, minus the command word
    ushort[] compile(string line)
    {
        Argument[] argv = arguments(line);
        return pattern(CharacterSet.ascii, argv[1..$]).data;
    }
    void test_throw(string line)
    {
        ushort[] r;
        try { r = compile(line); } catch (Exception) { return; }

        import std.stdio : stderr, writeln;
        stderr.writeln("Failed to throw with: ", line, " it produced: ", r);
        assert(false, "test_throw test failed");
    }

    static immutable ushort[] EXAMPLE = // C:\Example Space\2
        [ 'C', ':', '\\', 'E', 'x', 'a', 'm', 'p', 'l', 'e', ' ',
          'S', 'p', 'a', 'c', 'e', '\\', '2' ];
    static immutable ushort[] USERS = // C:\Users
        [ 'C', ':', '\\', 'U', 's', 'e', 'r', 's' ];

    // The headline: a path is typed as a path, no quoting and no doubling
    assert(compile(`find s:C:\Users`)    == USERS);
    assert(compile(`find s:'C:\Users'`)  == USERS);
    assert(compile(`find s:"C:\\Users"`) == USERS);

    // ...and the space only costs quotes, not escapes
    assert(compile(`find s:'C:\Example Space\2'`)   == EXAMPLE);
    assert(compile(`find s:"C:\\Example Space\\2"`) == EXAMPLE);

    // Unquoted and single quoted are both raw, so they behave identically and
    // only differ on whitespace. Double quotes are the C string
    assert(compile(`find s:a\tb`)     == [ 'a', '\\', 't', 'b' ]);
    assert(compile(`find s:'a\tb'`)   == [ 'a', '\\', 't', 'b' ]);
    assert(compile(`find s:"a\tb"`)   == [ 'a', '\t', 'b' ]);
    assert(compile(`find s:\x1b[0m`)  == [ '\\', 'x', '1', 'b', '[', '0', 'm' ]);
    assert(compile(`find s:"\x1b[0m"`) == [ 0x1b, '[', '0', 'm' ]);

    // Raw means raw, so a backslash never has to be justified and a bad escape
    // is only bad where escapes exist
    assert(compile(`find s:C:\dir`)  == [ 'C', ':', '\\', 'd', 'i', 'r' ]);
    assert(compile(`find s:abc\`)    == [ 'a', 'b', 'c', '\\' ]);
    test_throw(`find s:"C:\Users"`);
    test_throw(`find s:"abc\"`);

    // Nothing collapses backslashes on the way in, so what layer 2 sees is what
    // was typed and only the C string form halves them
    assert(compile(`find s:C:\\Users`)     == [ 'C', ':', '\\', '\\', 'U', 's', 'e', 'r', 's' ]);
    assert(compile(`find s:"C:\\\\Users"`) == [ 'C', ':', '\\', '\\', 'U', 's', 'e', 'r', 's' ]);

    // A needle ending on a backslash works in all three forms, since a
    // backslash pair does not swallow the closing quote
    assert(compile(`find s:C:\`)     == [ 'C', ':', '\\' ]);
    assert(compile(`find s:'C:\'`)   == [ 'C', ':', '\\' ]);
    assert(compile(`find s:"C:\\"`)  == [ 'C', ':', '\\' ]);

    // Which form applies is per span, so the two concatenate and each part
    // keeps its own reading. That is what makes a path with a terminator, or a
    // path with a space in it, one argument and no doubling
    assert(compile(`find s:'C:\Users'"\0"`) == USERS ~ cast(ushort)0);
    assert(compile(`find s:C:\dir"a b"`)
        == [ 'C', ':', '\\', 'd', 'i', 'r', 'a', ' ', 'b' ]);
    assert(compile(`find s:"a\tb"\x`)   == [ 'a', '\t', 'b', '\\', 'x' ]);
    assert(compile(`find s:'C:\dir'"a b"`)
        == [ 'C', ':', '\\', 'd', 'i', 'r', 'a', ' ', 'b' ]);

    // Whether the prefix sits inside or outside the quotes makes no difference
    assert(compile(`find 's:C:\Users'`) == compile(`find s:'C:\Users'`));
    assert(compile(`find "s:a\tb"`)     == compile(`find s:"a\tb"`));

    // Quotes reaching a string pattern. Layer 1 has no escapes outside of
    // double quotes, so a quote is written with the other kind of quote, and
    // layer 2 still takes \' and \" inside a C string
    assert(compile(`find s:'it'"'"'s'`) == [ 'i', 't', '\'', 's' ]);
    assert(compile(`find s:"it's"`)     == [ 'i', 't', '\'', 's' ]);
    assert(compile(`find s:"it\'s"`)    == [ 'i', 't', '\'', 's' ]);
    assert(compile(`find s:say'"'hi'"'`) == [ 's', 'a', 'y', '"', 'h', 'i', '"' ]);
    assert(compile(`find s:"say\"hi\""`) == [ 's', 'a', 'y', '"', 'h', 'i', '"' ]);
    // ...and a raw backslash before a quote is just a backslash, so it ends
    // the raw run instead of escaping anything
    assert(compile(`find s:it\'s'`)     == [ 'i', 't', '\\', 's' ]);

    // A prefix is mandatory: quotes are the shell's syntax, not a pattern type
    test_throw(`find "quoted"`);
    test_throw(`find 'quoted'`);

    // A wildcard is a whole argument of its own, so a prefix is all it takes to
    // ask for one as data. Quoting is not consulted and does not need to be
    assert(compile(`find x:00 ? x:FF`)  == [ 0, PATTERN_GLOB_ONE, 0xff ]);
    assert(compile(`find x:00 * x:FF`)  == [ 0, PATTERN_GLOB_MANY, 0xff ]);
    assert(compile(`find s:"a\tb" * s:c`) == [ 'a', '\t', 'b', PATTERN_GLOB_MANY, 'c' ]);
    assert(compile(`find s:*`)          == [ '*' ]);
    assert(compile(`find s:?`)          == [ '?' ]);
    assert(compile(`find s:'*'`)        == [ '*' ]);
    assert(compile(`find s:"?"`)        == [ '?' ]);
    assert(compile(`find '*'`)          == [ PATTERN_GLOB_MANY ]);

    // An unterminated quote never reaches the pattern parser at all
    test_throw(`find s:'C:\Users`);
    test_throw(`find s:"C:\\Users`);
}

/// Match a pattern against haystack starting at hPos/nPos.
///
/// It does not scan. That is what the search() function is for, in view.
///
/// Glob semantics are MINIMAL-MATCH: `*` consumes as few bytes as possible
/// (by backtracking one byte at a time when the rest of the pattern fails).
/// The returned length therefore reflects the shortest span at hPos that
/// satisfies the pattern. Switching to greedy semantics later would change
/// the meaning of the returned length and break callers (e.g. selection
/// sizing in find commands), so any such change must be deliberate.
///
/// Params:
///     haystack = Data buffer.
///     needle   = Compiled pattern (may contain ? and * wildcards).
///     hPos     = Starting offset in haystack.
///     nPos     = Starting offset in needle (normally 0).
/// Returns: Number of haystack bytes consumed on match, or -1 on no match.
ptrdiff_t matchPattern(ubyte[] haystack, Pattern needle, size_t hPos, size_t nPos)
{
    if ((needle.flags & PATTERN_HAS_GLOB) == 0)
    {
        size_t nl = needle.data.length;
        if (hPos + nl > haystack.length) return -1;
        // Calling .toBytes() would be wasteful for *every* matchPattern invocation
        foreach (i, nc; needle.data)
            if (haystack[hPos + i] != cast(ubyte) nc) return -1;
        return cast(ptrdiff_t) nl;
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
            return cast(ptrdiff_t)(h - hPos);
        if (starN != size_t.max) // backtrack to *
        {
            n = starN + 1;
            h = ++starH;
            continue;
        }
        return -1;
    }
    // trailing *s match empty
    while (n < needle.data.length && needle.data[n] == PATTERN_GLOB_MANY) n++;
    return n == needle.data.length ? cast(ptrdiff_t)(h - hPos) : -1;
}
unittest
{
    ubyte[] hay = cast(ubyte[]) "ABCDEF";

    Pattern p = pattern(CharacterSet.ascii, "s:ABC");
    assert(matchPattern(hay, p, 0, 0) == 3);
    assert(matchPattern(hay, p, 1, 0) == -1);
    assert(matchPattern(hay, p, 4, 0) == -1); // not enough room

    // ? matches exactly one byte
    p = pattern(CharacterSet.ascii, "?", "s:BC");
    assert(matchPattern(hay, p, 0, 0) == 3); // A matches ?
    assert(matchPattern(hay, p, 2, 0) == -1); // CD != BC

    // * matches zero or more (minimal-match)
    p = pattern(CharacterSet.ascii, "*", "s:EF");
    assert(matchPattern(hay, p, 0, 0) == 6); // * eats ABCD, then EF
    assert(matchPattern(hay, p, 4, 0) == 2); // * matches empty, then EF
    assert(matchPattern(hay, p, 5, 0) == -1); // only F left

    // Literal on both sides of *: span is the full A..F
    p = pattern(CharacterSet.ascii, "s:A", "*", "s:F");
    assert(matchPattern(hay, p, 0, 0) == 6);
    assert(matchPattern(hay, p, 1, 0) == -1);

    // Multiple stars must not exponentially backtrack
    p = pattern(CharacterSet.ascii, "*", "?", "*", "s:F");
    assert(matchPattern(hay, p, 0, 0) == 6);
    assert(matchPattern(hay, p, 6, 0) == -1); // past end

    // Fixed-position match: matchPattern tests AT hPos, not starting from hPos
    p = pattern(CharacterSet.ascii, "s:D", "?", "F");
    assert(matchPattern(hay, p, 3, 0) == 3);    // "DEF": D=D, E=?, F=F
    assert(matchPattern(hay, p, 0, 0) == -1);   // 'A' != 'D'
    assert(matchPattern(hay, p, 4, 0) == -1);   // not enough room
}