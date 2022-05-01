/// Type definition.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module types;

/// Character set.
enum CharacterSet : ubyte {
	ascii,	/// 7-bit US-ASCII
	cp437,	/// IBM PC CP-437
	ebcdic,	/// IBM EBCDIC Code Page 37
	mac,	/// Mac OS Roman (Windows 10000)
//	t61,	/// ITU T.61
//	gsm,	/// GSM 03.38
}

/// Number type to render either for offset or data
enum NumberType {
	hexadecimal,
	decimal,
	octal
}
/// Error codes
enum ErrorCode {
	success,
	unknown,
	exception,
	os,
	
	negativeValue = 5,
	fileEmpty,
	inputEmpty,
	invalidCommand,
	invalidParameter,
	invalidNumber,
	invalidType,
	invalidCharset,
	notFound,
	overflow,
	unparsable,
	noLastItem,
	eof,
	unimplemented,
	insufficientSpace,
	
	missingArgumentPosition = 40,
	missingArgumentType,
	missingArgumentNeedle,
	missingArgumentWidth,
	missingArgumentCharacter,
	missingArgumentCharset,
}

/// FileMode for Io.
enum FileMode {
	file,	/// Normal file.
	mmfile,	/// Memory-mapped file.
	stream,	/// Standard streaming I/O.
	memory,	/// Typically from a stream buffered into memory.
}
/// Current write mode.
enum WriteMode {
	readOnly,	/// 
	insert,	/// 
	overwrite,	/// 
}