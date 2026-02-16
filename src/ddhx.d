/// Interactive hex editor application, defines behavior for main program.
///
/// Also dubbed the View System. It attempts to visually represent types
/// on screen.
/// 
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx;

import configuration;
import core.stdc.stdlib : malloc, realloc, free, exit;
import document.base : IDocument;
import document.file : FileDocument;
import document.file;
import editor.base : IDocumentEditor;
import formatting;
import logger;
import os.terminal;
import patterns;
import platform : assertion;
import ranges;
import std.algorithm.comparison : min, max;
import std.conv : text;
import std.file : exists;
import std.string; // imports format
import transcoder;
import utils : BufferedWriter;

private debug enum DEBUG = "+debug"; else enum DEBUG = "";

/// Copyright string
immutable string DDHX_COPYRIGHT = "Copyright (c) 2017-2026 dd86k <dd@dax.moe>";
/// App version
immutable string DDHX_VERSION   = "0.8.3"~DEBUG;
/// Build information
immutable string DDHX_BUILDINFO = "Built: "~__TIMESTAMP__;

private enum // Internal editor status flags
{
    // Read from editor, content changed
    UREAD       = 1 << 1,
    UVIEW       = UREAD,    // older alias for UREAD
    // Update the header
    UHEADER     = 1 << 2,
    // Update statusbar
    USTATUS     = 1 << 3,
    USTATUSBAR  = USTATUS,  // older alias for USTATUS
    
    // Pending message
    UMESSAGE    = 1 << 16,
    // Editing in progress
    UEDITING    = 1 << 17,
    
    //
    UALL    = UHEADER | UVIEW | USTATUS,
    UINIT   = UALL,         // older alias for UALL
}

private enum PanelType
{
    data,
    text,
    //inspector,
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
    int status;     /// current status
}

private enum {
    /// Selection is active and has a range going
    SELECT_ACTIVE   = 1,
    /// Mark started, so don't clear it
    SELECT_ONGOING  = 2,
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
    
    // NOTE: Maximum number of handles
    //
    //       The front-end uses FileDocument class to open files, which uses OSFile.
    //       OSFile uses the operating system native File API, and not the C runtime's,
    //       which is typically limited from 512 to 4096 handles per process (and 32-bit seeks).
    //
    //       On Windows, that's typically about 64K (Win32) or 16M (Win64) file handles.
    //       16K for network files.
    //
    //       On Linux, querying prlimit.1 (6.17-generic amd64), or /proc/self/limits,
    //       for NOFILE ("Max open files"), yields 1024 as a soft limit, and 524288 as a
    //       hard limit.
    //
    //       Don't even worry about closing handles for undo operations because a redo will
    //       require to re-open that file anyway.
    /// Opened documents.
    ///
    /// Since the front-end is the one opening files, make it the one to track
    /// them as well. This leaves editors without the duty to manage them,
    /// making testing easier.
    IDocument[] documents;
    
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
    // Editor status, resetted every time update() is called
    int g_status;
    
    // Number of effective rows in view, updated by update()
    int g_rows;
    
    // Number of bytes for a row, updated by update()
    int g_linesize;
    
    // HACK: Global for screen resize events
    // Eventually, a session manager could hold multiple sessions and return
    // the 'current' session (return sessions[current]).
    Session *g_session;
    
    // Message buffer.
    // Sadly, format() allocates a buffer and sformat() throws when it runs out
    // of the buffer instead of resizing (that would suck to implement anyway).
    char[] g_messagebuf;
    // Message slice result.
    string g_message;
    
    /// Last search needle buffer (find commands use this).
    ubyte[] g_needle;
    
    /// Position of cursor when edit started
    long g_editcurpos;
    /// Input system
    InputFormatter g_input;
    
    /// Global clipboard buffer.
    ubyte *g_clipboard_ptr;
    size_t g_clipboard_len;
    
    /// Registered commands
    command_func[string] g_commands;
    /// Registered shortcuts
    Keybind[int] g_keys;
    
    /// 
    ColorMapper g_colors;
}

/// Represents a command with a name (required), a shortcut, and a function
/// that implements it (required).
struct Command
{
    string name;        /// Command short name
    string description; /// Short description
    int key;            /// Default shortcut
    command_func impl;  /// Implementation
}

