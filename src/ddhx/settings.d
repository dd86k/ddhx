/// Settings handler.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module ddhx.settings;

import ddhx;

void settingResetAll() {
	globals.rowWidth = 16;
	globals.defaultChar = '.';
	globals.charType = CharType.ascii;
	globals.offsetType = globals.dataType = NumberType.hexadecimal;
}

int settingWidth(string val) {
	with (globals)
	switch (val[0]) {
	case 'a': // Automatic
		int dataSize = void;
		final switch (dataType) with (NumberType) {
		case hexadecimal: dataSize = 2; break;
		case decimal, octal: dataSize = 3; break;
		}
		dataSize += 2; // Account for space
		// This should get the number of data entries per row optimal
		// given terminal width
		int w = terminalSize.width;
		rowWidth = cast(ushort)((w - 16) / (dataSize));
		//TODO: +groups
		//rowWidth = cast(ushort)((w - 12) / 4);
		break;
	case 'd': // Default
		rowWidth = 16;
		break;
	default:
		ushort l = void;
		if (convert(l, val))
			return errorSet(ErrorCode.invalidNumber);
		rowWidth = l;
	}
	return 0;
}

int settingOffset(string val) {
	if (val == null || val.length == 0)
		return errorSet(ErrorCode.invalidParameter);
	switch (val[0]) {
	case 'o', 'O': globals.offsetType = NumberType.octal; break;
	case 'd', 'D': globals.offsetType = NumberType.decimal; break;
	case 'h', 'H': globals.offsetType = NumberType.hexadecimal; break;
	default:       return errorSet(ErrorCode.invalidParameter);
	}
	return 0;
}

int settingData(string val) {
	if (val == null || val.length == 0)
		return errorSet(ErrorCode.invalidParameter);
	switch (val[0]) {
	case 'o', 'O': globals.dataType = NumberType.octal; break;
	case 'd', 'D': globals.dataType = NumberType.decimal; break;
	case 'h', 'H': globals.dataType = NumberType.hexadecimal; break;
	default:       return errorSet(ErrorCode.invalidParameter);
	}
	return 0;
}

int settingDefaultChar(string val) {
	if (val == null || val.length == 0)
		return errorSet(ErrorCode.invalidParameter);
	switch (val) { // aliases
	case "space": globals.defaultChar = ' '; break;
	case "dot":   globals.defaultChar = '.'; break;
	default:      globals.defaultChar = val[0];
	}
	return 0;
}

int settingCharset(string val) {
	if (val == null || val.length == 0)
		return errorSet(ErrorCode.invalidParameter);
	switch (val) {
	case "ascii":	globals.charType = CharType.ascii; break;
	case "cp437":	globals.charType = CharType.cp437; break;
	case "ebcdic":	globals.charType = CharType.ebcdic; break;
	case "mac":	globals.charType = CharType.mac; break;
	default:       return errorSet(ErrorCode.invalidCharset);
	}
	return 0;
}