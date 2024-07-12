/// Editor application.
/// 
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module editor.app;

import std.stdio;
import std.string;
import core.stdc.stdlib;
import core.stdc.string;
import core.stdc.errno;
import ddhx.document;
import ddhx.display;
import ddhx.transcoder;
import ddhx.formatter;
import ddhx.logger;
import ddhx.os.terminal : Key, Mod;
import ddhx.common;
import stack;

// NOTE: Glossary
//       Cursor
//         Visible on-screen cursor, positioned on a per-byte and additionally
//         per-digit basis when editing.
//       View/Camera
//         The "camera" that follows the cursor. Contains a read buffer that
//         the document is read from, and is used for rendering.

// NOTE: Edition must be strictly per-byte

// TODO: Navigation modes
//       Normal: element sized
//       Digit/nibble: 1-digit sized
//       Text: 1-char sized
// TODO: Upgrade defaultchar to multi-byte

private enum MIN_TERM_SIZE_WIDTH  = 40;
private enum MIN_TERM_SIZE_HEIGHT = 4;

// TODO: Column spacer
//       e.g., Add extra space
// TODO: Bring back virtual cursor, inverted colors
// TODO: Change "Offset(hex)" to "Offset:hex" and change address padding from 11 to 10
// TODO: Gray out zeros option

private enum // Update flags
{
    // Update the cursor position
    UCURSOR     = 1,
    // Update the current view
    UVIEW       = 1 << 1,
    // Update the header
    UHEADER     = 1 << 2,
    // Editing in progress
    UEDIT       = 1 << 3,
    
    // Message was sent, clear later
    UMESSAGE    = 1 << 8,
    
    //
    URESET = UCURSOR | UVIEW | UHEADER,
}

enum WriteMode
{
    readOnly,
    insert,
    overwrite
}

/// Represents a single edit
struct Edit
{
    long position;	/// Absolute offset of edit
    long digitpos;  /// Position of digit/nibble
    long value;     /// Value of digit/nibble
    WriteMode mode; /// Edit mode used (insert, overwrite, etc.)
}

private __gshared
{
    Document document;
    
    BUFFER *dispbuffer;
    
    /// Last read count in bytes, for limiting the cursor offsets
    size_t _elrdsz;
    
    /// Camera buffer
    void *_eviewbuffer;
    /// Camera buffer size
    size_t _eviewsize;
    /// Position of the camera, in bytes
    long _eviewpos;
    
    /// Position of the cursor in the file, in bytes
    long _ecurpos;
    /// Position of the cursor editing a group of bytes, in digits
    int _edgtpos; // e.g., hex=nibble, dec=digit, etc.
    /// Cursor edit mode (insert, overwrite, etc.)
    WriteMode _emode;
    
    /// Effective number of elements per row.
    int _erealcols;
    
    /// Size, in bytes, of each element
    int _egroupsize;
    
    Stack!Edit _ehistory;
    
    /// Editor status, used in updating certains portions of the screen
    int _estatus;
}

