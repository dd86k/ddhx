// Main application.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module ddhx;

import all, gitinfo;
import os.file : Io, Seek;
import os.terminal;

/// Copyright string
enum COPYRIGHT = "Copyright (c) 2017-2022 dd86k <dd@dax.moe>";
/// App version
enum VERSION = GIT_DESCRIPTION;
/// Version line
enum ABOUT = "ddhx " ~ VERSION ~ " (built: " ~ __TIMESTAMP__~")";

//TODO: deprecate this ugly thing
//      don't have any plans to replace it, though
__gshared Io io;	/// File/stream I/O instance.

/// Interactive application.
/// Params: skip = Seek to file/data position.
/// Returns: Error code.
int startInteractive(long skip = 0) {
	// NOTE: File I/O handled before due to stdin
	//TODO: negative should be starting from end of file (if not stdin)
	//      stdin: use seek
	if (skip < 0)
		// skip = +skip;
		return error.print(1, "Skip value must be positive");
	
	if (io.mode == FileMode.stream) {
		version (Trace) trace("slurp skip=%u", skip);
		if (io.toMemory(skip, 0))
			return error.print;
	} else {
		version (Trace) trace("seek skip=%u", skip);
		if (io.seek(Seek.start, skip))
			return error.print;
	}
	
	// Terminal setup (resets stdin if PIPE/FIFO is detected)
	version (Trace) trace("terminalInit");
	terminalInit(TermFeat.all);
	
	version (Trace) trace("terminalSize");
	TerminalSize termsize = terminalSize;
	
	if (termsize.height < 3)
		return error.print(1, "Need at least 3 lines to display properly");
	if (termsize.width < 20)
		return error.print(1, "Need at least 20 columns to display properly");
	
	// Setup
	adjustBuffer(true);
	if (io.read())
		return error.print;
	render();
	
	version (Trace) trace("loop");
	TerminalInput event;

L_INPUT:
	terminalInput(event);
	version (Trace) trace("type=%d", event.type);
	
	switch (event.type) with (InputType)
	{
	case keyDown: goto L_KEYDOWN;
	default: goto L_INPUT;
	}

L_KEYDOWN:
	version (Trace) trace("key=%d", event.key);
	
	switch (event.key) with (Key) with (Mod)
	{
	
	//
	// Navigation
	//
	
	case UpArrow, K:    moveRowUp; break;
	case DownArrow, J:  moveRowDown; break;
	case LeftArrow, H:  moveLeft; break;
	case RightArrow, L: moveRight; break;
	case PageUp:        movePageUp; break;
	case PageDown:      movePageDown; break;
	case Home:          moveAlignStart; break;
	case Home | ctrl:   moveStart; break;
	case End:           moveAlignEnd; break;
	case End | ctrl:    moveEnd; break;
	
	//
	// Actions/Shortcuts
	//
	
	case '/':
		menu(null, "/");
		break;
	case '?':
		menu(null, "?");
		break;
	case N:
		next;
		break;
	case Escape, Enter, Colon:
		terminalPauseInput;
		menu;
		terminalResumeInput;
		break;
	case G:
		menu("g ");
		break;
	case I:
		printFileInfo;
		break;
	case R, F5:
		refresh;
		break;
	case A:
		settings.setWidth("a");
		refresh;
		break;
	case Q: exit; break;
	default:
	}
	goto L_INPUT;
}

