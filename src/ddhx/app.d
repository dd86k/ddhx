/// Main application behavior.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module ddhx.app;

import std.stdio;
import std.file : getSize;
import std.string : split;
import core.stdc.string : memset;
import ddhx;

//TODO: Redo inputs relative to view, not absolute
//      Should fix bugs in 32-bit builds
//      In part:
//      - Check read result length to allow overflow past the view 
//      - Make seek safer in general instead of specific function

//
// User settings
//

int printError(A...)(int code, string fmt, A args) {
	stderr.write("error: ");
	stderr.writefln(fmt, args);
	return code;
}

int openFile(string path) {
	version (Trace) trace("path=%s", path);
	return input.openFile(path);
}
int openMmfile(string path) {
	version (Trace) trace("path=%s", path);
	return input.openMmfile(path);
}
int openStdin() {
	version (Trace) trace("-");
	return input.openStdin();
}

/// Main app entry point
int appInteractive(long skip = 0) {
	//TODO: Consider changing the buffering strategy
	//      e.g., flush+setvbuf/puts+flush
	
	//TODO: negative should be starting from end of file (if not stdin)
	if (skip < 0)
		skip = +skip;
	
	if (input.mode == InputMode.stdin) {
		version (Trace) trace("slurp skip=%u", skip);
		input.slurpStdin(skip);
	}
	
	input.position = skip;
	
	version (Trace) trace("coninit");
	terminalInit;
	version (Trace) trace("conclear");
	terminalClear;
	version (Trace) trace("conheight");
	globals.termHeight = terminalSize.height;
	resizeBuffer(true);
	input.read();
	render();
	
	TerminalInput event;
	version (Trace) trace("loop");

L_INPUT:
	terminalInput(event);
	version (Trace) trace("type=%d", event.type);
	
	final switch (event.type) with (InputType) {
	case keyDown: goto L_KEYDOWN;
	}

L_KEYDOWN:
	version (Trace) trace("key=%d", event.key);
	
	switch (event.key) with (Key) {
	
	//
	// Navigation
	//
	
	case UpArrow, K:    moveRowUp; break;
	case DownArrow, J:  moveRowDown; break;
	case LeftArrow, H:  moveLeft; break;
	case RightArrow, L: moveRight; break;
	case PageUp:            movePageUp; break;
	case PageDown:          movePageDown; break;
	case Home:              moveAlignStart; break;
	case Home | Mod.ctrl:   moveStart; break;
	case End:               moveAlignEnd; break;
	case End | Mod.ctrl:    moveEnd; break;
	
	//
	// Actions/Shortcuts
	//
	
	case '/':
		msgBottom("slash!");
		break;
	case N:
		if (searchLast())
			msgBottom(errorMsg);
		break;
	case Escape, Enter, Colon:
		terminalPauseInput;
		menu;
		terminalResumeInput;
		break;
	case G:
		menu("g ");
		displayRenderTop();
		break;
	case I:
		msgFileInfo;
		break;
	case R, F5:
		refresh;
		break;
	case A:
		settingWidth("a");
		refresh;
		break;
	case Q: exit; break;
	default:
	}
	goto L_INPUT;
}

/// Dump application.
/// Params:
/// 	skip = If set, number of bytes to skip.
/// 	length = If set, maximum length to read.
/// Returns: Error code.
int appDump(long skip, long length) {
	if (length < 0)
		return printError(2, "length negative");
	
	version (Trace) trace("skip=%d length=%d", skip, length);
	
	final switch (input.mode) {
	case InputMode.file, InputMode.mmfile:
		// negative skip value: from end of file
		if (skip < 0)
			skip = input.size + skip;
		
		// adjust length if unset
		if (length == 0)
			length = input.size - skip;
		
		// overflow check
		if (skip + length > input.size)
			return printError(3, "specified length is overflow file size");
		
		// start skipping
		if (skip)
			input.seek(skip);
		
		// top bar to stdout
		displayRenderTopRaw();
		
		// read for length by chunk
		if (length >= DEFAULT_BUFFER_SIZE) {
			input.adjust(DEFAULT_BUFFER_SIZE);
			do {
				input.read();
				displayRenderMainRaw();
				input.position += DEFAULT_BUFFER_SIZE;
			} while (length -= DEFAULT_BUFFER_SIZE > 0);
		}
		
		// read remaining length
		if (length > 0) {
			input.adjust(cast(uint)length);
			input.read();
			displayRenderMainRaw();
		}
		
		break;
	case InputMode.stdin:
		if (skip < 0)
			return printError(4, "skip value cannot be negative");
		
		size_t len = void;
		if (skip) {
			if (skip > DEFAULT_BUFFER_SIZE) {
				input.adjust(DEFAULT_BUFFER_SIZE);
			} else {
				input.adjust(cast(uint)(skip));
			}
			do {
				len = input.read().length;
			} while (len == DEFAULT_BUFFER_SIZE);
		}
		
		input.adjust(DEFAULT_BUFFER_SIZE);
		displayRenderTopRaw();
		
		do {
			len = input.read().length;
			displayRenderMainRaw();
			input.position += DEFAULT_BUFFER_SIZE;
		} while (len == DEFAULT_BUFFER_SIZE);
		break;
	}
	return 0;
}

