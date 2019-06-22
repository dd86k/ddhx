module utils;

import ddhx;

/**
 * Converts a string number to a long number.
 * Params:
 *   e = Input string
 *   l = Long number as a reference
 * Returns: Returns true if successful.
 */
bool unformat(string e, ref long l) {
	import std.conv : parse, ConvException;
	import std.algorithm.searching : startsWith;
	//TODO: Improve unformat
	try {
		if (e.startsWith("0x")) {
			l = unformatHex(e[2..$]);
		} /*else if (e[0] == '0') {
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
ulong unformatHex(string e) nothrow @nogc pure {
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
 *   buf = character buffer
 *   size = Long number
 *   base10 = Use x1000 instead
 * Returns: Range
 */
char[] formatsize(ref char[30] buf, long size, bool base10 = false) { //BUG: %f is unpure?
	import std.format : sformat;

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
			return buf.sformat!"%0.2f TiB"(s / TiB);
		else if (size > GiB)
			return buf.sformat!"%0.2f GiB"(s / GiB);
		else if (size > MiB)
			return buf.sformat!"%0.2f MiB"(s / MiB);
		else if (size > KiB)
			return buf.sformat!"%0.2f KiB"(s / KiB);
		else
			return buf.sformat!"%u B"(size);
	} else {
		if (size > TB)
			return buf.sformat!"%0.2f TB"(s / TB);
		else if (size > GB)
			return buf.sformat!"%0.2f GB"(s / GB);
		else if (size > MB)
			return buf.sformat!"%0.2f MB"(s / MB);
		else if (size > KB)
			return buf.sformat!"%0.2f KB"(s / KB);
		else
			return buf.sformat!"%u B"(size);
	}
}

/**
 * Byte swap a 2-byte number.
 * Params: n = 2-byte number to swap.
 * Returns: Byte swapped number.
 */
extern (C)
ushort bswap16(ushort n) pure nothrow @nogc {
	return cast(ushort)(n >> 8 | n << 8);
}

/**
 * Byte swap a 4-byte number.
 * Params: n = 4-byte number to swap.
 * Returns: Byte swapped number.
 */
extern (C)
uint bswap32(uint n) pure nothrow @nogc {
	version (D_InlineAsm_X86) {
		asm pure nothrow @nogc {
			mov EAX, n;
			bswap EAX;
			ret;
		}
	} else
	version (D_InlineAsm_X86_64) {
		asm pure nothrow @nogc {
			mov EAX, n;
			bswap EAX;
			ret;
		}
	} else
		return  (n & 0xFF00_0000) >> 24 |
			(n & 0x00FF_0000) >>  8 |
			(n & 0x0000_FF00) <<  8 |
			(cast(ubyte)n)    << 24;
}

/**
 * Byte swap a 8-byte number.
 * Params: n = 8-byte number to swap.
 * Returns: Byte swapped number.
 */
extern (C)
ulong bswap64(ulong n) pure nothrow @nogc {
	version (D_InlineAsm_X86_64) {
		asm pure nothrow @nogc {
			mov RAX, n;
			bswap RAX;
			ret;
		}
	} else {
		uint *p = cast(uint*)&n;
		const uint a = bswap32(p[0]);
		p[1] = bswap32(p[0]);
		p[0] = a;
		return n;
	}
}