/// Application.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module ddhx.ddhx;

import std.stdio;
import std.file : getSize;
import core.stdc.string : memset;
import ddhx.utils : unformat;
import ddhx.input, ddhx.menu, ddhx.terminal, ddhx.settings, ddhx.error;
import ddhx.searcher : searchLast;
import engine = ddhx.engine;

/// Copyright string
enum DDHX_COPYRIGHT = "Copyright (c) 2017-2021 dd86k <dd@dax.moe>";

/// App version
enum DDHX_VERSION = "0.3.3";

/// Version line
enum DDHX_VERSION_LINE = "ddhx " ~ DDHX_VERSION ~ " (built: " ~ __TIMESTAMP__~")";

//
// User settings
//

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
	CharType charType;	/// Current charset
	char defaultChar = '.';	/// Default character to use for non-ascii characters
//	int include;	/// Include what panels
	// Internals
	int termHeight;	/// Last known terminal height
	int termWidth;	/// Last known terminal width
}

__gshared Globals globals; /// Single-instance of globals.
__gshared Input   input;   /// Input file/stream

int printError(A...)(int code, string fmt, A args) {
	stderr.write("error: ");
	stderr.writefln(fmt, args);
	return code;
}

int ddhxOpenFile(string path) {
	version (Trace) trace("path=%s", path);
	
	return input.openFile(path);
}
int ddhxOpenMmfile(string path) {
	version (Trace) trace("path=%s", path);
	
	return input.openMmfile(path);
}
int ddhxOpenStdin() {
	version (Trace) trace("-");
	
	return input.openStdin();
}

/// Main app entry point
int ddhxInteractive(long skip = 0) {
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
	coninit;
	version (Trace) trace("conclear");
	conclear;
	version (Trace) trace("conheight");
	globals.termHeight = conheight;
	ddhxPrepBuffer(true);
	input.read();
	version (Trace) trace("buffer+read=%u", buffer.result.length);
	ddhxRender();
	
	InputInfo k;
	version (Trace) trace("loop");
L_KEY:
	coninput(k);
	version (Trace) trace("key=%d", k.value);
	
	with (globals) switch (k.value) {
	
	//
	// Navigation
	//
	
	case Key.UpArrow, Key.K:
		if (input.position - rowWidth >= 0)
			ddhxSeek(input.position - rowWidth);
		else
			ddhxSeek(0);
		break;
	case Key.DownArrow, Key.J:
		if (input.position + input.bufferSize + rowWidth <= input.size)
			ddhxSeek(input.position + rowWidth);
		else
			ddhxSeek(input.size - input.bufferSize);
		break;
	case Key.LeftArrow, Key.H:
		if (input.position - 1 >= 0) // Else already at 0
			ddhxSeek(input.position - 1);
		break;
	case Key.RightArrow, Key.L:
		if (input.position + input.bufferSize + 1 <= input.size)
			ddhxSeek(input.position + 1);
		else
			ddhxSeek(input.size - input.bufferSize);
		break;
	case Key.PageUp, Mouse.ScrollUp:
		if (input.position - cast(long)input.bufferSize >= 0)
			ddhxSeek(input.position - input.bufferSize);
		else
			ddhxSeek(0);
		break;
	case Key.PageDown, Mouse.ScrollDown:
		if (input.position + input.bufferSize + input.bufferSize <= input.size)
			ddhxSeek(input.position + input.bufferSize);
		else
			ddhxSeek(input.size - input.bufferSize);
		break;
	case Key.Home:
		ddhxSeek(k.key.ctrl ? 0 : input.position - (input.position % rowWidth));
		break;
	case Key.End:
		if (k.key.ctrl) {
			ddhxSeek(input.size - input.bufferSize);
		} else {
			const long np = input.position + (rowWidth - input.position % rowWidth);
			ddhxSeek(np + input.bufferSize <= input.size ? np : input.size - input.bufferSize);
		}
		break;

	//
	// Actions/Shortcuts
	//

	case Key.N:
		if (searchLast())
			ddhxMsgLow(ddhxErrorMsg);
		break;
	case Key.Escape, Key.Enter, Key.Colon:
		ddhxmenu;
		break;
	case Key.G:
		ddhxmenu("g ");
		engine.renderTopBar();
		break;
	case Key.I:
		ddhxMsgFileInfo;
		break;
	case Key.R, Key.F5:
		ddhxRefresh;
		break;
	case Key.A:
		optionWidth("a");
		ddhxRefresh;
		break;
	case Key.Q: ddhxExit; break;
	default:
		version (Trace) trace("unknown key=%u", k.value);
	}
	goto L_KEY;
}

