/// Pattern subsystem.
///
/// Used for creating patterns for searching and insertions.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module patterns; // plural not to mess with pattern function

import std.conv : text;
import std.math : E, PI, SQRT2;
import std.string : startsWith;
import std.system : Endian;

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
    bytes,    /// Literal bytes, as written ("x:", "0x").
    text,     /// Text encoded into bytes ("utf8:").
    scalar,   /// An integer encoded into bytes ("u8:", "x16:", "i32:", ...).
    floating, /// A float encoded into bytes ("f32:", "f64:", "f80:").
}

/// Everything a prefix decides about its argument.
private struct PatternSpec
{
    PatternType type;
    int radix;    /// Integer scalar radix: 16, 10, or 8. Floats parse their own literal.
    size_t width; /// Scalar size in bytes: 1, 2, 4, or 8 (4, 8, or 10 for floats).
    bool signed;  /// Integer scalar takes a leading '-' and encodes two's complement.
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
    // TODO: "f16:"/"bf16:" exotic IEEE-adjacent floats
    // TODO: "ibm32:"/"ibm64:" (System/360 hex floats, as in SEG-Y and SAS
    //       transport files) and "vax32:"/"vaxg64:" if anyone asks. These get
    //       prefixes rather than a setting: a format is what the file is, and
    //       "f32:" already means binary32 everywhere, so nothing changes
    //       meaning behind a setting nobody remembers flipping
    // TODO: More text encodings: "utf16:", "utf32:", "ascii:", ...
    //
    // Text names its encoding for the same reason a scalar names its width:
    // "utf8:" says what bytes come out, where the old "s:" left it to whatever
    // the character set setting happened to be. An encoding is what the file
    // is, so it belongs on the needle, not behind a setting.
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
        { "utf8:", { PatternType.text } },
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
        // IEEE-754 binary floats, plus x87's 80-bit (long double)
        { "f32:", { PatternType.floating, 10, 4 } },
        { "f64:", { PatternType.floating, 10, 8 } },
        { "f80:", { PatternType.floating, 10, 10 } },
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

    // NOTE: There used to be a bare `"STRING"` alias for `utf8:STRING` here.
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
    assert(patternpfx("utf8:hello") == Prefix("hello", TEXT));

