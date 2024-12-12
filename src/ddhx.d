/// Interactive hex editor application.
///
/// Defines behavior for main program.
/// 
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx;

import std.stdio;
import std.string;
import std.range;
import std.format;
import configuration;
import session;
import transcoder;
import terminal;
import tracer;

/// Copyright string
immutable string DDHX_COPYRIGHT = "Copyright (c) 2017-2025 dd86k <dd@dax.moe>";
/// App version
immutable string DDHX_VERSION   = "0.5.0";
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

/// Number of characters a row address will take
private enum ROW_WIDTH = 11; // temporary until added to RC/Session

private __gshared // globals have the ugly "_e" prefix to be told apart
{
    // Editor status
    int _estatus;
    // Updated at render
    int _erows;
    
    char[1024] _emessage;
    size_t _emessagelen;
    
    // TODO: Should be turned into a struct.
    //       Allows additional unittests and settings (e.g., RTL).
    // location where edit started
    long _editcurpos;
    // position of digit for edit, starting at most-significant digit
    size_t _editdigit;
    // 
    ubyte[8] _editbuf;
    
    /// HACK: Currently used session (for screen resize)
    Session _esession;
    
    /// Registered commands
    void function(Session)[string] _ecommands;
    /// Mapped keys to commands
    void function(Session)[int] _ekeys;
}

static assert(_emessage.length >= 32, "Message buffer is really too short");

// start editor
void startddhx(string path, RC rc)
{
    _estatus = UINIT; // init here since message could be called later
    
    // TODO: Load config from RC
    //       Should be in ctor, for consistency
    //       Editor can reject settings (via exception)
    Session session  = new Session();
    session.columns = 16;
    
    switch (path) {
    case null:
        message("new buffer");
        break;
    case "-": // MemoryDocument
        throw new Exception("TODO: Support streams.");
    default:
        import std.file : exists;
        import std.path : baseName;
        
        if (path && exists(path))
        {
            session.openFile(path, rc.readonly);
            message(baseName(path));
        }
        else // new buffer
        {
            // path is either null (no suggested name) or set to a path
            session.target = path;
            message("new buffer");
        }
    }
    
    // TODO: ^C handler
    terminalInit(TermFeat.altScreen | TermFeat.inputSys);
    // NOTE: This works with exceptions (vs. atexit(3))
    //       Called before exception handler is called (tested on linux)
    scope(exit) terminalRestore();
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
    _ekeys[Key.Tab]         = _ecommands["change-panel"]        = &change_writemode;
    _ekeys[Key.Insert]      = _ecommands["change-writemode"]    = &change_panel;
    _ekeys[Mod.ctrl|Key.S]  = _ecommands["save"]                = &save;
    _ekeys[Mod.ctrl|Key.Z]  = _ecommands["undo"]                = &undo;
    _ekeys[Mod.ctrl|Key.Y]  = _ecommands["redo"]                = &redo;
    
    loop(session); // use this editor
}

private:

// 
void loop(Session session)
{
    _esession = session; // save currently used editor due to resize function
    
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
            try (*fn)(session);
            catch (Exception ex)
            {
                message(ex.msg);
                trace("%s", ex);
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
            kv = keydata(session.datatype, input.key);
            if (kv < 0) // not a data input, so don't do anything
                goto Lread;
            break;
        default:
            message("Edit unsupported in panel: %s", session.panel);
            goto Lupdate;
        }
        
        // Check if the writing mode is valid
        final switch (session.writingmode) {
        // Can't edit while document was opened read-only
        case WritingMode.readonly:
            message("Can't edit in read-only mode");
            goto Lupdate;
        // Temporary since I don't yet support insertions
        case WritingMode.insert:
            message("TODO: Insert mode");
            goto Lupdate;
        case WritingMode.overwrite:
            break;
        }
        
        if (_editdigit == 0) // start new edit
        {
            _editcurpos = session.curpos;
            import core.stdc.string : memset;
            memset(_editbuf.ptr, 0, _editbuf.length);
        }
        
        _estatus |= UEDITING;
        shfdata(_editbuf.ptr, _editbuf.length, session.datatype, kv, _editdigit++);
        
        DataSpec spec = dataSpec(session.datatype);
        int chars = spec.spacing;
        
        // If entered an edit fully or cursor position changed,
        // add edit into history stack
        if (_editdigit >= chars)
        {
            session.historyAdd(_editcurpos, _editbuf.ptr, ubyte.sizeof);
            _editdigit = 0;
            move_right(session);
        }
        break;
    default:
        goto Lread;
    }
    
    goto Lupdate;
}

