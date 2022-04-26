/// Main application.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module ddhx.ddhx;

import std.stdio;
import ddhx;

/// Copyright string
enum COPYRIGHT = "Copyright (c) 2017-2022 dd86k <dd@dax.moe>";

/// App version
enum VERSION = "0.4.2";

/// Version line
enum ABOUT = "ddhx " ~ VERSION ~ " (built: " ~ __TIMESTAMP__~")";

//
// SECTION Input structure
//

// !SECTION

/// Number type to render either for offset or data
enum NumberType {
	hexadecimal,
	decimal,
	octal
}

//TODO: --no-header: bool
//TODO: --no-offset: bool
//TODO: --no-status: bool
/// Global definitions and default values
// Aren't all of these engine settings anyway?
struct Globals {
	// Settings
	ushort rowWidth = 16;	/// How many bytes are shown per row
	NumberType offsetType;	/// Current offset view type
	NumberType dataType;	/// Current data view type
	char defaultChar = '.';	/// Default character to use for non-ascii characters
	bool si;	/// Use SI prefixes over IEC
//	int include;	/// Include what panels
	// Internals
	TerminalSize termSize;	/// Last known terminal size
}

__gshared Globals globals; /// Single-instance of globals.
__gshared Io io;	/// File/stream I/O instance.

//TODO: ddhxApps could only return error code, let main print out error message

int printError() {
	stderr.write("error: ");
	stderr.writeln(errorMsg);
	return lastError;
}
int printError(A...)(int code, const(char)[] fmt, A args) {
	stderr.write("error: ");
	stderr.writefln(fmt, args);
	return code;
}

/// Interactive application.
/// Params: skip = Seek to file/data position.
/// Returns: Error code.
int ddhxInteractive(long skip = 0) {
	// NOTE: File I/O handled before due to stdin
	//TODO: negative should be starting from end of file (if not stdin)
	//      stdin: use seek
	if (skip < 0)
		// skip = +skip;
		return printError(1, "Skip value must be positive");
	
	if (io.mode == FileMode.stream) {
		version (Trace) trace("slurp skip=%u", skip);
		if (io.toMemory(skip, 0))
			return printError;
	} else {
		version (Trace) trace("seek skip=%u", skip);
		if (io.seek(Seek.start, skip))
			return printError;
	}
	
	// Terminal setup (resets stdin if PIPE/FIFO is detected)
	version (Trace) trace("terminalInit");
	terminalInit(TermFeat.all);
	version (Trace) trace("terminalSize");
	globals.termSize = terminalSize;
	if (globals.termSize.height < 3)
		return printError(1, "Need at least 3 lines to display properly");
	if (globals.termSize.width < 20)
		return printError(1, "Need at least 20 columns to display properly");
	
	// Setup
	appAdjustBuffer(true);
	if (io.read())
		return printError;
	appRender();
	
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
		break;
	case I:
		msgFileInfo;
		break;
	case R, F5:
		appRefresh;
		break;
	case A:
		settingWidth("a");
		appRefresh;
		break;
	case Q: appExit; break;
	default:
	}
	goto L_INPUT;
}

/// Dump to stdout, akin to xxd(1).
/// Params:
/// 	skip = If set, number of bytes to skip.
/// 	length = If set, maximum length to read.
/// Returns: Error code.
int ddhxDump(long skip, long length) {
	if (length < 0)
		return printError(1, "Length must be a positive value");
	
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
			return printError(1, "Length value must be positive");
		
		// overflow check
		//TODO: This shouldn't error and should take the size we get from file.
		if (skip + length > io.size)
			return printError(1, "Specified length overflows file size");
		
		break;
	case stream: // Has no size
		if (skip < 0)
			return printError(1, "Skip value must be positive with stream");
		if (length == 0)
			length = long.max;
		break;
	default: // Memory mode is never initiated from CLI
	}
	
	// start skipping
	if (skip)
		io.seek(Seek.start, skip);
	
	// top bar to stdout
	displayRenderTopRaw();
	
	// mitigate unaligned reads/renders
	io.resizeBuffer(globals.rowWidth * 16);
	
	// read until EOF or length spec
	long r;
	do {
		io.read();
		displayRenderMainRaw();
		r += io.buffer.length;
		io.position = r;
	} while (io.eof == false && r < length);
	
	return 0;
}

/// int appDiff(string path1, string path2)

//TODO: revamp menu system
//      char mode: character mode (':', '/', '?')
//      string command: command shortcut (e.g., 'g' + ' ' default)
private
void menu(string cmdPrepend = null, string cmdAlias = null) {
	// clear bar and command prepend
	terminalPos(0, 0);
	cwritef("%*s", terminalSize.width - 1, " ");
	
	// write prompt
	terminalPos(0, 0);
	if (cmdAlias == null) cwrite(":");
	if (cmdAlias) cwrite(cmdAlias);
	if (cmdPrepend) cwrite(cmdPrepend);
	
	// read command
	string line = cmdPrepend ~ cmdAlias ~ readln();
	
	// draw upper bar, clearing input
	displayRenderTop;
	
	if (command(line))
		msgBottom(errorMsg());
}

