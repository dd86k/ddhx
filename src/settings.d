/// Settings handler.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module settings;

import ddhx; // for NumberType
import os.terminal : TerminalSize, terminalSize;

enum SETTINGS_FILE = ".ddhxrc";
enum MAX_STATUS_ITEMS = 10;

enum StatusItem : ubyte {
	/// Empty.
	empty,
	/// Shows editing mode, like insertion.
	editMode,
	/// Shows binary data display formatting type.
	dataMode,
	/// Shows current character translation.
	charMode,
	/// Shows size of the view buffer in size.
	viewSize,
	/// Shows absolute file position following offset setting.
	absolutePosition,
	/// Shows absolute file position that its type can be changed.
	absolutePositionAlt,
	/// Shows absolute file position relative to file size in percentage.
	absolutePercentage,
}

immutable string COMMAND_COLUMNS = "columns";
immutable string CLI_COLUMNS = "w|"~COMMAND_COLUMNS;

//TODO: Consider having statusbar offset type seperate offset

private struct settings_t {
	/// Bytes per row.
	/// Default: 16
	int columns = 16;
	/// Offset number number formatting type.
	/// Default: hexadecimal
	NumberType offsetType;
	/// Binary data number formatting type.
	/// Default: hexadecimal
	NumberType dataType;
	// Number formatting type for absolute offset in statusbar.
	// Default: hexadecimal
//	NumberType statusType;
	/// Default character to use for non-ascii characters
	/// Default: Period ('.')
	char defaultChar = '.';
	/// Use ISO base-10 prefixes over IEC base-2
	/// Default: false
	bool si;
	/// 
	/// Default: As presented
	StatusItem[MAX_STATUS_ITEMS] statusItems = [
		StatusItem.editMode,
		StatusItem.dataMode,
		StatusItem.charMode,
		StatusItem.viewSize,
		StatusItem.absolutePosition,
		StatusItem.empty,
		StatusItem.empty,
		StatusItem.empty,
		StatusItem.empty,
		StatusItem.empty,
	];
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
		setting.columns = optimalWidth;
		break;
	case 'd': // Default
		setting.columns = 16;
		break;
	default:
		ushort l = void;
		if (convertToVal(l, val))
			return errorSet(ErrorCode.invalidNumber);
		setting.columns = l;
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
	screen.setOffsetFormat(setting.offsetType);
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
	screen.setBinaryFormat(setting.dataType);
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