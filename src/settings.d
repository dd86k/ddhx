/// Settings handler.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module settings;

import all;
import os.terminal : TerminalSize, terminalSize;

/// Bytes per row
__gshared ushort width = 16;
/// Current offset view type
__gshared NumberType offset;
/// Current data view type
__gshared NumberType data;
/// Default character to use for non-ascii characters
__gshared char defaultChar = '.';
/// Use SI prefixes over IEC
__gshared bool si;

/// Reset all settings to default.
void reset() {
	width = 16;
	defaultChar = '.';
	offset = data = NumberType.hexadecimal;
	transcoder.select(CharacterSet.ascii);
}

int setWidth(string val) {
	switch (val[0]) {
	case 'a': // Automatic (fit terminal width)
		TerminalSize termsize = terminalSize;
		//TODO: Module should return this
		int dataSize = void;
		final switch (data) with (NumberType) {
		case hexadecimal: dataSize = 2; break;
		case decimal, octal: dataSize = 3; break;
		}
		dataSize += 2; // Account for space
		// This should get the number of data entries per row optimal
		// given terminal width
		width = cast(ushort)((termsize.width - 16) / (dataSize));
		//TODO: +groups
		//width = cast(ushort)((w - 12) / 4);
		break;
	case 'd': // Default
		width = 16;
		break;
	default:
		ushort l = void;
		if (convert.toVal(l, val))
			return error.set(ErrorCode.invalidNumber);
		width = l;
	}
	return 0;
}

int setOffset(string val) {
	if (val == null || val.length == 0)
		return error.set(ErrorCode.invalidParameter);
	switch (val[0]) {
	case 'o','O':	offset = NumberType.octal; break;
	case 'd','D':	offset = NumberType.decimal; break;
	case 'h','H':	offset = NumberType.hexadecimal; break;
	default:	return error.set(ErrorCode.invalidParameter);
	}
	return 0;
}

int setData(string val) {
	if (val == null || val.length == 0)
		return error.set(ErrorCode.invalidParameter);
	switch (val[0]) {
	case 'o','O':	data = NumberType.octal; break;
	case 'd','D':	data = NumberType.decimal; break;
	case 'h','H':	data = NumberType.hexadecimal; break;
	default:	return error.set(ErrorCode.invalidParameter);
	}
	return 0;
}

int setDefaultChar(string val) {
	if (val == null || val.length == 0)
		return error.set(ErrorCode.invalidParameter);
	switch (val) { // aliases
	case "space":	defaultChar = ' '; break;
	case "dot":	defaultChar = '.'; break;
	default:	defaultChar = val[0];
	}
	return 0;
}

int setCharset(string val) {
	if (val == null || val.length == 0)
		return error.set(ErrorCode.invalidParameter);
	switch (val) {
	case "ascii":	transcoder.select(CharacterSet.ascii); break;
	case "cp437":	transcoder.select(CharacterSet.cp437); break;
	case "ebcdic":	transcoder.select(CharacterSet.ebcdic); break;
	case "mac":	transcoder.select(CharacterSet.mac); break;
	default:	return error.set(ErrorCode.invalidCharset);
	}
	return 0;
}