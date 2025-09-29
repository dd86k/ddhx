/// Interactive hex editor application.
///
/// Defines behavior for main program.
/// 
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx;

import std.stdio : readln;
import std.string;
import os.terminal;
import configuration;
import doceditor;
import logger;
import transcoder;

// TODO: Find a way to dump session data to be able to resume later
//       Session/project whatever

private debug enum DEBUG = "+debug"; else enum DEBUG = "";

/// Copyright string
immutable string DDHX_COPYRIGHT = "Copyright (c) 2017-2025 dd86k <dd@dax.moe>";
/// App version
immutable string DDHX_VERSION   = "0.5.1"~DEBUG;
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
    DocEditor editor;
    
    /// Logical position at the start of the view.
    long position_view;
    /// Logical position of the cursor in the editor.
    long position_cursor;
    /// Currently focused panel.
    PanelType panel;
    
    /// Target file.
    string target;
}

private
struct Keybind
{
    /// Function implementing command
    void function(Session*, string[]) impl;
    /// Parameters to add
    string[] parameters;
}

private __gshared // globals have the ugly "g_" prefix to be told apart
{
    // Editor status
    int g_status;
    // Updated at render
    int g_rows;
    
    // HACK: Global for screen resize events
    Session *g_session;
    
    string g_messagebuf;
    
    // TODO: Should be turned into a "reader" (struct+function)
    //       Allows additional unittests and settings (e.g., RTL).
    // location where edit started
    long g_editcurpos;
    // position of digit for edit, starting at most-significant digit
    size_t g_editdigit;
    // 
    ubyte[8] g_editbuf;
    
    /// Registered commands
    void function(Session*, string[])[string] g_commands;
    /// Registered shortcuts
    Keybind[int] g_keys;
}

/// Represents a command with a name (required), a shortcut, and a function
/// that implements it (required).
struct Command
{
    string name;        /// Command short name
    string description; /// Short description
    int key;            /// Default shortcut
    void function(Session*, string[]) impl; /// Implementation
}

