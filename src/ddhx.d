/// Interactive hex editor application.
///
/// Defines behavior for main program.
/// 
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx;

import std.conv : text;
import std.string;
import backend.base : IDocumentEditor;
import configuration;
import doceditor;
import logger;
import os.terminal;
import patterns;
import platform : assertion;
import transcoder;

// TODO: Find a way to dump session data to be able to resume later
//       Session/project whatever

private debug enum DEBUG = "+debug"; else enum DEBUG = "";

/// Copyright string
immutable string DDHX_COPYRIGHT = "Copyright (c) 2017-2025 dd86k <dd@dax.moe>";
/// App version
immutable string DDHX_VERSION   = "0.7.0"~DEBUG;
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

private alias command_func = void function(Session*, string[]);

private
struct Keybind
{
    /// Function implementing command
    command_func impl;
    /// Parameters to add
    string[] parameters;
}

private
struct CurrentSelection
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
    CurrentSelection selection;
    
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
    command_func[string] g_commands;
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
    command_func impl; /// Implementation
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
    // Deletions
    { "delete",                     "Delete data from position",
        Key.Delete,                 &delete_front },
    { "delete-back",                "Delete data from position backward",
        Key.Backspace,              &delete_back },
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
    { "select-top",                 "Extend selection to start of document",
        Mod.ctrl|Mod.shift|Key.Home,&select_top },
    { "select-bottom",              "Extend selection to end of document",
        Mod.ctrl|Mod.shift|Key.End, &select_bottom },
    { "select-all",                 "Select entire document",
        Mod.ctrl|Key.A,             &select_all },
    { "select",                     "Start a selection range",
        0,                          &select },
    // Mode, panel...
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
        Mod.ctrl|Key.N,             &find_next },
    { "find-prev",                  "Repeat search backward",
        Mod.shift|Key.N,            &find_prev },
    // Data manipulation
    { "replace",                    "Replace data using a pattern",
        0,                          &replace_ }, // avoid Phobos comflict
    { "insert",                     "Insert data using a pattern",
        0,                          &insert_ }, // avoid Phobos comflict
    { "replace-file",               "Replace data using a file",
        0,                          &replace_file },
    { "insert-file",                "Insert data using a file",
        0,                          &insert_file },
    // NOTE: "save-as" exists solely because it's a dedicated operation
    //       Despite that "save" could have just gotten an optional parameter
    { "save",                       "Save document to file",
        Mod.ctrl|Key.S,             &save },
    { "save-as",                    "Save document as a different file",
        Mod.ctrl|Key.O,             &save_as },
    // Undo-Redo
    { "undo",                       "Undo last edit",
        Mod.ctrl|Key.U,             &undo },
    { "redo",                       "Redo previously undone edit",
        Mod.ctrl|Key.R,             &redo },
    // Position
    { "goto",                       "Navigate or jump to a specific position",
        Mod.ctrl|Key.G,             &goto_ },
    // Reports
    { "report-position",            "Report cursor position on screen",
        Mod.ctrl|Key.P,             &report_position },
    { "report-name",                "Report document name on screen",
        0,                          &report_name },
    { "report-version",             "Report ddhx version on screen",
        0,                          &report_version },
    // Exports
    { "export-range",               "Export selected range to file",
        0,                          &export_range },
    // Misc actions
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
///     path = Target path.
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
                // "error: " is not prepended, because a message is already
                // an indicator that something happened.
                // For example, "Not implemented" is self-descriptive enough
                // to say "oh yeah, that's an error".
                // Plus, likely a waste of space.
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
        switch (session.rc.writemode) {
        case WritingMode.readonly:
            message("Can't edit in read-only mode");
            goto Lupdate;
        default:
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
            // Forcing to move cursor forces the edit to be applied,
            // since cursor position when starting an edit is saved
            try move_right(g_session, null);
            catch (Exception ex)
            {
                log("%s", ex);
                message(ex.msg);
            }
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
    
    g_status |= UVIEW; // view buffer size will be updated
    
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

string tempName(string basename)
{
    import std.random : uniform;
    import std.format : format;
    return format("%s.tmp-ddhx-%u", basename, uniform(10_000, 100_000)); // 10,000..99,999 incl.
}

// Save changes to this file
void save_file(IDocumentEditor editor, string target)
{
    log("SAVING target=%s", target);
    
    // NOTE: Caller is responsible to populate target path.
    //       Using assert will stop the program completely,
    //       which would not appear in logs (if enabled).
    //       This also allows the error message to be seen.
    assertion(target != null,    "target is NULL");
    assertion(target.length > 0, "target is EMPTY");
    
    import std.stdio : File;
    import std.conv  : text;
    import std.path : baseName, dirName, buildPath;
    import std.file : rename, exists,
        getAttributes, setAttributes, getTimes, setTimes;
    import std.datetime.systime : SysTime;
    import os.file : availableDiskSpace;
    
    long docsize = editor.size();
    
    // We need enough disk space for the temporary file
    ulong avail = availableDiskSpace(target);
    log("avail=%u docsize=%d", avail, docsize);
    if (avail < docsize)
        throw new Exception(text("Unsuficient space, need ", docsize - avail, " bytes"));
    
    // 1. Create a temp file into same directory (with tmp suffix)
    string basedir = dirName(target);
    string basenam = baseName(target);
    string tmpname = tempName(basenam);
    string tmppath = buildPath(basedir, tmpname);
    log(`basedir="%s" basenam="%s" tmpname="%s" tmppath="%s"`,
        basedir, basenam, tmpname, tmppath);
    
    { // scope allows earlier buffer being freed
        // Read buffer
        import core.stdc.stdlib : malloc, free;
        enum BUFFER_SIZE = 16 * 1024;
        ubyte[] buffer = (cast(ubyte*)malloc(BUFFER_SIZE))[0..BUFFER_SIZE];
        if (buffer is null)
            throw new Exception("error: Out of memory");
        scope(exit) free(buffer.ptr);
    
        // 2. Write data
        //    Could also do a hash and compare. Could be a debug option.
        File fileout = File(tmppath, "w");
        long position;
        do
        {
            fileout.rawWrite( editor.view(position, buffer) );
            position += BUFFER_SIZE;
        }
        while (position < docsize);
        fileout.flush();
        fileout.sync();
        fileout.close();
    }
    
    // 3. Copy attributes of target
    //    NOTE: Times
    //          POSIX only has concepts of access and modify times.
    //          Both are irrelevant for saving, but sadly, since there are no
    //          concepts of birth date handling (assumed read-only), then I
    //          won't rip my hair trying to get and set it to target.
    //          Windows... There are no std.file.setTimesWin. Don't know why.
    bool target_exists = exists(target);
    uint attr = void;
    if (target_exists)
        attr = getAttributes(target);
    
    // 4. Replace target
    //    NOTE: std.file.rename
    //          Windows: Uses MoveFileExW with MOVEFILE_REPLACE_EXISTING.
    //                   Remember, TxF (transactional stuff) is deprecated!
    //          POSIX: Confirmed a to be atomic on POSIX platforms.
    rename(tmppath, target);
    
    // 5. Apply attributes to target
    //    Windows: Hidden, system, etc.
    //    POSIX: Permissions
    if (target_exists)
        setAttributes(target, attr);
    editor.markSaved();
    
    // Generic house cleaning
    import core.memory : GC;
    GC.collect();
    GC.minimize();
}
unittest
{
    import backend.dummy : DummyDocumentEditor;
    import std.file : remove, readText, exists;
    
    static immutable path = "tmp_save_test";
    
    // In case residue exists from a failing test
    if (exists(path))
        remove(path);
    
    // Save file as new (target does not exist)
    static immutable string data0 = "test data";
    scope IDocumentEditor e0 = new DummyDocumentEditor(cast(immutable(ubyte)[])data0);
    save_file(e0, path);
    if (readText(path) != data0)
    {
        remove(path); // Let's not leave residue
        assert(false, "Save content differs for data0");
    }
    
    // Save different data to existing path (target exists)
    static immutable string data1 = "test data again!";
    scope IDocumentEditor e1 = new DummyDocumentEditor(cast(immutable(ubyte)[])data1);
    save_file(e1, path);
    if (readText(path) != data1)
    {
        remove(path); // Let's not leave residue
        assert(false, "Save content differs for data1");
    }
    remove(path);
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
        if (session.rc.writemode == WritingMode.overwrite)
            session.editor.replace(g_editcurpos, g_editbuf.ptr, ubyte.sizeof);
        else
            session.editor.insert(g_editcurpos, g_editbuf.ptr, ubyte.sizeof);
        g_status |= UVIEW; // new data
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
        g_status |= UVIEW; // missing data
    }
    else if (pos >= session.position_view + count) // cursor is ahead of view
    {
        session.position_view = align64up(pos - count + 1, session.rc.columns);
        g_status |= UVIEW; // missing data
    }
    
    session.position_cursor = pos;
    g_status |= USTATUSBAR;
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
        g_status |= UMESSAGE | USTATUSBAR;
    }
    catch (Exception ex)
    {
        log("%s", ex);
        message("%s", ex.msg);
    }
}