    // Every scalar states a width
    assert(patternpfx("x16:1122") == Prefix("1122", PatternSpec(PatternType.scalar, 16, 2)));
    assert(patternpfx("u16:255")  == Prefix("255",  PatternSpec(PatternType.scalar, 10, 2)));
    assert(patternpfx("o16:377")  == Prefix("377",  PatternSpec(PatternType.scalar,  8, 2)));
    assert(patternpfx("i8:-1")    == Prefix("-1",   PatternSpec(PatternType.scalar, 10, 1, true)));
    assert(patternpfx("i64:-1")   == Prefix("-1",   PatternSpec(PatternType.scalar, 10, 8, true)));
    assert(patternpfx("f32:1.0")  == Prefix("1.0",  PatternSpec(PatternType.floating, 10, 4)));
    assert(patternpfx("f64:-1.0") == Prefix("-1.0", PatternSpec(PatternType.floating, 10, 8)));
    assert(patternpfx("f80:1.0")  == Prefix("1.0",  PatternSpec(PatternType.floating, 10, 10)));

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
    assert(patternpfx("f:1.0")  == Prefix("f:1.0"));
    assert(patternpfx("f16:1")  == Prefix("f16:1"));
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

/// An x87 80-bit extended value, split the way the format stores it.
///
/// The odd one out among the float formats: its significand carries the integer
/// bit explicitly, where binary32 and binary64 leave it implied. So a normal has
/// bit 63 set, and clearing it does not halve the value, it makes an "unnormal"
/// the 387 and everything after it reject.
private struct Ext80
{
    ulong  significand; /// 64 bits, integer bit (bit 63) included.
    ushort signexp;     /// Sign in bit 15, biased exponent in bits 0-14.
}

/// A float constant named by its bits rather than by its value.
///
/// The NaNs have to be named this way: a float holding a signaling NaN is not
/// safe to pass around, since x87 quiets one on the way through a register, so
/// an `snan` carried as a value would arrive as a `qnan` on a 32-bit x86 build.
/// Infinity joins them so no spelling of these depends on what std.conv takes.
private struct FloatBits
{
    string name;
    ulong  f32; /// The binary32 bit pattern.
    ulong  f64; /// The binary64 bit pattern.
    Ext80  f80; /// The x87 extended bit pattern.
}
// IEEE-754 recommends the mantissa's top bit for quiet, which is what x86, ARM,
// SPARC, POWER and RISC-V do; MIPS before r6 and PA-RISC invert it. ddhx spells
// the recommended one on every host, the prefix naming a format and not a host.
//
// A signaling NaN is any nonzero mantissa with that bit clear, so a payload has
// to be picked, and there are two worth naming:
//
//   snan     payload 1, the smallest that is not infinity
//   snan_hi  payload's high bit, which is the bit just under the quiet bit,
//            the highest one a signaling NaN may set without going quiet
//
// The second is named for the bit and not for a toolchain, though it is what
// GCC and glibc's SNANF emit. The reason they pick it is that the payload keeps
// its position relative to the quiet bit when the width changes, where a
// payload of 1 does not: 7FA00000 widens to 7FFC000000000000 with its shape
// intact, while 7F800001 widens to 7FF8000020000000. Any other payload is a
// byte string, which is what "x32:" is for.
//
// "indefinite" is Intel's name for the negative quiet NaN, which is what x87
// and SSE hand back for 0.0/0.0 and the other invalid operations. It is a
// spelling of "-qnan" rather than a fifth value, and it earns a name by being
// the NaN most likely to be sitting in a dump: ARM defaults to the positive
// one, so this is not a value everything produces, only one everything meets.
//
// The 80-bit column keeps its integer bit set throughout: an infinity or a NaN
// without it is a "pseudo-infinity" or "pseudo-NaN", which the 8087 and 287
// produced and every x87 since treats as invalid. The quiet bit is the one
// below it, bit 62.
private static immutable FloatBits[] FLOAT_BITS = [
    { "inf",        0x7f80_0000, 0x7ff0_0000_0000_0000, { 0x8000_0000_0000_0000, 0x7fff } },
    { "nan",        0x7fc0_0000, 0x7ff8_0000_0000_0000, { 0xc000_0000_0000_0000, 0x7fff } },
    { "qnan",       0x7fc0_0000, 0x7ff8_0000_0000_0000, { 0xc000_0000_0000_0000, 0x7fff } },
    { "snan",       0x7f80_0001, 0x7ff0_0000_0000_0001, { 0x8000_0000_0000_0001, 0x7fff } },
    { "snan_hi",    0x7fa0_0000, 0x7ff4_0000_0000_0000, { 0xa000_0000_0000_0000, 0x7fff } },
    { "indefinite", 0xffc0_0000, 0xfff8_0000_0000_0000, { 0xc000_0000_0000_0000, 0xffff } },
];

/// A float constant a pattern can name instead of spelling out.
///
/// Every width is named because half of these are properties of the format
/// rather than numbers: binary32's largest value is not binary64's largest
/// narrowed down, that one being infinity. The mathematical ones are the same
/// number at three precisions, the first two narrowed by the compiler.
///
/// The 80-bit column is bits rather than a value because there is no host type
/// to hold it: D's `real` is x87 extended on x86 and a plain double on AArch64,
/// so a value there would make "f80:pi" mean one thing on a laptop and another
/// on a phone. These are written out instead, and the unittest below re-derives
/// them from decimal digits so the table is checked rather than trusted.
private struct FloatConstant
{
    string name;
    float  f32; /// The value at binary32.
    double f64; /// The value at binary64.
    Ext80  f80; /// The bit pattern at x87 extended.
}
// The constants worth a name are the ones nobody recognizes as hex: the maths
// that gets compiled into binaries, and the edges of the format that get used
// as sentinels (a clamp at FLT_MAX, a "no value" at the smallest subnormal).
//
// Matching is case insensitive, like the "nan" and "inf" std.conv already
// takes, and against the whole literal, so nothing here can shadow a number.
private static immutable FloatConstant[] FLOAT_CONSTANTS = [
    // Maths. PHI is not in std.math, so it is written out to the digits a
    // double holds; the rest are narrowed by the compiler, once. The 80-bit
    // column is the same number rounded to a 64-bit significand, and "pi" there
    // is the constant FLDPI loads, which is how one gets into a file this way
    { "pi",    cast(float)PI,          PI,          { 0xc90f_daa2_2168_c235, 0x4000 } }, // 64-bit truncated, not 66-bit
    { "e",     cast(float)E,           E,           { 0xadf8_5458_a2bb_4a9b, 0x4000 } },
    { "tau",   cast(float)(2 * PI),    2 * PI,      { 0xc90f_daa2_2168_c235, 0x4001 } },
    { "sqrt2", cast(float)SQRT2,       SQRT2,       { 0xb504_f333_f9de_6484, 0x3fff } },
    { "phi",   1.6180339887498948482f, 1.6180339887498948482,
                                                    { 0xcf1b_bcdc_bfa5_3e0b, 0x3fff } },
    // The format's own edges. "min" is the smallest normal, the C name for it
    // being FLT_MIN, and the subnormal below it is named in full
    { "max",        float.max,                double.max, { 0xffff_ffff_ffff_ffff, 0x7ffe } },
    { "min",        float.min_normal,         double.min_normal, { 0x8000_0000_0000_0000, 0x0001 } },
    { "epsilon",    float.epsilon,            double.epsilon, { 0x8000_0000_0000_0000, 0x3fc0 } }, // 2^-63, one bit of 64
    { "denorm_min", float.min_normal * float.epsilon,
                    double.min_normal * double.epsilon,
                    { 0x0000_0000_0000_0001, 0x0000 } },
];

// Lay out an x87 extended value: the significand, then the sign and exponent.
//
// Nothing but a little-endian machine has ever stored one natively, so big
// endian here means what it means for every other scalar, the same ten bytes in
// the other order. That is what a byte-swapped record holds, and it keeps the
// `endian` setting meaning one thing across every prefix.
private
ubyte[] encode80(Ext80 value, Endian endian)
{
    return endian == Endian.littleEndian
        ? encode(value.significand, 8, endian) ~ encode(value.signexp, 2, endian)
        : encode(value.signexp, 2, endian) ~ encode(value.significand, 8, endian);
}
unittest
{
    with (Endian)
    {
        // 1.0 is the integer bit alone at the bias
        assert(encode80(Ext80(0x8000_0000_0000_0000, 0x3fff), littleEndian)
            == [ 0, 0, 0, 0, 0, 0, 0, 0x80, 0xff, 0x3f ]);
        assert(encode80(Ext80(0x8000_0000_0000_0000, 0x3fff), bigEndian)
            == [ 0x3f, 0xff, 0x80, 0, 0, 0, 0, 0, 0, 0 ]);
        // ...and the whole object reverses, byte for byte
        assert(encode80(Ext80(0x0123_4567_89ab_cdef, 0x1234), littleEndian)
            == [ 0xef, 0xcd, 0xab, 0x89, 0x67, 0x45, 0x23, 0x01, 0x34, 0x12 ]);
        assert(encode80(Ext80(0x0123_4567_89ab_cdef, 0x1234), bigEndian)
            == [ 0x12, 0x34, 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef ]);
        assert(encode80(Ext80.init, littleEndian).length == 10);
    }
}

// Turn a decimal literal into the x87 extended value it names, exactly.
//
// This is integer arithmetic rather than a parse into a host float, because
// there is no host float to parse into: D's `real` is x87 extended on x86 and a
// plain double on AArch64, so std.conv would answer differently per machine.
// Nor is a double good enough as a stepping stone, being eleven bits short of
// the format: "3.14159265358979323846" widens to 4000 C90FDAA22168C000, where
// the value it spells is 4000 C90FDAA22168C235, the one FLDPI loads. A needle
// that misses by the last bits is a needle that finds nothing.
//
// A literal is an exact rational, digits times a power of ten, so it is built
// as one: numerator over denominator, divided to a 64-bit significand, and
// rounded to nearest with ties to even, which is the rounding IEEE-754 asks of
// every conversion. Nothing is approximated on the way, so the same literal is
// the same ten bytes on every host, and the format's full range comes with it
// (f80:1e400 has no double to be a stepping stone anyway).
private
Ext80 decimal80(const(char)[] input, bool negative, immutable(ubyte)[] arg)
{
    import core.bitop : bsr;
    import std.bigint : BigInt;

    enum ushort SIGN      = 0x8000; // sign, which lives in the exponent word
    enum int    BIAS      = 16383;  // what the exponent field is offset by
    enum int    SUBNORMAL = 16445;  // exponent of a subnormal's last bit, 16382 + 63
    // The magnitudes worth doing arithmetic for. The largest finite value is
    // 1.19e4932 and the smallest subnormal 3.65e-4951, so a magnitude outside
    // this cannot be represented and is answered without building a power of
    // ten nobody could have meant (10^^1000000 is not a division to attempt)
    enum long MAG_MAX = 4933;
    enum long MAG_MIN = -4950;
    enum int  EXP_LIMIT = 1_000_000; // where an exponent stops being counted

    // A word out of a positive BigInt. std.bigint only grew getDigit in 2.087,
    // which is newer than compilers still in service (GDC 11 carries the 2.076
    // front-end), so the words are shifted out instead: toLong is as old as
    // BigInt itself, and 32 bits at a time always fits in what it returns
    static uint word(BigInt value, size_t index)
    {
        BigInt digit = value >> (index * 32);
        digit -= (digit >> 32) << 32; // what is above the word saturates toLong
        return cast(uint)digit.toLong();
    }
    // Low 64 bits of a positive BigInt, whose value fits in them at both uses.
    static ulong low64(BigInt value)
    {
        return (cast(ulong)word(value, 1) << 32) | word(value, 0);
    }

    // Bit length of a positive BigInt, which is where the scaling starts below.
    static size_t bitlength(BigInt value)
    {
        size_t words = value.uintLength();
        if (words == 0)
            return 0;
        uint top = word(value, words - 1);
        return top == 0 ? 0 : (words - 1) * 32 + bsr(top) + 1;
    }

    // The literal is digits and a point and an exponent, and nothing else.
    // Names had their chance above, and std.conv's extras are not part of this
    // grammar: "1_0" is two answers to one question, "0x1p3" is bytes said the
    // long way, and "infinity" is spelled "inf" here
    char[] digits;
    size_t fraction; // how many of them fell after the point
    size_t i;
    bool point;
    for (; i < input.length; ++i)
    {
        char c = input[i];
        if (c >= '0' && c <= '9')
        {
            digits ~= c;
            if (point)
                ++fraction;
            continue;
        }
        if (c == '.' && point == false)
        {
            point = true;
            continue;
        }
        break;
    }
    if (digits.length == 0)
        throw new Exception(text(MSG_INVALID_NUMBER, printable(arg)));

    int exponent;
    if (i < input.length && (input[i] == 'e' || input[i] == 'E'))
    {
        bool exneg;
        if (++i < input.length && (input[i] == '+' || input[i] == '-'))
            exneg = input[i++] == '-';
        if (i >= input.length || input[i] < '0' || input[i] > '9')
            throw new Exception(text(MSG_INVALID_NUMBER, printable(arg)));
        for (; i < input.length && input[i] >= '0' && input[i] <= '9'; ++i)
            if (exponent < EXP_LIMIT) // ...past which it stops counting, rather
                exponent = exponent * 10 + (input[i] - '0'); // than wrapping
        if (exneg)
            exponent = -exponent;
    }
    // Taking the part that parsed and leaving the rest is what every other type
    // here refuses, so "f80:1.0f" is refused too
    if (i != input.length)
        throw new Exception(text(MSG_INVALID_NUMBER, printable(arg)));

    Ext80 result;
    if (negative)
        result.signexp = SIGN;

    // Leading zeros are not significant digits, and dropping them is what makes
    // the magnitude below a count rather than a guess
    size_t lead;
    while (lead < digits.length && digits[lead] == '0')
        ++lead;
    const(char)[] significant = digits[lead..$];
    if (significant.length == 0) // a zero, however it was spelled, sign kept
        return result;

    // value = significant * 10^^power, and 10^^(magnitude-1) <= value < 10^^magnitude
    int power = exponent - cast(int)fraction;
    long magnitude = cast(long)significant.length + power;
    if (magnitude > MAG_MAX)
        throw new Exception(text(MSG_VALUE_OUT_OF_RANGE, printable(arg)));
    if (magnitude < MAG_MIN) // under half the smallest subnormal, so it is zero,
        return result;       // which is what it rounds to at the other widths too

    BigInt numerator   = BigInt(significant);
    BigInt denominator = BigInt(1);
    if (power > 0)
        numerator *= BigInt(10) ^^ power;
    else if (power < 0)
        denominator = BigInt(10) ^^ -power;

    // Scale until the quotient is exactly 64 bits, which is the whole
    // significand: x87 stores the integer bit, so there is nothing implied to
    // put back afterwards. The first guess is off by at most a bit either way
    int shift = 63 - (cast(int)bitlength(numerator) - cast(int)bitlength(denominator));
    BigInt top    = shift > 0 ? numerator   << shift  : numerator;
    BigInt bottom = shift < 0 ? denominator << -shift : denominator;
    BigInt quotient = top / bottom;
    while (bitlength(quotient) > 64)
    {
        bottom <<= 1;
        --shift;
        quotient = top / bottom;
    }
    while (bitlength(quotient) < 64)
    {
        top <<= 1;
        ++shift;
        quotient = top / bottom;
    }

    // value = quotient * 2^^-shift, with the quotient at 64 bits, so the
    // unbiased exponent is what is left over
    int biased = 63 - shift + BIAS;
    if (biased > 0) // a normal, and the rounding is onto those 64 bits
    {
        ulong significand = low64(quotient);
        BigInt twice = (top - quotient * bottom) << 1;
        if (twice > bottom || (twice == bottom && (significand & 1)))
        {
            if (significand == ulong.max) // rounded up into a wider exponent
            {
                significand = 1UL << 63;
                ++biased;
            }
            else
                ++significand;
        }
        // The exponent field is full at 0x7FFF, and that encoding is spoken for
        // by the infinities and the NaNs, so there is nothing above this
        if (biased >= 0x7fff)
            throw new Exception(text(MSG_VALUE_OUT_OF_RANGE, printable(arg)));
        result.significand = significand;
        result.signexp |= cast(ushort)biased;
        return result;
    }

    // The exponent has bottomed out, so what is left is a subnormal: the value
    // rounds onto the fixed grid of 2^^-16445 rather than onto 64 significant
    // bits. It is rounded from the original ratio and not from the quotient
    // above, since rounding a value twice is how it lands a unit from where it
    // belongs (0.5 to even twice over, and 2.5 is 2 by way of 3)
    BigInt scaled  = numerator << SUBNORMAL;
    BigInt grid    = scaled / denominator;
    ulong subnormal = low64(grid); // under 2^^63, the branch says so
    BigInt over = (scaled - grid * denominator) << 1;
    if (over > denominator || (over == denominator && (subnormal & 1)))
        ++subnormal;

    // Rounding up can land exactly on 2^^63, which is no longer a subnormal but
    // the smallest normal. Its encoding is those same bits with the exponent
    // field at one, so the integer bit says which of the two this became
    result.significand = subnormal;
    result.signexp |= cast(ushort)(subnormal >> 63);
    return result;
}
unittest
{
    static Ext80 dec(const(char)[] literal, bool negative = false)
    {
        return decimal80(literal, negative, null);
    }
    static void invalid(string literal)
    {
        try
            cast(void)decimal80(literal, false, null);
        catch (Exception)
            return;

        import std.stdio : stderr, writeln;
        stderr.writeln("Failed to throw with: ", literal);
        assert(false, "decimal80 test failed");
    }

    // These are checked against what glibc's strtold makes of the same literal
    // on an x86 host, which is a conversion done in exact arithmetic like this
    // one and by someone else. Being right on this host is not the point; being
    // right the same way everywhere is, and that is what doing it in integers
    // rather than in a `real` buys
    enum ulong ONE = 0x8000_0000_0000_0000; // the integer bit, nothing after it

    // A power of two is the integer bit and an exponent
    assert(dec("1")     == Ext80(ONE, 0x3fff));
    assert(dec("1.0")   == Ext80(ONE, 0x3fff));
    assert(dec("1.")    == Ext80(ONE, 0x3fff));
    assert(dec("0001.000") == Ext80(ONE, 0x3fff));
    assert(dec("2")     == Ext80(ONE, 0x4000));
    assert(dec("0.5")   == Ext80(ONE, 0x3ffe));
    assert(dec(".5")    == Ext80(ONE, 0x3ffe));
    assert(dec("65536") == Ext80(ONE, 0x400f));
    assert(dec("1.5")   == Ext80(0xc000_0000_0000_0000, 0x3fff));
    assert(dec("100")   == Ext80(0xc800_0000_0000_0000, 0x4005));

    // Zero keeps its sign and nothing else, however it was spelled
    assert(dec("0")       == Ext80(0, 0));
    assert(dec("0.0")     == Ext80(0, 0));
    assert(dec("000.000") == Ext80(0, 0));
    assert(dec("0e999")   == Ext80(0, 0));
    assert(dec("0", true) == Ext80(0, 0x8000));

    // The sign is a field of the exponent word here, not the top of the value
    assert(dec("1.0", true) == Ext80(ONE, 0xbfff));
    assert(dec("0.5", true) == Ext80(ONE, 0xbffe));

    // The headline: 20 digits of pi land on the constant FLDPI loads, where the
    // same literal through a double would stop eleven bits short at ...C000
    assert(dec("3.14159265358979323846") == Ext80(0xc90f_daa2_2168_c235, 0x4000));

    // ...and the significand really is 64 bits wide, not a double's 53
    assert(dec("1.0000000000000000001") == Ext80(0x8000_0000_0000_0001, 0x3fff));
    assert(dec("9007199254740993")      == Ext80(0x8000_0000_0000_0400, 0x4034)); // 2^53+1
    assert(dec("18446744073709551615")  == Ext80(0xffff_ffff_ffff_ffff, 0x403e)); // 2^64-1
    assert(dec("18446744073709551616")  == Ext80(ONE, 0x403f));

    // Round to nearest, ties to even, as every other conversion does
    assert(dec("0.1")  == Ext80(0xcccc_cccc_cccc_cccd, 0x3ffb));
    assert(dec("1e-1") == Ext80(0xcccc_cccc_cccc_cccd, 0x3ffb));
    assert(dec("0.30000000000000000000000000001")
                       == Ext80(0x9999_9999_9999_999a, 0x3ffd));
    // ...including when rounding up carries into the next exponent
    assert(dec("1.99999999999999999999999999") == Ext80(ONE, 0x4000));

    // The exponent reaches where no double goes, which is half of why a file
    // holds one of these at all
    assert(dec("1e400")  == Ext80(0xda76_3fc8_cb9f_f9e6, 0x452f));
    assert(dec("1e-400") == Ext80(0x95fe_7e07_c91e_fafa, 0x3ace));
    assert(dec("0.000000001e409") == dec("1e400")); // same value, said differently
    assert(dec("1e4932") == Ext80(0xd72c_b2a9_5c7e_f6cd, 0x7ffe));
    assert(dec("1e308")  == Ext80(0x8e67_9c2f_5e44_ff8f, 0x43fe));

    // The format's own edges, by their digits rather than by name
    assert(dec("1.1897314953572317650e4932")  == Ext80(0xffff_ffff_ffff_ffff, 0x7ffe));
    assert(dec("3.36210314311209350626267781732175260259807934484647124E-4932")
        == Ext80(ONE, 0x0001));
    assert(dec("3.6451995318824746025e-4951") == Ext80(1, 0));

    // Below the smallest normal the value rounds onto a fixed grid instead of
    // onto 64 bits, which is what a subnormal is
    assert(dec("1e-4950") == Ext80(3, 0));
    assert(dec("1e-4951") == Ext80(0, 0)); // ...and under half a grid unit is zero
    assert(dec("1e-4966") == Ext80(0, 0));
    assert(dec("1e-4951", true) == Ext80(0, 0x8000)); // still signed
    // ...and rounding up off the top of that grid is the smallest normal, which
    // is the same bits with the exponent field at one
    assert(dec("3.3621031431120935062626778173217526025980793448464712E-4932")
        == Ext80(ONE, 0x0001));

    // Past the top there is no encoding left: 0x7FFF is spoken for by the
    // infinities and the NaNs, which have names of their own
    invalid("1.2e4932");
    invalid("1e4933");
    invalid("1e99999");
    invalid("1e999999999999999999"); // ...and an exponent nobody can mean is quick
    assert(dec("1e-999999999999999999") == Ext80(0, 0));

    // Digits, a point, and an exponent. Nothing else is a number here
    invalid("");
    invalid(".");
    invalid("-1");   // the sign is the caller's, and it arrives separately
    invalid("+1");
    invalid("1.0f");
    invalid("1.2.3");
    invalid("1e");
    invalid("1e+");
    invalid("1e+x");
    invalid("1 0");
    invalid("abc");
    invalid("inf");  // ...names are matched before this is ever called
    invalid("0x1p3");
}

// Parse a float and encode its bit pattern, per what its prefix asked for.
//
// A float is a scalar like any other here: the prefix names the width, and what
// lands in the needle is the bit pattern the value occupies in the file,
// ordered by `endian`. So "f32:1.0" finds 00 00 80 3f, not the digits.
//
// "f32:" means IEEE-754 binary32, "f64:" binary64, and "f80:" the 80-bit
// extended x87 stores, always, not "whatever this host calls a float". A needle
// describes bytes in a file, and a file does not change format because of the
// machine reading it, so the host is only the courier: it is used to do the
// binary32 and binary64 conversions because its floats happen to be those
// formats, and the static asserts below are what says so. Nothing on the host
// is that third format reliably, so f80: is done in integers (see decimal80).
//
// Machines that store floats some other way (VAX F/D/G, IBM System/360 hex
// floating point, Cray) are not a reason to make "f32:" mean two things. They
// are a reason for an encoder of their own, and those formats are worth having
// as prefixes for reading files rather than for hosting ddhx: IBM hex floats
// still turn up in SEG-Y seismic data and SAS transport files on machines that
// have not seen a System/360 in decades. See the TODO in patternpfx().
//
// The sign is left to the literal, since a float has no unsigned form to
// distinguish it from, and "nan" and "inf" are accepted along with the named
// constants below: none of them is memorable as hex, which is the whole reason
// to type a float instead of the bytes.
private
ubyte[] floating(const(char)[] input, PatternSpec spec, Endian endian, immutable(ubyte)[] arg)
{
    import std.algorithm.searching : canFind;
    import std.conv : ConvException, parse;
    import std.math : isInfinity, isNaN;
    import std.string : icmp;

    assert(spec.width == 4 || spec.width == 8 || spec.width == 10);

    // If this ever fires, the host is one of the exotic machines above and the
    // unions below are converting to its format instead of to the file's. The
    // fix is an explicit encoder here, never a silently different needle.
    static assert(float.sizeof == 4 && float.mant_dig == 24 && float.max_exp == 128,
        "host float is not IEEE-754 binary32, f32: needs an explicit encoder");
    static assert(double.sizeof == 8 && double.mant_dig == 53 && double.max_exp == 1024,
        "host double is not IEEE-754 binary64, f64: needs an explicit encoder");

    // The unions read the bits as a number, which is the host's business, and
    // encode() lays that number out in the order asked for, which is the file's.
    // Nothing here copies host bytes, so a big-endian build produces the same
    // needle for the same `endian` setting as a little-endian one does.
    static ulong bits32(float value)
    {
        union F32 { float f; uint bits; }
        F32 u = void;
        u.f = value;
        return u.bits;
    }
    static ulong bits64(double value)
    {
        union F64 { double d; ulong bits; }
        F64 u = void;
        u.d = value;
        return u.bits;
    }

    enum ulong  SIGN32 = 0x8000_0000;
    enum ulong  SIGN64 = 0x8000_0000_0000_0000;
    enum ushort SIGN80 = 0x8000; // ...which lives in the exponent word, not the
                                 // significand, x87 keeping the two apart

    // A constant is the whole literal, sign aside, so it can never be taken for
    // part of a number: the 'e' in "1e5" is an exponent, and "e" alone is not.
    const(char)[] name = input;
    bool negative;
    if (name[0] == '-' || name[0] == '+')
    {
        negative = name[0] == '-';
        name = name[1..$];
    }
    // The ones that are a bit pattern, so nothing they name passes through a
    // float register on the way here and nothing can quiet or requiet them
    foreach (ref special; FLOAT_BITS)
    {
        if (icmp(name, special.name) != 0)
            continue;

        // A sign can only add negativity here, never take it away, so
        // "-indefinite" agrees with what that name already is
        if (spec.width == 10)
        {
            Ext80 value = special.f80;
            if (negative)
                value.signexp |= SIGN80;
            return encode80(value, endian);
        }
        ulong bits = spec.width == 8 ? special.f64 : special.f32;
        if (negative)
            bits |= spec.width == 8 ? SIGN64 : SIGN32;
        return encode(bits, spec.width, endian);
    }
    foreach (ref constant; FLOAT_CONSTANTS)
    {
        if (icmp(name, constant.name) != 0)
            continue;

        // Each width takes its own value, since half of these are properties of
        // the format rather than numbers: f32:max is the largest binary32,
        // which is not the largest binary64 narrowed (that one is infinity)
        if (spec.width == 10)
        {
            Ext80 value = constant.f80;
            if (negative)
                value.signexp |= SIGN80;
            return encode80(value, endian);
        }
        return spec.width == 8
            ? encode(bits64(negative ? -constant.f64 : constant.f64), 8, endian)
            : encode(bits32(negative ? -constant.f32 : constant.f32), 4, endian);
    }

    // From here it is a number, so digits only: std.conv reads "1_0" as 10,
    // which the integer types refuse, and a needle is no place for two answers
    // to the same question. Names got their chance above, underscores included
    if (canFind(input, '_'))
        throw new Exception(text(MSG_INVALID_NUMBER, printable(arg)));

    // The 80-bit format has no host type to borrow, so its literal is converted
    // in integers, exactly. The sign goes along separately, since it is a field
    // of its own there rather than the top bit of the value
    if (spec.width == 10)
        return encode80(decimal80(name, negative, arg), endian);

    // NOTE: A value too large for a double comes back as a ConvException with
    //       no distinct type to catch, so it reads as an invalid number rather
    //       than as an out of range one, on the older Phobos below as well.
    //       Only f32 and f80 can tell the two apart, doing their own range
    //       check.
    double value = void;
    try
        value = parse!double(input);
    catch (ConvException)
        throw new Exception(text(MSG_INVALID_NUMBER, printable(arg)));

    // parse() stops at the first character it does not like and leaves the
    // rest behind, same as for integers ("f32:1.0f", "f64:infinity")
    if (input.length > 0)
        throw new Exception(text(MSG_INVALID_NUMBER, printable(arg)));

    // ...and it is only recent Phobos that raises above: 2.100 and older, which
    // is what GDC 12 ships, hand back an infinity for "1e999" instead. Every
    // infinity ddhx spells is a name handled above ("infinity" is not one of
    // them, and leaves "inity" for the check just made), so one arriving from a
    // literal is a magnitude that did not fit, refused the same way on either
    if (isInfinity(value))
        throw new Exception(text(MSG_INVALID_NUMBER, printable(arg)));

    // Every NaN ddhx spells is in FLOAT_BITS above, sign included, so one
    // arriving from std.conv is a spelling nothing here sanctioned. Refusing it
    // is what keeps a NaN from ever being encoded out of host bits, and out of
    // a sign std.conv drops on the way ("-nan" parses to a positive one).
    if (isNaN(value))
        throw new Exception(text(MSG_INVALID_NUMBER, printable(arg)));

    if (spec.width == 8)
        return encode(bits64(value), 8, endian);

    float narrowed = cast(float)value;
    // Rounding to infinity means the number typed was not the number encoded
    if (isInfinity(narrowed) && isInfinity(value) == false)
        throw new Exception(text(MSG_VALUE_OUT_OF_RANGE, printable(arg)));
    return encode(bits32(narrowed), 4, endian);
}
unittest
{
    static immutable PatternSpec F32 = { PatternType.floating, 10, 4 };
    static immutable PatternSpec F64 = { PatternType.floating, 10, 8 };
    static immutable PatternSpec F80 = { PatternType.floating, 10, 10 };

    // These are IEEE-754 encodings, spelled out because that is the contract:
    // they are what the needle is on any host, and a host whose floats are not
    // that format is one this would have refused to compile for
    with (Endian)
    {
        assert(floating("1.0",  F32, littleEndian, null) == [ 0, 0, 0x80, 0x3f ]);
        assert(floating("1.0",  F32, bigEndian,    null) == [ 0x3f, 0x80, 0, 0 ]);
        assert(floating("1.0",  F64, littleEndian, null) == [ 0, 0, 0, 0, 0, 0, 0xf0, 0x3f ]);
        assert(floating("-0.0", F32, littleEndian, null) == [ 0, 0, 0, 0x80 ]);

        // Infinity has one encoding, and the quiet NaN is picked rather than
        // borrowed, so neither depends on what the host prefers
        assert(floating("inf",  F32, littleEndian, null) == [ 0, 0, 0x80, 0x7f ]);
        assert(floating("inf",  F32, bigEndian,    null) == [ 0x7f, 0x80, 0, 0 ]);
        assert(floating("-inf", F32, littleEndian, null) == [ 0, 0, 0x80, 0xff ]);
        assert(floating("inf",  F64, littleEndian, null) == [ 0, 0, 0, 0, 0, 0, 0xf0, 0x7f ]);
        assert(floating("nan",  F32, littleEndian, null) == [ 0, 0, 0xc0, 0x7f ]);
        assert(floating("nan",  F32, bigEndian,    null) == [ 0x7f, 0xc0, 0, 0 ]);
        assert(floating("nan",  F64, littleEndian, null) == [ 0, 0, 0, 0, 0, 0, 0xf8, 0x7f ]);

        // A NaN keeps its sign, which std.conv drops: the negative one is what
        // x87 and SSE hand out for 0.0/0.0, so it is the one in the dump
        assert(floating("-nan", F32, littleEndian, null) == [ 0, 0, 0xc0, 0xff ]);
        assert(floating("-nan", F32, bigEndian,    null) == [ 0xff, 0xc0, 0, 0 ]);
        assert(floating("-nan", F64, littleEndian, null) == [ 0, 0, 0, 0, 0, 0, 0xf8, 0xff ]);
        assert(floating("+nan", F32, littleEndian, null) == [ 0, 0, 0xc0, 0x7f ]);

        // "qnan" is the same NaN said in IEEE's own words, "snan" the other
        // one: mantissa nonzero with the quiet bit clear, payload 1
        assert(floating("qnan", F32, littleEndian, null) == floating("nan", F32, littleEndian, null));
        assert(floating("qnan", F64, bigEndian,    null) == floating("nan", F64, bigEndian, null));
        assert(floating("snan", F32, bigEndian,    null) == [ 0x7f, 0x80, 0, 0x01 ]);
        assert(floating("snan", F32, littleEndian, null) == [ 0x01, 0, 0x80, 0x7f ]);
        assert(floating("snan", F64, bigEndian,    null) == [ 0x7f, 0xf0, 0, 0, 0, 0, 0, 0x01 ]);
        assert(floating("-snan", F32, bigEndian,   null) == [ 0xff, 0x80, 0, 0x01 ]);
        assert(floating("SNAN", F32, bigEndian,    null) == [ 0x7f, 0x80, 0, 0x01 ]);
        assert(floating("QNaN", F32, bigEndian,    null) == [ 0x7f, 0xc0, 0, 0 ]);

        // ...and the other payload worth a name, the highest bit one may set
        // without becoming the quiet bit above it
        assert(floating("snan_hi", F32, bigEndian,    null) == [ 0x7f, 0xa0, 0, 0 ]);
        assert(floating("snan_hi", F32, littleEndian, null) == [ 0, 0, 0xa0, 0x7f ]);
        assert(floating("snan_hi", F64, bigEndian,    null)
            == [ 0x7f, 0xf4, 0, 0, 0, 0, 0, 0 ]);
        assert(floating("-snan_hi", F32, bigEndian,   null) == [ 0xff, 0xa0, 0, 0 ]);
        assert(floating("SNAN_HI",  F32, bigEndian,   null) == [ 0x7f, 0xa0, 0, 0 ]);

        // A signaling NaN is a bit pattern and never a float value, so both
        // must arrive with the quiet bit still clear: an x87 build would have
        // quieted them into 7FC00001 and 7FE00000 had they passed through a
        // register. The bit is the mantissa's top one, 0x400000 of byte 1
        assert((floating("snan",    F32, bigEndian, null)[1] & 0x40) == 0);
        assert((floating("snan_hi", F32, bigEndian, null)[1] & 0x40) == 0);
        assert((floating("qnan",    F32, bigEndian, null)[1] & 0x40) == 0x40);
        assert((floating("snan",    F64, bigEndian, null)[1] & 0x08) == 0);
        assert((floating("snan_hi", F64, bigEndian, null)[1] & 0x08) == 0);
        assert((floating("qnan",    F64, bigEndian, null)[1] & 0x08) == 0x08);

        // Intel's name for the negative quiet NaN, which is 0.0/0.0 on x86
        assert(floating("indefinite", F32, bigEndian,    null) == [ 0xff, 0xc0, 0, 0 ]);
        assert(floating("indefinite", F32, littleEndian, null) == [ 0, 0, 0xc0, 0xff ]);
        assert(floating("indefinite", F64, littleEndian, null)
            == [ 0, 0, 0, 0, 0, 0, 0xf8, 0xff ]);
        assert(floating("indefinite", F32, littleEndian, null)
            == floating("-nan", F32, littleEndian, null));
        // ...so a sign on it can only agree with the name
        assert(floating("-indefinite", F32, bigEndian, null) == [ 0xff, 0xc0, 0, 0 ]);
        assert(floating("INDEFINITE", F32, bigEndian, null)  == [ 0xff, 0xc0, 0, 0 ]);

        // The width is the format's, not the host's idea of a float
        assert(floating("1.0", F32, littleEndian, null).length == 4);
        assert(floating("1.0", F64, littleEndian, null).length == 8);

        // Named constants, in the order the table has them
        assert(floating("pi",    F32, bigEndian, null) == [ 0x40, 0x49, 0x0f, 0xdb ]);
        assert(floating("e",     F32, bigEndian, null) == [ 0x40, 0x2d, 0xf8, 0x54 ]);
        assert(floating("tau",   F32, bigEndian, null) == [ 0x40, 0xc9, 0x0f, 0xdb ]);
        assert(floating("sqrt2", F32, bigEndian, null) == [ 0x3f, 0xb5, 0x04, 0xf3 ]);
        assert(floating("phi",   F32, bigEndian, null) == [ 0x3f, 0xcf, 0x1b, 0xbd ]);
        assert(floating("pi",    F64, bigEndian, null)
            == [ 0x40, 0x09, 0x21, 0xfb, 0x54, 0x44, 0x2d, 0x18 ]);
        assert(floating("e",     F64, bigEndian, null)
            == [ 0x40, 0x05, 0xbf, 0x0a, 0x8b, 0x14, 0x57, 0x69 ]);

        // Each width takes its own, since these are the format's own edges and
        // not a number that survives being narrowed
        assert(floating("max",        F32, bigEndian, null) == [ 0x7f, 0x7f, 0xff, 0xff ]);
        assert(floating("min",        F32, bigEndian, null) == [ 0x00, 0x80, 0x00, 0x00 ]);
        assert(floating("epsilon",    F32, bigEndian, null) == [ 0x34, 0x00, 0x00, 0x00 ]);
        assert(floating("denorm_min", F32, bigEndian, null) == [ 0x00, 0x00, 0x00, 0x01 ]);
        assert(floating("max",        F64, bigEndian, null)
            == [ 0x7f, 0xef, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff ]);
        assert(floating("min",        F64, bigEndian, null)
            == [ 0x00, 0x10, 0, 0, 0, 0, 0, 0 ]);
        assert(floating("epsilon",    F64, bigEndian, null)
            == [ 0x3c, 0xb0, 0, 0, 0, 0, 0, 0 ]);
        assert(floating("denorm_min", F64, bigEndian, null) == [ 0, 0, 0, 0, 0, 0, 0, 1 ]);

        // A sign applies to a constant the way it does to a literal, and only
        // the sign bit changes
        assert(floating("-pi",  F32, bigEndian, null) == [ 0xc0, 0x49, 0x0f, 0xdb ]);
        assert(floating("-max", F32, bigEndian, null) == [ 0xff, 0x7f, 0xff, 0xff ]);
        assert(floating("+pi",  F32, bigEndian, null) == floating("pi", F32, bigEndian, null));

        // Case follows what std.conv takes for "nan" and "inf"
        assert(floating("PI",  F32, bigEndian, null) == floating("pi", F32, bigEndian, null));
        assert(floating("Pi",  F32, bigEndian, null) == floating("pi", F32, bigEndian, null));
        assert(floating("NAN", F32, bigEndian, null) == floating("nan", F32, bigEndian, null));
        assert(floating("INF", F32, bigEndian, null) == floating("inf", F32, bigEndian, null));
        assert(floating("DENORM_MIN", F64, bigEndian, null) == [ 0, 0, 0, 0, 0, 0, 0, 1 ]);

        // The endian setting is not skipped on the way through the table
        assert(floating("pi",  F32, littleEndian, null) == [ 0xdb, 0x0f, 0x49, 0x40 ]);
        assert(floating("max", F32, littleEndian, null) == [ 0xff, 0xff, 0x7f, 0x7f ]);

        // The 80-bit format is ten bytes and stores its integer bit, so a 1.0
        // is that bit and an exponent rather than an exponent alone
        assert(floating("1.0", F80, littleEndian, null)
            == [ 0, 0, 0, 0, 0, 0, 0, 0x80, 0xff, 0x3f ]);
        assert(floating("1.0", F80, bigEndian, null)
            == [ 0x3f, 0xff, 0x80, 0, 0, 0, 0, 0, 0, 0 ]);
        assert(floating("-1.0", F80, bigEndian, null)
            == [ 0xbf, 0xff, 0x80, 0, 0, 0, 0, 0, 0, 0 ]);
        assert(floating("-0.0", F80, bigEndian, null)
            == [ 0x80, 0x00, 0, 0, 0, 0, 0, 0, 0, 0 ]);
        assert(floating("1.0", F80, littleEndian, null).length == 10);

        // The same names, on the same terms. An infinity or a NaN keeps the
        // integer bit set, one without it being a pseudo-NaN the 387 rejects
        assert(floating("inf",  F80, bigEndian, null)
            == [ 0x7f, 0xff, 0x80, 0, 0, 0, 0, 0, 0, 0 ]);
        assert(floating("-inf", F80, bigEndian, null)
            == [ 0xff, 0xff, 0x80, 0, 0, 0, 0, 0, 0, 0 ]);
        assert(floating("nan",  F80, bigEndian, null)
            == [ 0x7f, 0xff, 0xc0, 0, 0, 0, 0, 0, 0, 0 ]);
        assert(floating("qnan", F80, bigEndian, null) == floating("nan", F80, bigEndian, null));
        assert(floating("snan", F80, bigEndian, null)
            == [ 0x7f, 0xff, 0x80, 0, 0, 0, 0, 0, 0, 0x01 ]);
        assert(floating("snan_hi", F80, bigEndian, null)
            == [ 0x7f, 0xff, 0xa0, 0, 0, 0, 0, 0, 0, 0 ]);
        assert(floating("indefinite", F80, bigEndian, null)
            == [ 0xff, 0xff, 0xc0, 0, 0, 0, 0, 0, 0, 0 ]);
        assert(floating("indefinite", F80, littleEndian, null)
            == floating("-nan", F80, littleEndian, null));
        // ...and the quiet bit is bit 62, the one under the integer bit
        assert((floating("snan",    F80, bigEndian, null)[2] & 0x40) == 0);
        assert((floating("snan_hi", F80, bigEndian, null)[2] & 0x40) == 0);
        assert((floating("qnan",    F80, bigEndian, null)[2] & 0x40) == 0x40);

        // A constant at this width is 64 significant bits, so f80:pi is what
        // FLDPI loads and not a double's pi with zeros after it
        assert(floating("pi", F80, bigEndian, null)
            == [ 0x40, 0x00, 0xc9, 0x0f, 0xda, 0xa2, 0x21, 0x68, 0xc2, 0x35 ]);
        assert(floating("pi", F80, littleEndian, null)
            == [ 0x35, 0xc2, 0x68, 0x21, 0xa2, 0xda, 0x0f, 0xc9, 0x00, 0x40 ]);
        assert(floating("-pi", F80, bigEndian, null)
            == [ 0xc0, 0x00, 0xc9, 0x0f, 0xda, 0xa2, 0x21, 0x68, 0xc2, 0x35 ]);
        assert(floating("PI", F80, bigEndian, null) == floating("pi", F80, bigEndian, null));
        // ...and a literal of the same digits agrees with the name, which is
        // the whole reason the conversion is done in integers
        assert(floating("3.14159265358979323846", F80, bigEndian, null)
            == floating("pi", F80, bigEndian, null));
        assert(floating("e", F80, bigEndian, null)
            == [ 0x40, 0x00, 0xad, 0xf8, 0x54, 0x58, 0xa2, 0xbb, 0x4a, 0x9b ]);
        assert(floating("tau", F80, bigEndian, null)
            == [ 0x40, 0x01, 0xc9, 0x0f, 0xda, 0xa2, 0x21, 0x68, 0xc2, 0x35 ]);
        assert(floating("sqrt2", F80, bigEndian, null)
            == [ 0x3f, 0xff, 0xb5, 0x04, 0xf3, 0x33, 0xf9, 0xde, 0x64, 0x84 ]);
        assert(floating("phi", F80, bigEndian, null)
            == [ 0x3f, 0xff, 0xcf, 0x1b, 0xbc, 0xdc, 0xbf, 0xa5, 0x3e, 0x0b ]);

        // The format's edges, which are its own and not a narrowing of anything
        assert(floating("max", F80, bigEndian, null)
            == [ 0x7f, 0xfe, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff ]);
        assert(floating("min", F80, bigEndian, null)
            == [ 0x00, 0x01, 0x80, 0, 0, 0, 0, 0, 0, 0 ]);
        assert(floating("epsilon", F80, bigEndian, null) // 2^-63, one bit in 64
            == [ 0x3f, 0xc0, 0x80, 0, 0, 0, 0, 0, 0, 0 ]);
        assert(floating("denorm_min", F80, bigEndian, null)
            == [ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01 ]);
        assert(floating("-max", F80, bigEndian, null)
            == [ 0xff, 0xfe, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff ]);
    }
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
/// find utf8:C:\Users             raw, a path
/// find utf8:'C:\Program Files'   raw, quoted only for the space
/// find utf8:"\x1b[0m"            C string, an escape sequence
/// find utf8:'C:\Users'"\0"       both, concatenated
/// ---
///
/// A whole argument of `?` or `*` is a wildcard; anything with a prefix is
/// data, so `utf8:*` is already the way to search for one.
///
/// A prefix says whether its argument is a byte string or a value. Byte
/// strings are taken as written; values are encoded into the width their
/// prefix names, using `endian`:
///
/// ---
/// find x:1122         11 22       two bytes, as typed
/// find x16:1122       22 11       a 16-bit value, little endian
/// find u16:255        ff 00       as many bytes as the width asked for
/// find i16:-1         ff ff       two's complement
/// find f32:1.0        00 00 80 3f IEEE-754, the bits a float occupies
/// ---
///
/// Throws: FormatException or Exception for unknown prefix, empty values,
///         values too large for their width, invalid escape sequences, etc.
/// Params:
///     endian  = Byte order for scalar patterns.
///     args... = Array of arguments (e.g., "x:00","00").
/// Returns: Byte array.
Pattern pattern(Endian endian, Argument[] args)
{
    Pattern pat;
    PatternSpec last;
    foreach (Argument arg; args)
    {
        // Allow malformed text encodings in prefixes
        const(char)[] input = cast(const(char)[])arg.data;

        // A wildcard is a whole argument of its own, so a prefixed one is
        // already data and needs no quoting: `utf8:*` is a one-byte needle.
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
            // "utf8:" is the only encoding so far, and the command line already
            // hands it UTF-8, so its bytes are its bytes. Other encodings will
            // transcode here, per prefix, never per setting.
            foreach (char v; pfx.str) pat.data ~= cast(ubyte)v;
            break;
        case PatternType.scalar:
            foreach (ubyte v; scalar(pfx.str, pfx.spec, endian, arg.data)) pat.data ~= v;
            break;
        case PatternType.floating:
            foreach (ubyte v; floating(pfx.str, pfx.spec, endian, arg.data)) pat.data ~= v;
            break;
        case PatternType.unknown:
            assert(false, "Unknown prefixes are resolved or thrown above");
        }
        last = pfx.spec;
    }
    return pat;
}
/// Ditto
Pattern pattern(Endian endian, string[] args...) // string to Argument
{
    Argument[] wrapped = new Argument[args.length];
    foreach (i, arg; args) wrapped[i] = Argument(arg);
    return pattern(endian, wrapped);
}
unittest
{
    // Most of these do not care about endianness, so name the default once
    Pattern pat(string[] args...)
    {
        return pattern(Endian.littleEndian, args);
    }
    Pattern patbe(string[] args...)
    {
        return pattern(Endian.bigEndian, args);
    }

    // Official prefixes
    assert(pat("x:00").data              == [ 0 ]);
    assert(pat("u8:255").data            == [ 0xff ]);
    assert(pat("o8:377").data            == [ 0xff ]);
    assert(pat("x:00","00").data         == [ 0, 0 ]);
    assert(pat("utf8:test").data         == [ 't', 'e', 's', 't' ]);
    assert(pat("x:00","utf8:test").data  == [ 0, 't', 'e', 's', 't' ]);
    assert(pat("x:00","00","utf8:test").data == [ 0, 0, 't', 'e', 's', 't' ]);

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

    // Floats encode the bits they occupy, not the digits they were typed as
    assert(pat("f32:1.0").data           == [ 0, 0, 0x80, 0x3f ]);
    assert(patbe("f32:1.0").data         == [ 0x3f, 0x80, 0, 0 ]);
    assert(pat("f32:0.0").data           == [ 0, 0, 0, 0 ]);
    assert(pat("f32:-0.0").data          == [ 0, 0, 0, 0x80 ]); // a sign of its own
    assert(pat("f32:-1.0").data          == [ 0, 0, 0x80, 0xbf ]);
    assert(pat("f32:3.14159").data       == [ 0xd0, 0x0f, 0x49, 0x40 ]);
    assert(pat("f64:1.0").data           == [ 0, 0, 0, 0, 0, 0, 0xf0, 0x3f ]);
    assert(patbe("f64:1.0").data         == [ 0x3f, 0xf0, 0, 0, 0, 0, 0, 0 ]);
    assert(pat("f64:-1.0").data          == [ 0, 0, 0, 0, 0, 0, 0xf0, 0xbf ]);
    assert(pat("f64:0.5").data           == [ 0, 0, 0, 0, 0, 0, 0xe0, 0x3f ]);

    // An integer literal is a float here, the prefix says so
    assert(pat("f32:1").data             == [ 0, 0, 0x80, 0x3f ]);
    assert(pat("f32:1e2").data           == [ 0, 0, 0xc8, 0x42 ]);
    assert(pat("f32:.5").data            == [ 0, 0, 0, 0x3f ]);

    // ...and the two spellings no hex dump makes obvious. A NaN is any nonzero
    // mantissa, so ddhx picks the quiet one instead of asking the host
    assert(pat("f32:inf").data           == [ 0, 0, 0x80, 0x7f ]);
    assert(pat("f32:-inf").data          == [ 0, 0, 0x80, 0xff ]);
    assert(pat("f64:inf").data           == [ 0, 0, 0, 0, 0, 0, 0xf0, 0x7f ]);
    assert(pat("f32:nan").data           == [ 0, 0, 0xc0, 0x7f ]);
    assert(pat("f64:nan").data           == [ 0, 0, 0, 0, 0, 0, 0xf8, 0x7f ]);
    assert(patbe("f32:nan").data         == [ 0x7f, 0xc0, 0, 0 ]);
    assert(pat("f32:qnan").data          == [ 0, 0, 0xc0, 0x7f ]);
    assert(pat("f32:snan").data          == [ 0x01, 0, 0x80, 0x7f ]);
    assert(pat("f32:snan_hi").data       == [ 0, 0, 0xa0, 0x7f ]);
    assert(pat("f64:snan_hi").data       == [ 0, 0, 0, 0, 0, 0, 0xf4, 0x7f ]);
    // ...and the one 0.0/0.0 leaves behind on x86, by either of its names
    assert(pat("f32:-nan").data          == [ 0, 0, 0xc0, 0xff ]);
    assert(pat("f64:-nan").data          == [ 0, 0, 0, 0, 0, 0, 0xf8, 0xff ]);
    assert(pat("f32:indefinite").data    == [ 0, 0, 0xc0, 0xff ]);
    assert(pat("f64:indefinite").data    == [ 0, 0, 0, 0, 0, 0, 0xf8, 0xff ]);

    // Too large for a float, but not for the double it was parsed as
    assert(pat("f64:1e39").data.length   == 8);

    // The 80-bit x87 extended, which is ten bytes and no host's float type
    assert(pat("f80:1.0").data          == [ 0, 0, 0, 0, 0, 0, 0, 0x80, 0xff, 0x3f ]);
    assert(patbe("f80:1.0").data        == [ 0x3f, 0xff, 0x80, 0, 0, 0, 0, 0, 0, 0 ]);
    assert(pat("f80:-1.0").data         == [ 0, 0, 0, 0, 0, 0, 0, 0x80, 0xff, 0xbf ]);
    assert(pat("f80:0.0").data          == [ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ]);
    assert(pat("f80:-0.0").data         == [ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x80 ]);
    assert(pat("f80:0.5").data          == [ 0, 0, 0, 0, 0, 0, 0, 0x80, 0xfe, 0x3f ]);
    assert(pat("f80:1").data            == pat("f80:1.0").data);
    assert(pat("f80:inf").data          == [ 0, 0, 0, 0, 0, 0, 0, 0x80, 0xff, 0x7f ]);
    assert(pat("f80:nan").data          == [ 0, 0, 0, 0, 0, 0, 0, 0xc0, 0xff, 0x7f ]);
    assert(pat("f80:indefinite").data   == pat("f80:-nan").data);
    assert(pat("f80:snan").data         == [ 0x01, 0, 0, 0, 0, 0, 0, 0x80, 0xff, 0x7f ]);
    assert(pat("f80:pi").data           == [ 0x35, 0xc2, 0x68, 0x21, 0xa2, 0xda, 0x0f, 0xc9, 0x00, 0x40 ]);
    assert(pat("f80:max").data          == [ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe, 0x7f ]);

    // Its literals carry 64 significant bits and its own exponent range, so
    // neither the digits nor the magnitude have to fit in a double first
    assert(pat("f80:3.14159265358979323846").data == pat("f80:pi").data);
    assert(pat("f80:1e400").data         == [ 0xe6, 0xf9, 0x9f, 0xcb, 0xc8, 0x3f, 0x76, 0xda, 0x2f, 0x45 ]);
    assert(pat("f80:1e-400").data.length == 10);
    assert(pat("f80:1e4932").data.length == 10);

    // Named constants, for the values nobody recognizes as hex
    assert(pat("f32:pi").data           == [ 0xdb, 0x0f, 0x49, 0x40 ]);
    assert(patbe("f32:pi").data         == [ 0x40, 0x49, 0x0f, 0xdb ]);
    assert(pat("f32:-pi").data          == [ 0xdb, 0x0f, 0x49, 0xc0 ]);
    assert(pat("f32:max").data          == [ 0xff, 0xff, 0x7f, 0x7f ]);
    assert(pat("f64:pi").data           == [ 0x18, 0x2d, 0x44, 0x54, 0xfb, 0x21, 0x09, 0x40 ]);
    assert(pat("f32:PI").data           == pat("f32:pi").data); // as with "nan"
    // A constant carries over like anything else, and a needle can mix the two
    assert(pat("f32:pi", "e").data      == [ 0xdb, 0x0f, 0x49, 0x40, 0x54, 0xf8, 0x2d, 0x40 ]);
    assert(pat("f32:1.0", "pi").data    == [ 0, 0, 0x80, 0x3f, 0xdb, 0x0f, 0x49, 0x40 ]);

    // A width carries over the same way a bare prefix does
    assert(pat("u16:1", "2").data        == [ 1, 0, 2, 0 ]);
    assert(pat("i8:-1", "-2").data       == [ 0xff, 0xfe ]);
    assert(pat("f32:1.0", "2.0").data    == [ 0, 0, 0x80, 0x3f, 0, 0, 0, 0x40 ]);
    assert(pat("f64:1.0", "-1.0").data.length == 16);
    assert(pat("f80:1.0", "-1.0").data.length == 20);
    assert(pat("f80:pi", "e").data.length     == 20);

    // Which is how a needle of any length is built out of values, and it is
    // the carry-over that keeps it quick to type rather than the magnitude
    assert(pat("u8:255", "255", "255", "255", "255").data == [ 0xff, 0xff, 0xff, 0xff, 0xff ]);
    assert(pat("u8:1", "2", "3").data     == [ 1, 2, 3 ]);
    assert(pat("i16:-1", "-1", "-1").data == [ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff ]);

    // Plain strings are raw, so a backslash is a backslash
    assert(pat(`utf8:a\tb`).data      == [ 'a', '\\', 't', 'b' ]);
    assert(pat(`utf8:C:\dir`).data    == [ 'C', ':', '\\', 'd', 'i', 'r' ]);
    assert(pat(`utf8:C:\\`).data      == [ 'C', ':', '\\', '\\' ]);

    // ...and what an escape sequence produced is data like any other, since it
    // arrives here already resolved. Bytes that are not text included: this is
    // the layer that has no opinion on encodings
    ubyte[] bytes(immutable(ubyte)[] data)
    {
        Argument[] argv = [ Argument(data) ];
        ubyte[] result;
        foreach (ushort v; pattern(Endian.littleEndian, argv).data)
            result ~= cast(ubyte)v;
        return result;
    }
    assert(bytes(cast(immutable(ubyte)[])"utf8:\0")   == [ 0 ]);
    assert(bytes(cast(immutable(ubyte)[])"utf8:a\tb") == [ 'a', '\t', 'b' ]);
    assert(bytes(cast(immutable(ubyte)[])"utf8:\x1b[0m") == [ 0x1b, '[', '0', 'm' ]);
    assert(bytes(cast(immutable(ubyte)[])[ 'u', 't', 'f', '8', ':', 0xff, 0xfe ])
        == [ 0xff, 0xfe ]);

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
        try { r = pattern(Endian.littleEndian, input); }
        catch (Exception) { return; }

        import std.stdio : stderr, writeln;
        stderr.writeln("Failed to throw with: ", input, " it produced: ", r.data);
        assert(false, "test_throw test failed");
    }
    string[][] invalids = [
        // Missing prefix
        [""], ["00"], ["00", "0x00"],
        // Empty data
        ["x:"], ["utf8:"], ["0x"], ["x16:"], ["i8:"], ["i8:-"], ["u8:"], ["o8:"],
        ["f32:"], ["f64:"], ["f32:-"], ["f32:."],
        // Quotes are no longer a prefix alias
        ["\""], [`"yes"`],
        // Unknown prefixes, including widths that are not a type
        ["INVALID:ff"], ["INVALID:"], ["x24:00"], ["d128:1"], ["i:1"], ["u:1"],
        ["f:1.0"], ["f8:1"], ["f16:1"], ["f128:1"],
        // Tests last known good prefix
        ["x:00", "INVALID:ff"],
        // "s:" is the retired spelling of "utf8:", which people will still type
        ["s:"], ["s:hi"], ["x:00", "s:hi"],
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
        ["f32:zz"], ["f32:12zz"], ["f32:1.0f"], ["f32:1_0"], ["f64:infinity"],
        ["f32:1.2.3"], ["f32:--1"],
        ["f80:"], ["f80:-"], ["f80:."], ["f80:zz"], ["f80:12zz"], ["f80:1.0f"],
        ["f80:1_0"], ["f80:1.2.3"], ["f80:--1"], ["f80:1e"], ["f80:infinity"],
        // A constant is the whole literal or it is nothing, so no prefix of a
        // name, no name with something after it, and no name that is not one
        ["f32:p"], ["f32:pie"], ["f32:2pi"], ["f32:pi2"], ["f32:pi."],
        ["f32:denorm"], ["f32:min_normal"], ["f32:tau2"], ["f32:-"],
        ["f32:nan2"], ["f32:sn"], ["f32:snan1"], ["f32:indef"], ["f32:nan(1)"],
        ["f32:snan_"], ["f32:snan_lo"], ["f32:hi"], ["f32:_hi"],
        ["f80:p"], ["f80:pie"], ["f80:pi2"], ["f80:nan2"], ["f80:indef"],
        // ...and they belong to the float types only
        ["u8:pi"], ["i32:pi"], ["x16:pi"], ["u8:max"], ["o8:inf"],
        // Signs belong to the signed types only
        ["x:-1"], ["u16:-1"], ["x16:-1"], ["u8:+1"], ["o8:-1"],
        // Too large for the width asked for
        ["u8:256"], ["i8:128"], ["i8:-129"], ["u16:65536"], ["x8:100"],
        ["i16:32768"], ["i16:-32769"], ["i32:2147483648"], ["x16:10000"],
        ["i64:9223372036854775808"], ["i64:-9223372036854775809"],
        ["f32:1e39"], ["f32:-1e39"], // rounds to infinity, so it was not the value
        ["f80:1.2e4932"], ["f80:1e4933"], ["f80:-1e4933"],
        // Too large for anything
        ["u64:18446744073709551616"], ["f64:1e999"], ["f64:-1e999"],
        ["f80:1e99999"], ["f80:1e999999999999999999"],
    ];
    foreach (inv; invalids)
        test_throw(inv);

