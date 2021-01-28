module utils;

import ddhx;

/**
 * Converts a string number to a long number.
 * Params:
 *   e = Input string
 *   l = Long number as a reference
 * Returns: Returns true if successful.
 */
bool unformat(string e, ref long l) nothrow pure @nogc @safe {
	if (e.length == 0)
		return false;

	if (e[0] == '0') {
		if (e.length == 1) {
			l = 0;
			return true;
		}
		if (e[1] == 'x') { // hexadecimal
			l = unformatHex(e[2..$]);
		} else { // octal
			l = unformatOct(e[1..$]);
		}
	} else { // Decimal
		l = unformatDec(e);
	}

	return true;
}

/**
 * Converts a string HEX number to a long number, without the prefix.
 * Params: e = Input string
 * Returns: Unformatted number.
 */
private ulong unformatHex(string e) nothrow @nogc pure @safe {
	enum MINOR = '0' + 39, MAJOR = '0' + 7;
	int s;	// shift
	long l;	// result
	foreach_reverse (char c; e) {
		if (c >= '1' && c <= '9')
			l |= (c - '0') << s;
		else if (c >= 'a' && c <= 'f')
			l |= (c - MINOR) << s;
		else if (c >= 'A' && c <= 'F')
			l |= (c - MAJOR) << s;
		s += 4;
	}
	return l;
}

/**
 * Convert octal string to a long number, without the prefix.
 * Params: e = Input string
 * Returns: Unformatted number.
 */
private long unformatOct(string e) nothrow @nogc pure @safe {
	int s = 1;	// shift
	long l;	// result
	foreach_reverse (char c; e) {
		if (c >= '1' && c <= '7')
			l |= (c - '0') * s;
		s *= 8;
	}
	return l;
}

/**
 * Convert deical string to a long number.
 * Params: e = Input string
 * Returns: Unformatted number.
 */
private long unformatDec(string e) nothrow @nogc pure @safe {
	int s = 1;	// shift
	long l;	// result
	foreach_reverse (char c; e) {
		if (c >= '1' && c <= '9')
			l += (c - '0') * s;
		s *= 10;
	}
	if (e[0] == '-')
		l = -l;
	return l;
}

/**
 * Format byte size.
 * Params:
 *   buf = character buffer
 *   size = Long number
 *   b10  = Use base-1000 instead of base-1024
 * Returns: Character slice using sformat
 */
char[] formatsize(ref char[32] buf, long size, bool b10 = false) @safe {
	//BUG: %f is unpure?
	import std.format : sformat;

	enum : long {
		KB = 1024,	/// Represents one KiloByte
		MB = KB * 1024,	/// Represents one MegaByte
		GB = MB * 1024,	/// Represents one GigaByte
		TB = GB * 1024,	/// Represents one TeraByte
		KiB = 1000,	/// Represents one KibiByte
		MiB = KiB * 1000,	/// Represents one MebiByte
		GiB = MiB * 1000,	/// Represents one GibiByte
		TiB = GiB * 1000	/// Represents one TebiByte
	}

	const float s = size;

	if (size > TB)
		return b10 ?
			buf.sformat!"%0.2f TiB"(s / TiB) :
			buf.sformat!"%0.2f TB"(s / TB);

	if (size > GB)
		return b10 ?
			buf.sformat!"%0.2f GiB"(s / GiB) :
			buf.sformat!"%0.2f GB"(s / GB);

	if (size > MB)
		return b10 ?
			buf.sformat!"%0.2f MiB"(s / MiB) :
			buf.sformat!"%0.2f MB"(s / MB);

	if (size > KB)
		return b10 ?
			buf.sformat!"%0.2f KiB"(s / KiB) :
			buf.sformat!"%0.2f KB"(s / KB);

	return buf.sformat!"%u B"(size);
}

/**
 * Byte swap a 2-byte number.
 * Params: n = 2-byte number to swap.
 * Returns: Byte swapped number.
 */
deprecated ("Use core.bitops.bswap")
extern (C)
ushort bswap16(ushort n) pure nothrow @nogc @safe {
	return cast(ushort)(n >> 8 | n << 8);
}

/**
 * Byte swap a 4-byte number.
 * Params: n = 4-byte number to swap.
 * Returns: Byte swapped number.
 */
deprecated ("Use core.bitops.bswap")
extern (C)
uint bswap32(uint v) pure nothrow @nogc @safe {
	v = (v >> 16) | (v << 16);
	return ((v & 0xFF00FF00) >> 8) | ((v & 0x00FF00FF) << 8);
}

/**
 * Byte swap a 8-byte number.
 * Params: n = 8-byte number to swap.
 * Returns: Byte swapped number.
 */
deprecated ("Use core.bitops.bswap")
extern (C)
ulong bswap64(ulong v) pure nothrow @nogc @safe {
	v = (v >> 32) | (v << 32);
	v = ((v & 0xFFFF0000FFFF0000) >> 16) | ((v & 0x0000FFFF0000FFFF) << 16);
	return ((v & 0xFF00FF00FF00FF00) >> 8) | ((v & 0x00FF00FF00FF00FF) << 8);
}

@safe unittest {
	// bswap
	assert(0xAABB == bswap16(0xBBAA), "bswap16 failed");
	assert(0xAABBCCDD == bswap32(0xDDCCBBAA), "bswap32 failed");
	assert(0xAABBCCDD_11223344 == bswap64(0x44332211_DDCCBBAA), "bswap64 failed");
	// unformat core
	assert(unformatHex("AA")    == 0xAA, "unformatHex failed");
	assert(unformatOct("10222") == 4242, "unformatOctal failed");
	assert(unformatDec("4242")  == 4242, "unformatDec failed");
	// unformat
	long l;
	assert(unformat("0xAA", l));
	assert(l == 0xAA, "unformat::hex failed");
	assert(unformat("010222", l));
	assert(l == 4242, "unformat::octal failed");
	assert(unformat("4242", l));
	assert(l == 4242, "unformat::dec failed");
}