/// int appDiff(string path1, string path2)


//TODO: Dedicated command interpreter to use for dedicated files (settings)
private
void menu(string cmdPrepend = null) {
	// clear bar and command prepend
	terminalPos(0, 0);
	printf("%*s", terminalSize.width - 1, cast(char*)" ");
	terminalPos(0, 0);
	write(":");
	if (cmdPrepend) write(cmdPrepend);
	
	//TODO: GC-free merge prepend and readln(buf), then split
	//TODO: Smarter argv handling with single and double quotes
	//TODO: Consider std.getopt
	string[] argv = cast(string[])(cmdPrepend ~ readln[0..$-1]).split; // split ' ', no empty entries
	
	displayRenderTop;
	
	const size_t argc = argv.length;
	if (argc == 0) return;
	
	int error;
	switch (argv[0]) {
	case "g", "goto":
		if (argc <= 1) {
			msgBottom("Missing argument (position)");
			break;
		}
		switch (argv[1]) {
		case "e", "end":
			with (globals) seek(input.size - input.bufferSize);
			break;
		case "h", "home":
			seek(0);
			break;
		default:
			seek(argv[1]);
		}
		break;
	//TODO: Consider compacting keywords
	//      like "search "u8"" may confuse the module
	//      searchu8 seems a little appropriate
	case "s", "search": // Search
		if (argc <= 1) {
			msgBottom("Missing argument (type)");
			break;
		}
		if (argc <= 2) {
			msgBottom("Missing argument (needle)");
			break;
		}
		
		//TODO: search auto ...
		//      Auto-guess type (integer/"string"/byte array/etc.)
		void *p = void;
		size_t plen = void;
		string type = argv[1];
		string data = argv[2];
		
		error = convert(p, plen, data, type);
		if (error) break;
		
		search(p, plen, type);
		break; // "search"
	//case "backskip":
	case "skip":
		ubyte byte_ = void;
		if (argc <= 1) {
			byte_ = input.result[0];
			//msgBottom("Missing argument (byte)");
			//return;
		} else {
			if (argv[1] == "zero")
				byte_ = 0;
			else if ((error = convert(byte_, argv[1])) != 0)
				break;
		}
		error = skipByte(byte_);
		break;
	case "i", "info": msgFileInfo; break;
	case "refresh": refresh; break;
	case "quit": exit; break;
	case "about":
		enum C = "Written by dd86k. " ~ COPYRIGHT;
		msgBottom(C);
		break;
	case "version":
		msgBottom(VERSION_LINE);
		break;
	//
	// Settings
	//
	case "w", "width":
		if (settingWidth(argv[1])) {
			msgBottom(errorMsg);
			break;
		}
		refresh;
		break;
	case "o", "offset":
		if (argc <= 1) {
			msgBottom("Missing argument (number type)");
			break;
		}
		if ((error = settingOffset(argv[1])) != 0)
			break;
		render;
		break;
	case "d", "data":
		if (argc <= 1) {
			msgBottom("Missing argument (number type)");
			break;
		}
		if ((error = settingData(argv[1])) != 0)
			break;
		render;
		break;
	case "C", "defaultchar":
		if (settingDefaultChar(argv[1])) {
			msgBottom(errorMsg);
			break;
		}
		refresh;
		break;
	case "cp", "charset":
		if (argc <= 1) {
			msgBottom("Missing argument (charset)");
			break;
		}
		
		if ((error = settingCharset(argv[1])) != 0)
			break;
		displayRenderMain;
		break;
	case "reset":
		settingCharset("ascii");
		settingOffset("h");
		settingData("x");
		settingDefaultChar(".");
		settingWidth("16");
		break;
	default:
		error = errorSet(ErrorCode.invalidCommand);
	}
	
	if (error)
		msgBottom(errorMsg);
}

/// Automatically determine new buffer size for display engine from
/// console/terminal window size.
/// Params: skipTerm = Skip terminal size detection and use stored value.
void resizeBuffer(bool skipTerm = false) {
	//TODO: Avoid crash when on end of file + resize goes further than file
	version (Trace) trace("skip=%s", skipTerm);
	
	// Effective height
	const int h = (skipTerm ? globals.termHeight : terminalSize.height) - 2;
	
	int newSize = h * globals.rowWidth; // Proposed buffer size
	if (newSize >= input.size)
		newSize = cast(uint)(input.size - input.position);
	displayResizeBuffer(newSize);
}

/// Refresh the entire screen by:
/// 1. automatically resizing the view buffer
/// 2. Re-seeking to the current position (failsafe)
/// 3. Read buffer
/// 4. Clear the terminal
/// 5. Render
void refresh() {
	resizeBuffer();
	input.seek(input.position);
	input.read();
	terminalClear();
	render();
}

