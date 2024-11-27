/// Editor application.
/// 
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module editor;

import std.stdio;
import std.string;
import core.stdc.stdlib;
import core.stdc.string;
import core.stdc.errno;
import std.range;
import ddhx.document;
import ddhx.transcoder;
import ddhx.formatter;
import ddhx.logger;
import ddhx.os.terminal;
import ddhx.common;
import ddhx.utils.math;

// NOTE: Glossary
//       Cursor
//         On-screen terminal cursor used for editing.
//         The background highlight is used on other view columns
//       View
//         Region of data that is viewable on-screen.
//         Typically follows the cursor.

// NOTE: Edition must be strictly per-byte

// TODO: Column spacer
//       e.g., Add extra space
// TODO: Bring back virtual cursor, inverted colors
// TODO: Change "Offset(hex)" to "Offset:hex" and change address padding from 11 to 10
// TODO: Option: Address padding, and only print address offset type (e.g., "Hex")
// TODO: Option: Gray out zeros

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
    // When rendering, the first newline with empty data will contain an
    // address, so to indicate that the cursor can reach the new empty row,
    // it much not had any leftover space, e.g., a full row
    LEFTOVER    = 1 << 4,
    
    // Message was sent, clear later
    UMESSAGE    = 1 << 8,
    
    //
    UINIT = UCURSOR | UVIEW | UHEADER,
}

private __gshared // Editor-only settings
{
    Document document;
    
    /// Camera buffer
    deprecated("depend on term size") void *_eviewbuffer;
    /// Camera buffer size
    deprecated("depend on term size") size_t _eviewsize;
    /// Position of the camera, in bytes
    long _eviewpos;
    
    /// Position of the cursor in the file, in bytes
    long _ecurpos; // proposed location
    
    /// Position of the cursor editing a group of bytes, in digits
    int _edgtpos; // e.g., hex=nibble, dec=digit, etc.
    
    /// 
    char[2048] _emsgbuffer;
    /// 
    size_t _emsglength;
    
    /// Editor status, used in updating certains portions of the screen
    int _estatus;
}

// start with file
int startEditor(string filename, bool readonly)
{
    // TODO: Support streams (for editor, that's slurping all of stdin)
    //       doc.openBuffer
    switch (filename) {
    case null, "-":
        stderr.writeln("error: Filename required. No current support for streams.");
        return 1;
    default:
    }
    
    try document.openFile(filename, readonly);
    catch (Exception ex)
    {
        stderr.writeln("error: ", ex.msg);
        return 2;
    }
    
    setupscreen();
    return loop();
}

private:

