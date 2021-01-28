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
	import std.format : sformat;

	enum : float {
		KB  = 1024,	/// Represents one KiloByte
		MB  = KB * 1024,	/// Represents one MegaByte
		GB  = MB * 1024,	/// Represents one GigaByte
		TB  = GB * 1024,	/// Represents one TeraByte
		KiB = 1000,	/// Represents one KibiByte
		MiB = KiB * 1000,	/// Represents one MebiByte
		GiB = MiB * 1000,	/// Represents one GibiByte
		TiB = GiB * 1000	/// Represents one TebiByte
	}

	if (size > TB)
		return b10 ?
			buf.sformat!"%0.2f TiB"(size / TiB) :
			buf.sformat!"%0.2f TB"(size / TB);

	if (size > GB)
		return b10 ?
			buf.sformat!"%0.2f GiB"(size / GiB) :
			buf.sformat!"%0.2f GB"(size / GB);

	if (size > MB)
		return b10 ?
			buf.sformat!"%0.1f MiB"(size / MiB) :
			buf.sformat!"%0.1f MB"(size / MB);

	if (size > KB)
		return b10 ?
			buf.sformat!"%0.1f KiB"(size / KiB) :
			buf.sformat!"%0.1f KB"(size / KB);

	return buf.sformat!"%u B"(size);
}

@safe unittest {
	// unformat core
	assert(unformatHex("AA")    == 0xAA, "unformatHex failed");
	assert(unformatOct("10222") == 4242, "unformatOctal failed");
	assert(unformatDec("4242")  == 4242, "unformatDec failed");
	// unformat
	long l = void;
	assert(unformat("0xAA", l));
	assert(l == 0xAA, "unformat(hex) failed");
	assert(unformat("010222", l));
	assert(l == 4242, "unformat(octal) failed");
	assert(unformat("4242", l));
	assert(l == 4242, "unformat(dec) failed");
}