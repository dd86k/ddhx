/// Settings handler.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module ddhx.settings;

import ddhx;

int settingWidth(string val) {
	with (globals)
	switch (val[0]) {
	case 'a': // Automatic
		// This should get the number of data entries per row optimal
		// given terminal width
		int w = terminalSize.width;
		//TODO: +groups
		rowWidth = cast(ushort)((w - 12) / 4);
		break;
	case 'd': // Default
		rowWidth = 16;
		break;
	default:
		long l = void;
		if (unformat(val, l) == false)
			return errorSet(ErrorCode.invalidNumber);
		if (l < 1 || l > ushort.max)
			return errorSet(ErrorCode.invalidNumber);
		rowWidth = cast(ushort)l;
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
	case "ascii":  globals.charType = CharType.ascii; break;
	case "cp437":  globals.charType = CharType.cp437; break;
	case "ebcdic": globals.charType = CharType.ebcdic; break;
	default:       return errorSet(ErrorCode.invalidCharset);
	}
	return 0;
}