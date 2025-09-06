/// Interactive hex editor application.
///
/// Defines behavior for main program.
/// 
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx;

import configuration;
import document;
import editor;
import logger;
import os.terminal;
import std.format;
import std.range;
import std.stdio;
import std.string;
import transcoder;

// TODO: Find a way to dump session data to be able to resume later
//       Session/project whatever

private debug enum DEBUG = "+debug"; else enum DEBUG = "";

/// Copyright string
immutable string DDHX_COPYRIGHT = "Copyright (c) 2017-2025 dd86k <dd@dax.moe>";
/// App version
immutable string DDHX_VERSION   = "0.5.0-alpha.2"~DEBUG;
/// Build information
immutable string DDHX_BUILDINFO = "Built: "~__TIMESTAMP__;

private enum // Internal editor status flags
{
    // Update the current view
    UVIEW       = 1 << 1,
    // Update the header
    UHEADER     = 1 << 2,
    // Update statusbar
    USTATUSBAR  = 1 << 3,
    
    // Pending message
    UMESSAGE    = 1 << 16,
    // Editing in progress
    UEDITING    = 1 << 17,
    
    //
    UINIT = UHEADER | UVIEW | USTATUSBAR,
}

private enum PanelType
{
    data,
    text,
}

/// Editor session.
//
// Because Editor mostly exists for ddhx (editor) and RC can be manually
// handled elsewhere.
struct Session
{
    /// Runtime configuration.
    RC rc;
    
    /// 
    Editor editor;
    
    /// Logical position at the start of the view.
    long position_view;
    /// Logical position of the cursor in the editor.
    long position_cursor;
    /// Currently focused panel.
    PanelType panel;
    
    /// Target file.
    string target;
}

private __gshared // globals have the ugly "g_" prefix to be told apart
{
    // Editor status
    int _estatus;
    // Updated at render
    int _erows;
    
    // HACK: Global for screen resize events
    Session *g_session;
    
    string _emessagebuf;
    
    // TODO: Should be turned into a "reader" (struct+function)
    //       Allows additional unittests and settings (e.g., RTL).
    // location where edit started
    long _editcurpos;
    // position of digit for edit, starting at most-significant digit
    size_t _editdigit;
    // 
    ubyte[8] _editbuf;
    
    /// Registered commands
    void function(Session*, string[])[string] _ecommands;
    /// Mapped keys to commands
    void function(Session*, string[])[int] _ekeys;
}

// TODO: void startddhx(Editor editor, RC *rc, string path, string initmsg)