// Reserved (Idea: Ctrl=Action, Alt=Alternative):
// - "find" (Ctrl+F and/or '/'): Forward find
// - "find-back" (Ctrl+B and/or '?'): Backward search
// - "find-next" (prefill with Ctrl+F): Find next instance for find
// - "find-prev" (prefill with Ctrl+F): Find next instance for find-back
// - "toggle-*" (Alt+Key): Hiding/showing panels
// - "save-settings": Save session settings into .ddhxrc
// - "insert" (Ctrl+I): Insert data (generic, might redirect to other commands?)
// - "backspace" (Backspace): Delete elements backwards
// - "delete" (Delete): Delete elements forward
// - "bind": Bind shortcuts ("bind ctrl+5 goto +50")
// NOTE: Command names
//       Because navigation keys are the most essential, they get short names.
//       For example, mpv uses LEFT and RIGHT to bind to "seek -10" and "seek 10".
//       Here, both "bind ctrl+9 right" and "bind ctrl+9 goto +1" are both valid.
//       Otherwise, it's better to name them "do-thing" syntax.
/// List of default commands and shortcuts
immutable Command[] default_commands = [
    { "left",               "Navigate one element back",
        Key.LeftArrow,          &move_left },
    { "right",              "Navigate one element forward",
        Key.RightArrow,         &move_right },
    { "up",                 "Navigate one line back",
        Key.UpArrow,            &move_up },
    { "down",               "Navigate one line forward",
        Key.DownArrow,          &move_down },
    { "home",               "Navigate to start of line",
        Key.Home,               &move_ln_start },
    { "end",                "Navigate to end of line",
        Key.End,                &move_ln_end },
    { "top",                "Navigate to start (top) of document",
        Mod.ctrl|Key.Home,      &move_abs_start },
    { "bottom",             "Navigate to end (bottom) of document",
        Mod.ctrl|Key.End,       &move_abs_end },
    { "page-up",            "Navigate one screen page back",
        Key.PageUp,             &move_pg_up },
    { "page-down",          "Navigate one screen page forward",
        Key.PageDown,           &move_pg_down },
    { "skip-back",          "Skip backward to different element",
        Mod.ctrl|Key.LeftArrow, &move_skip_backward },
    { "skip-front",         "Skip forward to different element",
        Mod.ctrl|Key.RightArrow,&move_skip_forward },
    { "view-up",            "Move view up a row",
        Mod.ctrl|Key.UpArrow,   &view_up },
    { "view-down",          "Move view down a row",
        Mod.ctrl|Key.DownArrow, &view_down },
    { "change-panel",       "Switch to another data panel",
        Key.Tab,                &change_panel },
    { "change-mode",        "Change writing mode (between overwrite and insert)",
        Key.Insert,             &change_writemode },
    { "save",               "Save document to file",
        Mod.ctrl|Key.S,         &save },
    { "save-as",            "Save document as a different file",
        Mod.ctrl|Key.O,         &save_as },
    { "undo",               "Undo last edit",
        Mod.ctrl|Key.U,         &undo },
    { "redo",               "Redo previously undone edit",
        Mod.ctrl|Key.R,         &redo },
    { "goto",               "Navigate or jump to a specific position",
        Mod.ctrl|Key.G,         &goto_ },
    { "report-position",    "Report cursor position on screen",
        Mod.ctrl|Key.P,         &report_position },
    { "report-name",        "Report document name on screen",
        Mod.ctrl|Key.N,         &report_name },
    { "refresh",            "Refresh entire screen",
        Mod.ctrl|Key.L,         &refresh },
    { "autosize",           "Automatically set column size depending of screen",
        Mod.alt|Key.R,          &autosize },
    { "set",                "Set a configuration value",
        0,                      &set },
    { "bind",               "Bind a shortcut to an action",
        0,                      &bind },
    { "unbind",             "Remove or reset a bind shortcut",
        0,                      &unbind },
    { "reset-keys",         "Reset all binded keys to default",
        0,                      &reset_keys },
    { "quit",               "Quit program",
        Key.Q,                  &quit },
];
/// Check if command names or shortcuts are duplicated
unittest
{
    foreach (command; default_commands)
    {
        // Needs a command name
        assert(command.name, "missing command name");
        
        // Needs an implementation function
        assert(command.impl, "missing impl: "~command.name);
        
        // Check if command name is duplicated
        if (command.name in g_commands)
            assert(false, "dupe name: "~command.name);
        g_commands[command.name] = command.impl;
        
        // No need to check key if unset
        if (command.key == 0)
            continue;
        
        // Otherwise, check if shortcut is duplicated
        if (command.key in g_keys)
            assert(false, "dupe key: "~command.name);
        g_keys[command.key] = Keybind( command.impl, null );
    }
}

