/// Main application.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx;

//TODO: When searching strings, maybe convert it to current charset?

import gitinfo;
import os.terminal;
public import
    editor,
    searcher,
    encoding,
    error,
    converter,
    settings,
    screen,
    utils.args,
    utils.format,
    utils.memory;

/// Copyright string
enum DDHX_COPYRIGHT = "Copyright (c) 2017-2022 dd86k <dd@dax.moe>";
private enum DESCRIPTION = GIT_DESCRIPTION[1..$];
/// App version
debug enum DDHX_VERSION = DESCRIPTION~"+debug";
else  enum DDHX_VERSION = DESCRIPTION; /// Ditto
/// Version line
enum DDHX_ABOUT = "ddhx "~DDHX_VERSION~" (built: "~__TIMESTAMP__~")";

/// Number type to render either for offset or data
//TODO: NumberType -> OffsetType
enum NumberType : ubyte {
    hexadecimal,
    decimal,
    octal
}
//TODO: enum DataType { hex8, ... } etc.

//TODO: Seprate start functions into their own modules

/// Interactive application.
/// Params: skip = Seek to file/data position.
/// Returns: Error code.
int start(long skip = 0)
{
    if (skip)
    {
        //TODO: negative should be starting from end of file (if not stdin)
        //      stdin: use seek
        if (skip < 0)
            return errorPrint(1, "Skip value must be positive");
        
        if (editor.fileMode == FileMode.stream)
        {
            version (Trace) trace("slurp skip=%u", skip);
            if (editor.slurp(skip, 0))
                return errorPrint;
        }
        else if (skip)
        {
            version (Trace) trace("seek skip=%u", skip);
            editor.seek(skip);
            if (editor.err)
                return errorPrint;
        }
    }
    
    if (editor.fileMode == FileMode.stream)
    {
        editor.slurp(skip);
    }
    
    if (screen.initiate)
        panic;
    
    screen.onResize(&eventResize);
    
    refresh;
    
    inputLoop;
    return 0;
}

private:

//TODO: rename to "readbuffer"? or "screenData"?
//      screen.setData(...)?
__gshared ubyte[] readdata;

void inputLoop()
{
    version (Trace) trace("loop");
    TerminalInput event;
    
L_INPUT:
    terminalInput(event);
    version (Trace) trace("type=%d", event.type);
    
    switch (event.type) with (InputType) {
    case keyDown:    goto L_KEYDOWN;
    default:    goto L_INPUT; // unknown
    }
    
    //
    // Keyboard
    //
    
L_KEYDOWN:
    version (Trace) trace("key=%d", event.key);
    
    switch (event.key) with (Key) with (Mod) {
    
    // Navigation
    
    //TODO: ctrl+(up|down) = move view only
    //TODO: ctrl+(left|right) = move to next word
    
    case UpArrow, K:    moveRowUp; break;
    case DownArrow, J:  moveRowDown; break;
    case LeftArrow, H:  moveLeft; break;
    case RightArrow, L: moveRight; break;
    case PageUp:        movePageUp; break;
    case PageDown:      movePageDown; break;
    case Home:          moveAlignStart; break;
    case Home | ctrl:   moveAbsStart; break;
    case End:           moveAlignEnd; break;
    case End | ctrl:    moveAbsEnd; break;
    
    // Actions/Shortcuts
    
    case '/':
        menu(null, "/");
        break;
    case '?':
        menu(null, "?");
        break;
    case N:
        next;
        break;
    case Escape, Enter, ':':
        menu;
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
        settingsColumns("a");
        refresh;
        break;
    case Q: exit; break;
    default:
    }
    goto L_INPUT;
}

void eventResize()
{
    screen.updateTermSize();
    refresh; // temp
}

//TODO: revamp menu system
//      char mode: character mode (':', '/', '?')
//      string command: command shortcut (e.g., 'g' + ' ' default)
void menu(string prefix = ":", string prepend = null)
{
    import std.stdio : readln;
    import std.string : chomp, strip;
    
    // clear bar and command prepend
    screen.clearOffsetBar;
    
    string line = screen.prompt(prefix, prepend);
    
    scope (exit)
    {
        editor.cursorBound;
        updateCursor;
    }
    
    if (line.length == 0)
        return;
    
    if (command(line))
        screen.message(errorMessage());
}

int command(string line)
{
    return command(arguments(line));
}

