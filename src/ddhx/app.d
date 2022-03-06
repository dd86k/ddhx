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
//TODO: Rename all functions with app
//      appSeek, appPageDown, etc.

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
int appInteractive(long skip = 0) {
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
	terminalInit;
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
	
	switch (event.type) with (InputType) {
	case keyDown: goto L_KEYDOWN;
	default: goto L_INPUT;
	}

L_KEYDOWN:
	version (Trace) trace("key=%d", event.key);
	
	switch (event.key) with (Key) with (Mod) {
	
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
		displayRenderTop;
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
int appDump(long skip, long length) {
	if (length < 0)
		return printError(1, "Length must be a positive value");
	
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
	default: // Memory mode is never initiated by CLI
	}
	
	// start skipping
	if (skip)
		io.seek(Seek.start, skip);
	
	// top bar to stdout
	displayRenderTopRaw();
	
	// Mitigates unaligned reads/renders
	io.resizeBuffer(globals.rowWidth * 16);
	
	// read until EOF or length spec
	long r;
	do {
		io.read();
		displayRenderMainRaw();
		r += io.buffer.length;
	} while (io.eof == false && r < length);
	
	return 0;
}

/// int appDiff(string path1, string path2)

//TODO: Dedicated command interpreter to use for dedicated files (settings)
private
void menu(string cmdPrepend = null) {
	// clear bar and command prepend
	terminalPos(0, 0);
	writef("%*s", terminalSize.width - 1, " ");
	stdout.flush;
	
	// write prompt
	terminalPos(0, 0);
	write(":");
	if (cmdPrepend) write(cmdPrepend);
	stdout.flush;
	
	// read input split arguments by space, no empty entries
	//TODO: GC-free merge prepend and readln(buf), then split
	//TODO: Smarter argv handling with single and double quotes
	//TODO: Consider std.getopt
	string[] argv = cast(string[])(cmdPrepend ~ readln[0..$-1]).split;
	
	// draw upper bar, clearing input
	displayRenderTop;
	
	const size_t argc = argv.length;
	if (argc == 0) return;
	
	//TODO: replace error var usage with lastError
	int error;
	switch (argv[0]) {
	case "g", "goto":
		if (argc <= 1) {
			msgBottom("Missing argument (position)");
			break;
		}
		switch (argv[1]) {
		case "e", "end":
			moveEnd;
			break;
		case "h", "home":
			moveStart;
			break;
		default:
			appSeek(argv[1]);
		}
		break;
	case "s", "search": // Search
		if (argc <= 1) {
			//TODO: Missing type (just one argument) -> Auto guess
			//      Auto-guess type (integer/"string"/byte array/etc.)
			//      -2 -> byte
			//      0xffff -> ushort
			//      "test"w -> wchar
			//      etc.
			msgBottom("Missing argument (type)");
			break;
		}
		if (argc <= 2) {
			msgBottom("Missing argument (needle)");
			break;
		}
		
		void *p = void;
		size_t plen = void;
		string type = argv[1];
		string data = argv[2];
		
		error = convert(p, plen, data, type);
		if (error) break;
		
		search(p, plen, type);
		break; // "search"
	case "skip":
		ubyte byte_ = void;
		if (argc <= 1) {
			byte_ = io.buffer[0];
		} else {
			if (argv[1] == "zero")
				byte_ = 0;
			else if ((error = convert(byte_, argv[1])) != 0)
				break;
		}
		error = skipByte(byte_);
		break;
	case "i", "info": msgFileInfo; break;
	case "refresh": appRefresh; break;
	case "quit": appExit; break;
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
		appRefresh;
		break;
	case "o", "offset":
		if (argc <= 1) {
			msgBottom("Missing argument (number type)");
			break;
		}
		if ((error = settingOffset(argv[1])) != 0)
			break;
		appRender;
		break;
	case "d", "data":
		if (argc <= 1) {
			msgBottom("Missing argument (number type)");
			break;
		}
		if ((error = settingData(argv[1])) != 0)
			break;
		appRender;
		break;
	case "C", "defaultchar":
		if (settingDefaultChar(argv[1])) {
			msgBottom(errorMsg);
			break;
		}
		appRefresh;
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
		settingResetAll();
		break;
	default:
		error = errorSet(ErrorCode.invalidCommand);
	}
	
	if (error)
		msgBottom(errorMsg);
}

/// Move the view to the start of the data
private void moveStart() {
	appSeek(0);
}
/// Move the view to the end of the data
private void moveEnd() {
	appSeek(io.size - io.readSize);
}
/// Align view to start of row
private void moveAlignStart() {
	appSeek(io.position - (io.position % globals.rowWidth));
}
/// Align view to end of row (start of row + row size)
private void moveAlignEnd() {
	const long n = io.position +
		(globals.rowWidth - io.position % globals.rowWidth);
	appSeek(n + io.readSize <= io.size ? n : io.size - io.readSize);
}
/// Move view to one data group to the left (backwards)
private void moveLeft() {
	if (io.position - 1 >= 0) // Else already at 0
		appSeek(io.position - 1);
}
/// Move view to one data group to the right (forwards)
private void moveRight() {
	if (io.position + io.readSize + 1 <= io.size)
		appSeek(io.position + 1);
	else
		appSeek(io.size - io.readSize);
}
/// Move view to one row size up (backwards)
private void moveRowUp() {
	if (io.position - globals.rowWidth >= 0)
		appSeek(io.position - globals.rowWidth);
	else
		appSeek(0);
}
/// Move view to one row size down (forwards)
private void moveRowDown() {
	if (io.position + io.readSize + globals.rowWidth <= io.size)
		appSeek(io.position + globals.rowWidth);
	else
		appSeek(io.size - io.readSize);
}
/// Move view to one page size up (backwards)
private void movePageUp() {
	if (io.position - cast(long)io.readSize >= 0)
		appSeek(io.position - io.readSize);
	else
		appSeek(0);
}
/// Move view to one page size down (forwards)
private void movePageDown() {
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
		//TODO: else what?
		newPos = io.position + newPos;
		if (newPos - io.readSize < io.size)
			appSeek(newPos);
		break;
	case '-':
		//TODO: else what?
		newPos = io.position - newPos;
		if (newPos >= 0)
			appSeek(newPos);
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
	
	appSeek(pos + io.readSize > io.size ? io.size - io.readSize : pos);
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
	writef("%s%*s", outs, (terminalSize.width - 1) - outs.length, " ");
	stdout.flush();
}

/// Print some file information at the bottom bar
void msgFileInfo() {
	msgBottom("%8s  %s", io.sizeString, io.name);
}

/// Exit ddhx.
/// Params: code = Exit code.
void appExit(int code = 0) {
	import core.stdc.stdlib : exit;
	exit(code);
}
