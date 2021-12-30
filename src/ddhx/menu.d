/// Menu system.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module ddhx.menu;

import std.array : split;
import std.stdio : readln, write;
import core.stdc.stdio : printf;
import ddhx.ddhx, ddhx.terminal, ddhx.settings, ddhx.searcher, ddhx.error, ddhx.types;
import engine = ddhx.engine;

/**
 * Internal command prompt.
 * Params: prepend = Initial command
 */
void ddhxmenu(string prepend = null) {

	conpos(0, 0);
	printf("%*s", conwidth - 1, cast(char*)" ");
	conpos(0, 0);
	printf(">");
	if (prepend)
		write(prepend);
	
	//TODO: GC-free merge prepend and readln(buf), then split
	//TODO: Smarter argv handling with single and double quotes
	//TODO: Consider std.getopt
	string[] argv = cast(string[])(prepend ~ readln[0..$-1]).split; // split ' ', no empty entries
	
	engine.renderTopBar();
	
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
		void *p = void;
		size_t plen = void;
		string type = argv[1];
		string data = argv[2];
		
		error = conv(p, plen, data, type);
		if (error)
		{
			ddhxMsgLow(ddhxErrorMsg());
			break;
		}
		
		search(p, plen, type);
		break; // "search"
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
		engine.renderTopBar();
		engine.renderMainRaw();
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
		engine.renderMain();
		break;
	default: error = DdhxError.invalidCommand;
	}
	
	if (error)
		ddhxMsgLow(ddhxErrorMsg);
}
