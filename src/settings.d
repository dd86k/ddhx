module settings;

import ddhx, error, ddcon, utils;

/// Offset types
enum OffsetType {
	hex,	/// Hexadecimal
	dec,	/// Decimal
	oct	/// Octal
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
		final switch (display) {
		case DisplayMode.all:
			rowWidth = cast(ushort)((conwidth - 11) / 4);
			break;
		case DisplayMode.text, DisplayMode.data:
			rowWidth = cast(ushort)((conwidth - 11) / 3);
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
	return false;
}

int optionOffset(string val) {
	switch (val[0]) {
	case 'o', 'O': globals.offset = OffsetType.oct; break;
	case 'd', 'D': globals.offset = OffsetType.dec; break;
	case 'h', 'H': globals.offset = OffsetType.hex; break;
	default: return true;
	}
	return false;
}

int optionDefaultChar(string val) {
	if (val == null || val.length == 0) {
		return ddhxError(DdhxError.invalidParameter);
	}
	switch (val) { // aliases
	case "space":	globals.defaultChar = ' '; break;
	case "dot":	globals.defaultChar = '.'; break;
	default:	globals.defaultChar = val[0];
	}
	return false;
}