// start editor
void startddhx(string path, RC rc)
{
    _estatus = UINIT; // init here since message could be called later
    
    g_session = new Session(rc);
    Editor editor = g_session.editor = new Editor();
    
    switch (path) {
    case null:
        message("new buffer");
        break;
    case "-": // MemoryDocument
        throw new Exception("TODO: Support streams.");
    default:
        import std.file : exists;
        import std.path : baseName;
        
        // path is either null (no suggested name) or set to a path
        // if path doesn't exist, Editor.save(string) will simply create it
        g_session.target = path;
        
        if (path && exists(path))
        {
            bool readonly = rc.writemode == WritingMode.readonly;
            editor.attach(new FileDocument(path, readonly));
            
            message(baseName(path));
        }
        else if (path)
        {
            message("(new file)");
        }
        else // new buffer
        {
            message("(new buffer)");
        }
    }
    
    // TODO: ^C handler
    terminalInit(TermFeat.altScreen | TermFeat.inputSys);
    // NOTE: This works with exceptions (vs. atexit(3))
    //       Called before exception handler is called (tested on linux)
    terminalOnResize(&onresize);
    terminalHideCursor();
    
    // Setup default commands and shortcuts
    _ekeys[Key.LeftArrow]   = _ecommands["cursor-left"]         = &move_left;
    _ekeys[Key.RightArrow]  = _ecommands["cursor-right"]        = &move_right;
    _ekeys[Key.UpArrow]     = _ecommands["cursor-up"]           = &move_up;
    _ekeys[Key.DownArrow]   = _ecommands["cursor-down"]         = &move_down;
    _ekeys[Key.PageUp]      = _ecommands["cursor-page-up"]      = &move_pg_up;
    _ekeys[Key.PageDown]    = _ecommands["cursor-page-down"]    = &move_pg_down;
    _ekeys[Key.Home]        = _ecommands["cursor-line-start"]   = &move_ln_start;
    _ekeys[Key.End]         = _ecommands["cursor-line-end"]     = &move_ln_end;
    _ekeys[Mod.ctrl|Key.Home] = _ecommands["cursor-sof"]        = &move_abs_start;
    _ekeys[Mod.ctrl|Key.End ] = _ecommands["cursor-eof"]        = &move_abs_end;
    _ekeys[Key.Q]           = _ecommands["quit"]                = &quit;
    _ekeys[Key.Tab]         = _ecommands["change-panel"]        = &change_panel;
    _ekeys[Key.Insert]      = _ecommands["change-writemode"]    = &change_writemode;
    _ekeys[Mod.ctrl|Key.S]  = _ecommands["save"]                = &save;
    _ekeys[Mod.ctrl|Key.U]  = _ecommands["undo"]                = &undo;
    _ekeys[Mod.ctrl|Key.R]  = _ecommands["redo"]                = &redo;
    _ekeys[Mod.ctrl|Key.G]  = _ecommands["goto"]                = &goto_;
    _ecommands["set"] = &set;
    
    // Special keybinds with no attached commands
    _ekeys[Key.Enter] = &prompt_command;
    //_ekeys['/'] = &prompt_frwd_search;
    //_ekeys['&'] = &prompt_back_search;
    
    loop(g_session);
    
    terminalRestore();
}

private:

// 
void loop(Session *session)
{
Lupdate:
    update(session);
    
Lread:
    TermInput input = terminalRead();
    switch (input.type) {
    case InputType.keyDown:
        // Key mapped to command
        auto fn = input.key in _ekeys;
        if (fn)
        {
            log("key=%s (%d)", input.key, input.key);
            try (*fn)(session, null);
            catch (IgnoreException) {}
            catch (Exception ex)
            {
                log("%s", ex);
                message(ex.msg);
            }
            goto Lupdate;
        }
        
        // Check if key is for data input.
        // Otherwise, ignore key.
        int kv = void;
        switch (session.panel) {
        case PanelType.data:
            // If the key input doesn't match the current data or text type, ignore
            // Should be at most 0-9, a-f, and A-F.
            kv = keydata(session.rc.data_type, input.key);
            if (kv < 0) // not a data input, so don't do anything
                goto Lread;
            break;
        default:
            message("Edit unsupported in panel: %s", session.panel);
            goto Lupdate;
        }
        
        // Check if the writing mode is valid
        final switch (session.rc.writemode) {
        case WritingMode.readonly:
            message("Can't edit in read-only mode");
            goto Lupdate;
        case WritingMode.insert: // temp for msg
            message("TODO: Insert mode");
            goto Lupdate;
        case WritingMode.overwrite:
            break;
        }
        
        if (_editdigit == 0) // start new edit
        {
            _editcurpos = session.position_cursor;
            import core.stdc.string : memset;
            memset(_editbuf.ptr, 0, _editbuf.length);
        }
        
        _estatus |= UEDITING;
        shfdata(_editbuf.ptr, _editbuf.length, session.rc.data_type, kv, _editdigit++);
        
        DataSpec spec = dataSpec(session.rc.data_type);
        int chars = spec.spacing;
        
        // If entered an edit fully or cursor position changed,
        // add edit into history stack
        if (_editdigit >= chars)
        {
            // TODO: multi-byte edits
            g_session.editor.overwrite(_editcurpos, _editbuf.ptr, ubyte.sizeof);
            _editdigit = 0;
            move_right(g_session, null);
        }
        break;
    default:
        goto Lread;
    }
    
    goto Lupdate;
}