int loop()
{
Lread:
    update();
    
    TermInput input = terminalRead();
    switch (input.type) {
    case InputType.keyDown: break;
    default:
        goto Lread;
    }
    
    int key = input.key;
    
    // TODO: Consider dictionary to map keys to commands
    //       Useful for user-defined shortcuts
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
        WriteMode wmode = document.writeMode();
        final switch (wmode) {
        case WriteMode.readOnly: // Can't switch from read-only to write
            goto Lread;
        case WriteMode.insert:
            wmode = WriteMode.overwrite;
            break;
        case WriteMode.overwrite:
            wmode = WriteMode.insert;
            break;
        }
        document.writeMode(wmode);
        goto Lread;
    
    // TODO: Search
    /*
    case Key.F | Mod.ctrl:
        break;
    */
    
    // Force refresh
    case Key.R | Mod.ctrl:
        _estatus = UINIT;
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
    terminalInit(TermFeat.altScreen | TermFeat.inputSys);
    _estatus = UINIT;
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

// Move the cursor relative to its position within the file
void moverel(long pos)
{
    if (pos == 0)
        return;
    
    moveabs(_ecurpos + pos);
}

// Move the cursor to an absolute file position
void moveabs(long pos)
{
    if (pos < 0)
        pos = 0;
    if (pos == _ecurpos)
        return;
    
    _ecurpos = pos;
    _estatus |= UCURSOR;
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
    
    moverel(-options.view_columns);
}
void move_down()
{
    moverel(options.view_columns);
}
void move_pg_up()
{
    if (_ecurpos == 0)
        return;
    
    // HACK: Use last rendered term size instead of using terminalSize
    moverel(-((terminalSize().rows - 2) * options.view_columns));
}
void move_pg_down()
{
    // HACK: Use last rendered term size instead of using terminalSize
    moverel((terminalSize().rows - 2) * options.view_columns);
}
void move_ln_start()
{
    moverel(-_ecurpos % options.view_columns);
}
void move_ln_end()
{
    moverel((options.view_columns - (_ecurpos % options.view_columns)) - 1);
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
    TerminalSize termsize = terminalSize();
    int colmax = termsize.columns - 1;
    
    // line buffer
    /*__gshared char *buffer = void;
    __gshared int bufsize;
    if (bufsize < termsize.columns)
    {
        buffer = cast(char*)malloc(termsize.columns);
        assert(buffer);
        bufsize = termsize.columns;
    }*/
    
    // NOTE: Address padding influences offset spacing/trimming
    
    FormatInfo info = formatInfo(options.data_format);
    
    // Number of terminal columns to fill after address
    int termcols = colmax - options.address_padding - 3; // 2 spaces + nl
    assert(termcols > options.address_padding + 3, "terminal need horizontal space");
    // Number of elements that can fit horizontally
    int linecount = options.view_columns; //termcols / 3; // temp: 3 = byte hex + 1 space
    
    // Number of terminal rows to fill
    int termrows = termsize.rows - 2;
    assert(termrows > 3, "terminal need vertical space");
    // Total amount of elements to read in total
    int totalcount = linecount * termrows;
    
    // Adjust view position
    //long viewpos = _eviewpos;
    if (_ecurpos < _eviewpos) // cursor is behind view
    {
        while (_ecurpos < _eviewpos)
        {
            _eviewpos -= options.view_columns;
            if (_eviewpos < 0)
            {
                _eviewpos = 0;
                break;
            }
        }
        _estatus |= UVIEW;
    }
    else if (_ecurpos >= _eviewpos + totalcount) // cursor is ahead of view
    {
        while (_ecurpos >= _eviewpos + totalcount)
        {
            _eviewpos += options.view_columns;
        }
        _estatus |= UVIEW;
    }
    
    // Update header bar
    if (_estatus & UHEADER)
    {
        terminalCursor(0, 0);
        static immutable string PREFIX = "Offset=";
        static immutable string[] FORMATS = [ "hex", "dec", "oct" ];
        string addrformat = FORMATS[Format.hex];
        
        // TODO: Fit header prefix to address padding
        //int width = _eaddrpadding;
        terminalWrite(PREFIX.ptr, PREFIX.length);
        terminalWrite(addrformat.ptr, addrformat.length);
        terminalWrite(" ".ptr, 1);
        
        char[32] buf = void;
        for (int i; i < linecount; i++)
        {
            size_t n = formatval(buf.ptr, buf.sizeof, info.size1, i, Format.hex);
            terminalWrite(" ".ptr, 1);
            terminalWrite(buf.ptr, n);
        }
    }
    
    // Update data view
    size_t lastread;
    if (_estatus & UVIEW)
    {
        static long oldpos;
        
        long address = _eviewpos;
        
        // TODO: Document should read and apply edits itself
        // TODO: Line buffer if rendered lines are longer than terminal windows cols
        
        // Seek to camera position and read buffer
        __gshared void* viewbuffer = void;
        __gshared size_t viewbufsz;
        if (totalcount > viewbufsz)
        {
            viewbuffer = malloc(totalcount);
            assert(viewbuffer, "malloc failed");
            viewbufsz = totalcount;
        }
        ubyte[] viewdata = document.readAt(address, viewbuffer, totalcount);
        trace("_eviewpos=%d addr=%u viewdata.length=%u totalcount=%u",
            _eviewpos, _eviewpos, viewdata.length, totalcount);
        if (viewdata is null || viewdata.length == 0) // If unsuccessful, reset & ignore
        {
            _eviewpos = oldpos;
            return;
        }
        
        // Success, render data buffer
        lastread = viewdata.length;
        oldpos = _eviewpos;
        
        // TODO: Editor applies previous edits in read buffer
        //       document or editor will have to mark in a separate
        //       buffer which bytes have been edited for later colorization
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
        
        // Render what's in the view buffer
        terminalCursor(0, 1);
        long curviewpos = _ecurpos - _eviewpos; // cursor pos in "view"
        char[64] buf = void;
        for (int i; termrows-- > 0; i += linecount, address += linecount)
        {
            // Format and print address
            size_t asize = formatval(buf.ptr, buf.sizeof,
                options.address_padding, address, Format.hex);
            terminalWrite(buf.ptr, asize);
            terminalWrite(" ".ptr, 1);
            
            // Print formatted data
            size_t o = i;
            for (int c; c < linecount; ++c)
            {
                if (o < viewdata.length)
                {
                    terminalWrite(" ".ptr, 1);
                    size_t n = formatval(buf.ptr, buf.sizeof,
                        2, viewdata[o++], Format.hex | F_ZEROPAD);
                    terminalWrite(buf.ptr, n);
                }
                else // fill rest of line with spaces until reaching character
                {
                    _estatus |= LEFTOVER;
                    terminalWrite("   ".ptr, 3);
                }
            }
            
            // Data-Character spaces
            terminalWrite("  ".ptr, 2);
            
            // Print character data
            o = i;
            for (int c; c < linecount; ++c)
            {
                if (o < viewdata.length)
                {
                    immutable(char)[] chr = transcode(viewdata[o++], CharacterSet.ascii);
                    if (chr)
                        terminalWrite(chr.ptr, chr.length);
                    else
                        terminalWrite(&options.character_default, 1);
                }
                else
                {
                    terminalWrite(" ".ptr, 1); // helps clearing damaged cells
                }
            }
            
            // End line
            terminalWrite("\n".ptr, 1);
        }
        
        // Leftover rows to fill in terminal view
        /*if (termrows > 0)
        {
            trace("rowsleft=%d", termrows);
            
            // First row will contain the address without data
            // if previously indicated as such
            if ((_estatus & LEFTOVER) == 0)
            {
                int asize = cast(int)formatval(buf.ptr, buf.sizeof,
                    options.address_padding, address, Format.hex);
                terminalWrite(buf.ptr, asize);
                
                // Fill rest after address
                for (int i; i < colmax - asize - 1; ++i)
                {
                    terminalWrite(" ".ptr, 1);
                }
                terminalWrite("\n".ptr, 1);
                --termrows;
            }
            
            // The rest are just empty lines
            while (termrows-- > 0)
            {
                for (int i; i < colmax; ++i)
                {
                    terminalWrite(" ".ptr, 1);
                }
                terminalWrite("\n".ptr, 1);
            }
        }*/
    }
    
    // Update statusbar
    terminalCursor(0, termsize.rows - 1);
    int msgsize = void;
    if (_estatus & UMESSAGE)
    {
        msgsize = cast(int)terminalWrite(_emsgbuffer.ptr, min(colmax, _emsglength));
    }
    else
    {
        static immutable string[] editmodes = [ "ro", "in", "ov" ];
        
        enum STATBFSZ = 1 * 1024;
        char[STATBFSZ] statbuf = void;
        
        FormatInfo finfo = formatInfo(options.data_format);
        string charset = charsetName(options.character_set);
        string editmode = editmodes[document.writeMode()];
        
        int statlen = snprintf(statbuf.ptr, STATBFSZ, "%.*s | %.*s | %.*s | %lld",
            cast(int)editmode.length, editmode.ptr,
            cast(int)finfo.name.length, finfo.name.ptr,
            cast(int)charset.length, charset.ptr,
            _ecurpos);
        
        msgsize = cast(int)terminalWrite(statbuf.ptr, min(colmax, statlen));
    }
    if (msgsize < colmax) // fill the rest
    {
        int left = colmax - msgsize;
        
        for (int i; i < left; i++)
        {
            terminalWrite(" ".ptr, 1);
        }
    }
    
    // Update virtual visible cursor
    {
        // TODO: Highlight other column with background
        
        // If absolute cursor position is further than view pos + last read length
        long avail = _eviewpos + lastread;
        if (_ecurpos > avail)
            _ecurpos = avail;
        
        // Cursor position in camera
        int curview = cast(int)(_ecurpos - _eviewpos);
        
        // Translate cursor position to 2D coords
        int elemsz = info.size1 + 1; // + space
        int row = 1 + (cast(int)curview / options.view_columns); // header + stuff
        int col = (options.address_padding + 2 + ((curview % options.view_columns) * elemsz));
        terminalCursor(col, row);
    }
    
    // Clear all
    _estatus = 0;
}

// add message to buffer
void message(A...)(const(char)[] fmt, A args)
{
    import std.format : sformat;
    _emsglength = sformat(_emsgbuffer[], fmt, args).length;
    _estatus |= UMESSAGE;
}

void quit()
{
    // TODO: Ask confirmation
    trace("quit");
    exit(0);
}