// Reserved (Ideal: Ctrl=Action, Alt=Alternative):
// - "toggle-inspector" (Alt+I): Toggle data inspector
// - "hash": Hash selection with result in status
//           Mostly checksums and digests under 256 bits.
//           256 bits -> 32 Bytes -> 64 hex characters
// - "bookmark-add RANGE": Add bookmark
// - "bookmark-remove RANGE": Remove all bookmarks touched by RANGE
// - "bookmark-next": Next bookmark
// - "bookmark-prev": Previous bookmark
// NOTE: Command names
//       Because navigation keys are the most essential, they get short names.
//       For example, mpv uses LEFT and RIGHT to bind to "seek -10" and "seek 10".
//       Here, both "bind ctrl+9 right" and "bind ctrl+9 goto +1" are both valid.
//       I probably would have preferred to go with "do-thing" syntax, but
//       I somehow decided to go with "thing-do". Oh well.
// NOTE: Command designs
//       - Names: If commonly used (ie, navigation), command is one word
//       - Selection: command parameters are prioritized over selections
/// List of default commands and shortcuts
immutable Command[] default_commands = [
    // Navigation
    { "left",                       "Move cursor left one element",
        Key.LeftArrow,              &move_left },
    { "right",                      "Move cursor right one element",
        Key.RightArrow,             &move_right },
    { "up",                         "Move cursor upward a line",
        Key.UpArrow,                &move_up },
    { "down",                       "Move cursor downward a line",
        Key.DownArrow,              &move_down },
    { "home",                       "Move cursor to start of line",
        Key.Home,                   &move_ln_start },
    { "end",                        "Move cursor to end of line",
        Key.End,                    &move_ln_end },
    { "top",                        "Move cursor to start of document",
        Mod.ctrl|Key.Home,          &move_abs_start },
    { "bottom",                     "Move cursor to end of document",
        Mod.ctrl|Key.End,           &move_abs_end },
    { "page-up",                    "Move cursor up a screen",
        Key.PageUp,                 &move_pg_up },
    { "page-down",                  "Move cursor down a screen",
        Key.PageDown,               &move_pg_down },
    { "view-up",                    "Move view up a row",
        Mod.ctrl|Key.UpArrow,       &view_up },
    { "view-down",                  "Move view down a row",
        Mod.ctrl|Key.DownArrow,     &view_down },
    { "skip-back",                  "Skip same elements backends",
        Mod.ctrl|Key.LeftArrow,     &move_skip_backward },
    { "skip-front",                 "Skip same elements forward",
        Mod.ctrl|Key.RightArrow,    &move_skip_forward },
    // Deletions
    { "delete",                     "Delete data at cursor position",
        Key.Delete,                 &delete_front },
    { "delete-back",                "Delete data before cursor position",
        Key.Backspace,              &delete_back },
    // Selections
    { "select-left",                "Extend selection one element backward",
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
    { "select",                     "Select elements using a range expression",
        0,                          &select },
    { "mark" ,                      "Start a selection",
        0,                          &mark },
    { "unmark",                     "End selection",
        0,                          &unmark },
    // Mode, panel...
    { "change-panel",               "Switch data panel",
        Key.Tab,                    &change_panel },
    { "change-mode",                "Change writing mode (between overwrite and insert)",
        Key.Insert,                 &change_writemode },
    // Find
    { "find",                       "Find data in document using patterns",
        Mod.ctrl|Key.F,             &find },
    { "find-back",                  "Find data in document, backward direction",
        Mod.ctrl|Key.B,             &find_back },
    { "find-next",                  "Repeat search forward",
        Mod.ctrl|Key.N,             &find_next },
    { "find-prev",                  "Repeat search backward",
        Mod.shift|Key.N,            &find_prev },
    // Data manipulation
    { "replace",                    "Replace data using a pattern",
        0,                          &replace_ }, // avoid Phobos conflict
    { "insert",                     "Insert data using a pattern",
        0,                          &insert_ }, // avoid Phobos conflict
    { "replace-file",               "Replace data using a file",
        0,                          &replace_file },
    { "insert-file",                "Insert data using a file",
        0,                          &insert_file },
    // Copy-Paste
    { "copy",                       "Copy data into buffer",
        Mod.alt|Key.C,              &clip_copy },
    { "cut",                        "Copy data into buffer and delete selection",
        Mod.alt|Key.X,              &clip_cut },
    { "paste",                      "Paste clipboard data into document", // modal!
        Mod.alt|Key.V,              &clip_paste },
    { "clear-clip",                 "Clear clipboard data",
        0,                          &clip_clear },
    { "save",                       "Save document",
        Mod.ctrl|Key.S,             &save },
    // NOTE: "save-as" exists solely because it's a dedicated operation.
    //       Despite that "save" could have just gotten an optional parameter.
    //       Analogous to GNU nano having ^O.
    { "save-as",                    "Save document as a different file",
        Mod.ctrl|Key.O,             &save_as },
    // Undo-Redo
    { "undo",                       "Undo last edit",
        Mod.ctrl|Key.U,             &undo },
    { "redo",                       "Redo previous change",
        Mod.ctrl|Key.R,             &redo },
    // Position
    { "goto",                       "Navigate or jump to a specific position",
        Mod.ctrl|Key.G,             &goto_ },
    // Reports
    { "report-position",            "Report position, document size, and % in bytes",
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
    { "set",                        "Set a configuration value for this session",
        0,                          &set },
    { "bind",                       "Bind a shortcut to an action for this session",
        0,                          &bind },
    { "unbind",                     "Remove or reset a bind shortcut",
        0,                          &unbind },
    { "reset-keys",                 "Reset all binded keys to default for this session",
        0,                          &reset_keys },
    { "menu",                       "Invoke command prompt",
        Key.Enter,                  &prompt_command },
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
    
    // Add a "debug" command for, you guessed it, debugging for debug builds
    debug g_commands["debug"] =
    (Session* session, string[] args)
    {
        if (args.length == 0)
            throw new Exception("Missing action");
        
        // Don't need a throw command, this throws plenty
        switch (args[0]) {
        case "msg":
            // Very long message by default
            string msg = args.length > 1 ?
                args[1] :
                "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"~
                "aaaaaa"; // Otherwise, 86x 'a'
            
            message(msg);
            break;
        case "dump":
            string target = args.length > 1 ? args[1] : "ddhx_dump.txt";
            
            import std.stdio : File;
            import std.datetime : Clock;
            import platform : TARGET_ENV, TARGET_OS, TARGET_PLATFORM;
            File file; // Old LDC opAssign bug might resurface, idk
            file.open(target, "w");
            file.writeln("ddhx debug dump");
            file.writeln("Time\t: ", Clock.currTime());
            file.writeln("Version\t: ", DDHX_VERSION);
            file.writeln("System\t: ", TARGET_OS);
            file.writeln("Environment\t: ", TARGET_ENV);
            file.writeln("Platform\t: ", TARGET_PLATFORM);
            file.writeln();
            
            import core.memory : GC;
            GC.Stats stats = GC.stats();
            file.writeln("GC");
            file.writeln("\t", stats.freeSize, " B Free");
            file.writeln("\t", stats.usedSize, " B Used");
            static if (__VERSION__ >= 2087)
                file.writeln("\t", stats.allocatedInCurrentThread, " B Allocated (thread)");
            /*GC.ProfileStats profiler = GC.profileStats(); // Useless if not enabled?
            file.writeln("\t", profiler.numCollections, " Cycles");
            file.writeln("\t", profiler.totalCollectionTime, " Total Collection Time");
            file.writeln("\t", profiler.totalPauseTime, " Total Pause Time");
            file.writeln("\t", profiler.maxPauseTime, " Max Pause Time");
            file.writeln("\t", profiler.maxCollectionTime, " Max Collection Time");*/
            
            file.writeln("Globals");
            file.writeln("\tg_messagebuf.length\t: ", g_messagebuf.length);
            file.writeln("\tg_message.length\t: ", g_message.length);
            file.writeln("\tg_needle.length\t: ", g_needle.length);
            file.writeln("\tg_editcurpos\t: ", g_editcurpos);
            file.writeln("\tg_input.index\t: ", g_input.index);
            file.writeln("\tg_clipboard_ptr\t: ", g_clipboard_ptr);
            file.writeln("\tg_clipboard_len\t: ", g_clipboard_len);
            file.writeln("\tg_commands.length\t: ", g_commands.length);
            file.writeln("\tg_keys.length\t: ", g_keys.length);
            
            file.writeln("Session");
            file.writeln("\tg_session.position_cursor\t: ", g_session.position_cursor);
            file.writeln("\tg_session.position_view\t: ", g_session.position_view);
            file.writeln("\tg_session.target\t: ", g_session.target);
            file.writeln("\tg_session.selection.anchor\t: ", g_session.selection.anchor);
            file.writeln("\tg_session.selection.status\t: ", g_session.selection.status);
            
            file.writeln("Selection");
            Selection sel = selection(g_session);
            file.writeln("\tselection.start\t: ", sel.start);
            file.writeln("\tselection.end\t: ", sel.end);
            file.writeln("\tselection.length\t: ", sel.length);
            
            file.writeln("RC");
            file.writeln("\tg_session.rc.address_spacing\t: ", g_session.rc.address_spacing);
            file.writeln("\tg_session.rc.address_type\t: ", g_session.rc.address_type);
            file.writeln("\tg_session.rc.charset\t: ", g_session.rc.charset);
            file.writeln("\tg_session.rc.columns\t: ", g_session.rc.columns);
            file.writeln("\tg_session.rc.data_type\t: ", g_session.rc.data_type);
            file.writeln("\tg_session.rc.header\t: ", g_session.rc.header);
            file.writeln("\tg_session.rc.status\t: ", g_session.rc.status);
            file.writeln("\tg_session.rc.mirror_cursor\t: ", g_session.rc.mirror_cursor);
            file.writeln("\tg_session.rc.writemode\t: ", g_session.rc.writemode);
            
            // TODO: Dump open documents information
            
            import editor.piecev2 : PieceV2DocumentEditor;
            file.writeln("Editor");
            file.writeln("\tClass\t: ", session.editor); // prints type!
            file.writeln("\tSize\t: ", session.editor.size());
            file.writeln("\tEdited\t: ", session.editor.edited());
            /*
            if (PieceV2DocumentEditor piecev2 = cast(PieceV2DocumentEditor)session.editor)
            {
                // TODO: Make PieceV2DocumentEditor internals visible
                //       Piece table (pos+size), command history, buffer size, etc.
            }
            */
            
            file.flush();
            file.close();
            break;
        default:
            throw new Exception("Exception");
        }
    };
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

pragma(inline)
const(Keybind)* binded(int key)
{
    return key in g_keys;
}


Session* create_session(IDocumentEditor editor, ref RC rc, string path)
{
    Session *session = new Session(rc);
    session.target = path;    // assign target path, a NULL value is valid
    session.editor = editor;  // assign editor instance
    return session;
}

void start_session(Session *session, string initmsg)
{
    terminalInit(TermFeat.altScreen | TermFeat.inputSys);
    // NOTE: Alternate buffers are usually "clean" except on framebuffers (fbcon)
    terminalClear();
    terminalResizeHandler(&onresize);
    terminalHideCursor();
    
    g_session = session;
    
    g_status = UINIT;
    g_messagebuf.length = 4096;
    
    g_input = new InputFormatter; // hack due to buffer escapes
    g_input.change(session.rc.data_type);

    // Sync editor options
    session.editor.coalescing = session.rc.coalescing;
    
    message(initmsg);
    
    loop(g_session);
    
    terminalRestore();
}

private:

void onresize() // NOTE: I/O is allowed here
{
    // TODO: Consider rendering something like "SMALL" if screen too small
    
    // If autoresize configuration is enabled, automatically set column count
    if (g_session.rc.columns == COLUMNS_AUTO)
        autosize(g_session, null);
    
    // Yes, on resize, conhost will show the console's cursor again
    version (Windows)
        terminalHideCursor();
    
    g_status |= UINIT; // draw everything
    update(g_session);
}

// 
void loop(Session *session)
{
    bool ctrlc;
    
Lupdate:
    update(session); // Clears status!
    
Lread:
    TermInput input = terminalRead();
    switch (input.type) {
    case InputType.keyDown:
        if (input.key == (Mod.ctrl | Key.C))
        {
            // Quit without saving
            if (ctrlc)
            {
                terminalRestore();
                exit(0);
            }
            
            session.selection.status = 0; // force all select off
            ctrlc = true;
            message("Again to quit");
            goto Lupdate;
        }
        
        ctrlc = false;
        
        // Key mapped to command
        const(Keybind) *k = binded( input.key );
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
        
        // Check if the writing mode is valid
        switch (session.rc.writemode) {
        case WritingMode.readonly:
            message("Can't edit in read-only mode");
            goto Lupdate;
        default:
        }
        
        // start new edit
        if (g_input.index == 0)
            g_editcurpos = session.position_cursor;
        
        // Prefer kbuffer to key because key gets translated (e.g., 'f' -> 'F')
        if (g_input.add(cast(char)input.kbuffer[0]) == false)
            goto Lread; // don't even bother updating the screen
        
        // We have a valid key and mode, so disrupt selection
        session.selection.status = 0;
        
        // if full, move cursor
        if (g_input.full())
        {
            // Forcing to move cursor forces the edit to be applied,
            // since cursor position when starting an edit is saved.
            // The other of this is in moveabs. It detects when cursor
            // has moved and will proceed with saving, but might throw
            // too.
            try move_right(g_session, null);
            catch (Exception ex)
            {
                log("%s", ex);
                message(ex.msg);
            }
            goto Lupdate;
        }
        
        g_status |= UEDITING; // active edit
        break;
    default:
        goto Lread;
    }
    
    goto Lupdate;
}

// Returns true if key is Key.Escape or Mod.ctrl+Key.C
bool iscancel(int key)
{
    return key == (Mod.ctrl|Key.C) || key == Key.Escape;
}

// Invoke command prompt
string promptline(string prompt)
{
    assert(prompt, "Prompt text missing");
    assert(prompt.length, "Prompt text required"); // disallow empty
    
    // Repaint header at minimum, but with view... Just in case
    g_status |= USTATUS;
    
    // Clear upper space
    TerminalSize tsize = terminalSize();
    
    // Print prompt, cursor will be after prompt
    terminalCursor(0, tsize.rows - 1);
    terminalWrite(prompt);
    
    // Show and hide cursor for this scope. scope(exit) is OK with exceptions
    terminalShowCursor();
    scope(exit) terminalHideCursor();
    
    // Passing x,y to fix issues where obtaining cursor position is not possible
    return readline(cast(int)prompt.length, tsize.rows - 1);
}
int promptkey(string text)
{
    assert(text, "Prompt text missing");
    assert(text.length, "Prompt text required"); // disallow empty
    
    g_status |= USTATUS; // Needs to be repainted anyway
    
    // Clear upper space
    TerminalSize tsize = terminalSize();
    int tcols = tsize.columns - 1;
    if (tcols < 10)
        throw new Exception("Not enough space for prompt");
    terminalCursor(0, tsize.rows - 1);
    terminalWriteChar(' ', tcols);
    
    // Print prompt, cursor will be after prompt
    terminalCursor(0, tsize.rows - 1);
    terminalWrite(text);
    
    terminalShowCursor();
    scope(exit) terminalHideCursor();
    
    // Read character
Lread:
    TermInput input = terminalRead();
    if (input.type != InputType.keyDown)
        goto Lread;
    if (iscancel(input.key))
        throw new Exception("Cancelled");
    
    return input.key;
}

// Command requires argument
string askstring(string[] args, size_t idx, string prefix)
{
    string s = args is null || args.length <= idx ?
        promptline(prefix) : args[idx];
    
    // Empty string? Cancel! Can't do anything with that.
    // Bonus: Besides, throwing an exception is easier to manage than
    // manually checking the output at every invokation.
    if (s is null || s.length == 0)
        throw new Exception("Cancelled");
    
    return s;
}

// Ask for range expression
Range askrange(string[] args, size_t idx, string prefix)
{
    string str = askstring(args, idx, prefix);
    
    Range r = range(str);
    
    switch (r.start) {
    case RangeSentinel.eof: // why would you?
        throw new Exception("Range start cannot be EOF");
    case RangeSentinel.cursor:
        r.start = g_session.position_cursor;
        break;
    default:
    }
    
    long docsize = g_session.editor.size();
    
    switch (r.end) {
    case RangeSentinel.eof:
        r.end = docsize == 0 ? 0 : docsize - 1;
        break;
    case RangeSentinel.cursor:
        r.end = g_session.position_cursor;
        break;
    default:
        if (r.flags & RANGE_RELATIVE)
            r.end = r.start + r.end;
    }
    
    if (r.start < 0)
        throw new Exception("range: Start out of range");
    if (r.end   < 0)
        throw new Exception("range: End out of range");
    if (r.start > r.end)
        throw new Exception("range: Cannot start after end");
    
    return r;
}
// Get length from range result
long rangelen(ref Range r)
{
    return r.end - r.start + 1;
}

string tempName(string basename)
{
    import std.random : uniform;
    import std.format : format;
    return format("%s.tmp-ddhx-%u", basename, uniform(10_000, 100_000)); // 10,000..99,999 incl.
}

// Save changes to file target
void save_to_file(IDocumentEditor editor, string target)
{
    log("target='%s'", target);
    
    // NOTE: Caller is responsible to populate target path.
    //       Using assert will stop the program completely,
    //       which would not appear in logs (if enabled).
    //       This also allows the error message to be seen.
    assertion(target != null,    "target is NULL");
    assertion(target.length > 0, "target is EMPTY");
    
    import std.stdio : File;
    import std.conv  : text;
    import std.path : baseName, dirName, buildPath;
    import std.file : rename, exists, getAttributes, setAttributes;
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
    
    // 2. Allocate buffer, read from editor, and write to temp file
    {
        enum BUFFER_SIZE = 16 * 1024;
        ubyte[] buffer = (cast(ubyte*)malloc(BUFFER_SIZE))[0..BUFFER_SIZE];
        if (buffer is null)
            throw new Exception("error: Out of memory");
        scope(exit) free(buffer.ptr);
        
        File fileout = File(tmppath, "w");
        long position;
        do
        {
            fileout.rawWrite( editor.view(position, buffer) );
            position += BUFFER_SIZE;
        }
        while (position < docsize);
        fileout.flush(); // On the safer side
        fileout.sync();
        fileout.close();
    }
    
    // 3. Copy attributes of target
    // NOTE: Times
    //       POSIX only has concepts of access and modify times.
    //       Both are irrelevant for saving. And sadly, since there are no
    //       concepts of birth date handling (assumed read-only), then I
    //       won't rip my hair trying to get and set it to target.
    //       Windows... There are no std.file.setTimesWin. Don't know why.
    bool target_exists = exists(target);
    uint attr = void;
    if (target_exists)
        attr = getAttributes(target);
    
    // 4. Replace target
    // NOTE: std.file.rename
    //       Windows: Uses MoveFileExW with MOVEFILE_REPLACE_EXISTING.
    //                Remember, TxF (transactional stuff) is deprecated!
    //       POSIX: Confirmed a to be an atomic operation, using rename(3).
    rename(tmppath, target);
    
    // 5. Apply attributes to target
    //    Windows: Hidden, system, etc.
    //    POSIX: Permissions
    if (target_exists)
    {
        // NOTE: GVFS might refuse to set attributes, a minor defect.
        //       A good test is using chmod.1, it will spit out an error.
        try setAttributes(target, attr);
        catch (Exception ex)
        {
            log("[WARNING] setAttributes failed: %s", ex);
        }
    }
    editor.markSaved();
    
    // Generic house cleaning
    import core.memory : GC;
    GC.collect();
    GC.minimize();
}
unittest
{
    import editor.dummy : DummyDocumentEditor;
    import std.file : remove, readText, exists;
    
    static immutable path = "tmp_save_test";
    
    // In case residue exists from a failing test
    if (exists(path))
        remove(path);
    
    // Save file as new (target does not exist)
    static immutable string data0 = "test data";
    scope IDocumentEditor e0 = new DummyDocumentEditor(cast(immutable(ubyte)[])data0);
    save_to_file(e0, path);
    if (readText(path) != data0)
    {
        remove(path); // Let's not leave residue
        assert(false, "Save content differs for data0");
    }
    
    // Save different data to existing path (target exists)
    static immutable string data1 = "test data again!";
    scope IDocumentEditor e1 = new DummyDocumentEditor(cast(immutable(ubyte)[])data1);
    save_to_file(e1, path);
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
    if (g_input.index && g_editcurpos != pos)
    {
        ubyte[] data = g_input.data;
        if (session.rc.writemode == WritingMode.overwrite)
            session.editor.replace(g_editcurpos, data.ptr, data.length);
        else
            session.editor.insert(g_editcurpos, data.ptr, data.length);
        g_input.reset(); // needed so new input isn't confused
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
    
    int data_size = size_of(session.rc.data_type);
    
    // Adjust cursor position to base depending on data size
    // NOTE: Can throw SIGFPE if data_size is wrong (zero?)
    pos -= pos % data_size;
    
    // No need to update if it's at the same place
    if (pos == session.position_cursor)
        return;
    
    // Adjust view position if cursor outside of view
    import utils : align64down, align64up;
    int g = session.rc.columns * data_size; // group size
    int count = g * g_rows;
    if (pos < session.position_view) // cursor is behind view
    {
        session.position_view = align64down(pos, g);
        g_status |= UVIEW; // missing data
    }
    else if (pos >= session.position_view + count) // cursor is ahead of view
    {
        session.position_view = align64up(pos - count + data_size, g);
        g_status |= UVIEW; // missing data
    }
    
    session.position_cursor = pos;
    g_status |= USTATUS;
}

// TODO: Handle multiple messages.
//       It COULD happen that multiple messages are sent before they
//       are displayed. Right now, only the last message is taken into
//       account.
//       Easiest fix would be string[] or something similar.
// Send a message within the editor to be displayed.
void message(A...)(string fmt, A args)
{
    try
    {
        g_message = cast(string)sformat(g_messagebuf, fmt, args);
        g_status |= UMESSAGE | USTATUS;
    }
    catch (Exception ex)
    {
        log("%s", ex);
        message(ex.msg);
    }
}

// Render header bar on screen
void update_header(Session *session, TerminalSize termsize)
{
    terminalCursor(0, 0);
    
    BufferedWriter!((void *data, size_t size) {
        terminalWrite(data, size);
    }, 256) buffwriter;
    
    AddressFormatter address = AddressFormatter(session.rc.address_type);
    DataSpec dataspec = selectDataSpec(session.rc.data_type);
    
    // Print spacers and current address type
    string atype = addressTypeToString(session.rc.address_type);
    int prespaces = session.rc.address_spacing - cast(int)atype.length;
    buffwriter.repeat(' ', prespaces);
    buffwriter.put(atype);
    buffwriter.repeat(' ', 1);
    
    ElementText buf = void;
    int cols = session.rc.columns;
    for (int col, ad; col < cols; ++col, ad += dataspec.size_of)
    {
        buffwriter.repeat(' ', 1);
        buffwriter.put(address.textual(buf, ad, dataspec.spacing));
    }
    
    // Fill rest of upper bar with spaces
    int rem = termsize.columns - cast(int)buffwriter.length();
    if (rem > 0)
        buffwriter.repeat(' ', rem);
    
    buffwriter.flush();
    terminalFlush();
}

struct ElementState
{
    // booleans are fine for now, not looking into high performance right now
    bool isSelected;
    bool isCursor;
    bool hasData;
    bool isActiveEdit;
    bool isZero;
    
    ColorScheme dataScheme(PanelType panel, bool mirror)
    {
        if (isCursor && panel == PanelType.data)
            return ColorScheme.cursor;
        
        if (isSelected && (panel == PanelType.data || mirror))
            return ColorScheme.selection;
        
        if (isCursor && mirror && panel != PanelType.data)
            return ColorScheme.mirror;
        
        if (isZero)
            return ColorScheme.unimportant;
        
        return ColorScheme.normal;
    }
    
    ColorScheme textScheme(PanelType panel, bool mirror)
    {
        if (isCursor && panel == PanelType.text)
            return ColorScheme.cursor;
        
        if (isSelected && (panel == PanelType.text || mirror))
            return ColorScheme.selection;
        
        if (isCursor && mirror && panel != PanelType.text)
            return ColorScheme.mirror;
        
        if (isZero)
            return ColorScheme.unimportant;
        
        return ColorScheme.normal;
    }
}
ElementState getElementState(int elementIndex, int viewpos, int sl0, int sl1, 
                             bool selectionActive, int readlen, size_t inputIndex,
                             bool zero)
{
    bool isCursor = elementIndex == viewpos;
    return ElementState(
        selectionActive && elementIndex >= sl0 && elementIndex <= sl1,
        isCursor,
        elementIndex < readlen,
        inputIndex && isCursor,
        zero
    );
}

// Render view with data on screen
void update_view(Session *session, TerminalSize termsize)
{
    // What do you want me to do with so little space?
    if (termsize.rows < 3)
        return;
    
    int cols        = session.rc.columns;       /// elements per row
    int rows        = g_rows;                   /// rows available
    int count       = rows * cols;              /// elements on screen
    long curpos     = session.position_cursor;  /// Cursor position
    long address    = session.position_view;    /// Base address
    
    bool logging    = logEnabled();
    
    debug import std.datetime.stopwatch : StopWatch, Duration;
    debug StopWatch sw;
    
    __gshared ubyte[] viewbuf;  /// View buffer (capacity)
    __gshared ubyte[] result;   /// View buffer slice (result)
    __gshared int readlen;      /// Slice length in int, easier to add with col/row
    
    DataSpec data_spec = selectDataSpec(session.rc.data_type);
    
    g_linesize = cols * data_spec.size_of; // line is worth this many bytes
    
    /// Requested size of view buffer
    size_t viewsize = count * data_spec.size_of;
    
    // Bit of a hack to force update when buffer size changes (config or otherwise)
    // Only useful when screen resizes, but fails when data changes (ie, a paste)
    if (viewbuf.length != viewsize) // only resize if required
    {
        viewbuf.length = viewsize;
        g_status |= UVIEW;
    }
    
    // Read data
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
    if (g_status & UVIEW)
    {
        debug if (logging) sw.start(); // For IDocumentEditor.view()
        
        result  = session.editor.view(address, viewbuf);
        readlen = cast(int)result.length;
        
        debug if (logging)
        {
            sw.stop();
            log("READ view=%s", sw.peek());
            sw.reset();
        }
    }
    
    // Effective number of rows to render
    int erows = readlen / (cols * data_spec.size_of);
    // If col count flush and "view incomplete", add row
    if (readlen % cols == 0 && readlen < count) erows++;
    // If col count not flush (near EOF) and view full, add row
    else if (readlen % cols) erows++;
    
    // Selection stuff (relative to view)
    // NOTE: Watch out for element-oriented views, selection is byte-wise
    Selection sel   = selection(session);
    int sel_start   = cast(int)(sel.start - address) / data_spec.size_of;
    int sel_end     = cast(int)(sel.end   - address) / data_spec.size_of;
    
    // Render view
    int viewpos     = cast(int)(curpos - address) / data_spec.size_of; // relative cursor position in view
    PanelType panel = session.panel;
    
    if (logging)
    {
        log("address=%d viewpos=%d cols=%d rows=%d count=%d readlen=%d panel=%s "~
            "select.anchor=%d selection=%#x sel_start=%d sel_end=%d",
            address, viewpos, cols, erows, count, readlen, panel,
            session.selection.anchor, session.selection.status, sel_start, sel_end);
    }
    
    static immutable string DEFAULT = ".";
    
    debug if (logging) sw.start();
    
    int row;
    int rowdisp = session.rc.header ? 1 : 0; // lazy hack if header is present
    
    DataFormatter dfmt = DataFormatter(session.rc.data_type, result.ptr, result.length);
    AddressFormatter afmt = AddressFormatter(session.rc.address_type);
    
    Line line = Line(128); // init with 128 segments
    ElementText buf = void;
    bool prev_selected;
    size_t ci; // character index because lazy
    for (; row < erows; ++row, address += g_linesize)
    {
        line.reset();
        
        // Add address + one spacer
        line.normal(afmt.textual(buf, address, session.rc.address_spacing), " ");
        
        // expected amount of characters to be rendered on screen
        size_t chars;
        
        // Render data by element, so by column
        for (int col; col < cols; col++)
        {
            if (chars > termsize.columns)
                break;
            
            int elemidx = (row * cols) + col;
            
            // Is element zero?
            bool zero = session.rc.gray_zeros && dfmt.iszero();
            
            ElementState state = getElementState(
                elemidx, viewpos, sel_start, sel_end, session.selection.status != 0,
                readlen, g_input.index, zero);
            
            ColorScheme current = state.dataScheme(panel, session.rc.mirror_cursor);
            
            // Add spacer (before element) with scheme continuous to previous one
            ColorScheme spacerscheme =
                col &&                      // avoid first spacer being styled
                state.isSelected &&         // current element selected
                prev_selected &&            // previous element selected
                panel == PanelType.data ?   // focused on data panel
                ColorScheme.selection : ColorScheme.normal;
            chars += line.add(" ", spacerscheme);
            prev_selected = state.isSelected;
            
            // Add data text
            string data = state.isActiveEdit ? g_input.format : dfmt.textual(buf);
            assertion(data);
            dfmt.step();
            chars += line.add(data, current);
        }
        
        // data-text spacers
        chars += line.normal("  ");
        
        // Render text by byte
        for (int idx; idx < g_linesize; idx++, ci++)
        {
            if (chars > termsize.columns)
                break;
            
            // Convert byte offset to element index for state checking
            int elementIndex = ((row * g_linesize) + idx) / data_spec.size_of;
            
            // Is element zero?
            bool zero = session.rc.gray_zeros && ci < result.length ? result[ci] == 0 : false;
            
            // Calculate element state
            ElementState state = getElementState(elementIndex, viewpos, sel_start, sel_end,
                                                session.selection.status != 0, readlen, g_input.index, zero);
            
            // Get color scheme for this element in text panel
            ColorScheme scheme = state.textScheme(panel, session.rc.mirror_cursor);
            
            // Get character
            string text;
            if (ci < result.length)
            {
                string c = transcode(result[ci], session.rc.charset);
                text = c ? c : DEFAULT;
            }
            else
            {
                text = " ";
            }
            
            chars += line.add(text, scheme);
        }
        
        // Render line segments on screen
        terminalCursor(0, row + rowdisp);
        int last_scheme_flags; // ColorScheme might not be normal at address
        foreach (ref segment; line.segments)
        {
            ColorMap map = g_colors.get(segment.scheme);

            bool change = last_scheme_flags != map.flags;

            if (change)
                terminalResetColor(); // fixes runaway color with invert (cursor) on POSIX

            // Apply attribute(s)
            if (map.flags & COLORMAP_FOREGROUND && change)
                terminalForeground(map.fg);
            if (map.flags & COLORMAP_BACKGROUND && change)
                terminalBackground(map.bg);
            if (map.flags & COLORMAP_INVERTED && change)
                terminalInvertColor();

            terminalWrite(segment.data);

            last_scheme_flags = map.flags;
        }

        // Fill rest of term with spaces
        if (chars < termsize.columns)
        {
            terminalResetColor();   // fixes colors when in text column
            terminalWriteChar(' ', cast(int)(termsize.columns - chars));
        }

        terminalFlush();        // important for fbcon, no-op on Windows
    }
    
    // NOTE: terminalWriteChar does buffering on its own
    //       Increased stack buffer size from 32 to 128 to help
    int tcols = termsize.columns - 1;
    for (; row < rows; ++row)
    {
        terminalCursor(0, row + rowdisp);
        terminalWriteChar(' ', tcols);
    }
    
    // Important for fbcon
    terminalFlush();
    
    debug if (logging)
    {
        sw.stop();
        log("RENDER update_view=%s", sw.peek());
    }
}

// Render status bar on screen
void update_status(Session *session, TerminalSize termsize)
{
    terminalCursor(0, termsize.rows - 1);
    
    AddressFormatter address = void;
    ElementText buf0 = void;
    ElementText buf1 = void;
    
    Selection sel = selection(session);
    string msg = void;
    if (g_status & UMESSAGE) // Pending message
    {
        msg = g_message;
    }
    else if (sel.length) // Active selection
    {
        address.change(session.rc.address_type);
        
        msg = cast(string)sformat(g_messagebuf, "SEL: %s-%s (%d Bytes)",
            address.textual(buf0, sel.start, 1),
            address.textual(buf1, sel.end, 1),
            sel.length
        );
    }
    else // Regular status bar
    {
        address.change(session.rc.address_type);
        
        msg = cast(string)sformat(g_messagebuf, "%c %s | %3s | %8s | %s",
            session.editor.edited() ? '*' : ' ',
            writingModeToString(session.rc.writemode),
            dataTypeToString(session.rc.data_type),
            charsetID(session.rc.charset),
            address.textual(buf0, session.position_cursor, 8));
    }
    
    // Attempt to fit the new message on screen
    int msglen = cast(int)msg.length;
    int cols = termsize.columns; // "-1" was when I was worried about line wrapping
    if (msglen >= cols) // message does not fit on screen
    {
        // TODO: Attempt to "scroll" message
        //       Loop keypresses to continue?
        //       Might include "+" at end of message to signal continuation
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
    
    // Number of available rows
    g_rows = termsize.rows;
    
    // Header enabled
    if (session.rc.header) g_rows--;
    // Status enabled
    if (session.rc.status) g_rows--;
    
    if (session.rc.header)
        update_header(session, termsize);
    
    update_view(session, termsize);
    
    if (session.rc.status || g_status & UMESSAGE)
        update_status(session, termsize);
    
    g_status = 0;
}

// Special function to update progress
// (Closer to update() than update_* functions...)
void update_progress(Session *session, long position, long total)
{
    __gshared int lastx;
    
    TerminalSize termsize = terminalSize();
    int width = termsize.columns - 2;
    
    assert(position <= total, "position <= total");
    
    int x = cast(int)(width * (cast(double)position / total));
    // Same position, avoid unnecessary I/O
    if (x == lastx)
        return;
    
    lastx = x;
    
    int rem = width - x;
    
    log("w=%d p=%d t=%d x=%d r=%d",
        width, position, total, x, rem);
    
    terminalMove(0, termsize.rows - 1);
    
    BufferedWriter!((void *data, size_t size) {
        terminalWrite(data, size);
    }, 256) buffwriter;
    
    buffwriter.repeat('[', 1);
    buffwriter.repeat('#', x);
    buffwriter.repeat(' ', rem);
    buffwriter.repeat(']', 1);
    
    buffwriter.flush();
    terminalFlush();
}

// Peek input if cancel key is requested, used in I/O intense scenarios,
// like the search function.
int cancelling()
{
    int num = terminalHasInput();
    if (num == 0)
        return 0;
    
    for (int i; i < num; i++)
    {
        TermInput r = terminalRead();
        if (r.type != InputType.keyDown)
            continue;
        
        if (iscancel(r.key))
            return 1;
    }
    
    return 0;
}

//
// Search function
//

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
/// Search result not found.
enum SEARCH_RESULT_NOT_FOUND = -1;

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
/// Returns: Position or SEARCH_RESULT_NOT_FOUND. SEARCH_LASTPOS overrides SEARCH_RESULT_NOT_FOUND.
long search(Session *session, ubyte[] needle, long position, int flags, void delegate(long, long) progress)
{
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
    
    long docsize = session.editor.size();
    
    debug import std.datetime.stopwatch : StopWatch;
    debug StopWatch sw;
    debug sw.start;
    
    if (flags & SEARCH_REVERSE)
    {
        long base = position;
        do
        {
            if (cancelling())
                throw new Exception("Cancelled");
            
            base -= SEARCH_SIZE;
            if (base < 0)
                base = 0;
            
            ubyte[] haystack = session.editor.view(base, hay);
            if (haystack.length < needle.length)
                // somehow haystack is smaller than needle
                return SEARCH_RESULT_NOT_FOUND;
            
            for (size_t o = cast(size_t)(position - base); o > 0; o -= alignment, position -= alignment)
            {
                int r = memcmp(needle.ptr, haystack.ptr + o, needle.length);
                
                // if memcmp==0 (exact) != diff=1 -> SKIP
                // if memcmp!=0 (diff)  != diff=0 -> SKIP
                if ((diff == 0 && r != 0) || (diff && r == 0))
                    continue;
                
                return position;
            }
            
            // 1. After that loop to avoid flickerin between status-progress
            // 2. In reverse mode, it's towards zero, so base decrements
            // NOTE: If we wanted a reverse progress bar, just pass base, but would be confusing
            if (progress) progress(docsize - base, docsize);
        }
        while (base > 0);
    }
    else // forward
    {
        do
        {
            if (cancelling())
                throw new Exception("Cancelled");
            
            ubyte[] haystack = session.editor.view(position, hay);
            if (haystack.length < needle.length)
                return SEARCH_RESULT_NOT_FOUND;
            
            for (size_t o; o < haystack.length; o += alignment, position += alignment)
            {
                int r = memcmp(needle.ptr, haystack.ptr + o, needle.length);
                
                // if memcmp==0 (exact) != diff=1 -> SKIP
                // if memcmp!=0 (diff)  != diff=0 -> SKIP
                if ((diff == 0 && r != 0) || (diff && r == 0))
                    continue;
                
                return position;
            }
            
            // Same as other remark for this
            if (progress) progress(position, docsize);
        }
        while (position < docsize);
    }
    
    debug sw.stop();
    debug log("search=%s", sw.peek());
    
    return flags & SEARCH_LASTPOS ? position : SEARCH_RESULT_NOT_FOUND;
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
    unselect(session);
    
    if (session.position_cursor == 0)
        return;
    
    moverel(session, -size_of(session.rc.data_type));
}
// Move forward a single item
void move_right(Session *session, string[] args)
{
    unselect(session);
    
    moverel(session, +size_of(session.rc.data_type));
}
// Move back a row
void move_up(Session *session, string[] args)
{
    unselect(session);
    
    if (session.position_cursor == 0)
        return;
    
    moverel(session, -(session.rc.columns * size_of(session.rc.data_type)));
}
// Move forward a row
void move_down(Session *session, string[] args)
{
    unselect(session);
    
    moverel(session, +(session.rc.columns * size_of(session.rc.data_type)));
}
// Move back a page
void move_pg_up(Session *session, string[] args)
{
    unselect(session);
    
    if (session.position_cursor == 0)
        return;
    
    moverel(session, -(g_rows * (session.rc.columns * size_of(session.rc.data_type))));
}
// Move forward a page
void move_pg_down(Session *session, string[] args)
{
    unselect(session);
    
    moverel(session, +(g_rows * (session.rc.columns * size_of(session.rc.data_type))));
}
// Move to start of line
void move_ln_start(Session *session, string[] args) // move to start of line
{
    unselect(session);
    
    int g = session.rc.columns * size_of(session.rc.data_type);
    moverel(session, -(session.position_cursor % g));
}
// Move to end of line
void move_ln_end(Session *session, string[] args) // move to end of line
{
    unselect(session);
    
    int g = (session.rc.columns * size_of(session.rc.data_type));
    moverel(session, +(g - (session.position_cursor % g)) - 1);
}
// Move to absolute start of document
void move_abs_start(Session *session, string[] args)
{
    unselect(session);
    
    moveabs(session, 0);
}
// Move to absolute end of document
void move_abs_end(Session *session, string[] args)
{
    unselect(session);
    
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
    if (sel.length)
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
        int sz = size_of(session.rc.data_type);
        
        // Get current element
        Element elem;
        needle = session.editor.view(curpos, elem.raw.ptr, sz);
        if (needle.length < sz)
            return; // Nothing to do
        sel.start = curpos;
    }
    
    session.selection.status = 0;
    
    // Move even if nothing found, since it is the intent.
    // In a text editor, if Ctrl+Left is hit (imagine a long line of same
    // characters) the cursor still moves to the start of the document.
    moveabs(session,
        search(session, needle, sel.start - needle.length,
            SEARCH_LASTPOS|SEARCH_DIFF|SEARCH_REVERSE|SEARCH_ALIGNED,
            (pos, total){ update_progress(session, pos, total); }));
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
    if (sel.length)
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
        int sz = size_of(session.rc.data_type);
        
        // Get current element
        Element elem;
        needle = session.editor.view(curpos, elem.raw.ptr, sz);
        if (needle.length < sz)
            return; // Nothing to do
        sel.start = curpos;
    }
    
    session.selection.status = 0;
    
    moveabs(session,
        search(session, needle, sel.start + needle.length,
            SEARCH_LASTPOS|SEARCH_DIFF|SEARCH_ALIGNED,
            (pos, total){ update_progress(session, pos, total); }));
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
    if (args.length > 0)
    {
        Range r = askrange(args, 0, "Range: ");
        session.editor.remove(r.start, rangelen(r));
        g_status |= UVIEW;
        return;
    }
    else if (sel.length)
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
    session.editor.remove(curpos, size_of(session.rc.data_type));
    g_status |= UVIEW;
}

void delete_back(Session *session, string[] args)
{
    Selection sel = selection(session);
    if (sel.length)
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
    int s = size_of(session.rc.data_type);
    moverel(session, -s);
    session.editor.remove(session.position_cursor, s);
    g_status |= UVIEW;
}

//
// Selection
//

/// Selection information
struct Selection
{
    long start, end, length;
}

// Force unselection
void unselect(Session *session)
{
    if (session.selection.status & SELECT_ONGOING)
        return;
    
    session.selection.status = 0;
}

// Get selection information
Selection selection(Session *session)
{
    Selection sel;
    if (session.selection.status == 0)
        return sel;
    
    int g = size_of(session.rc.data_type);
    
    // NOTE: Adjustment in moveabs right now fucks a little with sel.end
    sel.start = min(session.selection.anchor, session.position_cursor);
    sel.end   = max(session.selection.anchor, session.position_cursor);
    
    if (sel.end >= session.editor.size())
        sel.end -= g;
    
    // End marker is inclusive
    sel.length = sel.end - sel.start + g;
    
    return sel;
}
unittest
{
    Session session;
    
    import editor.dummy : DummyDocumentEditor;
    session.editor = new DummyDocumentEditor(); // needed for length
    
    // Not selected
    Selection sel = selection(&session);
    assert(sel.length == 0);
    
    // Emulate a selection where cursor is behind anchor
    session.selection.status = SELECT_ACTIVE;
    session.selection.anchor = 4;
    session.position_cursor  = 2;
    session.rc.data_type     = DataType.x8;
    
    sel = selection(&session);
    assert(sel.length == 3);
    assert(sel.start  == 2);
    assert(sel.end    == 4);
    
    // Emulate a selection where only one element is selected
    session.selection.status = SELECT_ACTIVE;
    session.selection.anchor = 2;
    session.position_cursor  = 2;
    sel = selection(&session);
    assert(sel.length == 1);
    assert(sel.start  == 2);
    assert(sel.end    == 2);
    
    // Test x16
    /*
    session.selection.status = SELECT_ACTIVE;
    session.selection.anchor = 0;
    session.position_cursor  = 2;
    session.rc.data_type     = DataType.x16;
    sel = selection(&session);
    assert(sel.length == 2);
    assert(sel.start  == 0);
    assert(sel.end    == 2);
    
    session.selection.status = SELECT_ACTIVE;
    session.selection.anchor = 4;
    session.position_cursor  = 2;
    session.rc.data_type     = DataType.x16;
    sel = selection(&session);
    assert(sel.length == 4);
    assert(sel.start  == 2);
    assert(sel.end    == 4);
    */
}

// Expand selection backward
void select_left(Session *session, string[] args)
{
    if (!session.selection.status)
    {
        session.selection.status = SELECT_ACTIVE;
        session.selection.anchor = session.position_cursor;
    }
    
    moverel(session, -size_of(session.rc.data_type));
}

// Expand selection forward
void select_right(Session *session, string[] args)
{
    if (!session.selection.status)
    {
        session.selection.status = SELECT_ACTIVE;
        session.selection.anchor = session.position_cursor;
    }
    
    moverel(session, +size_of(session.rc.data_type));
}

// Expand selection back a line
void select_up(Session *session, string[] args)
{
    if (!session.selection.status)
    {
        session.selection.status = SELECT_ACTIVE;
        session.selection.anchor = session.position_cursor;
    }
    
    moverel(session, -(session.rc.columns * size_of(session.rc.data_type)));
}

// Expand selection forward a line
void select_down(Session *session, string[] args)
{
    if (!session.selection.status)
    {
        session.selection.status = SELECT_ACTIVE;
        session.selection.anchor = session.position_cursor;
    }
    
    moverel(session, +(session.rc.columns * size_of(session.rc.data_type)));
}

// Expand selection towards end of line
void select_home(Session *session, string[] args)
{
    if (!session.selection.status)
    {
        session.selection.status = SELECT_ACTIVE;
        session.selection.anchor = session.position_cursor;
    }
    
    int g = session.rc.columns * size_of(session.rc.data_type);
    moverel(session, -(session.position_cursor % g));
}

// Expand selection forward a line
void select_end(Session *session, string[] args)
{
    if (!session.selection.status)
    {
        session.selection.status = SELECT_ACTIVE;
        session.selection.anchor = session.position_cursor;
    }
    
    int g = session.rc.columns * size_of(session.rc.data_type);
    moverel(session, +(g - (session.position_cursor % g)) - 1);
}

// Select from current position to start of document
void select_top(Session *session, string[] args)
{
    long docsize = session.editor.size();
    if (docsize <= 0)
        return;
    
    session.position_cursor  = 0;
    session.selection.anchor = session.position_cursor;
    session.selection.status = SELECT_ACTIVE;
}

// Select from current position to end of document
void select_bottom(Session *session, string[] args)
{
    long docsize = session.editor.size();
    if (docsize <= 0)
        return;
    
    session.position_cursor  = docsize - 1;
    session.selection.anchor = session.position_cursor;
    session.selection.status = SELECT_ACTIVE;
}

// Select all of document
void select_all(Session *session, string[] args)
{
    long docsize = session.editor.size();
    if (docsize <= 0)
        return;
    
    session.position_cursor  = docsize - 1;
    session.selection.anchor = 0;
    session.selection.status = SELECT_ACTIVE;
}

// Make an explicit selection
void select(Session *session, string[] args)
{
    Range ran = askrange(args, 0, "Range: ");
    
    session.position_cursor  = ran.end;
    session.selection.anchor = ran.start;
    session.selection.status = SELECT_ACTIVE;
}

// Start an active selection
void mark(Session *session, string[] args)
{
    session.selection.status = SELECT_ACTIVE | SELECT_ONGOING;
    session.selection.anchor = session.position_cursor;
}

// End the active selection
void unmark(Session *session, string[] args)
{
    session.selection.status &= ~SELECT_ONGOING;
}

//
// Etc
//

// Change writing mode
void change_writemode(Session *session, string[] args)
{
    // Can't switch from restricted mode
    if (session.rc.writemode == WritingMode.readonly)
        throw new Exception("Can't edit in read-only");
    
    // Optional argument
    if (args.length > 0)
    {
        switch (args[0][0]) {
        case 'i':
            session.rc.writemode = WritingMode.insert;
            break;
        case 'o':
            session.rc.writemode = WritingMode.overwrite;
            break;
        case 'r':
            session.rc.writemode = WritingMode.readonly;
            break;
        default:
            throw new Exception(text("Unknown writemode:", args[0]));
        }
    }
    else
    {
        session.rc.writemode =
            session.rc.writemode == WritingMode.insert ?
            WritingMode.overwrite : WritingMode.insert;
    }
    g_status |= USTATUS;
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
    // TODO: First parameter should be a panel
    //       Default to just cycle
    
    session.panel++;
    if (session.panel >= PanelType.max + 1)
        session.panel = PanelType.init;
}

// 
void undo(Session *session, string[] args)
{
    long pos = session.editor.undo();
    if (pos < 0)
        return;
    
    unselect(session);
    moveabs(session, pos);
    g_status |= UVIEW; // new data
}

// 
void redo(Session *session, string[] args)
{
    long pos = session.editor.redo();
    if (pos < 0)
        return;
    
    unselect(session);
    moveabs(session, pos);
    g_status |= UVIEW; // new data
}

// Go to position in document
void goto_(Session *session, string[] args)
{
    import utils : scan;
    
    long position = void;
    bool absolute = void;
    
    // Selection
    Selection sel = selection(session);
    if (sel.length)
    {
        if (sel.length > long.sizeof)
            throw new Exception("Selection too large");
        
        Element e;
        ubyte[] res = session.editor.view(sel.start, e.raw.ptr, cast(size_t)sel.length);
        
        absolute = true; // eh, just assuming
        
        if (res.length > uint.sizeof) // same as selection length but.. size_t
            position = e.u64;
        else if (res.length > ushort.sizeof)
            position = e.u32;
        else if (res.length > ubyte.sizeof)
            position = e.u16;
        else
            position = e.u8;
    }
    else
    {
        string off = askstring(args, 0, "offset: ");
        
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
            import utils : llpercentdivf;
            
            if (off.length <= 1) // just '%'
                throw new Exception("Need percentage number");
            
            double per = to!double(off[1..$]);
            if (per > 100.0) // Can't go beyond document (EOF)
                throw new Exception("Percentage cannot be over 100");
            position = llpercentdivf(session.editor.size(), per);
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
    // TODO: Repurpose "report-position" to show ROW/COL *and* percent
    //       Then remove after statusbar customization
    
    long docsize = session.editor.size();
    Selection sel = selection(session);
    if (sel.length)
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
    message( session.target is null ? "(new buffer)" : baseName(session.target) );
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
    enum X8SPACING = 2; // temp constants
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
    DataSpec spec = selectDataSpec(session.rc.data_type);
    TerminalSize tsize = terminalSize();
    
    session.rc.columns = suggestcols(tsize.columns, adspacing, spec.spacing);
}

// Export selected range to file
void export_range(Session *session, string[] args)
{
    Selection sel = selection(session);
    if (sel.length == 0)
        throw new Exception("Need selection");
    
    string name = askstring(args, 0, "Name: ");
    if (exists(name))
    {
        int key = promptkey("File exists, overwrite? [y/N] ");
        switch (key) {
        case 'y', 'Y': break;
        default: return;
        }
    }
    
    import std.stdio : File;
    File output = File(name, "w");
    
    // Re-using search alloc func because lazy
    enum EXPORT_SIZE = 4096; // export buffer, tend to be smaller
    ubyte[] buf = (cast(ubyte*)malloc(EXPORT_SIZE))[0..EXPORT_SIZE];
    if (buf is null)
        throw new Exception("error: Out of memory");
    scope(exit) free(buf.ptr);
    
    // HACK: end is inclusive. D ranges are not.
    sel.end++;
    
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
    if (session.rc.writemode == WritingMode.readonly)
        throw new Exception("Cannot edit, read-only");
    
    Selection sel = selection(session);
    if (sel.length)
    {
        if (args.length < 1)
        {
            message("Missing pattern");
            return;
        }
        ubyte[] p = pattern(session.rc.charset, args);
        session.editor.patternReplace(sel.start, sel.length, p.ptr, p.length);
        g_status |= UVIEW | UHEADER | USTATUS;
        return;
    }
    
    if (args.length < 1)
    {
        message("Missing range");
        return;
    }
    if (args.length < 2)
    {
        message("Missing pattern");
        return;
    }
    
    Range r = askrange(args, 0, "Range: ");
    ubyte[] p = pattern(session.rc.charset, args[1..$]);
    session.editor.patternReplace(r.start, rangelen(r), p.ptr, p.length);
    g_status |= UVIEW | UHEADER | USTATUS;
}

// Insert data using pattern
void insert_(Session *session, string[] args)
{
    if (session.rc.writemode == WritingMode.readonly)
        throw new Exception("Cannot edit, read-only");
    
    Selection sel = selection(session);
    if (sel.length)
    {
        if (args.length < 1)
        {
            message("Need pattern");
            return;
        }
        ubyte[] p = pattern(session.rc.charset, args);
        session.editor.patternInsert(sel.start, sel.length, p.ptr, p.length);
        g_status |= UVIEW | UHEADER | USTATUS;
        return;
    }
    
    if (args.length < 1)
    {
        message("Missing range");
        return;
    }
    if (args.length < 2)
    {
        message("Missing pattern");
        return;
    }
    
    Range r = askrange(args, 0, "Range: ");
    ubyte[] p = pattern(session.rc.charset, args[1..$]);
    session.editor.patternInsert(r.start, rangelen(r), p.ptr, p.length);
    g_status |= UVIEW | UHEADER | USTATUS;
}

// Replace data using file
void replace_file(Session *session, string[] args)
{
    if (session.rc.writemode == WritingMode.readonly)
        throw new Exception("Cannot edit, read-only");
    
    string path = askstring(args, 0, "File: ");
    
    IDocument file = new FileDocument(path, true);
    session.documents ~= file;
    long curpos = session.position_cursor;
    
    session.editor.fileReplace(curpos, file);
    g_status |= UVIEW;
}

// Insert data using file
void insert_file(Session *session, string[] args)
{
    if (session.rc.writemode == WritingMode.readonly)
        throw new Exception("Cannot edit, read-only");
    
    string path = askstring(args, 0, "File: ");
    
    IDocument file = new FileDocument(path, true);
    session.documents ~= file;
    long curpos = session.position_cursor;
    
    session.editor.fileInsert(curpos, file);
    g_status |= UVIEW;
}

/// Amount of data before warning for a copy.
enum COPY_WORRY = MiB!(16);

// Copy data into clipboard buffer
void clip_copy(Session *session, string[] args)
{
    long start;
    size_t len;
    
    Selection sel = selection(session);
    if (sel.length)
    {
        // Address space range check (notably on 32-bit systems)
        import platform : MAXSIZE;
        if (sel.length > MAXSIZE)
            throw new Exception("Clipboard cannot contain selection");
        
        if (sel.length >= COPY_WORRY)
        {
            int k = promptkey("Copy >16 MiB into clipboard? [y/N] ");
            switch (k) {
            case 'y', 'Y': break;
            default: return;
            }
        }
        
        len   = cast(size_t)sel.length;
        start = sel.start;
    }
    else // No selection
    {
        len   = 1;
        start = session.position_cursor;
    }
    
    log("Copying %u bytes...", len);
    
    void *ptr = realloc(g_clipboard_ptr, len);
    if (ptr == null)
        throw new Exception("Allocation failed");
    g_clipboard_ptr = cast(ubyte*)ptr;
    
    g_clipboard_len = len;
    
    cast(void)session.editor.view(start, g_clipboard_ptr[0..len]);
}

// Cut data into clipboard buffer
void clip_cut(Session *session, string[] args)
{
    // shameless copy from clip_copy
    long start;
    size_t len;
    
    Selection sel = selection(session);
    if (sel.length)
    {
        // Address space range check (notably on 32-bit systems)
        import platform : MAXSIZE;
        if (sel.length > MAXSIZE)
            throw new Exception("Clipboard cannot contain selection");
        
        if (sel.length >= COPY_WORRY)
        {
            int k = promptkey("Copy >16 MiB into clipboard? [y/N] ");
            switch (k) {
            case 'y', 'Y': break;
            default: return;
            }
        }
        
        len   = cast(size_t)sel.length;
        start = sel.start;
    }
    else // No selection: Copy element (right now, that's only a byte)
    {
        len   = 1;
        start = session.position_cursor;
    }
    
    log("Copying %u bytes...", len);
    
    void *ptr = realloc(g_clipboard_ptr, len);
    if (ptr == null)
        throw new Exception("Allocation failed");
    g_clipboard_ptr = cast(ubyte*)ptr;
    
    g_clipboard_len = len;
    
    cast(void)session.editor.view(start, g_clipboard_ptr[0..len]);
    
    session.editor.remove(start, len);
    g_status |= UVIEW; // force read
}

// Paste data from clipboard buffer
void clip_paste(Session *session, string[] args)
{
    if (g_clipboard_ptr == null)
        throw new Exception("Clipboard is empty");
    
    // Typical behaviour with text editors: If we paste with a selection,
    // (a) selection region gets removed and (b) new data is inserted
    Selection sel = selection(session);
    if (sel.length)
    {
        session.editor.remove(sel.start, sel.length);
        
        // Force selection OFF even with an active marking
        session.selection.status = 0;
        
        // NOTE: Editor isn't smart enough for positions after document
        //       So force the new position to be minimum value
        session.position_cursor = sel.start;
    }
    
    // Depending on mode (modal), insert or overwrite
    final switch (session.rc.writemode) {
    case WritingMode.insert:
        session.editor.insert(session.position_cursor, g_clipboard_ptr, g_clipboard_len);
        break;
    case WritingMode.overwrite:
        session.editor.replace(session.position_cursor, g_clipboard_ptr, g_clipboard_len);
        break;
    case WritingMode.readonly:
        throw new Exception("Document is read-only");
    }
    
    // Move cursor to end of pasted data, which helps repeating the action of
    // pasting over and over
    long newpos = session.position_cursor + g_clipboard_len;
    moveabs(session, newpos);
    
    g_status |= UVIEW; // force read
}

// Clear clipboard buffer
void clip_clear(Session *session, string[] args)
{
    if (g_clipboard_ptr == null)
        return;
    
    free(g_clipboard_ptr);
    g_clipboard_ptr = null;
    g_clipboard_len = 0;
}

// Save changes (assumes to a file)
void save(Session *session, string[] args)
{
    if (session.rc.writemode == WritingMode.readonly)
        throw new Exception("Cannot save, read-only");
    
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
        if (exists(target))
        {
            // NOTE: Don't explicitly check if directory exists.
            //       The filesystem will report the error anyway.
            switch (promptkey("Overwrite? [y/N] ")) {
            case 'y', 'Y': // Continue
                break;
            default:
                throw new Exception("Canceled");
            }
        }
        
        session.target = target;
    }
    
    // Force updating the status bar to indicate that we're currently saving.
    // It might take a while with the current implementation.
    message("Saving...");
    update_status(session, terminalSize());
    
    save_to_file(session.editor, session.target);
    message("Saved");
}

// Save as file
void save_as(Session *session, string[] args)
{
    string name = askstring(args, 0, "Save as: ");
    
    message("Saving...");
    update_status(session, terminalSize());
    
    save_to_file(session.editor, name);
    message("Saved");
    
    // Successful save, set as target
    session.target = name;
}

// Set runtime config
void set(Session *session, string[] args)
{
    string setting = askstring(args, 0, "Setting: ");
    string value   = askstring(args, 1, "Value: ");
    
    configRC(session.rc, setting, value);

    // Sync editor options
    session.editor.coalescing = session.rc.coalescing;
}

// Bind key to action (command + parameters)
void bind(Session *session, string[] args)
{
    int key = terminal_keybind( askstring(args, 0, "Key: ") );
    // BUG: promptline returns as one string, so "goto +32" might happen
    string command = askstring(args, 1, "Command: ");
    
    bindkey(key, command, args.length >= 2 ? args[2..$] : null);
    message("Key binded");
}

// Unbind key
void unbind(Session *session, string[] args)
{
    int key = terminal_keybind( askstring(args, 0, "Key: ") );
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
    else if (sel.length) // selection
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
    
    message("Searching...");
    update_status(session, terminalSize());
    
    long p =
        search(session, g_needle, sel.start, 0,
        (pos, total){ update_progress(session, pos, total); });
    if (p < 0)
    {
        message("Not found");
        return;
    }
    
    moveabs(session, p);
    
    ElementText buf = void;
    AddressFormatter addr = AddressFormatter(session.rc.address_type);
    message("Found at %s", addr.textual(buf, p, 1));
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
    else if (sel.length) // selection
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
    
    message("Searching...");
    update_status(session, terminalSize());
    
    long p =
        search(session, g_needle, sel.start, SEARCH_REVERSE,
        (pos, total){ update_progress(session, pos, total); });
    if (p < 0)
    {
        message("Not found");
        return;
    }
    
    moveabs(session, p);
    
    ElementText buf = void;
    AddressFormatter addr = AddressFormatter(session.rc.address_type);
    message("Found at %s", addr.textual(buf, p, 1));
}

// 
void find_next(Session *session, string[] args)
{
    if (g_needle is null)
        return;
    
    unselect(session);
    
    message("Searching...");
    update_status(session, terminalSize());
    
    long p =
        search(session, g_needle, session.position_cursor + g_needle.length, 0,
        (pos, total){ update_progress(session, pos, total); });
    if (p < 0)
    {
        message("Not found");
        return;
    }
    
    moveabs(session, p);
    
    ElementText buf = void;
    AddressFormatter addr = AddressFormatter(session.rc.address_type);
    message("Found at %s", addr.textual(buf, p, 1));
}

// 
void find_prev(Session *session, string[] args)
{
    if (g_needle is null)
        return;
    
    unselect(session);
    
    message("Searching...");
    update_status(session, terminalSize());
    
    long p =
        search(session, g_needle, session.position_cursor - 1, SEARCH_REVERSE,
        (pos, total){ update_progress(session, pos, total); });
    if (p < 0)
    {
        message("Not found");
        return;
    }
    
    moveabs(session, p);
    
    ElementText buf = void;
    AddressFormatter addr = AddressFormatter(session.rc.address_type);
    message("Found at %s", addr.textual(buf, p, 1));
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
            // Canceling isn't an error, don't know
            message("Canceled");
            return;
        }
    }
    
Lexit:
    terminalRestore();
    exit(0);
}