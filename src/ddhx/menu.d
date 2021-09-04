module ddhx.menu;

import std.stdio : readln, write;
import core.stdc.stdio : printf;
import ddhx.ddhx, ddhx.terminal, ddhx.settings, ddhx.searcher, ddhx.error;

/**
 * Internal command prompt.
 * Params: prepend = Initial command
 */
void hxmenu(string prepend = null) {
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

//	size_t argc;
//	char[1024] inbuf = void;
//	string[12] argv  = void;
//	const size_t inbufl = readln(inbuf);

	//TODO: GC-free merge prepend and readln(buf), then split
	string[] argv = cast(string[])(prepend ~ readln[0..$-1]).split; // split ' ', no empty entries
	
	ddhxUpdateOffsetbar;
	
	const size_t argc = argv.length;
	if (argc == 0) return;
	
	switch (argv[0]) {
	case "g", "goto":
		if (argc <= 1) {
			ddhxMsgLow("Missing position (number)");
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
	case "s", "search": // Search
		if (argc <= 1) {
			ddhxMsgLow("Missing data type");
			break;
		}
		if (argc <= 2) {
			ddhxMsgLow("Missing data argument");
			break;
		}

		string value = argv[2];
		switch (argv[1]) {
		case "u8", "byte":
			argv[1] = value;
			goto SEARCH_BYTE;
		case "u16", "short":
			search!ushort(value);
			break;
		case "u32", "int":
			search!uint(value);
			break;
		case "u64", "long":
			search!ulong(value);
			break;
		case "utf8", "string":
			search!string(value);
			break;
		case "utf16", "wstring":
			search!wstring(value);
			break;
		case "utf32", "dstring":
			search!dstring(value);
			break;
		default:
			ddhxMsgLow("Invalid type (%s)", argv[1]);
			break;
		}
		break; // "search"
	case "ss": // Search ASCII/UTF-8 string
		if (argc <= 1) {
			ddhxMsgLow("Missing argument (string)");
			break;
		}
		search!string(argv[1]);
		break;
	case "sw": // Search UTF-16 string
		if (argc <= 1) {
			ddhxMsgLow("Missing argument (wstring)");
			break;
		}
		search!wstring(argv[1]);
		break;
	case "sd": // Search UTF-32 string
		if (argc <= 1) {
			ddhxMsgLow("Missing argument (dstring)");
			break;
		}
		search!dstring(argv[1]);
		break;
	case "sb": // Search byte
SEARCH_BYTE:
		if (argc <= 1) {
			ddhxMsgLow("Missing argument (u8)");
			break;
		}
		search!ubyte(argv[1]);
		break;
	case "i", "info": ddhxMsgFileInfo; break;
	case "o", "offset":
		if (argc <= 1) {
			ddhxMsgLow("Missing offset");
			break;
		}
		if (optionOffset(argv[1])) {
			ddhxMsgLow(ddhxErrorMsg);
			break;
		}
		ddhxUpdateOffsetbar;
		ddhxDrawRaw;
		break;
	case "refresh": ddhxRefresh; break;
	case "quit": ddhxExit; break;
	case "about":
		enum C = "Written by dd86k. " ~ DDHX_COPYRIGHT;
		ddhxMsgLow(C);
		break;
	case "version":
		ddhxMsgLow(DDHX_VERSION);
		break;
	//
	// Setting manager
	//
	case "set":
		if (argc <= 2) {
			ddhxMsgLow(argc <= 1 ?
				"Missing setting" :
				"Missing setting option");
			break;
		}
		switch (argv[1]) {
		case "width", "w":
			if (optionWidth(argv[2])) {
				ddhxMsgLow(ddhxErrorMsg);
				break;
			}
			ddhxPrepBuffer;
			ddhxRefresh;
			break;
		case "offset", "o":
			if (optionOffset(argv[2])) {
				ddhxMsgLow(ddhxErrorMsg);
				break;
			}
			ddhxRefresh;
			break;
		case "defaultchar", "C":
			if (optionDefaultChar(argv[2])) {
				ddhxMsgLow(ddhxErrorMsg);
				break;
			}
			ddhxRefresh;
			break;
		default:
			ddhxMsgLow("Unknown setting: %s", argv[1]);
			break;
		}
		break;
	default: ddhxMsgLow("Unknown command: %s", argv[0]); break;
	}
}