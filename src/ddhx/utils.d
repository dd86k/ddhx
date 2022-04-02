/// Random utilities.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module ddhx.utils;

/// Format byte size.
/// Params:
///   buf = Character buffer.
///   size = Binary number.
///   b10  = Use SI suffixes instead of IEC suffixes.
/// Returns: Character slice using sformat
char[] formatSize(ref char[32] buf, long size, bool b10 = false) {
	import std.format : sformat;
	
	enum : float {
		// SI (base10)
		SI = 1000,
		kB = SI,	/// Represents one KiloByte
		MB = kB * SI,	/// Represents one MegaByte
		GB = MB * SI,	/// Represents one GigaByte
		TB = GB * SI,	/// Represents one TeraByte
		// IEC (base2)
		IEC = 1024,
		KiB = IEC,	/// Represents one KibiByte
		MiB = KiB * IEC,	/// Represents one MebiByte
		GiB = MiB * IEC,	/// Represents one GibiByte
		TiB = GiB * IEC	/// Represents one TebiByte
	}
	
	//TODO: table of strings with loop-based solution?
	
	if (b10) {
		if (size > TB)
			return buf.sformat!"%0.2f TB"(size / TB);
		if (size > GB)
			return buf.sformat!"%0.2f GB"(size / GB);
		if (size > MB)
			return buf.sformat!"%0.1f MB"(size / MB);
		if (size > kB)
			return buf.sformat!"%0.1f kB"(size / kB);
	} else {
		if (size > TiB)
			return buf.sformat!"%0.2f TiB"(size / TiB);
		if (size > GiB)
			return buf.sformat!"%0.2f GiB"(size / GiB);
		if (size > MiB)
			return buf.sformat!"%0.1f MiB"(size / MiB);
		if (size > KiB)
			return buf.sformat!"%0.1f KiB"(size / KiB);
	}
	
	return buf.sformat!"%u B"(size);
}