void startEditor(Document doc)
{
    document = doc;
    
    // Init display in TUI mode
    disp_init(true);
    
    setupscreen();
    
Lread:
    cast(void)update();
    int key = disp_readkey();
    
    // TODO: Consider dictionary to map keys to actions
    //       Useful for user shortcuts
    switch (key) {
    // Navigation keys
    case Key.LeftArrow:     move_left();        break;
    case Key.RightArrow:    move_right();       break;
    case Key.DownArrow:     move_down();        break;
    case Key.UpArrow:       move_up();          break;
    case Key.PageDown:      move_pg_down();     break;
    case Key.PageUp:        move_pg_up();       break;
    case Key.Home:          move_ln_start();    break;
    case Key.End:           move_ln_end();      break;
    case Key.Home|Mod.ctrl: move_abs_start();   break;
    case Key.End |Mod.ctrl: move_abs_end();     break;
    
    // Insert
    case Key.Insert:
        final switch (_emode) {
        case WriteMode.readOnly: // Can't switch from read-only to write
            goto Lread;
        case WriteMode.insert:
            _emode = WriteMode.overwrite;
            goto Lread;
        case WriteMode.overwrite:
            _emode = WriteMode.insert;
            goto Lread;
        }
    
    // TODO: Search
    /*
    case Key.F | Mod.ctrl:
        break;
    */
    
    // Reset screen
    case Key.R | Mod.ctrl:
        setupscreen();
        break;
    
    // Quit
    case Key.Q:
        quit();
        break;
    
    default:
        // TODO: Check which column are being edited (data or text)
        version (none)
        {
        // Can't edit while in this write mode
        if (_emode == WriteMode.readOnly)
        {
            message("Can't edit, read-only.");
            goto Lread;
        }
        
        // Edit mode: Data
        int digit = keydata(_odatafmt, key);
        if (digit < 0) // Not a digit for mode
            break;
        
        // TODO: Transform value into byte positions+mask only
        //       e.g., functions that convert it back
        //             3rd digit with decimal data -> 0x12c
        //             and vice versa
        
        trace("EDIT key=%d digit=%d pos=%d dgtpost=%d mode=%d",
            key, digit, _ecurpos, _edgtpos, _emode);
        
        _ehistory.push(Edit(_ecurpos, _edgtpos++, digit, _emode));
        
        // Check if digit position overflows the maximum element size.
        FormatInfo fmtinfo = formatInfo(_odatafmt);
        if (_edgtpos >= fmtinfo.size1)
        {
            _edgtpos = 0;
            move_right();
            return;
        }
        }
    }
    goto Lread;
}

// Setup screen and buffers
void setupscreen()
{
    // NOTE: At this point, the terminal is setup
    
    int tcols = void, trows = void;
    disp_size(tcols, trows);
    trace("tcols=%d trows=%d", tcols, trows);
    if (tcols < MIN_TERM_SIZE_WIDTH || trows < MIN_TERM_SIZE_HEIGHT)
    {
        trace("error: Terminal too small, need %dx%d",
            MIN_TERM_SIZE_WIDTH, MIN_TERM_SIZE_HEIGHT);
        stderr.writefln("error: Terminal too small, need %dx%d",
            MIN_TERM_SIZE_WIDTH, MIN_TERM_SIZE_HEIGHT);
        exit(4);
    }
    
    FormatInfo fmtinfo = formatInfo(_odatafmt);
    
    RECOMMENDATION rec = disp_recommend_values(_ocolumns, _oaddrpad, fmtinfo.size1);
    trace("%s", rec);
    // If _ocolumns=0 then this is always a no-op
    // More of a check with specified amount of columns
    if (rec.columns < _ocolumns)
    {
        trace("error: Terminal can't hold %d elements per row", rec.columns);
        stderr.writefln("error: Terminal can't hold %d elements per row", rec.columns);
        exit(6);
    }
    
    _erealcols = rec.columns;
    _eviewsize = rec.viewsize;
    
    // Create display buffer
    dispbuffer = disp_configure(dispbuffer, rec.viewsize,
        _odatafmt, _ogrpsize,
        _oaddrfmt, _oaddrpad,
        _ofillchar, _ocharset);
    if (dispbuffer == null)
    {
        trace("error: Unknown error creating display");
        stderr.writeln("error: Unknown error creating display");
        exit(5);
    }
    
    // Allocate read buffer
    assert(_eviewsize);
    _eviewbuffer = malloc(_eviewsize);
    if (_eviewbuffer == null)
    {
        trace("error: %s", fromStringz(strerror(errno)));
        stderr.writeln("error: ", fromStringz(strerror(errno)));
        exit(6);
    }
    
    // Initially render these things
    _estatus = URESET;
}

// Invoke command prompt
string prompt(string text)
{
    throw new Exception("Not implemented");
}

