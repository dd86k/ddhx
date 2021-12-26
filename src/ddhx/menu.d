module ddhx.menu;

import std.stdio : readln, write;
import core.stdc.stdio : printf;
import ddhx.ddhx, ddhx.terminal, ddhx.settings, ddhx.searcher, ddhx.error;
import ddhx.engine;

/**
 * Internal command prompt.
 * Params: prepend = Initial command
 */
void ddhxmenu(string prepend = null) {
	import std.array : split;
	import std.algorithm.iteration : splitter;
	import std.algorithm.sorting : merge;
	import std.range : chain;
	import std.algorithm : joiner;
	import std.format : sformat;

	conpos(0, 0);
	printf("%*s", conwidth - 1, cast(char*)" ");
	conpos(0, 0);
	printf(">");
	if (prepend)
		write(prepend);

	//TODO: GC-free merge prepend and readln(buf), then split
	//TODO: Smarter argv handling with single and double quotes
	string[] argv = cast(string[])(prepend ~ readln[0..$-1]).split; // split ' ', no empty entries
	
	ddhxUpdateOffsetbar;
	
	const size_t argc = argv.length;
	if (argc == 0) return;
	
	int error;
	string value = void;
	menu: switch (argv[0]) {
	case "g", "goto":
		if (argc <= 1) {
			ddhxMsgLow("Missing argument (position)");
			break;
		}
		switch (argv[1]) {
		case "e", "end":
			with (globals) ddhxSeek(input.size - input.bufferSize);
			break;
		case "h", "home":
			ddhxSeek(0);
			break;
		default:
			ddhxSeek(argv[1]);
		}
		break;
	//TODO: Consider compacting keywords
	//      like "search "u8"" may confuse the module
	//      searchu8 seems a little appropriate
	case "s", "search": // Search
		if (argc <= 1) {
			ddhxMsgLow("Missing argument (type)");
			break;
		}
		if (argc <= 2) {
			ddhxMsgLow("Missing argument (needle)");
			break;
		}
		
		//TODO: search auto ...
		//      Auto-guess type (integer/"string"/byte array/etc.)
		value = argv[2];
		switch (argv[1]) {
		case "u8", "byte":
			error = search!ubyte(value);
			break;
		case "u16", "short":
			error = search!ushort(value);
			break;
		case "u32", "int":
			error = search!uint(value);
			break;
		case "u64", "long":
			error = search!ulong(value);
			break;
		case "utf8", "string":
			error = search!string(value);
			break;
		case "utf16", "wstring":
			error = search!wstring(value);
			break;
		case "utf32", "dstring":
			error = search!dstring(value);
			break;
		default:
			ddhxMsgLow("Invalid type (%s)", argv[1]);
			break;
		}
		break; // "search"
	case "sb": // Search byte
		if (argc <= 1) {
			ddhxMsgLow("Missing argument (u8)");
			break;
		}
		error = search!ubyte(argv[1]);
		break;
	case "sw": // Search word
		if (argc <= 1) {
			ddhxMsgLow("Missing argument (u8)");
			break;
		}
		error = search!ushort(argv[1]);
		break;
	case "sd": // Search dword
		if (argc <= 1) {
			ddhxMsgLow("Missing argument (u8)");
			break;
		}
		error = search!uint(argv[1]);
		break;
	case "sl": // Search long
		if (argc <= 1) {
			ddhxMsgLow("Missing argument (u8)");
			break;
		}
		error = search!ulong(argv[1]);
		break;
	case "ss": // Search ASCII/UTF-8 string
		if (argc <= 1) {
			ddhxMsgLow("Missing argument (string)");
			break;
		}
		error = search!string(argv[1]);
		break;
	case "sws": // Search UTF-16 string
		if (argc <= 1) {
			ddhxMsgLow("Missing argument (wstring)");
			break;
		}
		error = search!wstring(argv[1]);
		break;
	case "sds": // Search UTF-32 string
		if (argc <= 1) {
			ddhxMsgLow("Missing argument (dstring)");
			break;
		}
		error = search!dstring(argv[1]);
		break;
	case "i", "info": ddhxMsgFileInfo; break;
	case "refresh": ddhxRefresh; break;
	case "quit": ddhxExit; break;
	case "about":
		enum C = "Written by dd86k. " ~ DDHX_COPYRIGHT;
		ddhxMsgLow(C);
		break;
	case "version":
		ddhxMsgLow(DDHX_VERSION_LINE);
		break;
	//
	// Settings
	//
	case "w", "width":
		if (optionWidth(argv[1])) {
			ddhxMsgLow(ddhxErrorMsg);
			break;
		}
		ddhxPrepBuffer;
		ddhxRefresh;
		break;
	case "o", "offset":
		if (argc <= 1) {
			ddhxMsgLow("Missing argument (offset)");
			break;
		}
		if ((error = optionOffset(argv[1])) != 0)
			break;
		ddhxUpdateOffsetbar;
		ddhxDrawRaw;
		break;
	case "C", "defaultchar":
		if (optionDefaultChar(argv[1])) {
			ddhxMsgLow(ddhxErrorMsg);
			break;
		}
		ddhxRefresh;
		break;
	case "c", "charset":
		if (argc <= 1) {
			ddhxMsgLow("Missing argument (charset)");
			break;
		}
		
		if ((error = optionCharset(argv[1])) != 0)
			break;
		ddhxDraw;
		break;
	default: error = DdhxError.invalidCommand;
	}
	
	if (error)
		ddhxMsgLow(ddhxErrorMsg);
}