    // A byte string has no width to overflow, so what used to be "too long"
    // is now just a longer needle
    assert(pat("0x010101010101010101").data.length == 9); // 64+8 bits
    assert(pat("0x0101010101010101010101").data.length == 11);

    // Bad escapes are the command line's problem, not this layer's: by the
    // time a pattern is built, a backslash is only ever a backslash
    foreach (string bad; [ `utf8:\`, `utf8:\z`, `utf8:\x`, `utf8:\400` ])
        assert(pat(bad).data.length);

    // Globbers
    assert(pat("?")                 == [ PATTERN_GLOB_ONE ]);
    assert(pat("*")                 == [ PATTERN_GLOB_MANY ]);
    assert(pat("x:00", "?", "x:FF") == [ 0, PATTERN_GLOB_ONE,  0xff ]);
    assert(pat("x:00", "*", "x:FF") == [ 0, PATTERN_GLOB_MANY, 0xff ]);
    // A prefix already makes it data, no quoting involved
    assert(pat("utf8:*").data == [ '*' ]);
    assert(pat("utf8:?").data == [ '?' ]);
    assert(bytes(cast(immutable(ubyte)[])"utf8:*") == [ '*' ]);
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
//     utf8:text   no                     no
//     utf8:'text' yes                    no
//     utf8:"text" yes                    yes
//
// Which is the same deal a string literal offers in any language: the quoting
// style says how to read the text. So a Windows path is a Windows path,
//
//      find utf8:C:\Users                  raw, nothing to escape
//      find utf8:'C:\Example Space\2'      raw, quoted only for the space
//      find utf8:"C:\\Example Space\\2"    C string, so the backslashes double
//
// and an escape sequence is something you opt into with double quotes. The two
// forms concatenate, each keeping its own reading, the way string literals do:
//
//      find utf8:'C:\Users'"\0"            a path with a NUL after it
@system unittest
{
    import utils : arguments;

    // Compile a command line the way the prompt would, minus the command word
    ushort[] compile(string line)
    {
        Argument[] argv = arguments(line);
        return pattern(Endian.littleEndian, argv[1..$]).data;
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
    assert(compile(`find utf8:C:\Users`)    == USERS);
    assert(compile(`find utf8:'C:\Users'`)  == USERS);
    assert(compile(`find utf8:"C:\\Users"`) == USERS);

    // ...and the space only costs quotes, not escapes
    assert(compile(`find utf8:'C:\Example Space\2'`)   == EXAMPLE);
    assert(compile(`find utf8:"C:\\Example Space\\2"`) == EXAMPLE);

    // Unquoted and single quoted are both raw, so they behave identically and
    // only differ on whitespace. Double quotes are the C string
    assert(compile(`find utf8:a\tb`)      == [ 'a', '\\', 't', 'b' ]);
    assert(compile(`find utf8:'a\tb'`)    == [ 'a', '\\', 't', 'b' ]);
    assert(compile(`find utf8:"a\tb"`)    == [ 'a', '\t', 'b' ]);
    assert(compile(`find utf8:\x1b[0m`)   == [ '\\', 'x', '1', 'b', '[', '0', 'm' ]);
    assert(compile(`find utf8:"\x1b[0m"`) == [ 0x1b, '[', '0', 'm' ]);

    // Raw means raw, so a backslash never has to be justified and a bad escape
    // is only bad where escapes exist
    assert(compile(`find utf8:C:\dir`) == [ 'C', ':', '\\', 'd', 'i', 'r' ]);
    assert(compile(`find utf8:abc\`)   == [ 'a', 'b', 'c', '\\' ]);
    test_throw(`find utf8:"C:\Users"`);
    test_throw(`find utf8:"abc\"`);

    // Nothing collapses backslashes on the way in, so what layer 2 sees is what
    // was typed and only the C string form halves them
    assert(compile(`find utf8:C:\\Users`)     == [ 'C', ':', '\\', '\\', 'U', 's', 'e', 'r', 's' ]);
    assert(compile(`find utf8:"C:\\\\Users"`) == [ 'C', ':', '\\', '\\', 'U', 's', 'e', 'r', 's' ]);

    // A needle ending on a backslash works in all three forms, since a
    // backslash pair does not swallow the closing quote
    assert(compile(`find utf8:C:\`)    == [ 'C', ':', '\\' ]);
    assert(compile(`find utf8:'C:\'`)  == [ 'C', ':', '\\' ]);
    assert(compile(`find utf8:"C:\\"`) == [ 'C', ':', '\\' ]);

    // Which form applies is per span, so the two concatenate and each part
    // keeps its own reading. That is what makes a path with a terminator, or a
    // path with a space in it, one argument and no doubling
    assert(compile(`find utf8:'C:\Users'"\0"`) == USERS ~ cast(ushort)0);
    assert(compile(`find utf8:C:\dir"a b"`)
        == [ 'C', ':', '\\', 'd', 'i', 'r', 'a', ' ', 'b' ]);
    assert(compile(`find utf8:"a\tb"\x`)   == [ 'a', '\t', 'b', '\\', 'x' ]);
    assert(compile(`find utf8:'C:\dir'"a b"`)
        == [ 'C', ':', '\\', 'd', 'i', 'r', 'a', ' ', 'b' ]);

    // Whether the prefix sits inside or outside the quotes makes no difference
    assert(compile(`find 'utf8:C:\Users'`) == compile(`find utf8:'C:\Users'`));
    assert(compile(`find "utf8:a\tb"`)     == compile(`find utf8:"a\tb"`));

    // Quotes reaching a string pattern. Layer 1 has no escapes outside of
    // double quotes, so a quote is written with the other kind of quote, and
    // layer 2 still takes \' and \" inside a C string
    assert(compile(`find utf8:'it'"'"'s'`) == [ 'i', 't', '\'', 's' ]);
    assert(compile(`find utf8:"it's"`)     == [ 'i', 't', '\'', 's' ]);
    assert(compile(`find utf8:"it\'s"`)    == [ 'i', 't', '\'', 's' ]);
    assert(compile(`find utf8:say'"'hi'"'`) == [ 's', 'a', 'y', '"', 'h', 'i', '"' ]);
    assert(compile(`find utf8:"say\"hi\""`) == [ 's', 'a', 'y', '"', 'h', 'i', '"' ]);
    // ...and a raw backslash before a quote is just a backslash, so it ends
    // the raw run instead of escaping anything
    assert(compile(`find utf8:it\'s'`)     == [ 'i', 't', '\\', 's' ]);

    // A prefix is mandatory: quotes are the shell's syntax, not a pattern type
    test_throw(`find "quoted"`);
    test_throw(`find 'quoted'`);

    // A wildcard is a whole argument of its own, so a prefix is all it takes to
    // ask for one as data. Quoting is not consulted and does not need to be
    assert(compile(`find x:00 ? x:FF`) == [ 0, PATTERN_GLOB_ONE, 0xff ]);
    assert(compile(`find x:00 * x:FF`) == [ 0, PATTERN_GLOB_MANY, 0xff ]);
    assert(compile(`find utf8:"a\tb" * utf8:c`) == [ 'a', '\t', 'b', PATTERN_GLOB_MANY, 'c' ]);
    assert(compile(`find utf8:*`)      == [ '*' ]);
    assert(compile(`find utf8:?`)      == [ '?' ]);
    assert(compile(`find utf8:'*'`)    == [ '*' ]);
    assert(compile(`find utf8:"?"`)    == [ '?' ]);
    assert(compile(`find '*'`)         == [ PATTERN_GLOB_MANY ]);

    // An unterminated quote never reaches the pattern parser at all
    test_throw(`find utf8:'C:\Users`);
    test_throw(`find utf8:"C:\\Users`);
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

    Pattern p = pattern(Endian.littleEndian, "utf8:ABC");
    assert(matchPattern(hay, p, 0, 0) == 3);
    assert(matchPattern(hay, p, 1, 0) == -1);
    assert(matchPattern(hay, p, 4, 0) == -1); // not enough room

    // ? matches exactly one byte
    p = pattern(Endian.littleEndian, "?", "utf8:BC");
    assert(matchPattern(hay, p, 0, 0) == 3); // A matches ?
    assert(matchPattern(hay, p, 2, 0) == -1); // CD != BC

    // * matches zero or more (minimal-match)
    p = pattern(Endian.littleEndian, "*", "utf8:EF");
    assert(matchPattern(hay, p, 0, 0) == 6); // * eats ABCD, then EF
    assert(matchPattern(hay, p, 4, 0) == 2); // * matches empty, then EF
    assert(matchPattern(hay, p, 5, 0) == -1); // only F left

    // Literal on both sides of *: span is the full A..F
    p = pattern(Endian.littleEndian, "utf8:A", "*", "utf8:F");
    assert(matchPattern(hay, p, 0, 0) == 6);
    assert(matchPattern(hay, p, 1, 0) == -1);

    // Multiple stars must not exponentially backtrack
    p = pattern(Endian.littleEndian, "*", "?", "*", "utf8:F");
    assert(matchPattern(hay, p, 0, 0) == 6);
    assert(matchPattern(hay, p, 6, 0) == -1); // past end

    // Fixed-position match: matchPattern tests AT hPos, not starting from hPos
    p = pattern(Endian.littleEndian, "utf8:D", "?", "F");
    assert(matchPattern(hay, p, 3, 0) == 3);    // "DEF": D=D, E=?, F=F
    assert(matchPattern(hay, p, 0, 0) == -1);   // 'A' != 'D'
    assert(matchPattern(hay, p, 4, 0) == -1);   // not enough room
}