void onresize()
{
    update(g_session);
}

// Invoke command prompt
string promptline(string text)
{
    assert(text, "Prompt text missing");
    assert(text.length, "Prompt text required"); // disallow empty
    
    _estatus |= UHEADER; // Needs to be repainted anyway
    
    // Clear upper space
    TerminalSize tsize = terminalSize();
    int tcols = tsize.columns - 1;
    if (tcols < 10)
        throw new Exception("Not enough space for prompt");
    
    // Clear upper space
    terminalCursor(0, 0);
    terminalWriteChar(' ', tcols);
    
    // Print prompt, cursor will be after prompt
    terminalCursor(0, 0);
    terminalWrite(text);
    
    // Read line
    terminalPauseInput();
    terminalShowCursor();
    import std.string : chomp;
    string line = chomp(readln());
    terminalHideCursor();
    terminalResumeInput();
    
    // Force update view if prompt+line overflows to view,
    // since we're currently reading lines at the top of screen
    if (text.length + line.length >= tcols)
        _estatus |= UVIEW;
    
    return line;
}
int promptkey(string text)
{
    assert(text, "Prompt text missing");
    assert(text.length, "Prompt text required"); // disallow empty
    
    _estatus |= UHEADER; // Needs to be repainted anyway
    
    // Clear upper space
    TerminalSize tsize = terminalSize();
    int tcols = tsize.columns - 1;
    if (tcols < 10)
        throw new Exception("Not enough space for prompt");
    
    // Clear upper space
    terminalCursor(0, 0);
    for (int x; x < tcols; ++x)
        terminalWrite(" ");
    
    // Print prompt, cursor will be after prompt
    terminalCursor(0, 0);
    terminalWrite(text);
    
    // Read character
    terminalShowCursor();
Lread:
    TermInput input = terminalRead();
    if (input.type != InputType.keyDown)
        goto Lread;
    terminalHideCursor();
    
    return input.key;
}

// Given the data type (hex, dec, oct) return the value
// of the keychar to a digit/nibble.
//
// For example, 'a' will return 0xa, and 'r' will return -1, an error.
int keydata(DataType type, int keychar) @safe
{
    switch (type) with (DataType) {
    case x8:
        if (keychar >= '0' && keychar <= '9')
            return keychar - '0';
        if (keychar >= 'A' && keychar <= 'F')
            return (keychar - 'A') + 10;
        if (keychar >= 'a' && keychar <= 'f')
            return (keychar - 'a') + 10;
        break;
    /*
    case dec:
        if (keychar >= '0' && keychar <= '9')
            return keychar - '0';
        break;
    */
    /*
    case oct:
        if (keychar >= '0' && keychar <= '7')
            return keychar - '0';
        break;
    */
    default:
    }
    return -1;
}
@safe unittest
{
    assert(keydata(DataType.x8, 'a') == 0xa);
    assert(keydata(DataType.x8, 'b') == 0xb);
    assert(keydata(DataType.x8, 'A') == 0xa);
    assert(keydata(DataType.x8, 'B') == 0xb);
    assert(keydata(DataType.x8, '0') == 0);
    assert(keydata(DataType.x8, '3') == 3);
    assert(keydata(DataType.x8, '9') == 9);
    assert(keydata(DataType.x8, 'j') < 0);
    
    /*
    assert(keydata(DataType.d8, '0') == 0);
    assert(keydata(DataType.d8, '1') == 1);
    assert(keydata(DataType.d8, '9') == 9);
    assert(keydata(DataType.d8, 't') < 0);
    assert(keydata(DataType.d8, 'a') < 0);
    assert(keydata(DataType.d8, 'A') < 0);
    */
    /*
    assert(keydata(DataType.o8, '0') == 0);
    assert(keydata(DataType.o8, '1') == 1);
    assert(keydata(DataType.o8, '7') == 7);
    assert(keydata(DataType.o8, '9') < 0);
    assert(keydata(DataType.o8, 'a') < 0);
    assert(keydata(DataType.o8, 'L') < 0);
    */
}