// for more elaborate user inputs (commands invoke this)
// prompt="save as"
// "save as: " + user input
/*private
string input(string prompt) {
	terminalPos(0, 0);
	cwrite(prompt, ": ");
	return readln;
}*/

/// Move the view to the start of the data
void moveStart() {
	appSeek(0);
}
/// Move the view to the end of the data
void moveEnd() {
	appSeek(io.size - io.readSize);
}
/// Align view to start of row
void moveAlignStart() {
	appSeek(io.position - (io.position % globals.rowWidth));
}
/// Align view to end of row (start of row + row size)
void moveAlignEnd() {
	const long n = io.position +
		(globals.rowWidth - io.position % globals.rowWidth);
	appSeek(n + io.readSize <= io.size ? n : io.size - io.readSize);
}
/// Move view to one data group to the left (backwards)
void moveLeft() {
	if (io.position - 1 >= 0) // Else already at 0
		appSeek(io.position - 1);
}
/// Move view to one data group to the right (forwards)
void moveRight() {
	if (io.position + io.readSize + 1 <= io.size)
		appSeek(io.position + 1);
	else
		appSeek(io.size - io.readSize);
}
/// Move view to one row size up (backwards)
void moveRowUp() {
	if (io.position - globals.rowWidth >= 0)
		appSeek(io.position - globals.rowWidth);
	else
		appSeek(0);
}
/// Move view to one row size down (forwards)
void moveRowDown() {
	if (io.position + io.readSize + globals.rowWidth <= io.size)
		appSeek(io.position + globals.rowWidth);
	else
		appSeek(io.size - io.readSize);
}
/// Move view to one page size up (backwards)
void movePageUp() {
	if (io.position - cast(long)io.readSize >= 0)
		appSeek(io.position - io.readSize);
	else
		appSeek(0);
}
/// Move view to one page size down (forwards)
void movePageDown() {
	if (io.position + (io.readSize << 1) <= io.size)
		appSeek(io.position + io.readSize);
	else
		appSeek(io.size - io.readSize);
}

/// Automatically determine new buffer size for display engine from
/// console/terminal window size.
/// Params: skipTerm = Skip terminal size detection and use stored value.
void appAdjustBuffer(bool skipTerm = false) {
	//TODO: Avoid crash when on end of file + resize goes further than file
	version (Trace) trace("skip=%s", skipTerm);
	
	// Effective height
	const int h = (skipTerm ? globals.termSize.height : terminalSize.height) - 2;
	
	int newSize = h * globals.rowWidth; // Proposed buffer size
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
void appRefresh() {
	appAdjustBuffer();
	io.seek(Seek.start, io.position);
	io.read();
	terminalClear();
	appRender();
}

/// Render screen (all elements)
void appRender() {
	// Meh, screw it
	displayRenderTop;
	displayRenderMain;
	displayRenderBottom;
}

/// Seek to position in data, reads view's worth, and display that.
/// Ignores bounds checking for performance reasons.
/// Sets CurrentPosition.
/// Params: pos = New position
void appSeek(long pos) {
	version (Trace) trace("pos=%d", pos);
	
	if (io.readSize >= io.size) {
		msgBottom("Navigation disabled, buffer too small");
		return;
	}

	io.seek(Seek.start, pos);
	io.read();
	appRender();
}

/// Parses the string as a long and navigates to the file location.
/// Includes offset checking (+/- notation).
/// Params: str = String as a number
void appSeek(string str) {
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
		appSafeSeek(io.position + newPos);
		break;
	case '-':
		appSafeSeek(io.position - newPos);
		break;
	default:
		if (newPos < 0) {
			msgBottom("Range underflow: %d (0x%x)", newPos, newPos);
		} else if (newPos >= io.size - io.readSize) {
			msgBottom("Range overflow: %d (0x%x)", newPos, newPos);
		} else {
			appSeek(newPos);
		}
	}
}

/// Goes to the specified position in the file.
/// Checks bounds and calls Goto.
/// Params: pos = New position
void appSafeSeek(long pos) {
	version (Trace) trace("pos=%s", pos);
	
	if (pos + io.readSize >= io.size)
		pos = io.size - io.readSize;
	else if (pos < 0)
		pos = 0;
	
	appSeek(pos);
}

/// Display a message on the top row.
/// Params:
/// 	fmt = Format.
/// 	args = Arguments.
void msgTop(A...)(const(char)[] fmt, A args) {
	terminalPos(0, 0);
	msg(fmt, args);
}

/// Display a message on the bottom row.
/// Params:
/// 	fmt = Format.
/// 	args = Arguments.
void msgBottom(A...)(const(char)[] fmt, A args) {
	terminalPos(0, terminalSize.height - 1);
	msg(fmt, args);
}

private void msg(A...)(const(char)[] fmt, A args) {
	import std.format : sformat;
	char[256] outbuf = void;
	char[] outs = outbuf[].sformat(fmt, args);
	cwritef("%s%*s", outs, (terminalSize.width - 1) - outs.length, " ");
}

/// Print some file information at the bottom bar
void msgFileInfo() {
	msgBottom("%11s  %s", io.sizeString, io.name);
}

/// Exit ddhx.
/// Params: code = Exit code.
void appExit(int code = 0) {
	import core.stdc.stdlib : exit;
	version (Trace) trace("code=%u", code);
	exit(code);
}
