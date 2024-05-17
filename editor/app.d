/// Main module, handling core TUI operations.
/// 
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module editor.app;

import std.stdio;
import core.stdc.stdlib : exit;
import editor.file;
import ddhx.display;
import ddhx.transcoder : CharacterSet;
import ddhx.formatter : Format;
import ddhx.logger;
import ddhx.os.terminal : Key, Mod;
import ddhx.common;

// NOTE: Glossary
//       Cursor
//         Visible on-screen cursor, positioned on a per-byte and additionall
//         per-digit basis.
//       View
//         Position and length of the "view" of the view buffer within file or memory buffer.

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
    
    // Clear the current message
    UMESSAGE    = 1 << 8,
    
    //
    URESET = UCURSOR | UVIEW | UHEADER,
}

private __gshared
{
    FileEditor _efile;
    
    BUFFER *dispbuffer;
    
    int _etrows;
    int _etcols;
    
    long _efilesize;
    
    /// Position of the view, in bytes
    long _eviewpos;
    /// Size of the view, in bytes
    int _eviewsize;
    
    /// Position of the cursor in the file, in bytes
    long _ecurpos;
    /// Position of the cursor editing a group of bytes, in digits
    int _edgtpos; // e.g., hex=nibble, dec=digit, etc.
    /// Cursor edit mode (insert, overwrite, etc.)
    int _emode;
    /// 
    enum EDITBFSZ = 8;
    /// Value of edit input, as a digit
    char[EDITBFSZ] _ebuffer;
    
    /// System status, used in updating certains portions of the screen
    int _estatus;
}

int start(string path)
{
    trace("ddhx starting");
    
    //TODO: Stream support
    //      With length, build up a memory buffer
    if (path == null)
    {
        trace("todo: Stdin");
        stderr.writeln("todo: Stdin");
        return 2;
    }
    
    // Open file
    if (_efile.open(path, true, _oreadonly))
    {
        trace("error: Could not open file");
        stderr.writeln("error: Could not open file");
        return 3;
    }
    
    _efilesize = _efile.size();
    trace("filesize=%d", _efilesize);
    
    // Init display in TUI mode
    disp_init(true);
    
    disp_size(_etrows, _etcols);
    if (_etrows < 4 || _etcols < 20)
    {
        stderr.writeln("error: Terminal too small");
        return 4;
    }
    trace("term.rows=%d term.cols=%d", _etrows, _etcols);
    
    // Set number of columns, or automatically get column count
    // from terminal.
    _ocolumns = _ocolumns ? _ocolumns : disp_hint_columns();
    trace("hintcols=%d", _ocolumns);
    //TODO: Check column size
    /*if (columns < 0) {
    }*/
    
    // Get "view" buffer size, in bytes
    _eviewsize = disp_hint_viewsize(_ocolumns);
    
    // Create buffer
    dispbuffer = disp_create(_etrows - 2, _ocolumns, 0);
    if (dispbuffer == null)
    {
        stderr.writeln("error: Unknown error creating display");
        return 5;
    }
    
    // Allocate buffer according to desired cols
    trace("viewsize=%d", _eviewsize);
    _efile.setbuffer( _eviewsize );
    
    // Initially render these things
    _estatus = URESET;
    
Lread:
    cast(void)update();
    int key = disp_readkey();
    
    switch (key)
    {
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
    
    // Search
    case Key.W | Mod.ctrl:
        break;
    
    // Reset screen
    case Key.R | Mod.ctrl:
        //TODO: Need to remember if cols was set to 0
        _ocolumns = disp_hint_columns();
        _eviewsize = disp_hint_viewsize(_ocolumns);
        _efile.setbuffer( _eviewsize );
        _estatus = URESET;
        break;
    
    // Quit
    case Key.Q:
        quit();
        break;
    
    default:
        // Edit mode
        if (_editkey(_odatafmt, key))
        {
            // 1. Check if key can be inserted into group
            // 2. 
            
            //TODO: When group size filled, add to edit history
            trace("EDIT key=%c", cast(char)key);
            _ebuffer[_edgtpos++] = cast(ubyte)key;
            _estatus |= UEDIT;
            
            /*if (_edgtpos >= _odigits) {
                //TODO: add byte+address to edits
                editpos = 0;
                _move_rel(1);
            }*/
            goto Lread;
        }
    }
    goto Lread;
}

string prompt(string text)
{
    throw new Exception("Not implemented");
}