// Given the data type (hex, dec, oct) return the value
// of the keychar to a digit/nibble.
//
// For example, 'a' will return 0xa, and 'r' will return -1, an error.
private
int keydata(int type, int keychar) @safe
{
    switch (type) with (Format)
    {
    case hex:
        if (keychar >= '0' && keychar <= '9')
            return keychar - '0';
        if (keychar >= 'A' && keychar <= 'F')
            return (keychar - 'A') + 10;
        if (keychar >= 'a' && keychar <= 'f')
            return (keychar - 'a') + 10;
        break;
    case dec:
        if (keychar >= '0' && keychar <= '9')
            return keychar - '0';
        break;
    case oct:  
        if (keychar >= '0' && keychar <= '7')
            return keychar - '0';
        break;
    default:
    }
    return -1;
}
@safe unittest
{
    assert(keydata(Format.hex, 'a') == 0xa);
    assert(keydata(Format.hex, 'b') == 0xb);
    assert(keydata(Format.hex, 'A') == 0xa);
    assert(keydata(Format.hex, 'B') == 0xb);
    assert(keydata(Format.hex, '0') == 0);
    assert(keydata(Format.hex, '3') == 3);
    assert(keydata(Format.hex, '9') == 9);
    assert(keydata(Format.hex, 'j') < 0);
    
    assert(keydata(Format.dec, '0') == 0);
    assert(keydata(Format.dec, '1') == 1);
    assert(keydata(Format.dec, '9') == 9);
    assert(keydata(Format.dec, 't') < 0);
    assert(keydata(Format.dec, 'a') < 0);
    assert(keydata(Format.dec, 'A') < 0);
    
    assert(keydata(Format.oct, '0') == 0);
    assert(keydata(Format.oct, '1') == 1);
    assert(keydata(Format.oct, '7') == 7);
    assert(keydata(Format.oct, '9') < 0);
    assert(keydata(Format.oct, 'a') < 0);
    assert(keydata(Format.oct, 'L') < 0);
}

// Transforms a text character value into the value of the desired characterset.
// For example, ASCII 'b' (98) source translates to 'b' (130) EBCDIC destination value.
private
int keytext(int dstset, int srcset, int keychar)
{
    throw new Exception("TODO");
}

// Move the cursor relative to its position within the file
private
void moverel(long pos)
{
    if (pos == 0)
        return;
    
    long tmp = _ecurpos + pos;
    if (pos < 0 && tmp < 0)
        tmp = 0;
    
    if (tmp == _ecurpos)
        return;
    
    _ecurpos = tmp;
    _estatus |= UCURSOR;
    _adjust_viewpos();
}

// Move the cursor to an absolute file position
private
void moveabs(long pos)
{
    if (pos < 0)
        pos = 0;

    if (pos == _ecurpos)
        return;
    
    _ecurpos = pos;
    _estatus |= UCURSOR;
    _adjust_viewpos();
}

// Adjust the camera positon to the cursor
void _adjust_viewpos()
{
    //TODO: Adjust view position algorithmically
    
    // Cursor is ahead the view
    if (_ecurpos >= _eviewpos + _eviewsize)
    {
        while (_ecurpos >= _eviewpos + _eviewsize)
        {
            _eviewpos += _erealcols;
        }
        _estatus |= UVIEW;
    }
    // Cursor is behind the view
    else if (_ecurpos < _eviewpos)
    {
        while (_ecurpos < _eviewpos)
        {
            _eviewpos -= _erealcols;
            if (_eviewpos <= 0)
                break;
        }
        _estatus |= UVIEW;
    }
}

void move_left()
{
    if (_ecurpos == 0)
        return;
    
    moverel(-1);
}
void move_right()
{
    moverel(1);
}
void move_up()
{
    if (_ecurpos == 0)
        return;
    
    moverel(-_erealcols);
}
void move_down()
{
    moverel(_erealcols);
}
void move_pg_up()
{
    if (_ecurpos == 0)
        return;
    
    moverel(-_eviewsize);
}
void move_pg_down()
{
    moverel(_eviewsize);
}
void move_ln_start()
{
    moverel(-_ecurpos % _erealcols);
}
void move_ln_end()
{
    moverel((_erealcols - (_ecurpos % _erealcols)) - 1);
}
void move_abs_start()
{
    moveabs(0);
}
void move_abs_end()
{
    long size = document.size();
    if (size < 0)
        message("Don't know end of document");
    moveabs(size);
}

