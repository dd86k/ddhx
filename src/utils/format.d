/// Bit utilities.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module utils.format;
    
private enum : float {
    // SI (base-10)
    SI = 1000,    /// SI base
    kB = SI,    /// Represents one KiloByte
    MB = kB * SI,    /// Represents one MegaByte
    GB = MB * SI,    /// Represents one GigaByte
    TB = GB * SI,    /// Represents one TeraByte
    PB = TB * SI,    /// Represents one PetaByte
    EB = PB * SI,    /// Represents one ExaByte
    // IEC (base-2)
    IEC = 1024,    /// IEC base
    KiB = IEC,    /// Represents one KibiByte (1024)
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
const(char)[] formatBin(long size, bool b10 = false) {
    import std.format : format;
    
    // NOTE: ulong.max = (2^64)-1 Bytes = 16 EiB - 1 = 16 * 1024⁵
    
    //TODO: Pretty this up with some clever math
    
    if (b10) { // base 1000
        if (size >= EB)
            return format("%0.2f EB", size / EB);
        if (size >= PB)
            return format("%0.2f TB", size / PB);
        if (size >= TB)
            return format("%0.2f TB", size / TB);
        if (size >= GB)
            return format("%0.2f GB", size / GB);
        if (size >= MB)
            return format("%0.1f MB", size / MB);
        if (size >= kB)
            return format("%0.1f kB", size / kB);
    } else { // base 1024
        if (size >= EiB)
            return format("%0.2f EiB", size / EiB);
        if (size >= PiB)
            return format("%0.2f TiB", size / PiB);
        if (size >= TiB)
            return format("%0.2f TiB", size / TiB);
        if (size >= GiB)
            return format("%0.2f GiB", size / GiB);
        if (size >= MiB)
            return format("%0.1f MiB", size / MiB);
        if (size >= KiB)
            return format("%0.1f KiB", size / KiB);
    }
    
    return format("%u B", size);
}

unittest {
    assert(formatBin(0) == "0 B");
    assert(formatBin(1) == "1 B");
    assert(formatBin(1023) == "1023 B");
    assert(formatBin(1024) == "1.0 KiB");
    // Wouldn't this more exactly 7.99 EiB? Precision limitation?
    assert(formatBin(long.max) == "8.00 EiB");
    assert(formatBin(999,  true) == "999 B");
    assert(formatBin(1000, true) == "1.0 kB");
}