/// Dump to stdout, akin to xxd(1).
/// Params:
/// 	skip = If set, number of bytes to skip.
/// 	length = If set, maximum length to read.
/// Returns: Error code.
int startDump(long skip, long length) {
	if (length < 0)
		return error.print(1, "Length must be a positive value");
	
	terminalInit(TermFeat.minimum);
	
	version (Trace) trace("skip=%d length=%d", skip, length);
	
	switch (io.mode) with (FileMode) {
	case file, mmfile: // Has size
		// negative skip value: from end of file
		if (skip < 0)
			skip = io.size + skip;
		
		// adjust length if unset
		if (length == 0)
			length = io.size - skip;
		else if (length < 0)
			return error.print(1, "Length value must be positive");
		
		// overflow check
		//TODO: This shouldn't error and should take the size we get from file.
		if (skip + length > io.size)
			return error.print(1, "Specified length overflows file size");
		
		break;
	case stream: // Has no size
		if (skip < 0)
			return error.print(1, "Skip value must be positive with stream");
		if (length == 0)
			length = long.max;
		break;
	default: // Memory mode is never initiated from CLI
	}
	
	// start skipping
	if (skip)
		io.seek(Seek.start, skip);
	
	// top bar to stdout
	screen.renderOffsetBar();
	
	// mitigate unaligned reads/renders
	const uint a = settings.width * 16; 
	io.resizeBuffer(a);
	
	if (a > length) {
		io.resizeBuffer(cast(uint)length);
	}
	
	// read until EOF or length spec
	long r;
	do {
		io.read();
		screen.renderContent(false);
		r += io.buffer.length;
		io.position = r;
	} while (io.eof == false && r < length);
	
	return 0;
}

/// int startDiff(string path1, string path2)

//TODO: revamp menu system
//      char mode: character mode (':', '/', '?')
//      string command: command shortcut (e.g., 'g' + ' ' default)
private
void menu(string cmdPrepend = null, string cmdAlias = null) {
	import std.stdio : readln;
	
	// clear bar and command prepend
	screen.clearOffsetBar;
	
	// write prompt
	terminalPos(0, 0);
	if (cmdAlias == null) screen.cwrite(":");
	if (cmdAlias) screen.cwrite(cmdAlias);
	if (cmdPrepend) screen.cwrite(cmdPrepend);
	
	// read command
	string line = cmdPrepend ~ cmdAlias ~ readln();
	
	// draw upper bar, clearing input
	screen.renderOffsetBar;
	
	if (command(line))
		screen.message(error.message());
}

private
int command(string line) {
	return command(arguments(line));
}

private
int command(string[] argv) {
	const size_t argc = argv.length;
	if (argc == 0) return 0;
	
	version (Trace) trace("%(%s %)", argv);
	
	string command = argv[0];
	//TODO: Check length of command string?
	
	switch (command[0]) {
	case '/': // Search
		if (command.length <= 1)
			return error.set(ErrorCode.missingArgumentType);
		if (argc <= 1)
			return error.set(ErrorCode.missingArgumentNeedle);
		
		return ddhx.lookup(command[1..$], argv[1], true, true);
	case '?': // Search backwards
		if (command.length <= 1)
			return error.set(ErrorCode.missingArgumentType);
		if (argc <= 1)
			return error.set(ErrorCode.missingArgumentNeedle);
		
		return ddhx.lookup(command[1..$], argv[1], false, true);
	default: // Regular
		switch (argv[0]) {
		case "g", "goto":
			if (argc <= 1)
				return error.set(ErrorCode.missingArgumentPosition);
			
			switch (argv[1])
			{
			case "e", "end":
				ddhx.moveEnd;
				break;
			case "h", "home":
				ddhx.moveStart;
				break;
			default:
				ddhx.seek(argv[1]);
			}
			return 0;
		case "skip":
			ubyte byte_ = void;
			if (argc <= 1) {
				byte_ = ddhx.io.buffer[0];
			} else {
				if (argv[1] == "zero")
					byte_ = 0;
				else if (convert.toVal(byte_, argv[1]))
					return error.lastError;
			}
			return ddhx.skip(byte_);
		case "i", "info":
			ddhx.printFileInfo;
			return 0;
		case "refresh":
			ddhx.refresh;
			return 0;
		case "q", "quit":
			ddhx.exit;
			return 0;
		case "about":
			enum C = "Written by dd86k. " ~ ddhx.COPYRIGHT;
			ddhx.screen.message(C);
			return 0;
		case "version":
			ddhx.screen.message(ddhx.ABOUT);
			return 0;
		//
		// Settings
		//
		case "w", "width":
			if (argc <= 1)
				return error.set(ErrorCode.missingArgumentWidth);
			
			if (settings.setWidth(argv[1]))
				return error.lastError;
			
			ddhx.refresh;
			return 0;
		case "o", "offset":
			if (argc <= 1)
				return error.set(ErrorCode.missingArgumentType);
			
			if (settings.setOffset(argv[1]))
				return error.lastError;
			
			ddhx.render;
			return 0;
		case "d", "data":
			if (argc <= 1)
				return error.set(ErrorCode.missingArgumentType);
			
			if (settings.setData(argv[1]))
				return error.lastError;
			
			ddhx.render;
			return 0;
		case "C", "defaultchar":
			if (argc <= 1)
				return error.set(ErrorCode.missingArgumentCharacter);
			
			if (settings.setDefaultChar(argv[1]))
				return error.lastError;
			
			ddhx.render;
			return 0;
		case "cp", "charset":
			if (argc <= 1)
				return error.set(ErrorCode.missingArgumentCharset);
			
			if (settings.setCharset(argv[1]))
				return error.lastError;
			
			ddhx.render;
			return 0;
		case "reset":
			settings.reset();
			ddhx.render;
			return 0;
		default:
			return error.set(ErrorCode.invalidCommand);
		}
	}
}