//TODO: Merge _editkey and _editval
//      Could return a struct
private
int _editkey(int type, int key)
{
    switch (type) with (Format)
    {
    case hex:
        return (key >= '0' && key <= '9') ||
            (key >= 'A' && key <= 'F') ||
            (key >= 'a' && key <= 'f');
    case dec:   return key >= '0' && key <= '9';
    case oct:   return key >= '0' && key <= '7';
    default:
    }
    return 0;
}
private
int _editval(int type, int key)
{
    switch (type) with (Format)
    {
    case hex:
        if (key >= '0' && key <= '9')
            return key - '0';
        if (key >= 'A' && key <= 'F')
            return key - 'A' + 0x10;
        if (key >= 'a' && key <= 'f')
            return key - 'a' + 0x10;
        goto default;
    case dec:
        if (key >= '0' && key <= '9')
            return key - '0';
        goto default;
    case oct:
        if (key >= '0' && key <= '7')
            return key - '0';
        goto default;
    default:
        throw new Exception(__FUNCTION__);
    }
}

// Move the cursor relative to its position within the file
private
void moverel(long pos)
{
    if (pos == 0)
        return;
    
    long tmp = _ecurpos + pos;
    if (pos > 0 && tmp >= _efilesize)
        tmp = _efilesize;
    else if (pos < 0 && tmp < 0)
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
    if (pos >= _efilesize)
        pos = _efilesize;
    else if (pos < 0)
        pos = 0;

    if (pos == _ecurpos)
        return;
    
    _ecurpos = pos;
    _estatus |= UCURSOR;
    _adjust_viewpos();
}
// Adjust the view positon
void _adjust_viewpos()
{
    //TODO: Adjust view position algorithmically
    
    // Cursor is ahead the view
    if (_ecurpos >= _eviewpos + _eviewsize)
    {
        while (_ecurpos >= _eviewpos + _eviewsize)
        {
            _eviewpos += _ocolumns;
            if (_eviewpos >= _efilesize - _eviewsize)
                break;
        }
        _estatus |= UVIEW;
    }
    // Cursor is behind the view
    else if (_ecurpos < _eviewpos)
    {
        while (_ecurpos < _eviewpos)
        {
            _eviewpos -= _ocolumns;
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
    if (_ecurpos == _efilesize)
        return;
    
    moverel(1);
}
void move_up()
{
    if (_ecurpos == 0)
        return;
    
    moverel(-_ocolumns);
}
void move_down()
{
    if (_ecurpos == _efilesize)
        return;
    
    moverel(_ocolumns);
}
void move_pg_up()
{
    if (_ecurpos == 0)
        return;
    
    moverel(-_eviewsize);
}
void move_pg_down()
{
    if (_ecurpos == _efilesize)
        return;
    
    moverel(_eviewsize);
}
void move_ln_start()
{
    moverel(-_ecurpos % _ocolumns);
}
void move_ln_end()
{
    moverel((_ocolumns - (_ecurpos % _ocolumns)) - 1);
}
void move_abs_start()
{
    moveabs(0);
}
void move_abs_end()
{
    moveabs(_efilesize);
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
    
    // Update status
    update_status();
    
    // Update cursor position back into view (data) section
    // NOTE: Should always be updated due to frequent movement
    //       That includes messages, cursor naviation, menu invokes, etc.
    int curdiff = cast(int)(_ecurpos - _eviewpos);
    trace("cur=%d", curdiff);
    update_cursor(curdiff, _ocolumns, _oaddrpad);
    
    _estatus = 0;
}

void update_header()
{
    disp_cursor(0, 0);
    disp_header(_ocolumns);
}

void update_view()
{
    _efile.seek(_eviewpos);
    ubyte[] data = _efile.read();
    trace("addr=%u data.length=%u", _eviewpos, data.length);
    
    disp_render_buffer(dispbuffer, _eviewpos, data,
        _ocolumns, Format.hex, Format.hex, _ofillchar,
        _ocharset, _oaddrpad, 1);
    
    //TODO: Editor applies previous edits in BUFFER
    //TODO: Editor applies current edit in BUFFER
    
    disp_cursor(1, 0);
    disp_print_buffer(dispbuffer);
}

// relative cursor position
//TODO: Should be: byte pos + digit pos
void update_cursor(int curpos, int columns, int addrpadd)
{
    enum hexsize = 3;
    int row = 1 + (curpos / columns);
    int col = (addrpadd + 2 + ((curpos % columns) * hexsize));
    disp_cursor(row, col);
    
    // Editing in progress
    /*if (editbuf && editsz)
    {
        disp_write(editbuf, editsz);
    }*/
}

void update_status()
{
    //TODO: Could limit write length by terminal width?
    //TODO: check number of edits
    enum STATBFSZ = 2 * 1024;
    char[STATBFSZ] statbuf = void;
    int statlen = snprintf(statbuf.ptr, STATBFSZ, "%s | %s", "test".ptr, "test2".ptr);
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