void shfdata(void *b, size_t len, DataType t, int d, size_t digit)
{
    enum XSHIFT = 4;  // << 4
    enum DSHIFT = 10; // * 10
    enum OSHIFT = 8;  // * 8
    size_t space;
    switch (t) {
    case DataType.x8:
        space = 2;
    //Lxshift:
        // from current number of digits entered to digit position
        size_t p = ((2 - 1) - digit);
        *cast(ubyte*)b |= d << (XSHIFT * p);
        break;
    default:
        throw new Exception("TODO");
    }
}
unittest
{
    ubyte[8] b;
    long* s64 = cast(long*)b.ptr;
    shfdata(b.ptr, b.length, DataType.x8, 1,   0);
    assert(*s64 == 0x10);
    shfdata(b.ptr, b.length, DataType.x8, 0xf, 1);
    assert(*s64 == 0x1f);
}

// Move the cursor relative to its position within the file
void moverel(Session *session, long pos)
{
    moveabs(session, session.position_cursor + pos);
}

// Move the cursor to an absolute file position
void moveabs(Session *session, long pos)
{
    // If the cursor position changed while editing... Just save the edit.
    // Both _editdigit and _editcurpos are set by the editor reliably.
    if (_editdigit && _editcurpos != pos)
    {
        _editdigit = 0;
        session.editor.overwrite(_editcurpos, _editbuf.ptr, ubyte.sizeof);
    }
    
    // Can't go beyond file
    if (pos < 0)
        pos = 0;
    // No need to update if it's at the same place
    if (pos == session.position_cursor)
        return;
    
    session.position_cursor = pos;
    _estatus |= UVIEW | USTATUSBAR;
}

// Send a message within the editor to be displayed.
void message(A...)(string fmt, A args)
{
    // TODO: Handle multiple messages.
    //       It COULD happen that multiple messages are sent before they
    //       are displayed. Right now, only the last message is taken into
    //       account.
    //       Easiest fix would be string[] or something similar.
    
    try
    {
        _emessagebuf = format(fmt, args);
        _estatus |= UMESSAGE;
    }
    catch (Exception ex)
    {
        log("%s", ex);
        message("internal: %s", ex.msg);
    }
}

// Render header bar on screen
void update_header(Session *session, TerminalSize termsize)
{
    terminalCursor(0, 0);
    
    // Print spacers and current address type
    string atype = addressTypeToString(session.rc.address_type);
    int prespaces = session.rc.address_spacing - cast(int)atype.length;
    size_t l = terminalWriteChar(' ', prespaces); // Print x spaces before address type
    l += terminalWrite(atype, " "); // print address type + spacer
    
    int cols = session.rc.columns;
    int cwidth = dataSpec(session.rc.data_type).spacing; // data width spec (for alignment with col headers)
    char[32] buf = void;
    for (int col; col < cols; ++col)
    {
        string chdr = formatAddress(buf[], col, cwidth, session.rc.address_type);
        l += terminalWrite(" ", chdr); // spacer + column header
    }
    
    // Fill rest of upper bar with spaces
    int rem = termsize.columns - cast(int)l - 1;
    if (rem > 0)
        terminalWriteChar(' ', rem);
}