/// Start a new instance of the hex editor.
/// Params:
///     editor = Document editor instance.
///     rc = Copy of the RC instance.
///     string = Target path.
///     initmsg = Initial message.
void startddhx(DocEditor editor, ref RC rc, string path, string initmsg)
{
    g_status = UINIT; // init here since message could be called later
    
    g_session = new Session(rc);
    g_session.target = path;    // assign target path, NULL unsets this
    g_session.editor = editor;  // assign editor instance
    
    message(initmsg);
    
    // TODO: ^C handler
    terminalInit(TermFeat.altScreen | TermFeat.inputSys);
    terminalOnResize(&onresize);
    terminalHideCursor();
    
    // Setup default commands and shortcuts
    foreach (command; default_commands)
    {
        g_commands[command.name] = command.impl;
        
        if (command.key)
            g_keys[command.key] = Keybind( command.impl, null );
    }
    
    // Add commands and shortcuts for debug builds.
    debug
    {
        g_commands["test-error"] =
        (Session*, string[])
        {
            throw new Exception("error test");
        };
        
        // ^H is binded to something on my terminal... No idea what.
        g_keys[Mod.ctrl|Key.J] =
        Keybind((Session*, string[])
            {
                throw new Exception("error test");
            },
            null
        );
    }
    
    // Special keybinds with no attached commands
    g_keys[Key.Enter] = Keybind( &prompt_command, null );
    
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
        const(Keybind) *k = input.key in g_keys;
        if (k)
        {
            log("key=%s (%d)", input.key, input.key);
            try k.impl(session, cast(string[])k.parameters);
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
        
        if (g_editdigit == 0) // start new edit
        {
            g_editcurpos = session.position_cursor;
            import core.stdc.string : memset;
            memset(g_editbuf.ptr, 0, g_editbuf.length);
        }
        
        g_status |= UEDITING;
        shfdata(g_editbuf.ptr, g_editbuf.length, session.rc.data_type, kv, g_editdigit++);
        
        DataSpec spec = dataSpec(session.rc.data_type);
        int chars = spec.spacing;
        
        // If entered an edit fully or cursor position changed,
        // add edit into history stack
        if (g_editdigit >= chars)
        {
            // TODO: multi-byte edits
            g_session.editor.overwrite(g_editcurpos, g_editbuf.ptr, ubyte.sizeof);
            g_editdigit = 0;
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
    // If autoresize configuration is enabled, automatically set columns
    if (g_session.rc.autoresize)
        autosize(g_session, null);
    
    update(g_session);
}

// Bind a key to a command with default set of parameters
void bindkey(int key, string command, string[] parameters)
{
    import std.conv : text;
    
    log(`key=%d command="%s" params="%s"`, key, command, parameters);
    
    void function(Session*, string[]) *impl = command in g_commands;
    if (impl == null)
        throw new Exception(text("Unknown command: ", command));
    
    g_keys[key] = Keybind( *impl, parameters );
}

// Unbind/reset key
void unbindkey(int key)
{
    Keybind *k = key in g_keys;
    if (k == null) // nothing to unbind
        return;
    
    // Check commands for a default keybind
    foreach (command; default_commands)
    {
        // Reset keybind to its default
        if (command.key == key)
        {
            k.impl = command.impl;
            k.parameters = null;
            return;
        }
    }
    
    // If key is not part of default keybinds, remove from active set
    g_keys.remove(key);
}

// Return key value from string interpretation
int keybind(string value)
{
    import std.string : startsWith;
    
    int mod; /// modificators
    
    static immutable string ctrlpfx = "ctrl+";
    if (startsWith(value, ctrlpfx))
    {
        mod |= Mod.ctrl;
        value = value[ctrlpfx.length..$];
    }
    
    static immutable string altpfx = "alt+";
    if (startsWith(value, altpfx))
    {
        mod |= Mod.alt;
        value = value[altpfx.length..$];
    }
    
    static immutable string shiftpfx = "shift+";
    if (startsWith(value, shiftpfx))
    {
        mod |= Mod.shift;
        value = value[shiftpfx.length..$];
    }
    
    if (value.length == 0)
        throw new Exception("Expected key, got empty");
    
    int c = value[0];
    if (value.length == 1 && c >= 'a' && c <= 'z')
        return mod | (c - 32);
    else if (value.length == 1 && c >= '0' && c <= '9') // NOTE: '0'==Key.D0
        return mod | c;
    
    switch (value) {
    case "insert":      return mod | Key.Insert;
    case "home":        return mod | Key.Home;
    case "page-up":     return mod | Key.PageUp;
    case "page-down":   return mod | Key.PageDown;
    case "delete":      return mod | Key.Delete;
    case "left-arrow":  return mod | Key.LeftArrow;
    case "right-arrow": return mod | Key.RightArrow;
    case "up-arrow":    return mod | Key.UpArrow;
    case "down-arrow":  return mod | Key.DownArrow;
    default:
        throw new Exception("Unknown key");
    }
}
unittest
{
    assert(keybind("a")             == Key.A);
    assert(keybind("alt+a")         == Mod.alt+Key.A);
    assert(keybind("ctrl+a")        == Mod.ctrl+Key.A);
    assert(keybind("shift+a")       == Mod.shift+Key.A);
    assert(keybind("ctrl+0")        == Mod.ctrl+Key.D0);
    assert(keybind("ctrl+insert")   == Mod.ctrl+Key.Insert);
    assert(keybind("ctrl+home")     == Mod.ctrl+Key.Home);
    assert(keybind("page-up")       == Key.PageUp);
    assert(keybind("shift+page-up") == Mod.shift+Key.PageUp);
    assert(keybind("delete")        == Key.Delete);
}

// Invoke command prompt
string promptline(string text)
{
    assert(text, "Prompt text missing");
    assert(text.length, "Prompt text required"); // disallow empty
    
    g_status |= UHEADER; // Needs to be repainted anyway
    
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
        g_status |= UVIEW;
    
    return line;
}
int promptkey(string text)
{
    assert(text, "Prompt text missing");
    assert(text.length, "Prompt text required"); // disallow empty
    
    g_status |= UHEADER; // Needs to be repainted anyway
    
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

// Command requires argument
string arg(string[] args, size_t idx, string prefix)
{
    if (args is null || args.length <= idx)
        return promptline(prefix);
    else
        return args[idx];
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
    if (g_editdigit && g_editcurpos != pos)
    {
        g_editdigit = 0;
        session.editor.overwrite(g_editcurpos, g_editbuf.ptr, ubyte.sizeof);
    }
    
    // Can't go beyond file
    long docsize = session.editor.currentSize;
    if (pos < 0) // cursor shouldn't be negative position
        pos = 0;
    if (pos > docsize) // cursor past document
        pos = docsize;
    
    // No need to update if it's at the same place
    if (pos == session.position_cursor)
        return;
    
    // Adjust base (camera/view) position if the moved cursor (new position)
    // is behind or ahead of the view.
    import utils : align64down, align64up;
    int count = session.rc.columns * g_rows;
    if (pos < session.position_view) // cursor is behind view
    {
        session.position_view = align64down(pos, session.rc.columns);
    }
    else if (pos >= session.position_view + count) // cursor is ahead of view
    {
        session.position_view = align64up(pos - count + 1, session.rc.columns);
    }
    
    session.position_cursor = pos;
    g_status |= UVIEW | USTATUSBAR;
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
        g_messagebuf = format(fmt, args);
        g_status |= UMESSAGE;
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
    
    import std.datetime.stopwatch : StopWatch, Duration;
    debug StopWatch sw;
    debug sw.start();
    
    int cols        = session.rc.columns;
    int rows        = g_rows = termsize.rows - 2;
    int count       = rows * cols;
    long curpos     = session.position_cursor;
    long basepos    = session.position_view;
    
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
            
            if (g_editdigit && highlight) // apply current edit at position
            {
                dfmt.skip();
                
                w += terminalWrite(
                    formatData(txtbuf[], g_editbuf.ptr, g_editbuf.length, session.rc.data_type)
                );
            }
            else if (i < reslen) // apply data
            {
                w += terminalWrite(dfmt.formatdata());
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
            
            if (i < reslen)
            {
                // NOTE: Escape codes do not seem to be a worry with tests
                string c = transcode(result[i], session.rc.charset);
                w += terminalWrite(c ? c : ".");
            }
            else // no data
            {
                w += terminalWrite(" ");
            }
            
            if (highlight) terminalResetColor();
        }
        
        // Fill rest of spaces
        int f = termsize.columns - cast(int)w;
        if (f > 0)
            terminalWriteChar(' ', f);
    }
    
    debug sw.stop();
    debug log("TIME update_view=%s", sw.peek());
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
    if (g_status & UMESSAGE)
    {
        msg = g_messagebuf;
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
        //       Might include "+" at end of message to signal continuation
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
    g_rows = termsize.rows - 2;
    
    update_header(session, termsize);
    
    update_view(session, termsize);
    
    update_status(session, termsize);
    
    g_status = 0;
}

//
// ANCHOR Commands
//

// TODO: args[0] could be prompt shortcut
//       ie, "/" for forward search.
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
    string name = argv[0];
    argv = argv.length > 1 ? argv[1..$] : null;
    
    // Get command by its name
    const(void function(Session*, string[])) *com = name in g_commands;
    if (com == null)
    {
        import std.conv : text;
        throw new Exception(text("command not found: ", name));
    }
    
    // Run command, it's ok if it throws, it's covered by a key operation,
    // including command prompt (Return)
    (*com)(session, argv);
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
    
    moverel(session, -(g_rows * session.rc.columns));
}
// Move forward a page
void move_pg_down(Session *session, string[] args)
{
    moverel(session, +(g_rows * session.rc.columns));
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

/// For move_diff_backward and move_diff_forward, this is the size of the
/// search buffer (haystack).
enum SEARCH_SIZE = 16 * 1024;

// Move to different element backward
void move_skip_backward(Session *session, string[] args)
{
    import core.stdc.string : memcmp;
    import core.stdc.stdlib : malloc, free;
    
    size_t elemsize = ubyte.sizeof; // temp until multibyte stuff
    long curpos = session.position_cursor;
    
    // Nothing to really do... so avoid the necessary work
    if (curpos == 0)
        return;
    
    // If cursor is at the very end of buffer, move it by one element
    // back, because there's no data where the cursor points to.
    if (session.position_cursor == session.editor.currentSize())
        --curpos;
    
    // Get current element
    ubyte buffer = void;
    ubyte[] needle = session.editor.view(curpos, &buffer, elemsize);
    if (needle.length < elemsize)
        return; // Nothing to do
    
    // Position cursor at its starting line. If there isn't different
    // data anyway, it would already be moved and ready next time
    // the command is hit.
    curpos -= elemsize;
    
    // See notes in move_skip_forward
    ubyte[] haybuffer = (cast(ubyte*)malloc(SEARCH_SIZE))[0..SEARCH_SIZE];
    if (haybuffer is null)
        throw new Exception("error: Out of memory");
    scope(exit) free(haybuffer.ptr);
    
    // 
    long base = curpos;
    loop: do
    {
        base -= SEARCH_SIZE;
        if (base < 0)
            base = 0;
        
        ubyte[] haystack = session.editor.view(base, haybuffer);
        if (haystack.length < elemsize)
        {
            // somehow haystack is smaller than needle, so give up
            // move by needle size backward
            moveabs(session, curpos - elemsize);
            return;
        }
        
        for (size_t o = cast(size_t)(curpos - base); o > 0; --o, --curpos)
        {
            if (memcmp(needle.ptr, haystack.ptr + o, elemsize))
            {
                break loop;
            }
        }
    }
    while (base > 0);
    
    // Move even if nothing found, since it is the intent.
    // In a text editor, if Ctrl+Left is hit (imagine a long line of same
    // characters) the cursor still moves to the start of the document.
    moveabs(session, curpos);
}

// TODO: Skip by selection (argument takes precedence)
//       ubyte[] selected = selection();
//       if (selected) needle = selected;
// Move to different element forward
void move_skip_forward(Session *session, string[] args)
{
    import core.stdc.string : memcmp;
    import core.stdc.stdlib : malloc, free;
    
    size_t elemsize = ubyte.sizeof; // temp until multibyte stuff
    long curpos  = session.position_cursor;
    long docsize = session.editor.size();
    
    // Already at the end of document, nothing to do
    if (curpos == docsize)
        return;
    
    // Get current element
    ubyte buffer = void;
    ubyte[] needle = session.editor.view(curpos, &buffer, elemsize);
    if (needle.length < elemsize)
        return; // Nothing to do
    
    curpos += elemsize;
    
    // TODO: Eventually re-visit need of malloc vs. array allocation
    // Throwing on malloc failure is weird... but uses less memory than a search buffer
    ubyte[] haybuffer = (cast(ubyte*)malloc(SEARCH_SIZE))[0..SEARCH_SIZE];
    if (haybuffer is null)
        throw new Exception("error: Out of memory");
    scope(exit) free(haybuffer.ptr);
    
    // 
    loop: do
    {
        ubyte[] haystack = session.editor.view(curpos, haybuffer);
        if (haystack.length < elemsize)
        {
            moveabs(session, curpos);
            return; // Nothing to do, but move by an element
        }
        
        for (size_t o; o < haystack.length; ++o, ++curpos)
        {
            if (memcmp(needle.ptr, haystack.ptr + o, elemsize))
            {
                break loop;
            }
        }
    }
    while (curpos < docsize);
    
    // If we reached end of buffer (EOF in the future), move there
    moveabs(session, curpos);
}

// Move view up
void view_up(Session *session, string[] args)
{
    if (session.position_view == 0)
        return;
    
    session.position_view -= session.rc.columns;
    if (session.position_view < 0)
        session.position_view = 0;
}

// Move view down
void view_down(Session *session, string[] args)
{
    int count = session.rc.columns * g_rows;
    long max = session.editor.currentSize - count;
    if (session.position_view > max)
        return;
    
    session.position_view += session.rc.columns;
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
    g_status |= USTATUSBAR;
}

// Refresh screen
void refresh(Session *session, string[] args)
{
    terminalClear();
    update(session);
}

// Change active panel
void change_panel(Session *session, string[] args)
{
    // TODO: First parameter should be a panel panel
    //       By default, just cycle
    
    session.panel++;
    if (session.panel >= PanelType.max + 1)
        session.panel = PanelType.init;
}

// 
void undo(Session *session, string[] args)
{
    import patcher : Patch;
    Patch patch = session.editor.undo();
    
    if (patch.size)
        moveabs(session, patch.address);
}

// 
void redo(Session *session, string[] args)
{
    import patcher : Patch;
    Patch patch = session.editor.redo();
    
    if (patch.size)
        moveabs(session, patch.address + patch.size);
}

// 
void goto_(Session *session, string[] args)
{
    import utils : scan;
    
    string off = arg(args, 0, "offset: ");
    if (off.length == 0)
        return; // special since it will happen often to cancel
    
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
    case '%':
        import std.conv : to;
        
        if (off.length <= 1) // just '%'
            throw new Exception("Need percentage number");
        
        // Didn't want to over-complicate myself with floats, so int it is for now.
        // Also, there are functions to do integer division with rem.
        //
        // Otherwise, I'd have to deal with floats, single-precision (float) only
        // have a mantissa of 23 bits and doubles have a mantissa of 53 bits.
        uint per = to!uint(off[1..$]);
        if (per > 100) // Yeah we can't go over the document
            throw new Exception("Percentage cannot be over 100");
        
        import utils : llpercentdiv;
        moveabs(session, llpercentdiv(session.editor.currentSize(), per));
        break;
    default:
        moveabs(session, scan(off));
    }
}

// Report cursor position on screen
void report_position(Session *session, string[] args)
{
    long curpos  = session.position_cursor;
    long docsize = session.editor.currentSize;
    message("%d / %d B (%f%%)",
        curpos,
        docsize,
        cast(float)curpos / docsize * 100);
}

// Report document name on screen (as a reminder)
void report_name(Session *session, string[] args)
{
    import std.path : baseName;
    
    if (session.target is null)
    {
        message("(new buffer)");
        return;
    }
    
    message( baseName(session.target) );
}

// Given parameters, suggest a number of available terminal columns.
int suggestcols(int tcols, int aspace, int dspace)
{
    int left = tcols - (aspace + 4); // address + spaces around data
    return left / (2+dspace); // old flawed algo, temporary
}
unittest
{
    enum X8SPACING = 2;
    enum D8SPACING = 3;
    assert(suggestcols(80, 11, X8SPACING) == 16); // 11 chars for address, x8 formatting
    //assert(suggestcols(80, 11, D8SPACING) == 16); // 11 chars for address, d8 formatting
}

// Automatically size the number of columns that can fix on screen
// using the currently selected data mode.
void autosize(Session *session, string[] args)
{
    int adspacing = session.rc.address_spacing;
    DataSpec spec = dataSpec(session.rc.data_type);
    TerminalSize tsize = terminalSize();
    
    session.rc.columns = suggestcols(tsize.columns, adspacing, spec.spacing);
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

// Save as file
void save_as(Session *session, string[] args)
{
    string name = arg(args, 0, "Save as: ");
    if (name.length == 0)
        throw new Exception("Canceled");
    
    session.target = name;
    save(session, null);
}

// Set runtime config
void set(Session *session, string[] args)
{
    string setting = arg(args, 0, "Setting: ");
    if (setting.length == 0)
        throw new Exception("Canceled");
    
    string value = arg(args, 1, "Value: ");
    if (value.length == 0)
        throw new Exception("Canceled");
    
    configRC(session.rc, setting, value);
}

// Bind key to action (command + parameters)
void bind(Session *session, string[] args)
{
    int key = keybind( arg(args, 0, "Key: ") );
    // BUG: promptline returns as one string, so "goto +32" might happen
    string command = arg(args, 1, "Command: ");
    
    bindkey(key, command, args.length >= 2 ? args[2..$] : null);
    message("Key binded");
}

// Unbind key
void unbind(Session *session, string[] args)
{
    int key = keybind( arg(args, 0, "Key: ") );
    unbindkey(key);
    message("Key unbinded");
}

// Reset all keys
void reset_keys(Session *session, string[] args)
{
    g_keys.clear();
    foreach (command; default_commands)
    {
        if (command.key)
            g_keys[command.key] = Keybind( command.impl, null );
    }
    message("All keys reset");
}

// Quit app
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