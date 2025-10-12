/// Interactive hex editor application.
///
/// Defines behavior for main program.
/// 
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx;

import std.string;
import os.terminal;
import configuration;
import doceditor;
import logger;
import transcoder;
import std.conv : text;
import backend.base : IDocumentEditor;

// TODO: Find a way to dump session data to be able to resume later
//       Session/project whatever

private debug enum DEBUG = "+debug"; else enum DEBUG = "";

/// Copyright string
immutable string DDHX_COPYRIGHT = "Copyright (c) 2017-2025 dd86k <dd@dax.moe>";
/// App version
immutable string DDHX_VERSION   = "0.6.0"~DEBUG;
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

private
struct Keybind
{
    /// Function implementing command
    void function(Session*, string[]) impl;
    /// Parameters to add
    string[] parameters;
}

private
struct Selection
{
    long anchor;    /// original position when started
    int status;
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
    IDocumentEditor editor;
    
    /// Active selection
    Selection selection;
    
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
    //
    // Reset every update
    int g_status;
    
    // Number of effective rows for view
    // 
    // Updated every update
    int g_rows;
    
    // HACK: Global for screen resize events
    Session *g_session;
    
    string g_messagebuf;
    
    /// Last search needle (find-* uses this).
    ubyte[] g_needle;
    
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
// - "find-back" (Ctrl+B and/or '?'): Backward search
// - "find-next" (prefill with Ctrl+F): Find next instance for find
// - "find-prev" (prefill with Ctrl+F): Find next instance for find-back
// - "toggle-*" (Alt+Key): Hiding/showing panels
// - "save-settings": Save session settings into .ddhxrc
// - "insert" (Ctrl+I): Insert data (generic, might redirect to other commands?)
// - "backspace" (Backspace): Delete elements before cursor position
// - "delete" (Delete): Delete elements at cursor position
// - "fill": Fill selection/range with bytes (overwrite only)
// - "hash": Hash selection with result in status
//           Mostly checksums and digests under 256 bits.
//           80 columns -> 40 bytes -> 320 bits.
// - "save-status": Save status/message content into file...?
// NOTE: Command names
//       Because navigation keys are the most essential, they get short names.
//       For example, mpv uses LEFT and RIGHT to bind to "seek -10" and "seek 10".
//       Here, both "bind ctrl+9 right" and "bind ctrl+9 goto +1" are both valid.
//       Otherwise, it's better to name them "do-thing" syntax.
// NOTE: Command designs
//       - Names: If commonly used (ie, navigation), one word
//       - Selection: command parameters are prioritized over selections
/// List of default commands and shortcuts
immutable Command[] default_commands = [
    // Navigation
    { "left",                       "Navigate one element back",
        Key.LeftArrow,              &move_left },
    { "right",                      "Navigate one element forward",
        Key.RightArrow,             &move_right },
    { "up",                         "Navigate one line back",
        Key.UpArrow,                &move_up },
    { "down",                       "Navigate one line forward",
        Key.DownArrow,              &move_down },
    { "home",                       "Navigate to start of line",
        Key.Home,                   &move_ln_start },
    { "end",                        "Navigate to end of line",
        Key.End,                    &move_ln_end },
    { "top",                        "Navigate to start (top) of document",
        Mod.ctrl|Key.Home,          &move_abs_start },
    { "bottom",                     "Navigate to end (bottom) of document",
        Mod.ctrl|Key.End,           &move_abs_end },
    { "page-up",                    "Navigate one screen page back",
        Key.PageUp,                 &move_pg_up },
    { "page-down",                  "Navigate one screen page forward",
        Key.PageDown,               &move_pg_down },
    { "skip-back",                  "Skip backward to different element",
        Mod.ctrl|Key.LeftArrow,     &move_skip_backward },
    { "skip-front",                 "Skip forward to different element",
        Mod.ctrl|Key.RightArrow,    &move_skip_forward },
    { "view-up",                    "Move view up a row",
        Mod.ctrl|Key.UpArrow,       &view_up },
    { "view-down",                  "Move view down a row",
        Mod.ctrl|Key.DownArrow,     &view_down },
    // Selections
    { "select-left",                "Extend selection one element back",
        Mod.shift|Key.LeftArrow,    &select_left },
    { "select-right",               "Extend selection one element forward", 
        Mod.shift|Key.RightArrow,   &select_right },
    { "select-up",                  "Extend selection one line up",
        Mod.shift|Key.UpArrow,      &select_up },
    { "select-down",                "Extend selection one line down",
        Mod.shift|Key.DownArrow,    &select_down },
    { "select-home",                "Extend selection to start of line",
        Mod.shift|Key.Home,         &select_home },
    { "select-end",                 "Extend selection to end of line",
        Mod.shift|Key.End,          &select_end },
    /*{ "select-top",                 "Extend selection to start of document",
        Mod.ctrl|Mod.shift|Key.Home,&select_top },
    { "select-bottom",              "Extend selection to end of document",
        Mod.ctrl|Mod.shift|Key.End, &select_bottom },
    { "select-all",                 "Select entire document",
        Mod.ctrl|Key.A,             &select_all },*/
    // 
    { "change-panel",               "Switch to another data panel",
        Key.Tab,                    &change_panel },
    { "change-mode",                "Change writing mode (between overwrite and insert)",
        Key.Insert,                 &change_writemode },
    // Find
    { "find",                       "Find a pattern in the document",
        Mod.ctrl|Key.F,             &find },
    { "find-back",                  "Find a pattern in the document backward",
        Mod.ctrl|Key.B,             &find_back },
    { "find-next",                  "Repeat search",
        Mod.ctrl|Key.X,             &find_next },
    { "find-prev",                  "Repeat search backward",
        Mod.shift|Key.X,            &find_prev },
    // Actions
    { "save",                       "Save document to file",
        Mod.ctrl|Key.S,             &save },
    { "save-as",                    "Save document as a different file",
        Mod.ctrl|Key.O,             &save_as },
    { "undo",                       "Undo last edit",
        Mod.ctrl|Key.U,             &undo },
    { "redo",                       "Redo previously undone edit",
        Mod.ctrl|Key.R,             &redo },
    { "goto",                       "Navigate or jump to a specific position",
        Mod.ctrl|Key.G,             &goto_ },
    { "report-position",            "Report cursor position on screen",
        Mod.ctrl|Key.P,             &report_position },
    { "report-name",                "Report document name on screen",
        Mod.ctrl|Key.N,             &report_name },
    { "refresh",                    "Refresh entire screen",
        Mod.ctrl|Key.L,             &refresh },
    { "autosize",                   "Automatically set column size depending of screen",
        Mod.alt|Key.R,              &autosize },
    { "set",                        "Set a configuration value",
        0,                          &set },
    { "bind",                       "Bind a shortcut to an action",
        0,                          &bind },
    { "unbind",                     "Remove or reset a bind shortcut",
        0,                          &unbind },
    { "reset-keys",                 "Reset all binded keys to default",
        0,                          &reset_keys },
    { "quit",                       "Quit program",
        Mod.ctrl|Key.Q,             &quit },
];
// NOTE: There used to be a test that checked for dupes but it caused issues elsewhere.

/// Initiate default keys and commands.
void initdefaults()
{
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
        
        // ^H is binded to ctrl+backspace.
        g_keys[Mod.ctrl|Key.J] =
        Keybind((Session*, string[])
            {
                throw new Exception("error test");
            },
            null
        );
    }
}