// Render view with data on screen
void update_view(Session *session, TerminalSize termsize)
{
    if (termsize.rows < 4)
        return;
    
    int cols        = session.rc.columns;
    int rows        = _erows = termsize.rows - 2;
    int count       = rows * cols;
    long curpos     = session.position_cursor;
    long basepos    = session.position_view;
    long docsize    = session.editor.currentSize();
    
    // Cursor is past EOF
    if (curpos > docsize)
        curpos = docsize;
    
    // Adjust base (camera/view) positon, which is the position we read at.
    if (curpos < basepos) // cursor is behind
    {
        while (curpos < basepos)
        {
            basepos -= cols;
            if (basepos < 0)
            {
                basepos = 0;
                break;
            }
        }
    }
    else if (curpos >= basepos + count) // cursor is ahead
    {
        // Catch up to cursor
        while (curpos >= basepos + count)
        {
            basepos += cols;
        }
    }
    
    // Read data
    // TODO: To avoid unecessary I/O, avoid calling .view() when:
    //       - position is the same as the last call
    //       - count is the same as the last call
    //       - no edits have been made (+ undo/redo)
    //       Could rely on UVIEW status
    // NOTE: scope T[] allocations does nothing
    //       This is a non-issue since the conservative GC will keep the
    //       allocation alive and simply resize it (either pool or realloc).
    // NOTE: new T[x] calls memset(3), wasting some cpu time
    __gshared ubyte[] viewbuf;
    if (viewbuf.length != count)
        viewbuf.length = count;
    ubyte[] result = session.editor.view(basepos, viewbuf);
    int reslen     = cast(int)result.length; // * bytesize
    
    // Update positions
    session.position_cursor = curpos;
    session.position_view   = basepos;
    
    // Render view
    char[32] txtbuf = void;
    long address    = basepos;
    int viewpos     = cast(int)(curpos - address); // relative cursor position in view
    int datawidth   = dataSpec(session.rc.data_type).spacing; // data element width
    int addspacing  = session.rc.address_spacing;
    PanelType panel = session.panel;
    DataFormatter dfmt = DataFormatter(session.rc.data_type, result.ptr, result.length);
    log("address=%d viewpos=%d cols=%d datawidth=%d count=%d reslen=%d",
        address, viewpos, cols, datawidth, count, reslen);
    terminalCursor(0, 1);
    for (int row; row < rows; ++row, address += cols)
    {
        // '\n' could count as a character, avoid using it
        terminalCursor(0, row + 1);
        
        string addr = formatAddress(txtbuf[], address, addspacing, session.rc.address_type);
        size_t w = terminalWrite(addr, " "); // row address + spacer
        
        // Render view data
        for (int col; col < cols; ++col)
        {
            int i = (row * cols) + col;
            
            bool highlight = i == viewpos && panel == PanelType.data;
            
            w += terminalWrite(" "); // data-data spacer
            
            if (highlight) terminalInvertColor();
            
            if (_editdigit && highlight) // apply current edit at position
            {
                dfmt.skip();
                
                string s = formatData(txtbuf[], _editbuf.ptr, _editbuf.length, session.rc.data_type);
                w += terminalWrite(s);
            }
            else if (i < reslen) // apply data
            {
                string s = dfmt.formatdata();
                w += terminalWrite(s);
            }
            else // no data, print spacer
            {
                w += terminalWriteChar(' ', datawidth);
            }
            
            if (highlight) terminalResetColor();
        }
        
        // data-text spacer
        w += terminalWrite("  ");
        
        // Render character data
        for (int col; col < cols; ++col)
        {
            int i = (row * cols) + col;
            
            bool highlight = i == viewpos && panel == PanelType.text;
            
            if (highlight) terminalInvertColor();
            
            if (i >= reslen) // unavail
            {
                w += terminalWrite(" ");
            }
            else
            {
                // NOTE: Escape codes do not seem to be a worry with tests
                string c = transcode(result[i], session.rc.charset);
                w += terminalWrite(c ? c : ".");
            }
            
            if (highlight) terminalResetColor();
        }
        
        // Fill rest of spaces
        int f = termsize.columns - cast(int)w;
        if (f > 0)
            terminalWriteChar(' ', f);
    }
}

