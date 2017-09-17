module Utils;

import ddhx;

/**
 * Converts a string number to a long number.
 * Params:
 *   e = Input string
 *   l = Long number as a reference
 * Returns: Returns true if successful.
 */
bool unformat(string e, ref long l)
{
    import std.conv : parse, ConvException;
    import std.algorithm.searching : startsWith;
    try {
        if (e.startsWith("0x")) {
            l = unformatHex(e[2..$]);
        } /*else if (e.startsWith("0")) {
            //TODO: UNFORMAT OCTAL
        } */else {
            switch (e[$ - 1]) {
            case 'h', 'H': l = unformatHex(e[0..$ - 1]); break;
            default: l = parse!long(e); break;
            }
        }
        return true;
    } catch (Exception) {
        return false;
    }
}

/**
 * Converts a string HEX number to a long number.
 * Params: e = Input string
 * Returns: Unformatted number.
 */
ulong unformatHex(string e) nothrow @nogc pure
{ //TODO: Use a byte pointer instead
    enum C_MINOR = '0' + 39, C_MAJOR = '0' + 7;
    int s; long l;
    foreach_reverse (c; e) {
        switch (c) {
            case '1': .. case '9': l |= (c - '0') << s; break;
            case 'A': .. case 'F': l |= (c - C_MAJOR) << s; break;
            case 'a': .. case 'f': l |= (c - C_MINOR) << s; break;
            default:
        }
        s += 4;
    }
    return l;
}

/**
 * Format byte size.
 * Params:
 *   size = Long number
 *   base10 = Use x1000 instead
 * Returns: Formatted string
 */
string formatsize(long size, bool base10 = false) //BUG: %f is unpure?
{
    import std.format : format;

    enum : long {
        KB = 1024,      /// Represents one KiloByte
        MB = KB * 1024, /// Represents one MegaByte
        GB = MB * 1024, /// Represents one GigaByte
        TB = GB * 1024, /// Represents one TeraByte
        KiB = 1000,       /// Represents one KibiByte
        MiB = KiB * 1000, /// Represents one MebiByte
        GiB = MiB * 1000, /// Represents one GibiByte
        TiB = GiB * 1000  /// Represents one TebiByte
    }

    const float s = size;

    if (base10) {
		if (size > TiB)
            return format("%0.2f TiB\0", s / TiB);
		else if (size > GiB)
            return format("%0.2f GiB\0", s / GiB);
		else if (size > MiB)
            return format("%0.2f MiB\0", s / MiB);
		else if (size > KiB)
            return format("%0.2f KiB\0", s / KiB);
		else
			return format("%d B\0", size);
	} else {
		if (size > TB)
            return format("%0.2f TB\0", s / TB);
		else if (size > GB)
            return format("%0.2f GB\0", s / GB);
		else if (size > MB)
            return format("%0.2f MB\0", s / MB);
		else if (size > KB)
            return format("%0.2f KB\0", s / KB);
		else
			return format("%d B\0", size);
	}
}

/**
 * Byte swap a 2-byte number.
 * Params: num = 2-byte number to swap.
 * Returns: Byte swapped number.
 */
ushort bswap(ushort num) pure nothrow @nogc
{
    version (X86) asm pure nothrow @nogc {
        naked;
        xchg AH, AL;
        ret;
    } else version (X86_64) {
        version (Windows) asm pure nothrow @nogc {
            naked;
            mov AX, CX;
            xchg AL, AH;
            ret;
        } else asm pure nothrow @nogc { // System V AMD64 ABI
            naked;
            mov EAX, EDI;
            xchg AL, AH;
            ret;
        }
    } else {
        if (num) {
            ubyte* p = cast(ubyte*)&num;
            return p[1] | p[0] << 8;
        }
    }
}

/**
 * Byte swap a 4-byte number.
 * Params: num = 4-byte number to swap.
 * Returns: Byte swapped number.
 */
uint bswap(uint num) pure nothrow @nogc
{
    version (X86) asm pure nothrow @nogc {
        naked;
        bswap EAX;
        ret;
    } else version (X86_64) {
        version (Windows) asm pure nothrow @nogc {
            naked;
            mov EAX, ECX;
            bswap EAX;
            ret;
        } else asm pure nothrow @nogc { // System V AMD64 ABI
            naked;
            mov RAX, RDI;
            bswap EAX;
            ret;
        }
    } else {
        if (num) {
            ubyte* p = cast(ubyte*)&num;
            return p[3] | p[2] << 8 | p[1] << 16 | p[0] << 24;
        }
    }
}

/**
 * Byte swap a 8-byte number.
 * Params: num = 8-byte number to swap.
 * Returns: Byte swapped number.
 */
ulong bswap(ulong num) pure nothrow @nogc
{
    version (X86) asm pure nothrow @nogc {
        naked;
        xchg EAX, EDX;
        bswap EDX;
        bswap EAX;
        ret;
    } else version (X86_64) {
        version (Windows) asm pure nothrow @nogc {
            naked;
            mov RAX, RCX;
            bswap RAX;
            ret;
        } else asm pure nothrow @nogc { // System V AMD64 ABI
            naked;
            mov RAX, RDI;
            bswap RAX;
            ret;
        }
    } else {
        if (num) {
            ubyte* p = cast(ubyte*)&num;
            ubyte c;
            for (int a, b = 7; a < 4; ++a, --b) {
                c = *(p + b);
                *(p + b) = *(p + a);
                *(p + a) = c;
            }
            return num;
        }
    }
}