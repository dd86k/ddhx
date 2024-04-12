/// Main module, handling core TUI operations.
/// 
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx;

import std.stdio;
import core.stdc.stdlib : exit;
import os.terminal : Key, Mod;
import editor;
import display;
import transcoder : CharacterSet;
import logger;

//TODO: On terminal resize, set UHEADER

private enum
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
    
    UINIT       = 0xff,
}

private __gshared
{
    Editor file;
    
    // Current file index (document selector)
    //int currenfile;
    
    /// Total length of the file or data buffer, in bytes
    long filesize;
    /// Position of the view, in bytes
    long viewpos;
    /// Size of the view, in bytes
    int viewsize;
    
    /// Number of columns desired, one per data group
    int columns;
    /// Address padding, in digits
    int addrpad = 11;
    
    /// The type of format to use for rendering offsets
    int offsetmode;
    /// The type of format to use for rendering data
    int datamode;
    /// The size of one data item, in bytes
    int groupsize;
    /// The type of character set to use for rendering text
    int charset;
    
    /// Number of digits per byte, in digits or nibbles
    int digits;
    
    /// Position of the cursor in the file, in bytes
    long curpos;
    /// Position of the cursor editing a group of bytes, in digits
    int editpos; // e.g., hex=nibble, dec=digit, etc.
    /// 
    int editmode;
    /// 
    enum EDITBFSZ = 8;
    /// Value of edit input, as a digit
    char[EDITBFSZ] editbuffer;
    
    /// System status, used in updating certains portions of the screen
    int status;
}

int ddhx_start(string path, bool readonly,
    long skip, long length,
    int cols, int ucharset)
{
    //TODO: Stream support
    //      With length, build up a buffer
    if (path == null)
    {
        stderr.writeln("todo: Stdin");
        return 2;
    }
    
    // Open file
    if (file.open(path, true, readonly))
    {
        stderr.writeln("error: Could not open file");
        return 3;
    }
    
    // 
    if (skip)
    {
        viewpos = curpos = skip;
    }
    
    charset = ucharset;
    
    filesize = file.size();
    
    // Init display in TUI mode
    disp_init(true);
    
    // Set number of columns, or automatically get column count
    // from terminal.
    columns = cols ? cols : disp_hint_cols();
    
    // Get "view" buffer size, in bytes
    viewsize = disp_hint_view(columns);
    
    // Allocate buffer according to desired cols
    trace("viewsize=%d", viewsize);
    file.setbuffer( viewsize );
    
    // Initially render everything
    status = UINIT;
    
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
        columns = disp_hint_cols();
        viewsize = disp_hint_view(columns);
        file.setbuffer( viewsize );
        status = UINIT;
        break;
    
    // 
    case Key.Q | Mod.ctrl:
        quit();
        break;
    
    default:
        // Edit mode
        /*if (_editkey(datamode, key))
        {
            //TODO: When group size filled, add to edit history
            trace("EDIT key=%c", cast(char)key);
            editbuffer[editpos++] = cast(ubyte)key;
            status |= UEDIT;
            
            if (editpos >= digits) {
                //TODO: add byte+address to edits
                editpos = 0;
                _move_rel(1);
            }
            goto Lread;
        }*/
    }
    goto Lread;
}

string prompt(string text)
{
    throw new Exception("Not implemented");
}

private
int _editkey(int type, int key)
{
    switch (type) with (Format)
    {
    case hex:
        return (key <= '0' && key <= '9') ||
            (key <= 'A' && key <= 'F') ||
            (key <= 'a' && key <= 'f');
    case dec:
        return key <= '0' && key <= '9';
    case oct:
        return key <= '0' && key <= '7';
    default:
        throw new Exception(__FUNCTION__);
    }
}
private
int _editval(int type, int key)
{
    switch (type) with (Format)
    {
    case hex:
        if (key <= '0' && key <= '9')
            return key - '0';
        if (key <= 'A' && key <= 'F')
            return key - 'A' + 0x10;
        if (key <= 'a' && key <= 'f')
            return key - 'a' + 0x10;
        goto default;
    case dec:
        if (key <= '0' && key <= '9')
            return key - '0';
        goto default;
    case oct:
        if (key <= '0' && key <= '7')
            return key - '0';
        goto default;
    default:
        throw new Exception(__FUNCTION__);
    }
}

// Move the cursor relative to its position within the file
private
void _move_rel(long pos)
{
    if (pos == 0)
        return;
    
    long old = curpos;
    curpos += pos;
    
    if (pos > 0 && curpos >= filesize)
        curpos = filesize;
    else if (pos < 0 && curpos < 0)
        curpos = 0;
    
    if (old == curpos)
        return;
    
    status |= UCURSOR;
    _adjust_viewpos();
}
// Move the cursor to an absolute file position
private
void _move_abs(long pos)
{
    long old = curpos;
    curpos = pos;

    if (curpos >= filesize)
        curpos = filesize;
    else if (curpos < 0)
        curpos = 0;

    if (old == curpos)
        return;
    
    status |= UCURSOR;
    _adjust_viewpos();
}
// Adjust the view positon
void _adjust_viewpos()
{
    //TODO: Adjust view position algorithmically
    
    // Cursor is ahead the view
    if (curpos >= viewpos + viewsize)
    {
        while (curpos >= viewpos + viewsize)
        {
            viewpos += columns;
            if (viewpos >= filesize - viewsize)
                break;
        }
        status |= UVIEW;
    }
    // Cursor is behind the view
    else if (curpos < viewpos)
    {
        while (curpos < viewpos)
        {
            viewpos -= columns;
            if (viewpos <= 0)
                break;
        }
        status |= UVIEW;
    }
}

void move_left()
{
    if (curpos == 0)
        return;
    
    _move_rel(-1);
}
void move_right()
{
    if (curpos == filesize)
        return;
    
    _move_rel(1);
}
void move_up()
{
    if (curpos == 0)
        return;
    
    _move_rel(-columns);
}
void move_down()
{
    if (curpos == filesize)
        return;
    
    _move_rel(columns);
}
void move_pg_up()
{
    if (curpos == 0)
        return;
    
    _move_rel(-viewsize);
}
void move_pg_down()
{
    if (curpos == filesize)
        return;
    
    _move_rel(viewsize);
}
void move_ln_start()
{
    _move_rel(-curpos % columns);
}
void move_ln_end()
{
    _move_rel((columns - (curpos % columns)) - 1);
}
void move_abs_start()
{
    _move_abs(0);
}
void move_abs_end()
{
    _move_abs(filesize);
}

// Update all elements on screen depending on status
// status global indicates what needs to be updated
void update()
{
    // Update header
    if (status & UHEADER)
        disp_header(columns);
    
    // Update the screen
    if (status & UVIEW)
        update_view();
    
    // Update status
    update_status();
    
    // Update cursor position
    // NOTE: Should always be updated due to frequent movement
    //       That includes messages, cursor naviation, menu invokes, etc.
    int curdiff = cast(int)(curpos - viewpos);
    trace("cur=%d", curdiff);
    update_edit(curdiff, columns, addrpad);
    
    status = 0;
}

void update_view()
{
    file.seek(viewpos);
    ubyte[] data = file.read();
    trace("addr=%u data.length=%u", viewpos, data.length);
    disp_update(viewpos, data, columns,
        Format.hex, Format.hex, '.',
        charset,
        11,
        1);
}

// relative cursor position
void update_edit(int curpos, int columns, int addrpadd)
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
    status |= UMESSAGE;
}

void quit()
{
    trace("quit");
    exit(0);
}