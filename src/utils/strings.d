/// Formatting utilities.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module utils.strings;

import core.stdc.stdio : sscanf;
import core.stdc.string : memcpy;
import std.string : toStringz;
import std.conv : text;
import utils.math;

private enum : double
{
    // SI (base-10)
    SI = 1000,          /// SI base
    kB = SI,            /// Represents one KiloByte (1000)
    MB = kB * SI,       /// Represents one MegaByte (1000²)
    GB = MB * SI,       /// Represents one GigaByte (1000³)
    TB = GB * SI,       /// Represents one TeraByte (1000⁴)
    PB = TB * SI,       /// Represents one PetaByte (1000⁵)
    EB = PB * SI,       /// Represents one ExaByte  (1000⁶)
    // IEC (base-2)
    IEC = 1024,         /// IEC base
    KiB = IEC,          /// Represents one KibiByte (1024)
    MiB = KiB * IEC,    /// Represents one MebiByte (1024²)
    GiB = MiB * IEC,    /// Represents one GibiByte (1024³)
    TiB = GiB * IEC,    /// Represents one TebiByte (1024⁴)
    PiB = TiB * IEC,    /// Represents one PebiByte (1024⁵)
    EiB = PiB * IEC,    /// Represents one PebiByte (1024⁶)
}

/// Format byte size.
/// Params:
///   size = Binary number.
///   b10  = Use SI suffixes instead of IEC suffixes.
/// Returns: Character slice using sformat
const(char)[] formatBin(long size, bool b10 = false) @safe
{
    import std.format : format;
    
    // NOTE: ulong.max = (2^64)-1 Bytes = 16 EiB - 1 = 16 * 1024⁵
    
    //TODO: Consider table+index
    
    static immutable string[] formatsIEC = [
        "%0.0f B",
        "%0.1f KiB",
        "%0.1f MiB",
        "%0.2f GiB",
        "%0.2f TiB",
        "%0.2f PiB",
        "%0.2f EiB",
    ];
    static immutable string[] formatsSI = [
        "%0.0f B",
        "%0.1f kB",
        "%0.1f MB",
        "%0.2f GB",
        "%0.2f TB",
        "%0.2f PB",
        "%0.2f EB",
    ];
    
    size_t i;
    double base = void;
    
    if (b10) // base 1000
    {
        base = 1000.0;
        if (size >= EB)         i = 6;
        else if (size >= PB)    i = 5;
        else if (size >= TB)    i = 4;
        else if (size >= GB)    i = 3;
        else if (size >= MB)    i = 2;
        else if (size >= kB)    i = 1;
    }
    else // base 1024
    {
        base = 1024.0;
        if (size >= EiB)         i = 6;
        else if (size >= PiB)    i = 5;
        else if (size >= TiB)    i = 4;
        else if (size >= GiB)    i = 3;
        else if (size >= MiB)    i = 2;
        else if (size >= KiB)    i = 1;
    }
    
    return format(b10 ? formatsSI[i] : formatsIEC[i], size / (base ^^ i));
}
@safe unittest
{
    assert(formatBin(0) == "0 B");
    assert(formatBin(1) == "1 B");
    assert(formatBin(1023) == "1023 B");
    assert(formatBin(1024) == "1.0 KiB");
    // Wouldn't this more exactly 7.99 EiB? Precision limitation?
    assert(formatBin(long.max) == "8.00 EiB");
    assert(formatBin(999,  true) == "999 B");
    assert(formatBin(1000, true) == "1.0 kB");
    assert(formatBin(1_000_000, true) == "1.0 MB");
}

long cparse(string arg) @trusted
{
    // NOTE: Since toStringz can allocate, and I use this function a lot,
    //       a regular static buffer is used instead.
    enum BUFSZ = 64;
    char[BUFSZ] buf = void;
    size_t sz = min(arg.length+1, BUFSZ-1); // Account for null terminator
    memcpy(buf.ptr, arg.ptr, sz);
    buf[sz] = 0;
    
    long r = void;
    if (sscanf(arg.toStringz, "%lli", &r) != 1)
        throw new Exception("Could not parse: ".text(arg));
    return r;
}
@safe unittest
{
    import std.conv : octal;
    assert(cparse("0") == 0);
    assert(cparse("1") == 1);
    assert(cparse("10") == 10);
    assert(cparse("20") == 20);
    assert(cparse("0x1") == 0x1);
    assert(cparse("0x10") == 0x10);
    assert(cparse("0x20") == 0x20);
    // NOTE: Signed numbers cannot be over 0x8000_0000_0000_000
    assert(cparse("0x1bcd1234ffffaaaa") == 0x1bcd_1234_ffff_aaaa);
    assert(cparse("0") == 0);
    assert(cparse("01") == 1);
    assert(cparse("010") == octal!"010");
    assert(cparse("020") == octal!"020");
}