// Render header bar on screen
void update_header(Session *session, TerminalSize termsize)
{
    terminalCursor(0, 0);
    
    import utils : BufferedWriter;
    BufferedWriter!((void *data, size_t size) {
        terminalWrite(data, size);
    }) buffwriter;
    
    // Print spacers and current address type
    string atype = addressTypeToString(session.rc.address_type);
    int prespaces = session.rc.address_spacing - cast(int)atype.length;
    buffwriter.put(' ', prespaces);
    buffwriter.put(atype);
    buffwriter.put(' ', 1);
    
    int cols = session.rc.columns;
    int cwidth = dataSpec(session.rc.data_type).spacing; // data width spec (for alignment with col headers)
    char[32] buf = void;
    for (int col; col < cols; ++col)
    {
        string chdr = formatAddress(buf[], col, cwidth, session.rc.address_type);
        buffwriter.put(' ', 1);
        buffwriter.put(chdr);
    }
    
    // Fill rest of upper bar with spaces
    int rem = termsize.columns - cast(int)buffwriter.length() - 1;
    if (rem > 0)
        buffwriter.put(' ', rem);
    
    buffwriter.flush();
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
    
    // Read data from editor
    // NOTE: To avoid unecessary I/O, call .view() when:
    //       - base position changed (when base pos changes, set UVIEW)
    //       - read size changed (resize event, set UVIEW flag)
    //       - new edit (set UVIEW when inserting/replacing/deleting)
    //       - undo or redo (set UVIEW)
    //       Basically, just rely on UVIEW flag.
    // NOTE: scope array allocations does nothing.
    //       This is a non-issue since the conservative GC will keep the
    //       allocation alive and simply resize it (either pool or realloc).
    // NOTE: new expression clears memory (memset).
    //       Unwanted, so avoid it to avoid wasting cpu time.
    __gshared ubyte[] viewbuf;
    __gshared ubyte[] result;
    __gshared int readlen;
    if (g_status & UVIEW) // view data needs to be updated
    {
        debug if (logging) sw.start(); // For IDocumentEditor.view()
        
        if (viewbuf.length != count) // only resize if required
            viewbuf.length = count;
        result  = session.editor.view(address, viewbuf);
        readlen = cast(int)result.length;
        
        debug if (logging)
        {
            sw.stop();
            log("TIME view=%s", sw.peek());
            sw.reset();
        }
    }
    
    // Effective number of rows to render
    int erows = readlen / cols;
    // If col count flush and "view incomplete", add row
    if (readlen % cols == 0 && readlen < count) erows++;
    // If col count not flush (near EOF) and view full, add row
    else if (readlen % cols) erows++;
    
    debug if (logging) sw.start();
    
    // Selection stuff
    Selection sel = selection(session);
    int sl0   = cast(int)(sel.start - address);
    int sl1   = cast(int)(sel.end   - address);
    
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
    
    import utils : BufferedWriter;
    BufferedWriter!((void *data, size_t size) {
        terminalWrite(data, size);
    }) buffwriter;
    int row;
    for (; row < erows; ++row, address += cols)
    {
        // '\n' counts as a character (on conhost), avoid using it
        terminalCursor(0, row + 1);
        
        buffwriter.clear();
        
        string addr = formatAddress(txtbuf, address, addspacing, session.rc.address_type);
        //size_t w = terminalWrite(addr, " "); // row address + spacer
        buffwriter.put(addr);
        buffwriter.put(" ");
        
        // Render view data
        for (int col; col < cols; ++col)
        {
            int i = (row * cols) + col;
            
            if (session.selection.status && i >= sl0 && i <= sl1 && panel == PanelType.data)
            {
                buffwriter.flush;
                // Depending where spacer is placed, invert its color earlier
                if (i != sl0) terminalInvertColor();
                /*w += */terminalWrite(" "); // data-data spacer
                if (i == sl0) terminalInvertColor();
                /*w += */terminalWrite(dfmt.formatdata());
                terminalResetColor();
                continue;
            }
            
            // BUG: When i == viewpos && we have selection, cursor renders
            bool highlight = i == viewpos && panel == PanelType.data;
            
            //w += terminalWrite(" "); // data-data spacer
            buffwriter.put(" ");
            
            if (highlight)
            {
                buffwriter.flush();
                terminalInvertColor();
            }
            
            if (g_editdigit && highlight) // apply current edit at position
            {
                dfmt.skip();
                /*w += */terminalWrite(
                    formatData(txtbuf, g_editbuf.ptr, g_editbuf.length, session.rc.data_type)
                );
            }
            else if (i < readlen) // apply data
            {
                //w += terminalWrite(dfmt.formatdata());
                if (highlight)
                    terminalWrite(dfmt.formatdata());
                else
                    buffwriter.put(dfmt.formatdata());
            }
            else // no data, print spacer
            {
                //w += terminalWriteChar(' ', datawidth);
                if (highlight)
                    terminalWriteChar(' ', datawidth);
                else
                    buffwriter.put(' ', datawidth);
            }
            
            if (highlight) terminalResetColor();
        }
        
        // data-text spacer
        //w += terminalWrite("  ");
        buffwriter.put(' ', 2);
        
        // Render character data
        for (int col; col < cols; ++col)
        {
            int i = (row * cols) + col;
            
            if (session.selection.status && i >= sl0 && i <= sl1 && panel == PanelType.text)
            {
                buffwriter.flush();
                terminalInvertColor();
                string c = transcode(result[i], session.rc.charset);
                /*w += */terminalWrite(c ? c : ".");
                terminalResetColor();
                continue;
            }
            
            bool highlight = i == viewpos && panel == PanelType.text;
            
            if (highlight)
            {
                buffwriter.flush();
                terminalInvertColor();
            }
            
            if (i < readlen)
            {
                // NOTE: Escape codes do not seem to be a worry with tests
                string c = transcode(result[i], session.rc.charset);
                //w += terminalWrite(c ? c : ".");
                if (highlight)
                    terminalWrite(c ? c : ".");
                else
                    buffwriter.put(c ? c : ".");
            }
            else // no data
            {
                //w += terminalWrite(" ");
                if (highlight)
                    terminalWrite(" ");
                else
                    buffwriter.put(' ', 1);
            }
            
            if (highlight) terminalResetColor();
        }
        
        // Fill rest of spaces
        // NOTE: Commented because of other fuckery around cursor
        //       Don't want to deal with it now and this shit is after
        //       character column -- empty space. This is also semi-useless.
        /*int f = termsize.columns - cast(int)buffwriter.length();
        if (f > 0)
            buffwriter.put(' ', f);*/
        
        buffwriter.flush;
    }
    
    // NOTE: terminalWriteChar does buffering on its own
    //       Increased stack buffer size from 32 to 128 to help
    int tcols = termsize.columns - 1;
    for (; row < rows; ++row)
    {
        terminalCursor(0, row + 1);
        terminalWriteChar(' ', tcols);
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
    
    // If there is a pending message, print that.
    // Otherwise, print status bar using the message buffer space.
    Selection sel = selection(session);
    string msg = void;
    if (g_status & UMESSAGE)
    {
        msg = g_messagebuf;
    }
    else if (sel)
    {
        string start = formatAddress(buf0, sel.start, 1, session.rc.address_type);
        string end   = formatAddress(buf1, sel.end,   1, session.rc.address_type);
        msg = cast(string)sformat(statusbuf, "SEL: %s-%s (%d Bytes)", start, end, sel.length);
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

/// Search buffer (haystack) size.
enum SEARCH_SIZE = 16 * 1024;

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
    
    assertion(needle, "Need needle");
    
    // Throwing on malloc failure is weird... but uses less memory than a search buffer
    ubyte[] hay = (cast(ubyte*)malloc(SEARCH_SIZE))[0..SEARCH_SIZE];
    if (hay is null)
        throw new Exception("error: Out of memory");
    scope(exit) free(hay.ptr);
    
    log("position=%d flags=%#x needle=[%(%#x,%)]", position, flags, needle);
    
    int diff = flags & SEARCH_DIFF;
    size_t alignment = flags & SEARCH_ALIGNED ? needle.length : 1;
    
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
    
    // Selection: needle
    ubyte[] needle;
    Selection sel = selection(session);
    if (sel)
    {
        if (sel.length > MiB!256)
            throw new Exception("Selection too big");
        needle.length = cast(size_t)sel.length;
        needle = session.editor.view(sel.start, needle);
        if (needle.length < sel.length)
            return; // Nothing to do
    }
    else // data by cursor position
    {
        // Get current element
        ubyte buffer = void;
        needle = session.editor.view(curpos, &buffer, ubyte.sizeof);
        if (needle.length < ubyte.sizeof)
            return; // Nothing to do
        sel.start = curpos;
    }
    
    session.selection.status = 0;
    
    // Move even if nothing found, since it is the intent.
    // In a text editor, if Ctrl+Left is hit (imagine a long line of same
    // characters) the cursor still moves to the start of the document.
    moveabs(session,
        search(session, needle, sel.start - needle.length,
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
    
    // Selection: Needle
    ubyte[] needle;
    Selection sel = selection(session);
    if (sel)
    {
        if (sel.length > MiB!256)
            throw new Exception("Selection too big");
        needle.length = cast(size_t)sel.length;
        needle = session.editor.view(sel.start, needle);
        if (needle.length < sel.length)
            return; // Nothing to do
    }
    else // data by cursor position
    {
        // Get current element
        ubyte buffer = void;
        needle = session.editor.view(curpos, &buffer, ubyte.sizeof);
        if (needle.length < ubyte.sizeof)
            return; // Nothing to do
        sel.start = curpos;
    }
    
    session.selection.status = 0;
    
    moveabs(session,
        search(session, needle, sel.start + needle.length,
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
// Deletion
//

void delete_front(Session *session, string[] args)
{
    Selection sel = selection(session);
    if (sel)
    {
        session.editor.remove(sel.start, sel.length);
        unselect(session);
        g_status |= UVIEW;
        
        // HACK: force cursor to go back to start of selection
        //       Fixes cursor "disappearing"
        moveabs(session, sel.start);
        return;
    }
    
    // Delete element where cursor points to
    long curpos = session.position_cursor;
    if (curpos == session.editor.size()) // nothing to delete in front
        return;
    session.editor.remove(curpos, 1);
    g_status |= UVIEW;
}

void delete_back(Session *session, string[] args)
{
    Selection sel = selection(session);
    if (sel)
    {
        session.editor.remove(sel.start, sel.length);
        unselect(session);
        g_status |= UVIEW;
        
        // See HACK command in delete_front
        moveabs(session, sel.start);
        return;
    }
    
    // Delete element behind cursor
    if (session.position_cursor == 0) // nothing to delete behind cursor
        return;
    moverel(session, -1);
    session.editor.remove(session.position_cursor, 1);
    g_status |= UVIEW;
}


//
// Selection
//

/// Selection information
struct Selection
{
    long start, end, length;
    alias length this;
}

// Force unselection
void unselect(Session *session)
{
    session.selection.status = 0;
}

// Get selection information
Selection selection(Session *session)
{
    import std.algorithm.comparison : min, max;
    
    Selection sel;
    if (session.selection.status == 0)
        return sel;
    
    sel.start = min(session.selection.anchor, session.position_cursor);
    sel.end   = max(session.selection.anchor, session.position_cursor);
    
    if (sel.end >= session.editor.size())
        sel.end--;
    
    // End marker is inclusive
    sel.length = sel.end - sel.start + 1;
    
    return sel;
}
unittest
{
    Session session;
    
    import backend.dummy : DummyDocumentEditor;
    session.editor = new DummyDocumentEditor(); // needed for length
    
    // Not selected
    Selection sel = selection(&session);
    assert(sel == 0);
    
    // Emulate a selection where cursor is behind anchor
    session.selection.status = 1;
    session.selection.anchor = 4;
    session.position_cursor  = 2;
    
    sel = selection(&session);
    assert(sel.length == 3);
    assert(sel.start  == 2);
    assert(sel.end    == 4);
    
    // Emulate a selection where only one element is selected
    session.selection.status = 1;
    session.selection.anchor = 2;
    session.position_cursor  = 2;
    sel = selection(&session);
    assert(sel.length == 1);
    assert(sel.start  == 2);
    assert(sel.end    == 2);
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

// Select from current position to start of document
void select_top(Session *session, string[] args)
{
    long docsize = session.editor.size();
    if (docsize < 1)
        return;
    
    session.selection.anchor = session.position_cursor;
    session.position_cursor  = 0;
    session.selection.status = 1;
}

// Select from current position to end of document
void select_bottom(Session *session, string[] args)
{
    long docsize = session.editor.size();
    if (docsize < 1)
        return;
    
    session.selection.anchor = session.position_cursor;
    session.position_cursor  = docsize - 1;
    session.selection.status = 1;
}

// Select all of document
void select_all(Session *session, string[] args)
{
    long docsize = session.editor.size();
    if (docsize < 1)
        return;
    
    session.selection.anchor = 0;
    session.position_cursor  = docsize - 1;
    session.selection.status = 1;
}

// Start an explicit selection
void select(Session *session, string[] args)
{
    string start = arg(args, 0, "Start: ");
    if (start is null)
        return;
    string end   = arg(args, 1, "End: ");
    if (end is null)
        return;
    
    import utils : scan;
    session.selection.status = 0;
    session.selection.anchor = scan( start ); // throws if wrong
    session.position_cursor  = scan( end );   // throws if wrong
    session.selection.status = 1;
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
    {
        moveabs(session, pos);
        g_status |= UVIEW; // new data
    }
}

// 
void redo(Session *session, string[] args)
{
    long pos = session.editor.redo();
    if (pos >= 0)
    {
        moveabs(session, pos);
        g_status |= UVIEW; // new data
    }
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
// Go to position in document
void goto_(Session *session, string[] args)
{
    import utils : scan;
    
    long position = void;
    bool absolute = void;
    
    // Selection
    Selection sel = selection(session);
    if (sel)
    {
        if (sel.length > long.sizeof)
            throw new Exception("Selection too large");
        
        B b; // = {0}
        
        ubyte[] res = session.editor.view(sel.start, b.ptr, cast(size_t)sel.length);
        
        absolute = true;
        
        if (res.length > uint.sizeof) // same as selection length but.. size_t
            position = b.u64;
        else if (res.length > ushort.sizeof)
            position = b.u32;
        else if (res.length > ubyte.sizeof)
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
            
            // TODO: Support double (mantissa issue isn't real)
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
    Selection sel = selection(session);
    if (sel)
    {
        message("%d-%d B (%f%%-%f%%)",
            sel.start, sel.end,
            cast(float)sel.start / docsize * 100,
            cast(float)sel.end   / docsize * 100);
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
    
    message( session.target is null ?
        "(new buffer)" :
        baseName(session.target) );
}

// Report program version on screen
void report_version(Session *session, string[] args)
{
    message( DDHX_VERSION );
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

// Export selected range to file
void export_range(Session *session, string[] args)
{
    Selection sel = selection(session);
    if (sel.length == 0)
        throw new Exception("Need selection");
    
    // TODO: Check if target exists
    string name = arg(args, 0, "Name: ");
    if (name is null || name.length == 0)
        return;
    
    import std.stdio : File;
    File output = File(name, "w");
    
    // Re-using search alloc func because lazy
    enum EXPORT_SIZE = 4096; // export buffer, tend to be smaller
    import core.stdc.stdlib : malloc, free;
    ubyte[] buf = (cast(ubyte*)malloc(EXPORT_SIZE))[0..EXPORT_SIZE];
    if (buf is null)
        throw new Exception("error: Out of memory");
    scope(exit) free(buf.ptr);
    
    // HACK: end is inclusive. D ranges are not.
    sel.end++;
    
    import std.algorithm.comparison : min;
    while (sel.start < sel.end)
    {
        long left = sel.end - sel.start;
        long want = min(left, EXPORT_SIZE);
        ubyte[] res = session.editor.view(sel.start, buf.ptr, cast(size_t)want);
        
        output.rawWrite(res);
        sel.start += EXPORT_SIZE;
    }
    
    // Unfortunately to force the message through
    unselect(session);
    
    message("Saved as %s", name); // confirmation
}

// Replace data using pattern
void replace_(Session *session, string[] args)
{
    Selection sel = selection(session);
    
    if (sel)
    {
        if (args.length < 1)
            throw new Exception("Need pattern");
        ubyte[] p = pattern(session.rc.charset, args[0]);
        session.editor.patternReplace(sel.start, sel.length, p.ptr, p.length);
        g_status |= UVIEW | UHEADER | USTATUSBAR;
        return;
    }
    
    throw new Exception("TODO: By range");
}

// Insert data using pattern
void insert_(Session *session, string[] args)
{
    Selection sel = selection(session);
    
    if (sel)
    {
        if (args.length < 1)
            throw new Exception("Need pattern");
        ubyte[] p = pattern(session.rc.charset, args);
        session.editor.patternInsert(sel.start, sel.length, p.ptr, p.length);
        g_status |= UVIEW | UHEADER | USTATUSBAR;
        return;
    }
    
    throw new Exception("TODO: By range");
}

// Replace data using file
void replace_file(Session *session, string[] args)
{
    string path = arg(args, 0, "File: ");
    
    import document.file : FileDocument;
    import document.base : IDocument;
    
    IDocument file = new FileDocument(path, true);
    long curpos = session.position_cursor;
    
    session.editor.fileReplace(curpos, file);
    g_status |= UVIEW;
}

// Insert data using file
void insert_file(Session *session, string[] args)
{
    string path = arg(args, 0, "File: ");
    
    import document.file : FileDocument;
    import document.base : IDocument;
    
    IDocument file = new FileDocument(path, true);
    long curpos = session.position_cursor;
    
    session.editor.fileInsert(curpos, file);
    g_status |= UVIEW;
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
    save_file(session.editor, session.target);
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

// TODO: Range interface
//       Syntax: START:END (inclusive)
//       0x10:0x100, 20:$, etc.
/*struct Range
{
    long start, end;
}
Range range(string expr)
{
    Range range;
    
    
    
    return range;
}
unittest
{
    assert(range("5:25") == Range( 5, 25 ));
}*/

/// Artificial needle size limit for find/find-back.
enum SEARCH_LIMIT = KiB!128;

//
void find(Session *session, string[] args)
{
    Selection sel = selection(session);
    
    // If arguments: Take those before selection
    if (args && args.length > 0)
    {
        g_needle = pattern(session.rc.charset, args);
        sel.start = session.position_cursor + g_needle.length;
    }
    else if (sel) // selection
    {
        if (sel.length > SEARCH_LIMIT)
            throw new Exception("Selection too big");
        g_needle.length = cast(size_t)sel.length;
        g_needle = session.editor.view(sel.start, g_needle);
        if (g_needle.length < sel.length)
            return; // Nothing to do
        sel.start += g_needle.length;
    }
    else // TODO: Ask using arg() + arguments()
        throw new Exception("Need find info");
    
    unselect(session);
    long p = search(session, g_needle, sel.start, 0);
    if (p < 0)
        throw new Exception("Not found");
    
    moveabs(session, p);
    
    char[32] buf = void;
    message("Found at %s", formatAddress(buf, p, 1, session.rc.address_type));
}

//
void find_back(Session *session, string[] args)
{
    Selection sel = selection(session);
    
    // If arguments: Take those before selection
    if (args && args.length > 0)
    {
        g_needle = pattern(session.rc.charset, args);
        sel.start = session.position_cursor - g_needle.length;
    }
    else if (sel) // selection
    {
        if (sel.length > SEARCH_LIMIT)
            throw new Exception("Selection too big");
        g_needle.length = cast(size_t)sel.length;
        g_needle = session.editor.view(sel.start, g_needle);
        if (g_needle.length < sel.length)
            return; // Nothing to do, couldn't read all of needle
        sel.start -= g_needle.length;
    }
    else // TODO: Ask using arg() + arguments()
        throw new Exception("Need find info");
    
    unselect(session);
    long p = search(session, g_needle, sel.start, SEARCH_REVERSE);
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
        switch (promptkey("Save? (Yes/No/Cancel) ")) {
        case 'n', 'N':
            goto Lexit; // quit without saving
        case 'y', 'Y':
            save(session, null); // save and continue to quit
            break;
        default:
            // Canceling isn't an error
            message("Canceled");
            return;
        }
    }
    
Lexit:
    import core.stdc.stdlib : exit;
    terminalRestore();
    exit(0);
}