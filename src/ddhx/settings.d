module ddhx.settings;

import ddhx.ddhx : globals;
import ddhx.input, ddhx.error, ddhx.terminal, ddhx.utils;

/// Offset types
enum OffsetType {
	hexadecimal,
	decimal,
	octal
}

/// 
enum DisplayMode {
	all,	/// Default
	text,	/// Text only
	data	/// Hex view only
}

int optionWidth(string val) {
	with (globals)
	switch (val[0]) {
	case 'a': // Automatic
		const int w = conwidth - 11;
		final switch (display) {
		case DisplayMode.all:
			rowWidth = cast(ushort)(w / 4);
			break;
		case DisplayMode.text, DisplayMode.data:
			rowWidth = cast(ushort)(w / 3);
			break;
		}
		break;
	case 'd': // Default
		globals.rowWidth = 16;
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
	case 'o', 'O': globals.offset = OffsetType.octal; break;
	case 'd', 'D': globals.offset = OffsetType.decimal; break;
	case 'h', 'H': globals.offset = OffsetType.hexadecimal; break;
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