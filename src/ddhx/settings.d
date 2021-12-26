module ddhx.settings;

import ddhx.ddhx : globals;
import ddhx.input, ddhx.error, ddhx.terminal, ddhx.utils;

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

int optionWidth(string val) {
	with (globals)
	switch (val[0]) {
	case 'a': // Automatic
		// This should get the number of data entries per row optimal
		// given terminal width
		int w = conwidth;
		//TODO: +groups
		rowWidth = cast(ushort)((w - 12) / 4);
		break;
	case 'd': // Default
		rowWidth = 16;
		break;
	default:
		long l = void;
		if (unformat(val, l) == false)
			return ddhxError(DdhxError.invalidNumber);
		if (l < 1 || l > ushort.max)
			return ddhxError(DdhxError.invalidNumber);
		rowWidth = cast(ushort)l;
	}
	return 0;
}

int optionOffset(string val) {
	switch (val[0]) {
	case 'o', 'O': globals.offsetType = NumberType.octal; break;
	case 'd', 'D': globals.offsetType = NumberType.decimal; break;
	case 'h', 'H': globals.offsetType = NumberType.hexadecimal; break;
	default: return ddhxError(DdhxError.invalidParameter);
	}
	return 0;
}

int optionDefaultChar(string val) {
	if (val == null || val.length == 0)
		return ddhxError(DdhxError.invalidParameter);
	switch (val) { // aliases
	case "space":	globals.defaultChar = ' '; break;
	case "dot":	globals.defaultChar = '.'; break;
	default:	globals.defaultChar = val[0];
	}
	return 0;
}

int optionCharset(string val) {
	if (val == null || val.length == 0)
		return ddhxError(DdhxError.invalidParameter);
	switch (val) {
	case "ascii":  globals.charType = CharType.ascii; break;
	case "cp437":  globals.charType = CharType.cp437; break;
	case "ebcdic": globals.charType = CharType.ebcdic; break;
	default: return DdhxError.invalidCharset;
	}
	return 0;
}