// Bind a key to a command with default set of parameters
void bindkey(int key, string command, string[] parameters)
{
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

version(unittest)
Keybind* binded(int key)
{
    return key in g_keys;
}

/// Start a new instance of the hex editor.
/// Params:
///     editor = Document editor instance.
///     rc = Copy of the RC instance.
///     string = Target path.
///     initmsg = Initial message.
void startddhx(IDocumentEditor editor, ref RC rc, string path, string initmsg)
{
    g_status = UINIT; // init here since message could be called later
    
    g_session = new Session(rc);
    g_session.target = path;    // assign target path, NULL unsets this
    g_session.editor = editor;  // assign editor instance
    
    message(initmsg);
    
    // TODO: Handle ^C
    //       1. Ignore + message to really quit
    //          Somehow re-init loop without longjmp (unavail on Windows)
    //       2. Quit, restore IOS
    terminalInit(TermFeat.altScreen | TermFeat.inputSys);
    terminalOnResize(&onresize);
    terminalHideCursor();
    
    // Special keybinds with no attached commands
    // TODO: Make "menu" bindable.
    //       Return should still be provided as a fallback.
    g_keys[Key.Enter] = Keybind( &prompt_command, null );
    
    // HACK: New input system tweaks fixes weird Shift+Arrow fuckery in conhost,
    //       but also captures Ctrl+C. Annoyingly, force quit when that happens.
    version (Windows)
    g_keys[Mod.ctrl|Key.C] = Keybind(
        (Session*, string[])
        {
            import core.stdc.stdlib : exit;
            exit(0);
        }, null);
    
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
        
        // We have a valid key and mode, so disrupt selection
        session.selection.status = 0;
        
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
            g_session.editor.replace(g_editcurpos, g_editbuf.ptr, ubyte.sizeof);
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
    string line = terminalReadline();
    
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
        session.editor.replace(g_editcurpos, g_editbuf.ptr, ubyte.sizeof);
    }
    
    long docsize = session.editor.size();
    // Cursor obviously cannot be of negative value
    if (pos < 0)
        pos = 0;
    // Fix when cursor is attempting to select non-existant data
    else if (session.selection.status && pos >= docsize)
        pos = docsize - 1;
    // Fix when cursor is past playable area (doc size + EOF)
    else if (pos > docsize)
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
    if (termsize.rows < 3)
        return;
    
    int cols        = session.rc.columns;       /// elements per row
    int rows        = g_rows;                   /// rows to render
    int count       = rows * cols;              /// elements on screen
    long curpos     = session.position_cursor;  /// Cursor position
    long address    = session.position_view;    /// Base address
    
    bool logging    = logEnabled();
    
    debug import std.datetime.stopwatch : StopWatch, Duration;
    debug StopWatch sw;
    debug if (logging) sw.start(); // For IDocumentEditor.view()
    
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
    if (viewbuf.length != count) // only resize if required
        viewbuf.length = count;
    ubyte[] result  = session.editor.view(address, viewbuf);
    int readlen     = cast(int)result.length; // * bytesize
    
    debug if (logging)
    {
        sw.stop();
        log("TIME view=%s", sw.peek());
        sw.reset();
        sw.start();
    }
    
    // Selection stuff
    long select_start = void, select_end = void;
    cast(void)selection(session, select_start, select_end); // Size not used...
    int sl0   = cast(int)(select_start - address);
    int sl1   = cast(int)(select_end   - address);
    
    // Render view
    char[32] txtbuf = void;
    int viewpos     = cast(int)(curpos - address); // relative cursor position in view
    int datawidth   = dataSpec(session.rc.data_type).spacing; // data element width
    int addspacing  = session.rc.address_spacing;
    PanelType panel = session.panel;
    if (logging) // branch avoids pushing all of this for nothing
        log("address=%d viewpos=%d cols=%d rows=%d count=%d Dwidth=%d readlen=%d panel=%s "~
            "select.anchor=%d select.status=%#x sl0=%d sl1=%d",
            address, viewpos, cols, rows, count, datawidth, readlen, panel,
            session.selection.anchor, session.selection.status, sl0, sl1);
    DataFormatter dfmt = DataFormatter(session.rc.data_type, result.ptr, result.length);
    for (int row; row < rows; ++row, address += cols)
    {
        // '\n' could count as a character, avoid using it
        terminalCursor(0, row + 1);
        
        string addr = formatAddress(txtbuf, address, addspacing, session.rc.address_type);
        size_t w = terminalWrite(addr, " "); // row address + spacer
        
        // Render view data
        for (int col; col < cols; ++col)
        {
            int i = (row * cols) + col;
            
            if (session.selection.status && i >= sl0 && i <= sl1 && panel == PanelType.data)
            {
                // Depending where spacer is placed, invert its color earlier
                if (i != sl0) terminalInvertColor();
                w += terminalWrite(" "); // data-data spacer
                if (i == sl0) terminalInvertColor();
                w += terminalWrite(dfmt.formatdata());
                terminalResetColor();
                continue;
            }
            
            // BUG: When i == viewpos && we have selection, cursor renders
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
            else if (i < readlen) // apply data
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
            
            if (session.selection.status && i >= sl0 && i <= sl1 && panel == PanelType.text)
            {
                terminalInvertColor();
                string c = transcode(result[i], session.rc.charset);
                w += terminalWrite(c ? c : ".");
                terminalResetColor();
                continue;
            }
            
            bool highlight = i == viewpos && panel == PanelType.text;
            
            if (highlight) terminalInvertColor();
            
            if (i < readlen)
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
    
    debug if (logging)
    {
        sw.stop();
        log("TIME update_view=%s", sw.peek());
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
    
    char[32] buf0 = void; // cursor address or selection start buffer
    char[32] buf1 = void; // selection end buffer
    
    long select_start = void, select_end = void;
    
    // If there is a pending message, print that.
    // Otherwise, print status bar using the message buffer space.
    long selectlen = selection(session, select_start, select_end);
    string msg = void;
    if (g_status & UMESSAGE)
    {
        msg = g_messagebuf;
    }
    else if (selectlen)
    {
        string start = formatAddress(buf0, select_start, 1, session.rc.address_type);
        string end   = formatAddress(buf1, select_end,   1, session.rc.address_type);
        msg = cast(string)sformat(statusbuf, "SEL: %s-%s (%d Bytes)", start, end, selectlen);
    }
    else
    {
        string curstr = formatAddress(buf0, session.position_cursor, 8, session.rc.address_type);
        
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

enum {
    /// Search for different needle value, not an exact one.
    SEARCH_DIFF     = 1,
    /// Search in reverse, not forward.
    SEARCH_REVERSE  = 2,
    /// Instead of returning -1, return the position when the search ended.
    SEARCH_LASTPOS  = 4,
    /// Search is done aligned to the size of the needle.
    SEARCH_ALIGNED  = 8,
    // Wrap search.
    //SEARCH_WRAP     = 16,
}

/// Search for data.
///
/// This function does not rely on the cursor position nor does it change it,
/// because command implementations might use the result differently.
///
/// Returning the position allows for specific error messages when a search
/// returns -1 (error: not found), or forced to return where the position is
/// after the search is concluded.
/// Params:
///     session = Current session.
///     needle = Data to compare against.
///     position = Starting position.
///     flags = Operation flags.
/// Returns: Found position, or -1. SEARCH_LASTPOS overrides returning -1.
long search(Session *session, ubyte[] needle, long position, int flags)
{
    import core.stdc.stdlib : malloc, free;
    import core.stdc.string : memcmp;
    import std.exception : enforce;
    
    enforce(needle, "Need needle");
    
    // Throwing on malloc failure is weird... but uses less memory than a search buffer
    ubyte[] hay = (cast(ubyte*)malloc(SEARCH_SIZE))[0..SEARCH_SIZE];
    if (hay is null)
        throw new Exception("error: Out of memory");
    scope(exit) free(hay.ptr);
    
    log("position=%d flags=%#x needle=[%(%#x,%)]", position, flags, needle);
    
    int diff = flags & SEARCH_DIFF;
    size_t alignment = flags & SEARCH_ALIGNED ? needle.length : 1;
    //ubyte first = needle[0];
    
    debug import std.datetime.stopwatch : StopWatch;
    debug StopWatch sw;
    debug sw.start;
    
    if (flags & SEARCH_REVERSE)
    {
        long base = position;
        do
        {
            base -= SEARCH_SIZE;
            if (base < 0)
                base = 0;
            
            ubyte[] haystack = session.editor.view(base, hay);
            if (haystack.length < needle.length)
            {
                // somehow haystack is smaller than needle
                return -2;
            }
            
            for (size_t o = cast(size_t)(position - base); o > 0; o -= alignment, position -= alignment)
            {
                int r = memcmp(needle.ptr, haystack.ptr + o, needle.length);
                
                // if memcmp=0 (exact)   != diff=1 -> SKIP
                // if memcmp=-1/1 (diff) != diff=0 -> SKIP
                if ((diff == 0 && r != 0) || (diff && r == 0))
                    continue;
                
                return position;
            }
        }
        while (base > 0);
    }
    else // forward
    {
        long docsize = session.editor.size();
        do
        {
            ubyte[] haystack = session.editor.view(position, hay);
            if (haystack.length < needle.length)
                return -2;
            
            for (size_t o; o < haystack.length; o += alignment, position += alignment)
            {
                int r = memcmp(needle.ptr, haystack.ptr + o, needle.length);
                
                // if memcmp=0 (exact)   != diff=1 -> SKIP
                // if memcmp=-1/1 (diff) != diff=0 -> SKIP
                if ((diff == 0 && r != 0) || (diff && r == 0))
                    continue;
                
                return position;
            }
        }
        while (position < docsize);
    }
    
    debug sw.stop();
    debug log("search=%s", sw.peek());
    
    return flags & SEARCH_LASTPOS ? position : -1;
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
        throw new Exception(text("command not found: ", name));
    }
    
    // Run command, it's ok if it throws, it's covered by a key operation,
    // including command prompt (Return)
    (*com)(session, argv);
}

// Move back a single item
void move_left(Session *session, string[] args)
{
    session.selection.status = 0;
    if (session.position_cursor == 0)
        return;
    
    moverel(session, -1);
}
// Move forward a single item
void move_right(Session *session, string[] args)
{
    session.selection.status = 0;
    moverel(session, +1);
}
// Move back a row
void move_up(Session *session, string[] args)
{
    session.selection.status = 0;
    if (session.position_cursor == 0)
        return;
    
    moverel(session, -session.rc.columns);
}
// Move forward a row
void move_down(Session *session, string[] args)
{
    session.selection.status = 0;
    moverel(session, +session.rc.columns);
}
// Move back a page
void move_pg_up(Session *session, string[] args)
{
    session.selection.status = 0;
    if (session.position_cursor == 0)
        return;
    
    moverel(session, -(g_rows * session.rc.columns));
}
// Move forward a page
void move_pg_down(Session *session, string[] args)
{
    session.selection.status = 0;
    moverel(session, +(g_rows * session.rc.columns));
}
// Move to start of line
void move_ln_start(Session *session, string[] args) // move to start of line
{
    session.selection.status = 0;
    moverel(session, -(session.position_cursor % session.rc.columns));
}
// Move to end of line
void move_ln_end(Session *session, string[] args) // move to end of line
{
    session.selection.status = 0;
    moverel(session, +(session.rc.columns - (session.position_cursor % session.rc.columns)) - 1);
}
// Move to absolute start of document
void move_abs_start(Session *session, string[] args)
{
    session.selection.status = 0;
    moveabs(session, 0);
}
// Move to absolute end of document
void move_abs_end(Session *session, string[] args)
{
    session.selection.status = 0;
    moveabs(session, session.editor.size());
}

/// For move_diff_backward and move_diff_forward, this is the size of the
/// search buffer (haystack).
enum SEARCH_SIZE = 16 * 1024;

// Move to different element backward
void move_skip_backward(Session *session, string[] args)
{
    long curpos = session.position_cursor;
    
    // Nothing to really do... so avoid the necessary work
    if (curpos == 0)
        return;
    
    // If cursor is at the very end of buffer, move it by one element
    // back, because there's no data where the cursor points to.
    if (session.position_cursor == session.editor.size())
        --curpos;
    
    // Use selection if active, otherwise use current element highlighted by
    // cursor
    ubyte[] needle;
    long select_start = void, select_end = void;
    long selectlen = selection(session, select_start, select_end);
    if (selectlen)
    {
        if (selectlen > MiB!256)
            throw new Exception("Selection too big");
        needle.length = cast(size_t)selectlen;
        needle = session.editor.view(select_start, needle);
        if (needle.length < selectlen)
            return; // Nothing to do
    }
    else // by cursor position
    {
        // Get current element
        ubyte buffer = void;
        needle = session.editor.view(curpos, &buffer, ubyte.sizeof);
        if (needle.length < ubyte.sizeof)
            return; // Nothing to do
        select_start = curpos;
    }
    
    session.selection.status = 0;
    
    // Move even if nothing found, since it is the intent.
    // In a text editor, if Ctrl+Left is hit (imagine a long line of same
    // characters) the cursor still moves to the start of the document.
    moveabs(session,
        search(session, needle, select_start - needle.length,
            SEARCH_LASTPOS|SEARCH_DIFF|SEARCH_REVERSE|SEARCH_ALIGNED));
}

template MiB(int base)
{
    enum MiB = cast(long)base * 1024 * 1024;
}
template KiB(int base)
{
    enum KiB = cast(long)base * 1024;
}

// Move to different element forward
void move_skip_forward(Session *session, string[] args)
{
    long curpos  = session.position_cursor;
    long docsize = session.editor.size();
    
    // Already at the end of document, nothing to do
    if (curpos == docsize)
        return;
    
    // Use selection if active, otherwise use current element highlighted by
    // cursor
    ubyte[] needle;
    long select_start = void, select_end = void;
    long selectlen = selection(session, select_start, select_end);
    if (selectlen)
    {
        if (selectlen > MiB!256)
            throw new Exception("Selection too big");
        needle.length = cast(size_t)selectlen;
        needle = session.editor.view(select_start, needle);
        if (needle.length < selectlen)
            return; // Nothing to do
    }
    else // by cursor position
    {
        // Get current element
        ubyte buffer = void;
        needle = session.editor.view(curpos, &buffer, ubyte.sizeof);
        if (needle.length < ubyte.sizeof)
            return; // Nothing to do
        select_start = curpos;
    }
    
    session.selection.status = 0;
    
    moveabs(session,
        search(session, needle, select_start + needle.length,
            SEARCH_LASTPOS|SEARCH_DIFF|SEARCH_ALIGNED));
}

// Move view up
void view_up(Session *session, string[] args)
{
    if (session.position_view == 0)
        return;
    
    session.position_view -= session.rc.columns;
    if (session.position_view < 0)
        session.position_view = 0;
    g_status |= UVIEW;
}

// Move view down
void view_down(Session *session, string[] args)
{
    int count = session.rc.columns * g_rows;
    long max = session.editor.size() - count;
    if (session.position_view > max)
        return;
    
    session.position_view += session.rc.columns;
    g_status |= UVIEW;
}

//
// Selection
//

// Force unselection
void unselect(Session *session)
{
    session.selection.status = 0;
}

// Get selection start, end, and its size
long selection(Session *session, ref long start, ref long end)
{
    import std.algorithm.comparison : min, max;
    
    if (session.selection.status == 0)
        return 0;
    
    start = min(session.selection.anchor, session.position_cursor);
    end   = max(session.selection.anchor, session.position_cursor);
    
    if (end >= session.editor.size())
        end--;
    
    // Return long, functions may use it differently.
    return end - start + 1;
}

// Expand selection backward
void select_left(Session *session, string[] args)
{
    if (!session.selection.status)
    {
        session.selection.status = 1;
        session.selection.anchor = session.position_cursor;
    }
    
    moverel(session, -1);
}

// Expand selection forward
void select_right(Session *session, string[] args)
{
    if (!session.selection.status)
    {
        session.selection.status = 1;
        session.selection.anchor = session.position_cursor;
    }
    
    moverel(session, +1);
}

// Expand selection back a line
void select_up(Session *session, string[] args)
{
    if (!session.selection.status)
    {
        session.selection.status = 1;
        session.selection.anchor = session.position_cursor;
    }
    
    moverel(session, -session.rc.columns);
}

// Expand selection forward a line
void select_down(Session *session, string[] args)
{
    if (!session.selection.status)
    {
        session.selection.status = 1;
        session.selection.anchor = session.position_cursor;
    }
    
    moverel(session, +session.rc.columns);
}

// Expand selection towards end of line
void select_home(Session *session, string[] args)
{
    if (!session.selection.status)
    {
        session.selection.status = 1;
        session.selection.anchor = session.position_cursor;
    }
    
    moverel(session, -(session.position_cursor % session.rc.columns));
}

// Expand selection forward a line
void select_end(Session *session, string[] args)
{
    if (!session.selection.status)
    {
        session.selection.status = 1;
        session.selection.anchor = session.position_cursor;
    }
    
    moverel(session, +(session.rc.columns - (session.position_cursor % session.rc.columns)) - 1);
}

//
// Etc
//

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
    long pos = session.editor.undo();
    if (pos >= 0)
        moveabs(session, pos);
}

// 
void redo(Session *session, string[] args)
{
    long pos = session.editor.redo();
    if (pos >= 0)
        moveabs(session, pos);
}

union B // Used in goto for now.
{
    ubyte[8] buf;
    long    u64;
    uint    u32;
    ushort  u16;
    ubyte   u8;
    alias buf this;
}
// 
void goto_(Session *session, string[] args)
{
    import utils : scan;
    
    long position = void;
    bool absolute = void;
    
    // Selection
    long sel0 = void, sel1 = void;
    long sellen = selection(session, sel0, sel1);
    if (sellen)
    {
        if (sellen > long.sizeof)
            throw new Exception("Selection too large");
        
        B b; // Let it .init (eq. to {0})
        
        ubyte[] sel = session.editor.view(sel0, b.ptr, cast(size_t)sellen);
        
        absolute = true;
        
        if (sel.length > uint.sizeof) // same as selection length but.. size_t
            position = b.u64;
        else if (sel.length > ushort.sizeof)
            position = b.u32;
        else if (sel.length > ubyte.sizeof)
            position = b.u16;
        else
            position = b.u8;
    }
    else
    {
        string off = arg(args, 0, "offset: ");
        if (off.length == 0)
            return; // special since it will happen often to cancel
        // Number
        switch (off[0]) {
        case '+':
            if (off.length <= 1)
                throw new Exception("Incomplete number");
            position = scan(off[1..$]);
            absolute = false;
            break;
        case '-':
            if (off.length <= 1)
                throw new Exception("Incomplete number");
            position = -scan(off[1..$]);
            absolute = false;
            break;
        case '%':
            import std.conv : to;
            import utils : llpercentdiv;
            
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
            position = llpercentdiv(session.editor.size(), per);
            absolute = true;
            break;
        default:
            position = scan(off);
            absolute = true;
        }
    }
    
    // Force selection off, we're navigating somewhere
    unselect(session);
    
    // Let's fucking go!
    if (absolute)
        moveabs(session, position);
    else
        moverel(session, position);
}

// Report cursor position on screen
void report_position(Session *session, string[] args)
{
    long docsize = session.editor.size();
    long select_start = void, select_end = void;
    long selectlen = selection(session, select_start, select_end);
    if (selectlen)
    {
        message("%d-%d B (%f%%-%f%%)",
            select_start,
            select_end,
            cast(float)select_start / docsize * 100,
            cast(float)select_end   / docsize * 100);
        return;
    }
    long curpos  = session.position_cursor;
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
    if (tcols < 20)
        return 1;
    int left = tcols - (aspace + 4); // address + spaces around data
    return left / (2+dspace); // old flawed algo, temporary
}
unittest
{
    enum X8SPACING = 2;
    enum D8SPACING = 3;
    assert(suggestcols(80, 11, X8SPACING) == 16); // 11 chars for address, x8 formatting
    //assert(suggestcols(80, 11, D8SPACING) == 16); // 11 chars for address, d8 formatting
    assert(suggestcols(0, 11, X8SPACING) == 1); // 11 chars for address, x8 formatting
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
    int key = terminal_keybind( arg(args, 0, "Key: ") );
    // BUG: promptline returns as one string, so "goto +32" might happen
    string command = arg(args, 1, "Command: ");
    
    bindkey(key, command, args.length >= 2 ? args[2..$] : null);
    message("Key binded");
}

// Unbind key
void unbind(Session *session, string[] args)
{
    int key = terminal_keybind( arg(args, 0, "Key: ") );
    unbindkey(key);
    message("Key unbinded");
}

// Reset all keys
void reset_keys(Session *session, string[] args)
{
    g_keys.clear();
    initdefaults();
    message("All keys reset");
}

// Temp enum until DataType improves
enum PatternType
{
    unknown,
    hex,
    dec,
    oct,
    string_,
}
// Recognize pattern input, slice input for later interpretation
PatternType patternpfx(ref string input)
{
    import std.string : startsWith;
    
    // Detect prefix
    static immutable pfxHex0 = `x:`;
    static immutable pfxHex1 = `0x`;
    static immutable pfxStr0 = `s:`;
    static immutable pfxStr1 = `"`;
    static immutable pfxDec0 = `d:`;
    static immutable pfxOct0 = `o:`;
    if (startsWith(input, pfxHex0) || startsWith(input, pfxHex1))
    {
        input = input[pfxHex1.length..$];
        return PatternType.hex;
    }
    else if (startsWith(input, pfxStr0))
    {
        input = input[pfxStr0.length..$];
        return PatternType.string_;
    }
    else if (startsWith(input, pfxStr1))
    {
        if (input.length < 2 || input[$-1] != '"')
            return PatternType.unknown;
        input = input[pfxStr1.length..$-1];
        return PatternType.string_;
    }
    else if (startsWith(input, pfxDec0))
    {
        input = input[pfxDec0.length..$];
        return PatternType.dec;
    }
    else if (startsWith(input, pfxOct0))
    {
        input = input[pfxOct0.length..$];
        return PatternType.oct;
    }
    
    return PatternType.unknown;
}
unittest
{
    string p0 = "0x00";
    assert(patternpfx(p0) == PatternType.hex);
    assert(p0 == "00");
    
    p0 = `x:00`;
    assert(patternpfx(p0) == PatternType.hex);
    assert(p0 == "00");
    
    p0 = `x:ff`;
    assert(patternpfx(p0) == PatternType.hex);
    assert(p0 == "ff");
    
    p0 = `o:377`;
    assert(patternpfx(p0) == PatternType.oct);
    assert(p0 == "377");
    
    p0 = `s:hello`;
    assert(patternpfx(p0) == PatternType.string_);
    assert(p0 == "hello");
    
    p0 = `"hello"`;
    assert(patternpfx(p0) == PatternType.string_);
    assert(p0 == "hello");
    
    p0 = `""`;
    assert(patternpfx(p0) == PatternType.string_);
    assert(p0 == "");
    p0 = `"a`;
    assert(patternpfx(p0) == PatternType.unknown);
    p0 = `"`;
    assert(patternpfx(p0) == PatternType.unknown);
}

ubyte[] pattern(CharacterSet charset, string[] args...)
{
    import std.format : unformatValue, singleSpec;
    ubyte[] needle;
    PatternType last;
    foreach (string arg; args)
    {
        string orig = arg;
        PatternType next = patternpfx(arg);
    Lretry:
        final switch (next) {
        case PatternType.hex:
            static immutable auto xspec = singleSpec("%x");
            ulong b = unformatValue!ulong(arg, xspec);
            needle ~= cast(ubyte)b;
            break;
        case PatternType.dec:
            static immutable auto dspec = singleSpec("%u");
            long b = unformatValue!long(arg, dspec);
            needle ~= cast(ubyte)b;
            break;
        case PatternType.oct:
            static immutable auto ospec = singleSpec("%o");
            long b = unformatValue!long(arg, ospec);
            needle ~= cast(ubyte)b;
            break;
        case PatternType.string_:
            if (arg.length == 0)
                throw new Exception("String is empty");
            // TODO: Transcode
            needle ~= arg;
            break;
        case PatternType.unknown:
            if (last)
            {
                next = last;
                goto Lretry;
            }
            throw new Exception(text("Unknown pattern prefix: ", orig));
        }
        last = next;
    }
    return needle;
}
unittest
{
    assert(pattern(CharacterSet.ascii, "0x00")          == [ 0 ]);
    assert(pattern(CharacterSet.ascii, "0xff")          == [ 0xff ]);
    assert(pattern(CharacterSet.ascii, "d:255")         == [ 0xff ]);
    assert(pattern(CharacterSet.ascii, "o:377")         == [ 0xff ]);
    assert(pattern(CharacterSet.ascii, "x:00")          == [ 0 ]);
    assert(pattern(CharacterSet.ascii, "x:00","00")     == [ 0, 0 ]);
    assert(pattern(CharacterSet.ascii, "s:test")        == "test");
    assert(pattern(CharacterSet.ascii, "x:0","s:test")  == "\0test");
    assert(pattern(CharacterSet.ascii, "x:0","0","s:test") == "\0\0test");
}

/// Artificial needle size limit
enum SEARCH_LIMIT = KiB!128;

//
void find(Session *session, string[] args)
{
    long select_start = void, select_end = void;
    long selectlen = selection(session, select_start, select_end);
    
    // If arguments: Take those before selection
    if (args && args.length > 0)
    {
        g_needle = pattern(session.rc.charset, args);
        select_start = session.position_cursor + g_needle.length;
    }
    else if (selectlen) // selection
    {
        if (selectlen > SEARCH_LIMIT)
            throw new Exception("Selection too big");
        g_needle.length = cast(size_t)selectlen;
        g_needle = session.editor.view(select_start, g_needle);
        if (g_needle.length < selectlen)
            return; // Nothing to do
        select_start += g_needle.length;
    }
    else // TODO: Ask using arg() + arguments()
        throw new Exception("Need find info");
    
    unselect(session);
    long p = search(session, g_needle, select_start, 0);
    if (p < 0)
        throw new Exception("Not found");
    
    moveabs(session, p);
    
    char[32] buf = void;
    message("Found at %s", formatAddress(buf, p, 1, session.rc.address_type));
}

//
void find_back(Session *session, string[] args)
{
    long select_start = void, select_end = void;
    long selectlen = selection(session, select_start, select_end);
    
    // If arguments: Take those before selection
    if (args && args.length > 0)
    {
        g_needle = pattern(session.rc.charset, args);
        select_start = session.position_cursor - g_needle.length;
    }
    else if (selectlen) // selection
    {
        if (selectlen > SEARCH_LIMIT)
            throw new Exception("Selection too big");
        g_needle.length = cast(size_t)selectlen;
        g_needle = session.editor.view(select_start, g_needle);
        if (g_needle.length < selectlen)
            return; // Nothing to do
        select_start -= g_needle.length;
    }
    else // TODO: Ask using arg() + arguments()
        throw new Exception("Need find info");
    
    unselect(session);
    long p = search(session, g_needle, select_start, SEARCH_REVERSE);
    if (p < 0)
        throw new Exception("Not found");
    
    moveabs(session, p);
    
    char[32] buf = void;
    message("Found at %s", formatAddress(buf, p, 1, session.rc.address_type));
}

// 
void find_next(Session *session, string[] args)
{
    if (g_needle is null)
        return;
    
    unselect(session);
    long p = search(session, g_needle, session.position_cursor + g_needle.length, 0);
    if (p < 0)
        throw new Exception("Not found");
    
    moveabs(session, p);
    
    char[32] buf = void;
    message("Found at %s", formatAddress(buf, p, 1, session.rc.address_type));
}

// 
void find_prev(Session *session, string[] args)
{
    if (g_needle is null)
        return;
    
    unselect(session);
    long p = search(session, g_needle, session.position_cursor - 1, SEARCH_REVERSE);
    if (p < 0)
        throw new Exception("Not found");
    
    moveabs(session, p);
    
    char[32] buf = void;
    message("Found at %s", formatAddress(buf, p, 1, session.rc.address_type));
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