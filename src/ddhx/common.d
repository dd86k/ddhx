/// Common global variables.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module ddhx.common;

import ddhx;

/// Copyright string
enum COPYRIGHT = "Copyright (c) 2017-2022 dd86k <dd@dax.moe>";

/// App version
enum VERSION = "0.4.0";

/// Version line
enum ABOUT = "ddhx " ~ VERSION ~ " (built: " ~ __TIMESTAMP__~")";

//
// SECTION Input structure
//

// !SECTION

/// Number type to render either for offset or data
enum NumberType {
	hexadecimal,
	decimal,
	octal
}

/// Character translation
enum CharType {
	ascii,	/// 7-bit US-ASCII
	cp437,	/// IBM PC CP-437
	ebcdic,	/// IBM EBCDIC Code Page 37
//	gsm,	/// GSM 03.38
}

//TODO: --no-header: bool
//TODO: --no-offset: bool
//TODO: --no-status: bool
/// Global definitions and default values
// Aren't all of these engine settings anyway?
struct Globals {
	// Settings
	ushort rowWidth = 16;	/// How many bytes are shown per row
	NumberType offsetType;	/// Current offset view type
	NumberType dataType;	/// Current data view type
	CharType charType;	/// Current charset
	char defaultChar = '.';	/// Default character to use for non-ascii characters
//	int include;	/// Include what panels
	// Internals
	TerminalSize termSize;	/// Last known terminal size
}

__gshared Globals globals; /// Single-instance of globals.
__gshared Io io;	/// File/stream I/O instance.