// Render status bar on screen
void update_status(Session *session, TerminalSize termsize)
{
    terminalCursor(0, termsize.rows - 1);
    
    // Typical session are 80/120 columns.
    // A fullscreen terminal window (1080p, 10pt) is around 240x54.
    // If crashes, at this point, fuck it just use a heap buffer starting at 4K.
    char[512] statusbuf = void;
    
    // If there is a pending message, print that.
    // Otherwise, print status bar using the message buffer space.
    string msg = void;
    if (_estatus & UMESSAGE)
    {
        msg = _emessagebuf;
    }
    else
    {
        char[32] curbuf = void; // cursor address
        string curstr = formatAddress(curbuf, session.position_cursor, 8, session.rc.address_type);
        
        msg = cast(string)sformat(statusbuf, "%c %s | %3s | %8s | %s",
            session.editor.edited() ? '*' : ' ',
            writingModeToString(session.rc.writemode),
            dataTypeToString(session.rc.data_type),
            charsetID(session.rc.charset),
            curstr);
        
    }
    
    // Attempt to fit the new message on screen
    int msglen = cast(int)msg.length;
    int cols = termsize.columns - 1;
    if (msglen >= cols) // message does not fit on screen
    {
        // TODO: Attempt to "scroll" message
        //       Loop keypresses to continue?
        //       Might include " >" to signal continuation
        import std.algorithm.comparison : min;
        size_t e = min(cols, msg.length);
        terminalWrite(msg[0..e]);
    }
    else // message fits on screen
    {
        import core.stdc.string : memset;
        
        terminalWrite(msg.ptr, msglen);
        
        // Pad to end of screen with spaces
        int rem = cols - msglen;
        if (rem > 0)
            terminalWriteChar(' ', rem);
    }
}

// Update all elements on screen depending on editor information
// status global indicates what needs to be updated
void update(Session *session)
{
    // NOTE: Right now, everything is updated unconditionally
    //       It's pointless to micro-optimize rendering processes while everything is WIP
    TerminalSize termsize = terminalSize();
    
    // Number of effective rows for data view
    _erows = termsize.rows - 2;
    
    update_header(session, termsize);
    
    update_view(session, termsize);
    
    update_status(session, termsize);
    
    _estatus = 0;
}

//
// ANCHOR Commands
//

// Run command
void prompt_command(Session *session, string[] args)
{
    import utils : arguments;
    
    string line = promptline(">");
    if (line.length == 0)
        return;
    
    string[] argv = arguments(line);
    if (argv.length == 0)
        return;
    
    log("command='%s'", argv);
    string argv0 = argv[0];
    argv = argv.length > 1 ? argv[1..$] : null;
    
    // Command
    const(void function(Session*, string[])) *com = argv0 in _ecommands;
    if (com)
    {
        try (*com)(session, argv);
        catch (IgnoreException) {}
        catch (Exception ex)
        {
            log("%s", ex);
            message(ex.msg);
        }
    }
    else
    {
        message("command not found: '%s'", argv0);
    }
}

// Move back a single item
void move_left(Session *session, string[] args)
{
    if (session.position_cursor == 0)
        return;
    
    moverel(session, -1);
}
// Move forward a single item
void move_right(Session *session, string[] args)
{
    moverel(session, +1);
}
// Move back a row
void move_up(Session *session, string[] args)
{
    if (session.position_cursor == 0)
        return;
    
    moverel(session, -session.rc.columns);
}
// Move forward a row
void move_down(Session *session, string[] args)
{
    moverel(session, +session.rc.columns);
}
// Move back a page
void move_pg_up(Session *session, string[] args)
{
    if (session.position_cursor == 0)
        return;
    
    moverel(session, -(_erows * session.rc.columns));
}
// Move forward a page
void move_pg_down(Session *session, string[] args)
{
    moverel(session, +(_erows * session.rc.columns));
}
// Move to start of line
void move_ln_start(Session *session, string[] args) // move to start of line
{
    moverel(session, -(session.position_cursor % session.rc.columns));
}
// Move to end of line
void move_ln_end(Session *session, string[] args) // move to end of line
{
    moverel(session, +(session.rc.columns - (session.position_cursor % session.rc.columns)) - 1);
}
// Move to absolute start of document
void move_abs_start(Session *session, string[] args)
{
    moveabs(session, 0);
}
// Move to absolute end of document
void move_abs_end(Session *session, string[] args)
{
    moveabs(session, session.editor.currentSize());
}