/// 
int ddhxDump(long skip, long length) {
	if (length < 0)
		return printError(2, "length negative");
	
	version (Trace) trace("skip=%d length=%d", skip, length);
	
	final switch (input.mode) {
	case InputMode.file, InputMode.mmfile:
		if (skip < 0) {
			skip = input.size + skip;
		}
		if (skip + length > input.size)
			return printError(3, "length overflow");
		if (length == 0)
			length = input.size - skip;
		if (skip)
			input.seek(skip);
		
		engine.renderTopBarRaw();
		
		if (length >= DEFAULT_BUFFER_SIZE) {
			input.adjust(DEFAULT_BUFFER_SIZE);
			do {
				input.read();
				engine.renderMainRaw();
				input.position += DEFAULT_BUFFER_SIZE;
			} while (length -= DEFAULT_BUFFER_SIZE > 0);
		}
		
		if (length > 0) {
			input.adjust(cast(uint)length);
			input.read();
			engine.renderMainRaw();
		}
	
		break;
	case InputMode.stdin:
		if (skip < 0)
			return printError(4, "skip value negative in stdin mode");
		
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
		engine.renderTopBarRaw();
		
		do {
			len = input.read().length;
			engine.renderMainRaw();
			input.position += DEFAULT_BUFFER_SIZE;
		} while (len == DEFAULT_BUFFER_SIZE);
		break;
	}
	return 0;
}

/// int ddhxDiff(string path1, string path2)

/// Automatically determine new buffer size for engine from console/terminal
/// window size.
void ddhxPrepBuffer(bool skipTerm = false)
{
	debug import std.conv : text;
	
	version (Trace) trace("skip=%s", skipTerm);
	
	// Console/Terminal height
	const int ch = conheight;
	// New effective height
	const int h = (skipTerm ? globals.termHeight : ch) - 2;
	
	debug
	{
		assert(h > 0);
		assert(h < ch, "h="~h.text~" >= conheight="~ch.text);
	}
	
	int newSize = h * globals.rowWidth; // Proposed buffer size
	if (newSize >= input.size)
		newSize = cast(uint)(input.size - input.position);
	engine.resizeBuffer(newSize);
}

/// Refresh the entire screen
void ddhxRefresh() {
	ddhxPrepBuffer();
	input.seek(input.position);
	input.read();
	conclear();
	ddhxRender();
}

/// Render all
void ddhxRender() {
	engine.renderTopBar();
	engine.renderMainRaw();
	engine.renderStatusBar();
}

/**
 * Goes to the specified position in the file.
 * Ignores bounds checking for performance reasons.
 * Sets CurrentPosition.
 * Params: pos = New position
 */
void ddhxSeek(long pos) {
	version (Trace) trace("pos=%d", pos);
	
	if (input.bufferSize < input.size) {
		input.seek(pos);
		input.read();
		ddhxRender();
	} else
		ddhxMsgLow("Navigation disabled, buffer too small");
}

/**
 * Parses the string as a long and navigates to the file location.
 * Includes offset checking (+/- notation).
 * Params: str = String as a number
 */
void ddhxSeek(string str) {
	version (Trace) trace("str=%s", str);
	
	const char seekmode = str[0];
	if (seekmode == '+' || seekmode == '-') { // relative input.position
		str = str[1..$];
	}
	long newPos = void;
	if (unformat(str, newPos) == false) {
		ddhxMsgLow("Could not parse number");
		return;
	}
	with (globals) switch (seekmode) {
	case '+':
		newPos = input.position + newPos;
		if (newPos - input.bufferSize < input.size)
			ddhxSeek(newPos);
		break;
	case '-':
		newPos = input.position - newPos;
		if (newPos >= 0)
			ddhxSeek(newPos);
		break;
	default:
		if (newPos < 0) {
			ddhxMsgLow("Range underflow: %d (0x%x)", newPos, newPos);
		} else if (newPos >= input.size - input.bufferSize) {
			ddhxMsgLow("Range overflow: %d (0x%x)", newPos, newPos);
		} else {
			ddhxSeek(newPos);
		}
	}
}

/**
 * Goes to the specified position in the file.
 * Checks bounds and calls Goto.
 * Params: pos = New position
 */
void ddhxSeekSafe(long pos) {
	version (Trace) trace("pos=%s", pos);
	
	if (pos + input.bufferSize > input.size)
		ddhxSeek(input.size - input.bufferSize);
	else
		ddhxSeek(pos);
}

/**
 * Message once (upper bar)
 * Params: msg = Message string
 */
void ddhxMsgTop(A...)(string fmt, A args) {
	conpos(0, 0);
	ddhxMsg(fmt, args);
}

void ddhxMsgLow(A...)(string fmt, A args) {
	conpos(0, conheight - 1);
	ddhxMsg(fmt, args);
}

private void ddhxMsg(A...)(string fmt, A args) {
	import std.format : sformat;
	char[256] outbuf = void;
	char[] outs = outbuf[].sformat(fmt, args);
	writef("%s%*s", outs, (conwidth - 1) - outs.length, " ");
	stdout.flush();
}

/// Print some file information at the bottom bar
void ddhxMsgFileInfo() {
	ddhxMsgLow("%8s  %s", input.sizeString, input.fileName);
}

void ddhxExit(int code = 0) {
	import core.stdc.stdlib : exit;
	conclear;
	conrestore;
	exit(code);
}