// Update all elements on screen depending on status
// status global indicates what needs to be updated
void update()
{
    // Update header
    if (_estatus & UHEADER)
        update_header();
    
    // Update the screen
    if (_estatus & UVIEW)
        update_view();
    
    // Update statusbar if no messages
    if ((_estatus & UMESSAGE) == 0)
        update_status();
    
    // Update cursor
    // NOTE: Should always be updated due to frequent movement
    //       That includes messages, cursor naviation, menu invokes, etc.
    update_cursor();
    
    // Clear all
    _estatus = 0;
}

void update_header()
{
    disp_cursor(0, 0);
    disp_header(_erealcols);
}

// Adjust camera offset
void update_view()
{
    static long oldpos;
    
    // Seek to camera position and read
    ubyte[] viewdata = document.readAt(_eviewpos, _eviewbuffer, _eviewsize);
    trace("_eviewpos=%d addr=%u viewdata.length=%u _eviewbuffer=%s _eviewsize=%u",
        _eviewpos, _eviewpos, viewdata.length, _eviewbuffer, _eviewsize);
    
    // If unsuccessful, reset & ignore
    if (viewdata == null || viewdata.length == 0)
    {
        _eviewpos = oldpos;
        return;
    }
    
    // Success, render data buffer
    _elrdsz = viewdata.length;
    oldpos = _eviewpos;
    
    // TODO: Find a way to print address even if no data read
    // TODO: Editor applies previous edits in BUFFER
    
    disp_render_elements(dispbuffer, viewdata);
    
    /*
    // Select edits to apply
    long memmin = _eviewpos;
    long memmax = _eviewpos + _eviewsize;
    Edit[] edits = _ehistory.getAll();
    foreach (ref Edit edit; edits)
    {
        // This edit's position is lower than the viewport? Skip
        if (edit.position < memmin)
            continue;
        // This edit's position is higher than the viewport? Skip
        if (edit.position > memmax)
            continue;
        
        // 
    }
    */
    
    disp_cursor(1, 0);
    disp_print_all(dispbuffer, _eviewpos, _erealcols);
}

// Adjust cursor position if outside bounds
void update_cursor()
{
    // If absolute cursor position is further than view pos + last read length
    long avail = _eviewpos + _elrdsz;
    if (_ecurpos > avail)
        _ecurpos = avail;
    
    // Cursor position in camera
    long curview = _ecurpos - _eviewpos;
    
    // Get 2D coords
    int elemsz = formatInfo(_odatafmt).size1 + 1;
    int row = 1 + (cast(int)curview / _erealcols);
    int col = (_oaddrpad + 2 + ((cast(int)curview % _erealcols) * elemsz));
    trace("_eviewpos=%d _ecurpos=%d _elrdsz=%d row=%d col=%d", _eviewpos, _ecurpos, _elrdsz, row, col);
    disp_cursor(row, col);
}

void update_status()
{
    static immutable string[] editmodes = [
        "readonly", "insert", "overwrite"
    ];
    
    enum STATBFSZ = 2 * 1024;
    char[STATBFSZ] statbuf = void;
    
    FormatInfo finfo = formatInfo(_odatafmt);
    string charset = charsetName(_ocharset);
    string editmode = editmodes[_emode];
    
    int statlen = snprintf(statbuf.ptr, STATBFSZ, "%.*s | %.*s | %.*s",
        cast(int)editmode.length, editmode.ptr,
        cast(int)finfo.name.length, finfo.name.ptr,
        cast(int)charset.length, charset.ptr,
    );
    disp_message(statbuf.ptr, statlen);
}

void message(const(char)[] msg)
{
    disp_message(msg.ptr, msg.length);
    _estatus |= UMESSAGE;
}

void quit()
{
    //TODO: Ask confirmation
    trace("quit");
    exit(0);
}