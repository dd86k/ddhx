/// Settings handler.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module settings;

import ddhx; // for NumberType
import os.terminal : TerminalSize, terminalSize;

//TODO: Save config file on parameter change?

private
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

immutable string COMMAND_COLUMNS	= "columns";
immutable string COMMAND_OFFSET	= "offset";
immutable string COMMAND_DATA	= "data";
immutable string COMMAND_FILLER	= "filler";
immutable string COMMAND_SI	= "si";
immutable string COMMAND_IEC	= "iec";
immutable string COMMAND_CHARSET	= "charset";
// Editing modes
immutable string COMMAND_INSERT	= "insert";
immutable string COMMAND_OVERWRITE	= "overwrite";
immutable string COMMAND_READONLY	= "readonly";
immutable string COMMAND_VIEW	= "view";

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

int settingsColumns(string val) {
	if (val == null || val.length == 0)
		return errorSet(ErrorCode.invalidParameter);
	
	version (Trace) trace("value='%s'", val);
	
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
		if (l == 0)
			return errorSet(ErrorCode.settingColumnsInvalid);
		setting.columns = l;
	}
	return 0;
}

int settingsOffset(string val) {
	if (val == null || val.length == 0)
		return errorSet(ErrorCode.invalidParameter);
	
	version (Trace) trace("value='%s'", val);
	
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
	
	version (Trace) trace("value='%s'", val);
	
	switch (val[0]) {
	case 'o','O':	setting.dataType = NumberType.octal; break;
	case 'd','D':	setting.dataType = NumberType.decimal; break;
	case 'h','H':	setting.dataType = NumberType.hexadecimal; break;
	default:	return errorSet(ErrorCode.invalidParameter);
	}
	screen.setBinaryFormat(setting.dataType);
	return 0;
}

int settingsFiller(string val) {
	if (val == null || val.length == 0)
		return errorSet(ErrorCode.invalidParameter);
	
	version (Trace) trace("value='%s'", val);
	
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
	
	version (Trace) trace("value='%s'", val);
	
	switch (val) {
	case "ascii":	transcoderSelect(CharacterSet.ascii); break;
	case "cp437":	transcoderSelect(CharacterSet.cp437); break;
	case "ebcdic":	transcoderSelect(CharacterSet.ebcdic); break;
	case "mac":	transcoderSelect(CharacterSet.mac); break;
	default:	return errorSet(ErrorCode.invalidCharset);
	}
	return 0;
}

//TODO: Consider doing an AA with string[]... functions
//      or enum size_t HASH_FILLER = "filler".hashOf();
//      Low priority

int set(string[] args) {
	const size_t argc = args.length;
	
	if (argc == 0)
		return errorSet(ErrorCode.missingOption);
	
	switch (args[0]) {
	case COMMAND_FILLER:
		if (argc < 2)
			return errorSet(ErrorCode.missingValue);
		return settingsFiller(args[1]);
	case COMMAND_COLUMNS:
		if (argc < 2)
			return errorSet(ErrorCode.missingValue);
		return settingsColumns(args[1]);
	case COMMAND_OFFSET:
		if (argc < 2)
			return errorSet(ErrorCode.missingValue);
		return settingsOffset(args[1]);
	case COMMAND_DATA:
		if (argc < 2)
			return errorSet(ErrorCode.missingValue);
		return settingsData(args[1]);
	case COMMAND_SI:
		setting.si = true;
		return 0;
	case COMMAND_IEC:
		setting.si = false;
		return 0;
	case COMMAND_CHARSET:
		if (argc < 2)
			return errorSet(ErrorCode.missingValue);
		return settingsCharset(args[1]);
	// Editing modes
	case COMMAND_INSERT:
		
		return 0;
	case COMMAND_OVERWRITE:
		
		return 0;
	case COMMAND_READONLY:
		
		return 0;
	case COMMAND_VIEW:
		
		return 0;
	default:
	}
	
	return errorSet(ErrorCode.invalidSetting);
}

int loadSettings(string rc) {
	import std.stdio : File;
	import std.file : exists;
	import os.path : buildUserFile, buildUserAppFile;
	import std.format.read : formattedRead;
	import std.string : chomp, strip;
	import utils.args : arguments;
	
	static immutable string cfgname = ".ddhxrc";
	
	if (rc == null) {
		rc = buildUserFile(cfgname);
		
		if (rc is null)
			goto L_APPCONFIG;
		if (rc.exists)
			goto L_SELECTED;
	
L_APPCONFIG:
		rc = buildUserAppFile("ddhx", cfgname);
		
		if (rc is null)
			return 0;
		if (rc.exists == false)
			return 0;
	} else {
		if (exists(rc) == false)
			return errorSet(ErrorCode.settingFileMissing);
	}
	
L_SELECTED:
	version (Trace) trace("rc='%s'", rc);
	
	File file;
	file.open(rc);
	int linenum;
	foreach (line; file.byLine()) {
		++linenum;
		if (line.length == 0) continue;
		if (line[0] == '#') continue;
		
		string[] args = arguments(cast(string)line.chomp);
		
		if (set(args))
			return errorcode;
	}
	
	return 0;
}