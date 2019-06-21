module menu;

import std.stdio : readln, write;
import core.stdc.stdio : printf;
import ddcon, ddhx, searcher;
import std.format : format;
import settings;

//TODO: count command (stat)
//TODO: Invert aliases
/*TODO: Aliases
	si: Search int
	sl: Search long
	utf8: search utf-8 string, etc.
*/

/**
 * Internal command prompt.
 * Params: init = Initial command
 */
void Menu(string prepend = null) {
	import std.array : split;
	import std.algorithm.iteration : splitter;
	import std.algorithm.sorting : merge;
	import std.range : chain;
	import std.algorithm : joiner;
	import std.format : sformat;

	ClearMsg;
	SetPos(0, 0);
	printf(">");
	if (prepend)
		write(prepend);

//	char[] inbuf = void;
//	const size_t inbufl = readln(inbuf);

	//TODO: GC-free merge prepend and readln(buf), then split
	string[] e = cast(string[])(prepend ~ readln[0..$-1]).split; // split ' ', no empty entries

	UpdateOffsetBar;
	const size_t argl = e.length;
	if (argl == 0) return;

	switch (e[0]) {
	case "g", "goto":
		if (argl > 1) {
			switch (e[1]) {
			case "e", "end":
				Goto(fsize - screenl);
				break;
			case "h", "home", "s":
				Goto(0);
				break;
			default:
				GotoStr(e[1]);
			}
		}
		break;
	case "s", "search": // Search
		if (argl <= 1) break;

		string value = e[$ - 1];
		const bool a2 = argl > 2;
		bool invert;
		if (a2) invert = e[2] == "invert";
		switch (e[1]) {
		case "u8":
			if (argl > 2) {
				e[1] = value;
				goto SEARCH_BYTE;
			} else
				MessageAlt("Missing argument. (Byte)");
			break;
		case "u16":
			if (argl > 2) {
				search_u16(value, invert);
			} else
				MessageAlt("Missing argument. (Number)");
			break;
		case "u32":
			if (argl > 2) {
				search_u32(value, invert);
			} else
				MessageAlt("Missing argument. (Number)");
			break;
		case "u64":
			if (argl > 2) {
				search_u64(value, invert);
			} else
				MessageAlt("Missing argument. (Number)");
			break;
		case "utf8":
			if (argl > 2)
				search_utf8(value);
			else
				MessageAlt("Missing argument. (String)");
			break;
		case "utf16":
			if (argl > 2)
				search_utf16(value, invert);
			else
				MessageAlt("Missing argument. (String)");
			break;
		default:
			MessageAlt(
				argl > 1 ? "Invalid type." : "Missing type."
			);
			break;
		}
		break; // "search"
	case "ss": // Search ASCII/UTF-8 string
		if (argl > 1)
			search_utf8(e[1]);
		else
			MessageAlt("Missing argument. (String)");
		break;
	case "sw": // Search UTF-16 string
		if (argl > 1)
			search_utf16(e[1]);
		else
			MessageAlt("Missing argument. (String)");
		break;
	//TODO: UTF-32 search alias
	case "sb": // Search byte
SEARCH_BYTE:
		if (argl > 1) {
			import utils : unformat;
			long l;
			if (unformat(e[1], l)) {
				search_u8(l & 0xFF);
			} else {
				MessageAlt("Could not parse number");
			}
		}
		break;
	case "i", "info": PrintFileInfo; break;
	case "o", "offset":
		if (argl > 1) {
			import settings : HandleOffset;
			HandleOffset(e[1]);
			UpdateOffsetBar;
			UpdateDisplayRawMM;
		}
		break;
	case "clear":
		Clear;
		UpdateOffsetBar;
		UpdateDisplayRawMM;
		UpdateInfoBarRaw;
		break;
	//
	// Setting manager
	//
	case "set":
		if (argl <= 1) {
			MessageAlt("Missing setting parameter");
			break;
		}
		import std.format : format;
		switch (e[1]) {
		case "width", "w":
			if (argl > 2) {
				HandleWidth(e[2]);
				PrepBuffer;
				RefreshAll;
			}
			break;
		case "offset", "o":
			if (argl > 2) {
				HandleOffset(e[2]);
				Clear;
				RefreshAll;
			}
			break;
		default:
			MessageAlt("Unknown setting parameter: %s", e[1]);
			break;
		}
		break;
	case "refresh": RefreshAll; break;
	case "quit": Exit; break;
	case "about": ShowAbout; break;
	case "version": ShowInfo; break;
	default: MessageAlt("Unknown command: %s", e[0]); break;
	}
}

private void ShowAbout() {
	MessageAlt("Written by dd86k. Copyright (c) dd86k 2017-2019");
}

private void ShowInfo() {
	MessageAlt("Using ddhx " ~ APP_VERSION); // const string
}