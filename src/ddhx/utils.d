module ddhx.utils;

import ddhx.error;

/**
 * Converts a string number to a long number.
 * Params:
 *   e = Input string
 *   l = Long number as a reference
 * Returns: Returns true if successful.
 */
bool unformat(string e, ref long l) {
	import core.stdc.stdio : sscanf;
	import std.string : toStringz;
	
	if (e.length == 0)
		return false;
	
	return sscanf(e.toStringz, "%lli", &l) == 1;
}

/*int (string s, out long l) {
	import core.stdc.stdio : sscanf;
	import std.string : toStringz;
	
	if (s.length == 0)
		return false;
	
	return sscanf(s.toStringz, "%lli", &l) != 1 ?
		ddhxError(DdhxError.unparsable) : 0;
}*/

/**
 * Format byte size.
 * Params:
 *   buf = character buffer
 *   size = Long number
 *   b10  = Use base-1000 instead of base-1024
 * Returns: Character slice using sformat
 */
char[] formatSize(ref char[32] buf, long size, bool b10 = false) {
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