/// Render screen (all elements)
void render() {
	displayRenderTop;
	displayRenderMainRaw;
	displayRenderBottomRaw;
}

/// Move the view to the start of the data
private void moveStart() {
	seek(0);
}
/// Move the view to the end of the data
private void moveEnd() {
	seek(input.size - input.bufferSize);
}
/// Align view to start of row
private void moveAlignStart() {
	seek(input.position - (input.position % globals.rowWidth));
}
/// Align view to end of row (start of row + row size)
private void moveAlignEnd() {
	const long n = input.position +
		(globals.rowWidth - input.position % globals.rowWidth);
	seek(n + input.bufferSize <= input.size ? n : input.size - input.bufferSize);
}
/// Move view to one data group to the left (backwards)
private void moveLeft() {
	if (input.position - 1 >= 0) // Else already at 0
		seek(input.position - 1);
}
/// Move view to one data group to the right (forwards)
private void moveRight() {
	if (input.position + input.bufferSize + 1 <= input.size)
		seek(input.position + 1);
	else
		seek(input.size - input.bufferSize);
}
/// Move view to one row size up (backwards)
private void moveRowUp() {
	if (input.position - globals.rowWidth >= 0)
		seek(input.position - globals.rowWidth);
	else
		seek(0);
}
/// Move view to one row size down (forwards)
private void moveRowDown() {
	if (input.position + input.bufferSize + globals.rowWidth <= input.size)
		seek(input.position + globals.rowWidth);
	else
		seek(input.size - input.bufferSize);
}
/// Move view to one page size up (backwards)
private void movePageUp() {
	if (input.position - cast(long)input.bufferSize >= 0)
		seek(input.position - input.bufferSize);
	else
		seek(0);
}
/// Move view to one page size down (forwards)
private void movePageDown() {
	if (input.position + input.bufferSize + input.bufferSize <= input.size)
		seek(input.position + input.bufferSize);
	else
		seek(input.size - input.bufferSize);
}


/// Seek to position in data, reads view's worth, and display that.
/// Ignores bounds checking for performance reasons.
/// Sets CurrentPosition.
/// Params: pos = New position
void seek(long pos) {
	version (Trace) trace("pos=%d", pos);
	
	if (input.bufferSize < input.size) {
		input.seek(pos);
		input.read();
		render();
	} else
		msgBottom("Navigation disabled, buffer too small");
}

/// Parses the string as a long and navigates to the file location.
/// Includes offset checking (+/- notation).
/// Params: str = String as a number
void seek(string str) {
	version (Trace) trace("str=%s", str);
	
	const char seekmode = str[0];
	if (seekmode == '+' || seekmode == '-') { // relative input.position
		str = str[1..$];
	}
	long newPos = void;
	if (convert(newPos, str)) {
		msgBottom("Could not parse number");
		return;
	}
	with (globals) switch (seekmode) {
	case '+':
		newPos = input.position + newPos;
		if (newPos - input.bufferSize < input.size)
			seek(newPos);
		break;
	case '-':
		newPos = input.position - newPos;
		if (newPos >= 0)
			seek(newPos);
		break;
	default:
		if (newPos < 0) {
			msgBottom("Range underflow: %d (0x%x)", newPos, newPos);
		} else if (newPos >= input.size - input.bufferSize) {
			msgBottom("Range overflow: %d (0x%x)", newPos, newPos);
		} else {
			seek(newPos);
		}
	}
}

/// Goes to the specified position in the file.
/// Checks bounds and calls Goto.
/// Params: pos = New position
void safeSeek(long pos) {
	version (Trace) trace("pos=%s", pos);
	
	seek(pos + input.bufferSize > input.size ?
		input.size - input.bufferSize : pos);
}

/// Display a message on the top row.
/// Params:
/// 	fmt = Format.
/// 	args = Arguments.
void msgTop(A...)(string fmt, A args) {
	terminalPos(0, 0);
	msg(fmt, args);
}

/// Display a message on the bottom row.
/// Params:
/// 	fmt = Format.
/// 	args = Arguments.
void msgBottom(A...)(string fmt, A args) {
	terminalPos(0, terminalSize.height - 1);
	msg(fmt, args);
}

private void msg(A...)(string fmt, A args) {
	import std.format : sformat;
	char[256] outbuf = void;
	char[] outs = outbuf[].sformat(fmt, args);
	writef("%s%*s", outs, (terminalSize.width - 1) - outs.length, " ");
	stdout.flush();
}

/// Print some file information at the bottom bar
void msgFileInfo() {
	msgBottom("%8s  %s", input.sizeString, input.fileName);
}

/// Exit ddhx.
/// Params: code = Exit code.
void exit(int code = 0) {
	import core.stdc.stdlib : exit;
	terminalPauseInput;
	terminalClear;
	exit(code);
}
