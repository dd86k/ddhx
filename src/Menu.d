module menu;

import std.stdio : readln, write;
import core.stdc.stdio : printf;
import ddcon, ddhx, searcher;
import settings;

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

	ddhx_update_offsetbar;

	const size_t argc = argv.length;
	if (argc == 0) return;

	switch (argv[0]) {
	case "g", "goto":
		if (argc <= 1) {
			ddhx_msglow("Missing position (number)");
			break;
		}
		switch (argv[1]) {
		case "e", "end":
			ddhx_seek_unsafe(fsize - screenl);
			break;
		case "h", "home":
			ddhx_seek_unsafe(0);
			break;
		default:
			ddhx_seek(argv[1]);
		}
		break;
	case "s", "search": // Search
		if (argc <= 1) {
			ddhx_msglow("Missing data type");
			break;
		}
		if (argc <= 2) {
			ddhx_msglow("Missing data argument");
			break;
		}

		string value = argv[2];
		switch (argv[1]) {
		case "u8":
			argv[1] = value;
			goto SEARCH_BYTE;
		case "u16":
			search_u16(value);
			break;
		case "u32":
			search_u32(value);
			break;
		case "u64":
			search_u64(value);
			break;
		case "utf8":
			search_utf8(value);
			break;
		case "utf16":
			search_utf16(value);
			break;
		default:
			ddhx_msglow("Invalid type (%s)", argv[1]);
			break;
		}
		break; // "search"
	case "ss": // Search ASCII/UTF-8 string
		if (argc > 1)
			search_utf8(argv[1]);
		else
			ddhx_msglow("Missing argument (utf8)");
		break;
	case "sw": // Search UTF-16 string
		if (argc > 1)
			search_utf16(argv[1]);
		else
			ddhx_msglow("Missing argument (utf16)");
		break;
	//TODO: UTF-32 search alias
	case "sb": // Search byte
SEARCH_BYTE:
		if (argc <= 1) {
			ddhx_msglow("Missing argument (u8)");
			break;
		}
		import utils : unformat;
		long l;
		if (unformat(argv[1], l)) {
			search_u8(l & 0xFF);
		} else {
			ddhx_msglow("Could not parse number");
		}
		break;
	case "i", "info": ddhx_fileinfo; break;
	case "o", "offset":
		import settings : HandleOffset;
		if (argc <= 1) {
			ddhx_msglow("Missing offset");
			break;
		}
		HandleOffset(argv[1]);
		ddhx_update_offsetbar;
		ddhx_render_raw;
		break;
	case "refresh": ddhx_refresh; break;
	case "quit": ddhx_exit; break;
	case "about":
		enum C = "Written by dd86k. " ~ COPYRIGHT;
		ddhx_msglow(C);
		break;
	case "version":
		enum V = "ddhx " ~ APP_VERSION ~ ", " ~ __TIMESTAMP__;
		ddhx_msglow(V);
		break;
	//
	// Setting manager
	//
	case "set":
		if (argc <= 1) {
			ddhx_msglow("Missing setting");
			break;
		}
		if (argc <= 2) {
			ddhx_msglow("Missing setting option");
			break;
		}
		switch (argv[1]) {
		case "width", "w":
			HandleWidth(argv[2]);
			ddhx_prep;
			ddhx_refresh;
			break;
		case "offset", "o":
			HandleOffset(argv[2]);
			conclear;
			ddhx_refresh;
			break;
		default:
			ddhx_msglow("Unknown setting: %s", argv[1]);
			break;
		}
		break;
	default: ddhx_msglow("Unknown command: %s", argv[0]); break;
	}
}