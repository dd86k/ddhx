module Utils;

import ddhx;

long unformatHex(string e)
{
	enum C_MINOR = '0' + 39,
		 C_MAJOR = '0' + 7;
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
 * Params: size = Long number
 * Returns: Formatted string
 */
string formatsize(long size) //BUG: %f is unpure?
{
    import std.format : format;

    enum : long {
        KB = 1024,
        MB = KB * 1024,
        GB = MB * 1024,
        TB = GB * 1024,
        KiB = 1000,
        MiB = KiB * 1000,
        GiB = MiB * 1000,
        TiB = GiB * 1000
    }

	const float s = size;

	if (Base10)
	{
		if (size > TiB)
			if (size > 100 * TiB)
				return format("%d TiB", size / TiB);
			else if (size > 10 * TiB)
				return format("%0.1f TiB", s / TiB);
			else
				return format("%0.2f TiB", s / TiB);
		else if (size > GiB)
			if (size > 100 * GiB)
				return format("%d GiB", size / GiB);
			else if (size > 10 * GiB)
				return format("%0.1f GiB", s / GiB);
			else
				return format("%0.2f GiB", s / GiB);
		else if (size > MiB)
			if (size > 100 * MiB)
				return format("%d MiB", size / MiB);
			else if (size > 10 * MiB)
				return format("%0.1f MiB", s / MiB);
			else
				return format("%0.2f MiB", s / MiB);
		else if (size > KiB)
			if (size > 100 * MiB)
				return format("%d KiB", size / KiB);
			else if (size > 10 * KiB)
				return format("%0.1f KiB", s / KiB);
			else
				return format("%0.2f KiB", s / KiB);
		else
			return format("%d B", size);
	}
	else
	{
		if (size > TB)
			if (size > 100 * TB)
				return format("%d TB", size / TB);
			else if (size > 10 * TB)
				return format("%0.1f TB", s / TB);
			else
				return format("%0.2f TB", s / TB);
		else if (size > GB)
			if (size > 100 * GB)
				return format("%d GB", size / GB);
			else if (size > 10 * GB)
				return format("%0.1f GB", s / GB);
			else
				return format("%0.2f GB", s / GB);
		else if (size > MB)
			if (size > 100 * MB)
				return format("%d MB", size / MB);
			else if (size > 10 * MB)
				return format("%0.1f MB", s / MB);
			else
				return format("%0.2f MB", s / MB);
		else if (size > KB)
			if (size > 100 * KB)
				return format("%d KB", size / KB);
			else if (size > 10 * KB)
				return format("%0.1f KB", s / KB);
			else
				return format("%0.2f KB", s / KB);
		else
			return format("%d B", size);
	}
}