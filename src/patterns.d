/// Pattern subsystem.
///
/// Used for creating patterns for searching and insertions.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module patterns; // plural not to mess with pattern function

import std.conv : text;
import std.string : startsWith;
import std.system : Endian;

import ddhx.transcoder : CharacterSet;

import utils : Argument, printable;

import messages;

/// What a prefix says its argument is.
///
/// The split that matters is byte string versus scalar. A byte string already
/// *is* a sequence of bytes, so its order is the order it was written in, and
/// neither a width nor an endian is a question that can be asked of it. A
/// scalar is a value that still has to be encoded into bytes, so both are.
///
/// Hexadecimal is the only radix with a byte string reading, since two digits
/// are exactly one byte. Decimal and octal do not tile bytes, so they are
/// always scalars.
enum PatternType
{
    unknown,
    bytes,  /// Literal bytes, as written ("x:", "0x").
    text,   /// Literal bytes, subject to the character set ("s:").
    scalar, /// A value encoded into bytes ("u8:", "x16:", "i32:", ...).
}

/// Everything a prefix decides about its argument.
private struct PatternSpec
{
    PatternType type;
    int radix;    /// Scalar radix: 16, 10, or 8.
    size_t width; /// Scalar size in bytes: 1, 2, 4, or 8.
    bool signed;  /// Scalar takes a leading '-' and encodes two's complement.
}
private struct Prefix { const(char)[] str; PatternSpec spec; }
/// Detect pattern prefix.
/// Params: input = Argument bytes. Sliced from prefix.
/// Returns: Prefix, of unknown type if it can't be detected.
private
Prefix patternpfx(const(char)[] input)
{
    Prefix pfx;
    
    if (input is null || input.length == 0)
        return pfx;

    // TODO: "re:" for Regular Expressions
    // TODO: Floats: At least "f32:" and "f64:"
    // TODO: "f24:"/"f48:" exotic floats
    // TODO: String types: "ascii:", etc. Avoids implicit transcoding surprise
    //
    // Endianness is deliberately absent: it is a property of the file being
    // looked at, not of one needle, so scalars follow the `endian` setting
    // (the same one the inspector uses) instead of doubling every prefix.
    //
    // Every scalar states a width, so there is no bare "d:", "o:", or "0o":
    // those sized themselves to the value, which put a pattern's length at the
    // mercy of the number written in it. See src/README for the full argument.
    //
    // Longest first: a bare prefix must not shadow its width forms.
    static immutable Prefix[] prefixes = [
        // Hexadecimal, as written
        { "x:",   { PatternType.bytes } },
        { "0x",   { PatternType.bytes } },
        // Text
        { "s:",   { PatternType.text } },
        // Hexadecimal, as a value
        { "x8:",  { PatternType.scalar, 16, 1 } },
        { "x16:", { PatternType.scalar, 16, 2 } },
        { "x32:", { PatternType.scalar, 16, 4 } },
        { "x64:", { PatternType.scalar, 16, 8 } },
        // Decimal, unsigned
        { "u8:",  { PatternType.scalar, 10, 1 } },
        { "u16:", { PatternType.scalar, 10, 2 } },
        { "u32:", { PatternType.scalar, 10, 4 } },
        { "u64:", { PatternType.scalar, 10, 8 } },
        // Decimal, signed
        { "i8:",  { PatternType.scalar, 10, 1, true } },
        { "i16:", { PatternType.scalar, 10, 2, true } },
        { "i32:", { PatternType.scalar, 10, 4, true } },
        { "i64:", { PatternType.scalar, 10, 8, true } },
        // Octal
        { "o8:",  { PatternType.scalar, 8, 1 } },
        { "o16:", { PatternType.scalar, 8, 2 } },
        { "o32:", { PatternType.scalar, 8, 4 } },
        { "o64:", { PatternType.scalar, 8, 8 } },
    ];
    foreach (prefix; prefixes)
    {
        if (startsWith(input, prefix.str))
        {
            pfx.str  = input[prefix.str.length..$];
            pfx.spec = prefix.spec;
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
    static immutable PatternSpec BYTES  = { PatternType.bytes };
    static immutable PatternSpec TEXT   = { PatternType.text };

    assert(patternpfx("0x00")    == Prefix("00", BYTES));
    assert(patternpfx("x:00")    == Prefix("00", BYTES));
    assert(patternpfx("x:ff")    == Prefix("ff", BYTES));
    assert(patternpfx("s:hello") == Prefix("hello", TEXT));

    // Every scalar states a width
    assert(patternpfx("x16:1122") == Prefix("1122", PatternSpec(PatternType.scalar, 16, 2)));
    assert(patternpfx("u16:255")  == Prefix("255",  PatternSpec(PatternType.scalar, 10, 2)));
    assert(patternpfx("o16:377")  == Prefix("377",  PatternSpec(PatternType.scalar,  8, 2)));
    assert(patternpfx("i8:-1")    == Prefix("-1",   PatternSpec(PatternType.scalar, 10, 1, true)));
    assert(patternpfx("i64:-1")   == Prefix("-1",   PatternSpec(PatternType.scalar, 10, 8, true)));

    // Quotes are not a prefix, they are the shell's business
    assert(patternpfx(`"hello"`) == Prefix(`"hello"`));
    assert(patternpfx(`"a`) == Prefix(`"a`));
    assert(patternpfx(`"`)  == Prefix(`"`));

    // Empty or null
    assert(patternpfx("")   == Prefix(""));
    assert(patternpfx(null) == Prefix(null));
    assert(patternpfx(`""`) == Prefix(`""`));

    // Invalid prefixes
    assert(patternpfx("INVALID:") == Prefix("INVALID:"));
    assert(patternpfx("x24:00")   == Prefix("x24:00"));

    // Removed: a scalar type with no width to encode into
    assert(patternpfx("d:255")  == Prefix("d:255"));
    assert(patternpfx("o:377")  == Prefix("o:377"));
    assert(patternpfx("0o377")  == Prefix("0o377"));
    assert(patternpfx("i:1")    == Prefix("i:1"));
    assert(patternpfx("u:1")    == Prefix("u:1"));
}

// Turn hex digits into the bytes they spell, in the order they were written.
//
// An odd digit count is refused rather than padded: a byte string with half a
// byte on the end is a typo, and guessing which end gains the zero is how "x:"
// used to end up meaning something other than what was typed.
//
// Used to append to a ushort array.
private
ubyte[] hexbytes(const(char)[] input, immutable(ubyte)[] arg)
{
    static int digit(char c)
    {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return -1;
    }

    if (input.length % 2)
        throw new Exception(text(MSG_ODD_HEX_DIGITS, printable(arg)));

    ubyte[] result = new ubyte[input.length / 2];
    foreach (i, ref ubyte b; result)
    {
        int hi = digit(input[i * 2]);
        int lo = digit(input[i * 2 + 1]);
        if (hi < 0 || lo < 0)
            throw new Exception(text(MSG_INVALID_NUMBER, printable(arg)));
        b = cast(ubyte)((hi << 4) | lo);
    }
    return result;
}

// Encode a value into `width` bytes, ordered by `endian`.
//
// The width is always the caller's, never the value's: a needle whose length
// depends on the number in it is a needle that overwrites a different amount
// of file for "replace d:255" than for "replace d:256".
//
// Negative values arrive already wrapped, so truncating to `width` bytes is
// the two's complement encoding.
private
ubyte[] encode(ulong value, size_t width, Endian endian)
{
    assert(width == 1 || width == 2 || width == 4 || width == 8);

    ubyte[] result = new ubyte[width];
    foreach (size_t i; 0..width)
    {
        ubyte b = cast(ubyte)(value >> (i * 8));
        result[endian == Endian.littleEndian ? i : width - 1 - i] = b;
    }
    return result;
}
unittest
{
    with (Endian)
    {
        assert(encode(0, 1, littleEndian)        == [ 0 ]);
        assert(encode(0xff, 1, littleEndian)     == [ 0xff ]);
        assert(encode(0x1122, 2, littleEndian)   == [ 0x22, 0x11 ]);
        assert(encode(0x1122, 2, bigEndian)      == [ 0x11, 0x22 ]);
        assert(encode(0x112233, 4, littleEndian) == [ 0x33, 0x22, 0x11, 0 ]);

        // A width pads, host word size never enters into it
        assert(encode(1, 1, littleEndian) == [ 1 ]);
        assert(encode(1, 2, littleEndian) == [ 1, 0 ]);
        assert(encode(1, 2, bigEndian)    == [ 0, 1 ]);
        assert(encode(1, 4, littleEndian) == [ 1, 0, 0, 0 ]);
        assert(encode(1, 8, bigEndian)    == [ 0, 0, 0, 0, 0, 0, 0, 1 ]);
        assert(encode(ulong.max, 8, littleEndian) ==
            [ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff ]);

        // Two's complement, courtesy of the truncation
        assert(encode(-1, 1, littleEndian) == [ 0xff ]);
        assert(encode(-1, 2, bigEndian)    == [ 0xff, 0xff ]);
        assert(encode(-2, 4, littleEndian) == [ 0xfe, 0xff, 0xff, 0xff ]);
    }
}

// Parse a scalar and encode it, per what its prefix asked for.
private
ubyte[] scalar(const(char)[] input, PatternSpec spec, Endian endian, immutable(ubyte)[] arg)
{
    import std.conv : ConvException, parse;

    // Only the signed types take a sign, and parse() only understands one at
    // radix 10 anyway, so it is taken off here and applied at the end
    bool negative;
    if (spec.signed && input[0] == '-')
    {
        negative = true;
        input = input[1..$];
        if (input.length == 0)
            throw new Exception(MSG_MISSING_PATTERN_DATA);
    }

    ulong value = void;
    try
        value = parse!ulong(input, spec.radix);
    catch (ConvException)
        throw new Exception(text(MSG_INVALID_NUMBER, printable(arg)));

    // parse() stops at the first character it does not like and leaves the
    // rest behind, which would quietly take "x16:12zz" for 0x12
    if (input.length > 0)
        throw new Exception(text(MSG_INVALID_NUMBER, printable(arg)));

    // Range check against the width asked for
    ulong max = void; // largest magnitude this width holds, sign included
    if (spec.signed == false)
        max = spec.width >= 8 ? ulong.max : (1UL << (spec.width * 8)) - 1;
    else if (spec.width >= 8)
        max = negative ? cast(ulong)long.max + 1 : long.max;
    else
    {
        ulong half = 1UL << (spec.width * 8 - 1);
        max = negative ? half : half - 1; // -128 fits where 128 does not
    }
    if (value > max)
        throw new Exception(text(MSG_VALUE_OUT_OF_RANGE, printable(arg)));

    if (negative)
        value = -value;

    return encode(value, spec.width, endian);
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
/// A prefix says whether its argument is a byte string or a value. Byte
/// strings are taken as written; values are encoded into the width their
/// prefix names, using `endian`:
///
/// ---
/// find x:1122         11 22       two bytes, as typed
/// find x16:1122       22 11       a 16-bit value, little endian
/// find d:255          ff          as many bytes as the value needs
/// find u16:255        ff 00       ...or as many as asked for
/// find i16:-1         ff ff       two's complement
/// ---
///
/// Throws: FormatException or Exception for unknown prefix, empty values,
///         values too large for their width, invalid escape sequences, etc.
/// Params:
///     charset = Current character set if string patterns used.
///     endian  = Byte order for scalar patterns.
///     args... = Array of arguments (e.g., "x:00","00").
/// Returns: Byte array.
Pattern pattern(CharacterSet charset, Endian endian, Argument[] args)
{
    Pattern pat;
    PatternSpec last;
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

        // If the last prefix was good ("x:00"), an argument without one
        // continues it, since this could just be "00" for example.
        if (pfx.spec.type == PatternType.unknown)
        {
            if (last.type == PatternType.unknown)
                throw new Exception(text(MSG_UNKNOWN_PATTERN_PREFIX, printable(arg.data)));
            pfx.spec = last;
        }

        // Throwing (after slicing) here makes the behaviour consistent and
        // ensures there is at least one or more characters
        if (pfx.str.length == 0)
            throw new Exception(MSG_MISSING_PATTERN_DATA);

        final switch (pfx.spec.type) {
        case PatternType.bytes:
            foreach (ubyte v; hexbytes(pfx.str, arg.data)) pat.data ~= v;
            break;
        case PatternType.text:
            // TODO: Possibly replace string pattern type for encoding-specific ones
            foreach (char v; pfx.str) pat.data ~= cast(ubyte)v;
            break;
        case PatternType.scalar:
            foreach (ubyte v; scalar(pfx.str, pfx.spec, endian, arg.data)) pat.data ~= v;
            break;
        case PatternType.unknown:
            assert(false, "Unknown prefixes are resolved or thrown above");
        }
        last = pfx.spec;
    }
    return pat;
}
/// Ditto
Pattern pattern(CharacterSet charset, Endian endian, string[] args...) // string to Argument
{
    Argument[] wrapped = new Argument[args.length];
    foreach (i, arg; args) wrapped[i] = Argument(arg);
    return pattern(charset, endian, wrapped);
}
unittest
{
    // Most of these do not care about endianness, so name the default once
    Pattern pat(string[] args...)
    {
        return pattern(CharacterSet.ascii, Endian.littleEndian, args);
    }
    Pattern patbe(string[] args...)
    {
        return pattern(CharacterSet.ascii, Endian.bigEndian, args);
    }

    // Official prefixes
    assert(pat("x:00").data              == [ 0 ]);
    assert(pat("u8:255").data            == [ 0xff ]);
    assert(pat("o8:377").data            == [ 0xff ]);
    assert(pat("x:00","00").data         == [ 0, 0 ]);
    assert(pat("s:test").data            == [ 't', 'e', 's', 't' ]);
    assert(pat("x:00","s:test").data     == [ 0, 't', 'e', 's', 't' ]);
    assert(pat("x:00","00","s:test").data == [ 0, 0, 't', 'e', 's', 't' ]);

    // Alias prefixes. "0x" survives because it is a byte string like "x:";
    // "0o" did not, because it was an octal scalar with no width
    assert(pat("0x00").data              == [ 0 ]);
    assert(pat("0xff").data              == [ 0xff ]);

    // Hex is a byte string: what is typed is what is searched for, in that
    // order, whatever the host or the endian setting says
    assert(pat("x:1122").data            == [ 0x11, 0x22 ]);
    assert(patbe("x:1122").data          == [ 0x11, 0x22 ]);
    assert(pat("x:0001").data            == [ 0x00, 0x01 ]); // no leading zero eaten
    assert(pat("x:deadbeef").data        == [ 0xde, 0xad, 0xbe, 0xef ]);
    assert(pat("x:DEADBEEF").data        == [ 0xde, 0xad, 0xbe, 0xef ]);
    assert(pat("x:00112233445566778899").data // longer than any scalar
        == [ 0, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99 ]);

    // ...and a width says the argument is a value instead, so it gets encoded
    assert(pat("x16:1122").data          == [ 0x22, 0x11 ]);
    assert(patbe("x16:1122").data        == [ 0x11, 0x22 ]);
    assert(pat("x8:ff").data             == [ 0xff ]);
    assert(pat("x32:1122").data          == [ 0x22, 0x11, 0, 0 ]);
    assert(patbe("x32:1122").data        == [ 0, 0, 0x11, 0x22 ]);
    assert(pat("x64:1").data             == [ 1, 0, 0, 0, 0, 0, 0, 0 ]);

    // The width is the prefix's, never the value's, so 255 and 256 occupy the
    // same two bytes and a replace overwrites the same amount either way
    assert(pat("u16:255").data           == [ 0xff, 0x00 ]);
    assert(pat("u16:256").data           == [ 0x00, 0x01 ]);
    assert(patbe("u16:256").data         == [ 0x01, 0x00 ]);
    assert(pat("u8:255").data            == [ 0xff ]);
    assert(pat("u16:255").data           == [ 0xff, 0x00 ]); // the point of widths
    assert(patbe("u16:255").data         == [ 0x00, 0xff ]);
    assert(pat("u32:1").data             == [ 1, 0, 0, 0 ]);
    assert(pat("u64:1").data             == [ 1, 0, 0, 0, 0, 0, 0, 0 ]);
    assert(pat("o16:377").data           == [ 0xff, 0x00 ]);
    assert(pat("u64:18446744073709551615").data
        == [ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff ]);

    // Signed types take a sign and encode two's complement
    assert(pat("i8:-1").data             == [ 0xff ]);
    assert(pat("i8:127").data            == [ 0x7f ]);
    assert(pat("i8:-128").data           == [ 0x80 ]);
    assert(pat("i16:-1").data            == [ 0xff, 0xff ]);
    assert(pat("i16:-2").data            == [ 0xfe, 0xff ]);
    assert(patbe("i16:-2").data          == [ 0xff, 0xfe ]);
    assert(pat("i32:-1").data            == [ 0xff, 0xff, 0xff, 0xff ]);
    assert(pat("i64:-1").data            == [ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff ]);
    assert(pat("i64:-9223372036854775808").data == [ 0, 0, 0, 0, 0, 0, 0, 0x80 ]);
    assert(pat("i16:1").data             == [ 0x01, 0x00 ]);

    // A width carries over the same way a bare prefix does
    assert(pat("u16:1", "2").data        == [ 1, 0, 2, 0 ]);
    assert(pat("i8:-1", "-2").data       == [ 0xff, 0xfe ]);

    // Which is how a needle of any length is built out of values, and it is
    // the carry-over that keeps it quick to type rather than the magnitude
    assert(pat("u8:255", "255", "255", "255", "255").data
        == [ 0xff, 0xff, 0xff, 0xff, 0xff ]);
    assert(pat("u8:1", "2", "3").data     == [ 1, 2, 3 ]);
    assert(pat("i16:-1", "-1", "-1").data == [ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff ]);

    // Plain strings are raw, so a backslash is a backslash
    assert(pat(`s:a\tb`).data            == [ 'a', '\\', 't', 'b' ]);
    assert(pat(`s:C:\dir`).data          == [ 'C', ':', '\\', 'd', 'i', 'r' ]);
    assert(pat(`s:C:\\`).data            == [ 'C', ':', '\\', '\\' ]);

    // ...and what an escape sequence produced is data like any other, since it
    // arrives here already resolved. Bytes that are not text included: this is
    // the layer that has no opinion on encodings
    ubyte[] bytes(immutable(ubyte)[] data)
    {
        Argument[] argv = [ Argument(data) ];
        ubyte[] result;
        foreach (ushort v; pattern(CharacterSet.ascii, Endian.littleEndian, argv).data)
            result ~= cast(ubyte)v;
        return result;
    }
    assert(bytes(cast(immutable(ubyte)[])"s:\0")     == [ 0 ]);
    assert(bytes(cast(immutable(ubyte)[])"s:a\tb")   == [ 'a', '\t', 'b' ]);
    assert(bytes(cast(immutable(ubyte)[])"s:\x1b[0m") == [ 0x1b, '[', '0', 'm' ]);
    assert(bytes(cast(immutable(ubyte)[])[ 's', ':', 0xff, 0xfe ]) == [ 0xff, 0xfe ]);

    // Non-string multibyte patterns
    assert(pat("0x01").data                == [ 1 ]);
    assert(pat("0x0101").data              == [ 1, 1 ]);
    assert(pat("0x010101").data            == [ 1, 1, 1 ]);
    assert(pat("0x01010101").data          == [ 1, 1, 1, 1 ]); // 32bit
    assert(pat("0x0101010101").data        == [ 1, 1, 1, 1, 1 ]);
    assert(pat("0x010101010101").data      == [ 1, 1, 1, 1, 1, 1 ]);
    assert(pat("0x01010101010101").data    == [ 1, 1, 1, 1, 1, 1, 1 ]);
    assert(pat("0x0101010101010101").data  == [ 1, 1, 1, 1, 1, 1, 1, 1 ]);

    // Invalid tests that need to throw
    void test_throw(string[] input)
    {
        Pattern r;
        try { r = pattern(CharacterSet.ascii, Endian.littleEndian, input); }
        catch (Exception) { return; }

        import std.stdio : stderr, writeln;
        stderr.writeln("Failed to throw with: ", input, " it produced: ", r.data);
        assert(false, "test_throw test failed");
    }
    string[][] invalids = [
        // Missing prefix
        [""], ["00"], ["00", "0x00"],
        // Empty data
        ["x:"], ["s:"], ["0x"], ["x16:"], ["i8:"], ["i8:-"], ["u8:"], ["o8:"],
        // Quotes are no longer a prefix alias
        ["\""], [`"yes"`],
        // Unknown prefixes, including widths that are not a type
        ["INVALID:ff"], ["INVALID:"], ["x24:00"], ["d128:1"], ["i:1"], ["u:1"],
        // Tests last known good prefix
        ["x:00", "INVALID:ff"],
        // Half a byte is a typo, not a byte
        ["x:0"], ["x:fff"], ["0x0"], ["0xfff"], ["x:00", "0"],
        // A scalar type without a width, whatever it would have encoded to.
        // "d:", "o:", and "0o" are the retired spellings people will still
        // type; "u:" and "i:" never existed
        ["u:"], ["u:0"], ["u:255"], ["u:256"], ["i:1"],
        ["d:"], ["d:0"], ["d:255"], ["d:256"], ["d:65536"],
        ["o:"], ["o:377"], ["0o0"], ["0o377"],
        ["x:00", "u:1"], ["x:00", "d:1"], ["u8:1", "d:1"],
        // Not digits, and no silently taking the part that was
        ["x:zz"], ["x:12zz"], ["u8:12zz"], ["o8:9"], ["o8:18"], ["u8:1_0"],
        // Signs belong to the signed types only
        ["x:-1"], ["u16:-1"], ["x16:-1"], ["u8:+1"], ["o8:-1"],
        // Too large for the width asked for
        ["u8:256"], ["i8:128"], ["i8:-129"], ["u16:65536"], ["x8:100"],
        ["i16:32768"], ["i16:-32769"], ["i32:2147483648"], ["x16:10000"],
        ["i64:9223372036854775808"], ["i64:-9223372036854775809"],
        // Too large for anything
        ["u64:18446744073709551616"],
    ];
    foreach (inv; invalids)
        test_throw(inv);

    // A byte string has no width to overflow, so what used to be "too long"
    // is now just a longer needle
    assert(pat("0x010101010101010101").data.length == 9); // 64+8 bits
    assert(pat("0x0101010101010101010101").data.length == 11);

    // Bad escapes are the command line's problem, not this layer's: by the
    // time a pattern is built, a backslash is only ever a backslash
    foreach (string bad; [ `s:\`, `s:\z`, `s:\x`, `s:\400` ])
        assert(pat(bad).data.length);

    // Globbers
    assert(pat("?")                 == [ PATTERN_GLOB_ONE ]);
    assert(pat("*")                 == [ PATTERN_GLOB_MANY ]);
    assert(pat("x:00", "?", "x:FF") == [ 0, PATTERN_GLOB_ONE,  0xff ]);
    assert(pat("x:00", "*", "x:FF") == [ 0, PATTERN_GLOB_MANY, 0xff ]);
    // A prefix already makes it data, no quoting involved
    assert(pat("s:*").data == [ '*' ]);
    assert(pat("s:?").data == [ '?' ]);
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
        return pattern(CharacterSet.ascii, Endian.littleEndian, argv[1..$]).data;
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

    Pattern p = pattern(CharacterSet.ascii, Endian.littleEndian, "s:ABC");
    assert(matchPattern(hay, p, 0, 0) == 3);
    assert(matchPattern(hay, p, 1, 0) == -1);
    assert(matchPattern(hay, p, 4, 0) == -1); // not enough room

    // ? matches exactly one byte
    p = pattern(CharacterSet.ascii, Endian.littleEndian, "?", "s:BC");
    assert(matchPattern(hay, p, 0, 0) == 3); // A matches ?
    assert(matchPattern(hay, p, 2, 0) == -1); // CD != BC

    // * matches zero or more (minimal-match)
    p = pattern(CharacterSet.ascii, Endian.littleEndian, "*", "s:EF");
    assert(matchPattern(hay, p, 0, 0) == 6); // * eats ABCD, then EF
    assert(matchPattern(hay, p, 4, 0) == 2); // * matches empty, then EF
    assert(matchPattern(hay, p, 5, 0) == -1); // only F left

    // Literal on both sides of *: span is the full A..F
    p = pattern(CharacterSet.ascii, Endian.littleEndian, "s:A", "*", "s:F");
    assert(matchPattern(hay, p, 0, 0) == 6);
    assert(matchPattern(hay, p, 1, 0) == -1);

    // Multiple stars must not exponentially backtrack
    p = pattern(CharacterSet.ascii, Endian.littleEndian, "*", "?", "*", "s:F");
    assert(matchPattern(hay, p, 0, 0) == 6);
    assert(matchPattern(hay, p, 6, 0) == -1); // past end

    // Fixed-position match: matchPattern tests AT hPos, not starting from hPos
    p = pattern(CharacterSet.ascii, Endian.littleEndian, "s:D", "?", "F");
    assert(matchPattern(hay, p, 3, 0) == 3);    // "DEF": D=D, E=?, F=F
    assert(matchPattern(hay, p, 0, 0) == -1);   // 'A' != 'D'
    assert(matchPattern(hay, p, 4, 0) == -1);   // not enough room
}