// Change writing mode
void change_writemode(Session *session, string[] args)
{
    final switch (session.rc.writemode) {
    case WritingMode.readonly: // Can't switch from read-only
        throw new Exception("Can't edit in read-only");
    case WritingMode.insert:
        session.rc.writemode = WritingMode.overwrite;
        break;
    case WritingMode.overwrite:
        session.rc.writemode = WritingMode.insert;
        break;
    }
    _estatus |= USTATUSBAR;
}

// Change active panel
void change_panel(Session *session, string[] args)
{
    session.panel++;
    if (session.panel >= PanelType.max + 1)
        session.panel = PanelType.init;
}

// 
void undo(Session *session, string[] args)
{
    import patcher : Patch;
    Patch patch = session.editor.undo();
    
    moveabs(session, patch.address);
}

// 
void redo(Session *session, string[] args)
{
    import patcher : Patch;
    Patch patch = session.editor.redo();

    moveabs(session, patch.address + patch.size);
}

// 
void goto_(Session *session, string[] args)
{
    import utils : scan;
    
    string off = void;
    if (args is null || args.length < 1)
        off = promptline("offset: ");
    else
        off = args[0];
    
    // Assume canceled
    if (off.length == 0)
        return;
    
    // Keywords
    switch (off) {
    case "end", "eof":   move_abs_end(session, null); return;
    case "start", "sof": move_abs_start(session, null); return;
    default:
    }
    
    // Number
    switch (off[0]) {
    case '+':
        if (off.length <= 1)
            throw new Exception("Incomplete number");
        
        moverel(session, scan(off[1..$]));
        break;
    case '-':
        if (off.length <= 1)
            throw new Exception("Incomplete number");
        
        moverel(session, -scan(off[1..$]));
        break;
    default:
        moveabs(session, scan(off));
    }
}

// Save changes
void save(Session *session, string[] args)
{
    // No known path... Ask for one!
    if (session.target is null)
    {
        // Ask for a filename
        string target = promptline("Name: ");
        if (target.length == 0)
        {
            throw new Exception("Canceled");
        }
        
        // Check if target exists to ask for overwrite
        import std.file : exists;
        if (exists(target))
        {
            // NOTE: Don't explicitly check if directory exists.
            //       The filesystem will report the error anyway.
            switch (promptkey("Overwrite? (Y/N) ")) {
            case 'y', 'Y': // Continue
                break;
            default:
                throw new Exception("Canceled");
            }
        }
        
        session.target = target;
    }
    
    log("target='%s'", session.target);
    
    // Force updating the status bar to indicate that we're currently saving.
    // It might take a while with the current implementation.
    message("Saving...");
    update_status(session, terminalSize());
    
    // On error, an exception is thrown, where the command handler receives,
    // and displays its message.
    session.editor.save(session.target);
    message("Saved");
}

void set(Session *session, string[] args)
{
    string setting = void;
    if (args is null || args.length < 1)
        setting = promptline("setting: ");
    else
        setting = args[0];
    
    string value = void;
    if (args is null || args.length < 2)
        value = promptline("value: ");
    else
        value = args[1];
    
    configRC(session.rc, setting, value);
}

void quit(Session *session, string[] args)
{
    if (session.editor.edited())
    {
        switch (promptkey("Save? (Y/N) ")) {
        case 'n', 'N':
            goto Lexit; // quit without saving
        case 'y', 'Y':
            save(session, null); // save and continue to quit
            break;
        default:
            throw new Exception("Canceled");
        }
    }
    
Lexit:
    import core.stdc.stdlib : exit;
    terminalRestore();
    exit(0);
}