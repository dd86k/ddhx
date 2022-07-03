/// Settings handler.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module settings;

import ddhx; // for NumberType
import os.terminal : TerminalSize, terminalSize;

//TODO: Move settings should be per module
//      editor settings:
//      - row width
//      - offset type
//      - data type
//      - default char
//      - si
//      And possibly deprecate settings
private struct settings_t {
	/// Bytes per row
	//TODO: Rename to columns
	int width = 16;
	/// Current offset view type
	NumberType offsetType;
	/// Current data view type
	NumberType dataType;
	/// Default character to use for non-ascii characters
	char defaultChar = '.';
	/// Use ISO base-10 prefixes over IEC base-2
	bool si;
}

/// Current settings.
public __gshared settings_t setting;

/// Reset all settings to default.
void resetSettings() {
	setting = setting.init;
	transcoderSelect(CharacterSet.ascii);
}

/// Determines the optimal column width given terminal width.
int optimalWidth() {
	TerminalSize termsize = terminalSize;
	int dataSize = void;
	final switch (setting.dataType) with (NumberType) {
	case hexadecimal: dataSize = 2; break;
	case decimal, octal: dataSize = 3; break;
	}
	dataSize += 2; // Account for space
	//TODO: +groups
	//width = cast(ushort)((w - 12) / 4);
	return (termsize.width - 16) / dataSize;
}

int settingsWidth(string val) {
	if (val == null || val.length == 0)
		return errorSet(ErrorCode.invalidParameter);
	switch (val[0]) {
	case 'a': // Automatic (fit terminal width)
		setting.width = optimalWidth;
		break;
	case 'd': // Default
		setting.width = 16;
		break;
	default:
		ushort l = void;
		if (convertToVal(l, val))
			return errorSet(ErrorCode.invalidNumber);
		setting.width = l;
	}
	return 0;
}

int settingsOffset(string val) {
	if (val == null || val.length == 0)
		return errorSet(ErrorCode.invalidParameter);
	switch (val[0]) {
	case 'o','O':	setting.offsetType = NumberType.octal; break;
	case 'd','D':	setting.offsetType = NumberType.decimal; break;
	case 'h','H':	setting.offsetType = NumberType.hexadecimal; break;
	default:	return errorSet(ErrorCode.invalidParameter);
	}
	return 0;
}

int settingsData(string val) {
	if (val == null || val.length == 0)
		return errorSet(ErrorCode.invalidParameter);
	switch (val[0]) {
	case 'o','O':	setting.dataType = NumberType.octal; break;
	case 'd','D':	setting.dataType = NumberType.decimal; break;
	case 'h','H':	setting.dataType = NumberType.hexadecimal; break;
	default:	return errorSet(ErrorCode.invalidParameter);
	}
	return 0;
}

int settingsDefaultChar(string val) {
	if (val == null || val.length == 0)
		return errorSet(ErrorCode.invalidParameter);
	switch (val) { // aliases
	case "space":	setting.defaultChar = ' '; break;
	case "dot":	setting.defaultChar = '.'; break;
	default:	setting.defaultChar = val[0];
	}
	return 0;
}

int settingsCharset(string val) {
	if (val == null || val.length == 0)
		return errorSet(ErrorCode.invalidParameter);
	switch (val) {
	case "ascii":	transcoderSelect(CharacterSet.ascii); break;
	case "cp437":	transcoderSelect(CharacterSet.cp437); break;
	case "ebcdic":	transcoderSelect(CharacterSet.ebcdic); break;
	case "mac":	transcoderSelect(CharacterSet.mac); break;
	default:	return errorSet(ErrorCode.invalidCharset);
	}
	return 0;
}