// for more elaborate user inputs (commands invoke this)
// prompt="save as"
// "save as: " + user input
/*private
string input(string prompt) {
	terminalPos(0, 0);
	screen.cwriteAt(0,0,prompt, ": ");
	return readln;
}*/

/// Move the view to the start of the data
void moveStart() {
	seek(0);
}
/// Move the view to the end of the data
void moveEnd() {
	seek(io.size - io.readSize);
}
/// Align view to start of row
void moveAlignStart() {
	seek(io.position - (io.position % settings.width));
}
/// Align view to end of row (start of row + row size)
void moveAlignEnd() {
	const long n = io.position +
		(settings.width - io.position % settings.width);
	seek(n + io.readSize <= io.size ? n : io.size - io.readSize);
}
/// Move view to one data group to the left (backwards)
void moveLeft() {
	if (io.position - 1 >= 0) // Else already at 0
		seek(io.position - 1);
}
/// Move view to one data group to the right (forwards)
void moveRight() {
	if (io.position + io.readSize + 1 <= io.size)
		seek(io.position + 1);
	else
		seek(io.size - io.readSize);
}
/// Move view to one row size up (backwards)
void moveRowUp() {
	if (io.position - settings.width >= 0)
		seek(io.position - settings.width);
	else
		seek(0);
}
/// Move view to one row size down (forwards)
void moveRowDown() {
	if (io.position + io.readSize + settings.width <= io.size)
		seek(io.position + settings.width);
	else
		seek(io.size - io.readSize);
}
/// Move view to one page size up (backwards)
void movePageUp() {
	if (io.position - cast(long)io.readSize >= 0)
		seek(io.position - io.readSize);
	else
		seek(0);
}
/// Move view to one page size down (forwards)
void movePageDown() {
	if (io.position + (io.readSize << 1) <= io.size)
		seek(io.position + io.readSize);
	else
		seek(io.size - io.readSize);
}

/// Automatically determine new buffer size for display engine from
/// console/terminal window size.
/// Params: skipTerm = Skip terminal size detection and use stored value.
//TODO: should adjustBuffer be in screen module?
//      add int termHeight long fileSize parameters
void adjustBuffer(bool skipTerm = false) {
	//TODO: Avoid crash when on end of file + resize goes further than file
	version (Trace) trace("skip=%s", skipTerm);
	
	TerminalSize termsize = terminalSize;
	
	// Effective height
	const int h = (skipTerm ? termsize.height : termsize.height) - 2;
	
	int newSize = h * settings.width; // Proposed buffer size
	if (newSize >= io.size)
		newSize = cast(uint)(io.size - io.position);
	io.resizeBuffer(newSize);
}