void onresize()
{
    update(_esession);
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
    for (int x; x < tcols; ++x)
        terminalWrite(" ");
    
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
void moverel(Session session, long pos)
{
    moveabs(session, session.curpos + pos);
}

// Move the cursor to an absolute file position
void moveabs(Session session, long pos)
{
    // If the cursor position changed while editing... Just save the edit.
    // Both _editdigit and _editcurpos are set by the editor reliably.
    if (_editdigit && _editcurpos != pos)
    {
        _editdigit = 0;
        session.historyAdd(_editcurpos, _editbuf.ptr, ubyte.sizeof);
    }
    
    // Can't go beyond file
    if (pos < 0)
        pos = 0;
    // No need to update if it's at the same place
    if (pos == session.curpos)
        return;
    
    session.curpos = pos;
    _estatus |= UVIEW | USTATUSBAR;
}

//
// Commands
//

// Move back a single item
void move_left(Session session)
{
    if (session.curpos == 0)
        return;
    
    moverel(session, -1);
}
// Move forward a single item
void move_right(Session session)
{
    moverel(session, +1);
}
// Move back a row
void move_up(Session session)
{
    if (session.curpos == 0)
        return;
    
    moverel(session, -session.columns);
}
// Move forward a row
void move_down(Session session)
{
    moverel(session, +session.columns);
}
// Move back a page
void move_pg_up(Session session)
{
    if (session.curpos == 0)
        return;
    
    moverel(session, -(_erows * session.columns));
}
// Move forward a page
void move_pg_down(Session session)
{
    moverel(session, +(_erows * session.columns));
}
// Move to start of line
void move_ln_start(Session session) // move to start of line
{
    moverel(session, -(session.curpos % session.columns));
}
// Move to end of line
void move_ln_end(Session session) // move to end of line
{
    moverel(session, +(session.columns - (session.curpos % session.columns)) - 1);
}
// Move to absolute start of document
void move_abs_start(Session session)
{
    moveabs(session, 0);
}
// Move to absolute end of document
void move_abs_end(Session session)
{
    moveabs(session, session.currentSize());
}

// Change writing mode
void change_writemode(Session session)
{
    final switch (session.writingmode) {
    case WritingMode.readonly: // Can't switch from read-only
        throw new Exception("Can't edit in read-only");
    case WritingMode.insert:
        session.writingmode = WritingMode.overwrite;
        break;
    case WritingMode.overwrite:
        session.writingmode = WritingMode.insert;
        break;
    }
    _estatus |= USTATUSBAR;
}

// Change active panel
void change_panel(Session session)
{
    session.panel++;
    if (session.panel >= PanelType.max + 1)
        session.panel = PanelType.init;
}

// 
void undo(Session session)
{
    throw new Exception("TODO: undo");
}

// 
void redo(Session session)
{
    throw new Exception("TODO: redo");
}

// Save changes
void save(Session session)
{
    // No known path... Ask for one!
    if (session.target is null)
    {
        string name = promptline("Name: ");
        if (name.length == 0)
        {
            throw new Exception("Canceled");
        }
        
        // Names:
        // - "test": cwd + test
        // - "./test": relative, as-is
        // - "../test": relative, as-is
        // - "/test": absolute, as-is
        
        session.target = name;
    }
    
    trace("target='%s'", session.target);
    
    // Force updating the status bar to indicate that we're currently saving.
    // It might take a while since the current implementation.
    message("Saving...");
    update_status(session, terminalSize());
    
    // On error, an exception is thrown, where the command handler receives,
    // and displays its message.
    session.save();
    message("Saved");
    
    trace("saved to '%s'", session.target);
}

// Send a message within the editor to be displayed.
void message(A...)(string fmt, A args)
{
    // TODO: Handle multiple messages.
    //       It COULD happen that multiple messages are sent before they
    //       are displayed. Right now, only the last message is taken into
    //       account.
    //       Easiest fix would be Array!char[1024] or something similar.
    import core.exception : RangeError;
    try
    {
        _emessagelen = sformat(_emessage[], fmt, args).length;
        _estatus |= UMESSAGE;
    }
    // While not recommended, I don't have a choice if this occurs
    // to avoid a crash while editing.
    // Sadly, can't know the effective number of characters that
    // would have been formatted, so just send a tiny message.
    catch (RangeError ex)
    {
        trace("%s", ex);
        message("message: RangeError");
    }
    // Should only be FormatException otherwise.
    catch (Exception ex)
    {
        trace("%s", ex);
        message("internal: %s", ex.msg);
    }
}

// Render header bar on screen
void update_header(Session session, TerminalSize termsize)
{
    terminalCursor(0, 0);
    
    // Print spacers and current address type
    string atype = addressTypeToString(session.addresstype);
    int prespaces = ROW_WIDTH - cast(int)atype.length;
    assert(prespaces >= 0, "ROW_WIDTH is too short"); // causes misalignment
    size_t l = terminalWriteChar(' ', prespaces); // Print x spaces before address type
    l += terminalWrite(atype, " "); // print address type + spacer
    
    int cols = session.columns;
    int cwidth = dataSpec(session.datatype).spacing; // data width spec (for alignment with col headers)
    char[32] buf = void;
    for (int col; col < cols; ++col)
    {
        string chdr = formatAddress(buf[], col, cwidth, session.addresstype);
        l += terminalWrite(" ", chdr); // spacer + column header
    }
    
    // TODO: Fill rest of upper bar with spaces
}

// Render view with data on screen
void update_view(Session session, TerminalSize termsize)
{
    if (termsize.rows < 4)
        return;
    
    // TODO: Error if rendered estimated length >= terminal columns
    
    int rows        = _erows = termsize.rows - 2;
    int count       = rows * session.columns;
    long curpos     = session.curpos;
    long basepos    = session.basepos;
    // NOTE: Reading memory might never have an end.
    //       In that case, limit could be long.max.
    long docsize    = session.currentSize();
    
    // Cursor is past EOF
    if (curpos > docsize)
        curpos = docsize;
    
    // Adjust base (camera/view) positon, which is the position we read at.
    if (curpos < basepos) // cursor is behind
    {
        while (curpos < basepos)
        {
            basepos -= session.columns;
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
            basepos += session.columns;
        }
    }
    
    // Read data
    ubyte[] result = session.read(basepos, count);
    int realcount  = cast(int)result.length;
    
    session.curpos  = curpos;
    session.basepos = basepos;
    
    // render
    char[32] txtbuf = void;
    long address    = basepos;
    int viewpos     = cast(int)(curpos - address); // relative cursor position in view
    int cols        = session.columns;
    int datawidth   = dataSpec(session.datatype).spacing; // data element width
    DataFormatter dfmt = DataFormatter(session.datatype, result.ptr, result.length);
    terminalCursor(0, 1);
    for (int row; row < rows; ++row, address += cols)
    {
        // NOTE: Because '\n' counts as a character, it might bug out the view
        //       Besides, we control buffering as best able
        terminalCursor(0, row + 1);
        
        string addr = formatAddress(txtbuf[], address, ROW_WIDTH, session.addresstype);
        terminalWrite(addr, " "); // row address + spacer
        
        // Render view data
        for (int col; col < cols; ++col)
        {
            int i = (row * cols) + col;
            
            bool highlight = i == viewpos && session.panel == PanelType.data;
            
            terminalWrite(" "); // data-data spacer
            
            if (highlight) terminalInvertColor();
            
            if (_editdigit && highlight) // apply current edit at position
            {
                dfmt.skip();
                
                string s = formatData(txtbuf[], _editbuf.ptr, _editbuf.length, session.datatype);
                terminalWrite(s);
            }
            else if (i < realcount) // apply data
            {
                string s = dfmt.formatdata();
                terminalWrite(s);
            }
            else // no data, print spacer
            {
                terminalWriteChar(' ', datawidth);
            }
            
            if (highlight) terminalResetColor();
        }
        
        // data-text spacer
        terminalWrite("  ");
        
        // Render character data
        for (int col; col < cols; ++col)
        {
            int i = (row * cols) + col;
            
            bool highlight = i == viewpos && session.panel == PanelType.text;
            
            if (highlight) terminalInvertColor();
            
            if (i >= realcount) // unavail
            {
                terminalWrite(" ");
            }
            else
            {
                // NOTE: Escape codes do not seem to be a worry with tests
                string c = transcode(result[i], session.charset);
                terminalWrite(c ? c : ".");
            }
            
            if (highlight) terminalResetColor();
        }
    }
}

// Render status bar on screen
void update_status(Session session, TerminalSize termsize)
{
    terminalCursor(0, termsize.rows - 1);
    
    // If there is a pending message, print that.
    // Otherwise, print status bar using the message buffer space.
    string msg = void;
    if (_estatus & UMESSAGE)
    {
        // NOTE: _emessagelen is kind of checked in message()
        msg = cast(string)_emessage[0.._emessagelen];
    }
    else
    {
        char[32] curbuf = void; // cursor address
        string curstr = formatAddress(curbuf[], session.curpos, 8, session.addresstype);
        
        msg = cast(string)sformat(_emessage[], "%c %s | %3s | %8s | %s",
            session.edited ? '*' : ' ',
            writingModeToString(session.writingmode),
            dataTypeToString(session.datatype),
            charsetID(session.charset),
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
        
        // Pad to end of screen with spaces
        int rem = cols - msglen;
        if (rem > 0)
        {
            memset(_emessage.ptr + msg.length, ' ', rem);
            msglen += rem;
        }
        
        terminalWrite(msg.ptr, msglen);
    }
}

// Update all elements on screen depending on editor information
// status global indicates what needs to be updated
void update(Session session)
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

void quit(Session session)
{
    if (session.edited)
    {
        int r = promptkey("Save? (Y/N) ");
        switch (r) {
        case 'n', 'N':
            goto Lexit; // quit without saving
        case 'y', 'Y':
            save(session); // save and continue to quit
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