int command(string[] argv)
{
    const size_t argc = argv.length;
    if (argc == 0) return 0;
    
    version (Trace) trace("argv=%(%s %)", argv);
    
    string command = argv[0];
    
    switch (command[0]) { // shortcuts
    case '/': // Search
        if (command.length < 2)
            return errorSet(ErrorCode.missingType);
        if (argc < 2)
            return errorSet(ErrorCode.missingNeedle);
        
        return ddhx.lookup(command[1..$], argv[1], true, true);
    case '?': // Search backwards
        if (command.length < 2)
            return errorSet(ErrorCode.missingType);
        if (argc < 2)
            return errorSet(ErrorCode.missingNeedle);
        
        return ddhx.lookup(command[1..$], argv[1], false, true);
    default:
    }
    
    switch (argv[0]) { // regular commands
    case "g", "goto":
        if (argc < 2)
            return errorSet(ErrorCode.missingValue);
        
        switch (argv[1]) {
        case "e", "end":
            moveAbsEnd;
            break;
        case "h", "home":
            moveAbsStart;
            break;
        default:
            seek(argv[1]);
        }
        return 0;
    case "skip":
        ubyte byte_ = void;
        if (argc <= 1)
        {
            byte_ = readdata[editor.cursor.position];
        } else {
            if (argv[1] == "zero")
                byte_ = 0;
            else if (convertToVal(byte_, argv[1]))
                return error.errorcode;
        }
        return skip(byte_);
    case "i", "info":
        printFileInfo;
        return 0;
    case "refresh":
        refresh;
        return 0;
    case "q", "quit":
        exit;
        return 0;
    case "about":
        enum C = "Written by dd86k. " ~ DDHX_COPYRIGHT;
        screen.message(C);
        return 0;
    case "version":
        screen.message(DDHX_ABOUT);
        return 0;
    case "reset":
        resetSettings();
        render;
        return 0;
    case "set":
        if (argc < 2)
            return errorSet(ErrorCode.missingOption);
        
        int e = settings.set(argv[1..$]);
        if (e == 0) refresh;
        return e;
    default:
        return errorSet(ErrorCode.invalidCommand);
    }
}

// for more elaborate user inputs (commands invoke this)
// prompt="save as"
// "save as: " + user input
/*private
string input(string prompt, string include)
{
    terminalPos(0, 0);
    screen.cwriteAt(0, 0, prompt, ": ", include);
    return readln;
}*/

//TODO: When screen doesn't move: Only render lines affected

/// Move the cursor to the start of the data
void moveAbsStart()
{
    if (editor.cursorAbsStart)
        readRender;
    else
        render;
    updateCursor;
}
/// Move the cursor to the end of the data
void moveAbsEnd()
{
    if (editor.cursorAbsEnd)
        readRender;
    else
        render;
    updateCursor;
}
/// Align cursor to start of row
void moveAlignStart()
{
    editor.cursorHome;
    render;
    updateCursor;
}
/// Align cursor to end of row
void moveAlignEnd()
{
    editor.cursorEnd;
    render;
    updateCursor;
}
/// Move cursor to one data group to the left (backwards)
void moveLeft()
{
    if (editor.cursorLeft)
        readRender;
    else
        render;
    updateCursor;
}
/// Move cursor to one data group to the right (forwards)
void moveRight()
{
    if (editor.cursorRight)
        readRender;
    else
        render;
    updateCursor;
}
/// Move cursor to one row size up (backwards)
void moveRowUp()
{
    if (editor.cursorUp)
        readRender;
    else
        render;
    updateCursor;
}
/// Move cursor to one row size down (forwards)
void moveRowDown()
{
    if (editor.cursorDown)
        readRender;
    else
        render;
    updateCursor;
}
/// Move cursor to one page size up (backwards)
void movePageUp()
{
    if (editor.cursorPageUp)
        readRender;
    else
        render;
    updateCursor;
}
/// Move view to one page size down (forwards)
void movePageDown()
{
    if (editor.cursorPageDown)
        readRender;
    updateStatus;
    updateCursor;
}

/// Initiate screen buffer
void initiate()
{
    screen.updateTermSize;
    
    long fsz = editor.fileSize; /// data size
    int ssize = (screen.termSize.height - 2) * setting.columns; /// screen size
    uint nsize = ssize >= fsz ? cast(uint)fsz : ssize;
    
    version (Trace) trace("fsz=%u ssz=%u nsize=%u", fsz, ssize, nsize);
    
    editor.setBuffer(nsize);
}

// read at current position
void read()
{
    editor.seek(editor.position);
    if (editor.err) panic;
    
    version (Trace) trace("editor.position=%u", editor.position);
    
    readdata = editor.read();
    if (editor.err) panic;
    
    version (Trace) trace("readdata.length=%u", readdata.length);
}

//TODO: Consider render with multiple parameters to select what to render

/// Render screen (all elements)
void renderAll()
{
    version (Trace) trace;
    
    updateOffset;
    updateContent;
    updateStatus;
}
void render()
{
    version (Trace) trace;
    
    updateContent;
    updateStatus;
}
void readRender()
{
    read;
    render;
}

void updateOffset()
{
    screen.cursorOffset;
    screen.renderOffset;
}

void updateContent()
{
    screen.cursorContent; // Set pos for rendering
    const int rows = screen.output(
        editor.position, readdata,
        editor.cursor.position);
    
    if (rows < 0)
    {
        message("Something bad happened");
        return;
    }
    
    screen.renderEmpty(rows);
}

void updateStatus()
{
    import std.format : format;
    
    long pos = editor.cursorTell;
    char[12] offset = void;
    size_t l = screen.offsetFormatter.offset(offset.ptr, pos);
    
    screen.cursorStatusbar;
    screen.renderStatusBar(
        editor.editModeString,
        screen.binaryFormatter.name,
        transcoder.name,
        formatBin(editor.readSize, setting.si),
        offset[0..l],
        format("%f%%",
            ((cast(double)pos) / editor.fileSize) * 100));
}