/// Refresh the entire screen by:
/// 1. automatically resizing the view buffer
/// 2. Re-seeking to the current position (failsafe)
/// 3. Read buffer
/// 4. Clear the terminal
/// 5. Render
void refresh() {
	adjustBuffer();
	io.seek(Seek.start, io.position);
	io.read();
	terminalClear();
	render();
}

/// Render screen (all elements)
void render() {
	screen.renderOffsetBar;
	screen.renderContent(false);
	screen.renderStatusBar;
}

/// Seek to position in data, reads view's worth, and display that.
/// Ignores bounds checking for performance reasons.
/// Sets CurrentPosition.
/// Params: pos = New position
void seek(long pos) {
	version (Trace) trace("pos=%d", pos);
	
	if (io.readSize >= io.size) {
		screen.message("Navigation disabled, buffer too small");
		return;
	}

	io.seek(Seek.start, pos);
	io.read();
	render();
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
	if (convert.toVal(newPos, str)) {
		screen.message("Could not parse number");
		return;
	}
	switch (seekmode) {
	case '+':
		safeSeek(io.position + newPos);
		break;
	case '-':
		safeSeek(io.position - newPos);
		break;
	default:
		if (newPos < 0) {
			screen.message("Range underflow: %d (0x%x)", newPos, newPos);
		} else if (newPos >= io.size - io.readSize) {
			screen.message("Range overflow: %d (0x%x)", newPos, newPos);
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
	
	if (pos + io.readSize >= io.size)
		pos = io.size - io.readSize;
	else if (pos < 0)
		pos = 0;
	
	seek(pos);
}

/// Default haystack buffer size.
private enum BUFFER_SIZE = 16 * 1024;

private enum LAST_BUFFER_SIZE = 128;
private __gshared ubyte[LAST_BUFFER_SIZE] lastItem;
private __gshared size_t lastSize;
private __gshared string lastType;
private __gshared bool lastForward;
private __gshared bool lastAvailable;

/// Search last item.
/// Returns: Error code if set.
int next() {
	if (lastAvailable == false) {
		return error.set(ErrorCode.noLastItem);
	}
	
	long pos = void;
	int e = search.data(pos, lastItem.ptr, lastSize, lastForward);
	
	if (e) {
		screen.message("Not found");
		return e;
	}
	
	safeSeek(pos);
	//TODO: Format position found with current offset type
	screen.message("Found at 0x%x", pos);
	return 0;
}

int lookup(string type, string data, bool forward, bool save) {
	void *p = void;
	size_t len = void;
	if (convert.toRaw(p, len, data, type))
		return error.lastError;
	
	if (save) {
		import core.stdc.string : memcpy;
		lastType = type;
		lastSize = len;
		lastForward = forward;
		//TODO: Check length against LAST_BUFFER_SIZE
		memcpy(lastItem.ptr, p, len);
		lastAvailable = true;
	}
	
	screen.message("Searching for %s...", type);
	
	long pos = void;
	int e = search.data(pos, p, len, forward);
	
	if (e) {
		screen.message("Not found");
		return e;
	}
	
	safeSeek(pos);
	//TODO: Format position found with current offset type
	screen.message("Found at 0x%x", pos);
	return 0;
}

int skip(ubyte data) {
	screen.message("Skipping all 0x%x...", data);
	
	long pos = void;
	const int e = search.skip(data, pos);
	
	if (e) {
		screen.message("End of file reached");
		return e;
	}
	
	safeSeek(pos);
	//TODO: Format position found with current offset type
	screen.message("Found at 0x%x", pos);
	return 0;
}

/// Print file information
void printFileInfo() {
	screen.message("%11s  %s", io.sizeString, io.name);
}

/// Exit ddhx.
/// Params: code = Exit code.
void exit(int code = 0) {
	import core.stdc.stdlib : exit;
	version (Trace) trace("code=%u", code);
	exit(code);
}