void updateCursor()
{
    version (Trace)
        with (editor.cursor)
            trace("pos=%u n=%u", position, nibble);
    
    //with (editor.cursor)
    //    screen.cursor(position, nibble);
}

/// Refresh the entire screen by:
/// 1. Clearing the terminal
/// 2. Automatically resizing the view buffer
/// 3. Re-seeking to the current position (failsafe)
/// 4. Read buffer
/// 5. Render
void refresh()
{
    version (Trace) trace;
    
    screen.clear;
    initiate;
    read;
    updateOffset;
    render;
    updateCursor;
}

/// Seek to position in data, reads view's worth, and display that.
/// Ignores bounds checking for performance reasons.
/// Sets CurrentPosition.
/// Params: pos = New position
void seek(long pos)
{
    version (Trace) trace("pos=%d", pos);
    
    if (editor.readSize >= editor.fileSize)
    {
        screen.message("Navigation disabled, file too small");
        return;
    }
    
    //TODO: cursorTo
    editor.seek(pos);
    readRender;
}

/// Parses the string as a long and navigates to the file location.
/// Includes offset checking (+/- notation).
/// Params: str = String as a number
void seek(string str)
{
    version (Trace) trace("str=%s", str);
    
    const char seekmode = str[0];
    if (seekmode == '+' || seekmode == '-') // relative input.position
    {
        str = str[1..$];
    }
    long newPos = void;
    if (convertToVal(newPos, str))
    {
        screen.message("Could not parse number");
        return;
    }
    switch (seekmode) {
    case '+': // Relative, add
        safeSeek(editor.position + newPos);
        break;
    case '-': // Relative, substract
        safeSeek(editor.position - newPos);
        break;
    default: // Absolute
        if (newPos < 0)
        {
            screen.message("Range underflow: %d (0x%x)", newPos, newPos);
        }
        else if (newPos >= editor.fileSize - editor.readSize)
        {
            screen.message("Range overflow: %d (0x%x)", newPos, newPos);
        }
        else
        {
            seek(newPos);
        }
    }
}

/// Goes to the specified position in the file.
/// Checks bounds and calls Goto.
/// Params: pos = New position
void safeSeek(long pos)
{
    version (Trace) trace("pos=%s", pos);
    
    long fsize = editor.fileSize;
    
    if (pos + editor.readSize >= fsize)
        pos = fsize - editor.readSize;
    else if (pos < 0)
        pos = 0;
    
    editor.cursorGoto(pos);
}

enum LAST_BUFFER_SIZE = 128;
__gshared ubyte[LAST_BUFFER_SIZE] lastItem;
__gshared size_t lastSize;
__gshared string lastType;
__gshared bool lastForward;
__gshared bool lastAvailable;

/// Search last item.
/// Returns: Error code if set.
//TODO: I don't think the return code is ever used...
int next()
{
    if (lastAvailable == false)
    {
        return errorSet(ErrorCode.noLastItem);
    }
    
    long pos = void;
    int e = searchData(pos, lastItem.ptr, lastSize, lastForward);
    
    if (e)
    {
        screen.message("Not found");
        return e;
    }
    
    safeSeek(pos);
    //TODO: Format position found with current offset type
    screen.message("Found at 0x%x", pos);
    return 0;
}

// Search data
int lookup(string type, string data, bool forward, bool save)
{
    void *p = void;
    size_t len = void;
    if (convertToRaw(p, len, data, type))
        return error.errorcode;
    
    if (save)
    {
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
    int e = searchData(pos, p, len, forward);
    
    if (e)
    {
        screen.message("Not found");
        return e;
    }
    
    safeSeek(pos);
    //TODO: Format position found with current offset type
    screen.message("Found at 0x%x", pos);
    return 0;
}

int skip(ubyte data)
{
    screen.message("Skipping all 0x%x...", data);
    
    long pos = void;
    const int e = searchSkip(data, pos);
    
    if (e)
    {
        screen.message("End of file reached");
        return e;
    }
    
    safeSeek(pos);
    //TODO: Format position found with current offset type
    screen.message("Found at 0x%x", pos);
    return 0;
}

/// Print file information
void printFileInfo()
{
    screen.message("%11s  %s",
        formatBin(editor.fileSize, setting.si),
        editor.fileName);
}

/// Exit the interactive ddhx session.
/// Params: code = Exit code.
deprecated("Use exit or panic")
void exit(int code)
{
    import core.stdc.stdlib : exit;
    version (Trace) trace("code=%u", code);
    exit(code);
}


void exit()
{
    import core.stdc.stdlib : exit;
    version (Trace) trace();
    exit(0);
}

void panic()
{
    import std.stdio : stderr;
    import core.stdc.stdlib : exit;
    version (Trace) trace("code=%u", errorcode);
    
    stderr.writeln("error: (", errorcode, ") ", errorMessage(errorcode));
    
    exit(errorcode);
}