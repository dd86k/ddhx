/// Session management.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module session;

import document : IDocument, FileDocument;
import transcoder : CharacterSet, transcode;
import std.format;
import history;
import tracer;

enum WritingMode
{
    readonly,
    overwrite,
    insert,
}
string writingModeToString(WritingMode mode)
{
    final switch (mode) {
    case WritingMode.readonly:  return "r/o";
    case WritingMode.overwrite: return "ovr";
    case WritingMode.insert:    return "ins";
    }
}

enum PanelType
{
    data,
    text,
}

//
// Address specifications
//

enum AddressType
{
    hex, dec, oct,
}
string addressTypeToString(AddressType type)
{
    final switch (type) {
    case AddressType.hex: return "hex";
    case AddressType.dec: return "dec";
    case AddressType.oct: return "oct";
    }
}
string formatAddress(char[] buf, long v, int spacing, AddressType type)
{
    string spec = void;
    final switch (type) {
    case AddressType.hex: spec = "%*x"; break;
    case AddressType.dec: spec = "%*d"; break;
    case AddressType.oct: spec = "%*o"; break;
    }
    return cast(string)sformat(buf, spec, spacing, v);
}
unittest
{
    char[32] buf = void;
    // Columns
    assert(formatAddress(buf[], 0x00, 2, AddressType.hex) == " 0");
    assert(formatAddress(buf[], 0x01, 2, AddressType.hex) == " 1");
    assert(formatAddress(buf[], 0x80, 2, AddressType.hex) == "80");
    assert(formatAddress(buf[], 0xff, 2, AddressType.hex) == "ff");
    // Rows
    assert(formatAddress(buf[], 0x00, 10, AddressType.hex)        == "         0");
    assert(formatAddress(buf[], 0x01, 10, AddressType.hex)        == "         1");
    assert(formatAddress(buf[], 0x80, 10, AddressType.hex)        == "        80");
    assert(formatAddress(buf[], 0xff, 10, AddressType.hex)        == "        ff");
    assert(formatAddress(buf[], 0x100, 10, AddressType.hex)       == "       100");
    assert(formatAddress(buf[], 0x1000, 10, AddressType.hex)      == "      1000");
    assert(formatAddress(buf[], 0x10000, 10, AddressType.hex)     == "     10000");
    assert(formatAddress(buf[], 0x100000, 10, AddressType.hex)    == "    100000");
    assert(formatAddress(buf[], 0x1000000, 10, AddressType.hex)   == "   1000000");
    assert(formatAddress(buf[], 0x10000000, 10, AddressType.hex)  == "  10000000");
    assert(formatAddress(buf[], 0x100000000, 10, AddressType.hex) == " 100000000");
}

//
// Data handling
//

// 
enum DataType
{
    x8,
}
struct DataSpec
{
    string name;
    /// Number of characters it occupies at maximum. Used for alignment.
    int spacing;
}
DataSpec dataSpec(DataType type)
{
    final switch (type) {
    case DataType.x8: return DataSpec("x8", 2);
    }
}
string dataTypeToString(DataType type) // for printing
{
    final switch (type) {
    case DataType.x8: return "x8";
    }
}
// Format element depending on editor settings
string formatData(char[] buf, void *dat, size_t len, DataType type)
{
    final switch (type) {
    case DataType.x8:
        assert(len >= ubyte.sizeof, "length ran out");
        return formatx8(buf, *cast(ubyte*)dat, false);
    }
}
unittest
{
    char[32] buf = void;
    ubyte a = 0x00;
    assert(formatData(buf[], &a, ubyte.sizeof, DataType.x8) == "00");
    ubyte b = 0x01;
    assert(formatData(buf[], &b, ubyte.sizeof, DataType.x8) == "01");
    ubyte c = 0xff;
    assert(formatData(buf[], &c, ubyte.sizeof, DataType.x8) == "ff");
}

string formatx8(char[] buf, ubyte v, bool spacer)
{
    return cast(string)sformat(buf, spacer ? "%2x" : "%02x", v);
}
unittest
{
    char[32] buf = void;
    assert(formatx8(buf[], 0x00, false) == "00");
    assert(formatx8(buf[], 0x01, false) == "01");
    assert(formatx8(buf[], 0xff, false) == "ff");
}

// Helps to walk over a buffer
struct DataFormatter
{
    this(DataType dtype, const(ubyte) *data, size_t len)
    {
        buffer = data;
        max = buffer + len;
        
        switch (dtype) {
        case DataType.x8:
            formatdata = () {
                if (buffer + size > max)
                    return null;
                return formatx8(textbuf[], *cast(ubyte*)(buffer++), false);
            };
            size = ubyte.sizeof;
            break;
        default:
            throw new Exception("TODO");
        }
    }
    
    void skip()
    {
        buffer += size;
    }
    
    string delegate() formatdata;
    
private:
    char[32] textbuf = void;
    size_t size;
    const(void) *buffer;
    const(void) *max;
}
unittest
{
    immutable ubyte[] data = [ 0x00, 0x01, 0xa0, 0xff ];
    DataFormatter formatter = DataFormatter(DataType.x8, data.ptr, data.length);
    assert(formatter.formatdata() == "00");
    assert(formatter.formatdata() == "01");
    assert(formatter.formatdata() == "a0");
    assert(formatter.formatdata() == "ff");
    assert(formatter.formatdata() == null);
}

// Represents a session.
//
// Manages edits and document handling. Mostly exists to hold current settings.
class Session
{
    // New empty session
    this()
    {
        // Defaults
        addresstype = AddressType.hex;
        datatype = DataType.x8;
        charset = CharacterSet.ascii;
        columns = 16;
        writingmode = WritingMode.overwrite;
        
        history = HistoryStack(4096);
    }
    
    // New session from file
    void openFile(string path, bool readonly)
    {
        _document = new FileDocument(path, readonly);
        _currentsize = _document.size();
        
        writingmode = readonly ? WritingMode.readonly : WritingMode.overwrite;
        
        target = path;
    }
    
    // TODO: openProcess(int) -> ProcessDocument
    
    //
    // Variables
    //
    
    /// Current writing mode (read-only, insert, overwrite, etc.)
    WritingMode writingmode;
    /// Current cursor position.
    long curpos;
    /// Base viewing position.
    long basepos;
    /// Currently select panel.
    PanelType panel;
    /// Target file, if known.
    string target;
    
    // TODO: Editor should keep a copy of RC to ease management
    /// Desired amount of number of columns per row for each element.
    int columns;
    AddressType addresstype;
    DataType datatype;
    CharacterSet charset;
    
    /// Current size of the document, including edits
    long currentSize()
    {
        return _currentsize;
    }
    
    ubyte[] read(long position, size_t count)
    {
        // If we originated with a document, keep a read buffer around
        if (_document)
        {
            bool resized = count != _readbuf.length;
            bool moved   = position != _lastposition;
            
            // Does D unconditionally resize given the save size?
            if (resized)
            {
                _readbuf.length = count;
            }
            
            // Update internal buffer
            if (resized || moved)
                _read2 = _document.readAt(position, _readbuf);
            _lastposition = position;
        }
        else
        {
            _read2 = [];
        }
        
        return history.apply(position, _read2);
    }
    
    // Save to target with edits
    void save()
    {
        // NOTE: Caller is responsible to populate target path
        assert(target, "target is NULL");
        assert(target.length, "target is EMPTY");
        
        // Careful failsafe
        if (writingmode == WritingMode.readonly)
        {
            throw new Exception("Cannot save readonly file");
        }
        
        // If there are really no edits (as caller should check on its own
        // anyway), then there are no new additional things to modify,
        // so return as saved. Nothing else to do.
        if (edited() == false)
            return;
        
        import std.stdio : File;
        import std.conv  : text;
        import std.file  : getAvailableDiskSpace;
        import std.path  : dirName;
        
        // We need enough disk space for the temporary file and the target.
        //
        // Attempt to get the parent directory of target (even when inexistent)
        // because on Windows, it needs to be a folder, to get available disk space.
        // TODO: Check disk space available separately for temp file.
        //       The temporary file might be on another location/disk.
        string parentdir = dirName(target);
        ulong avail = getAvailableDiskSpace(parentdir);
        if (avail < _currentsize * 2) // temp + target
            throw new Exception("Lacking space to save");
        
        // We can go from writing a few bytes to hundreds of gigabytes,
        // so to try to stay safe, we (at least for now) write everything
        // to a temporary file, and then attempt to replace the target
        // with our temporary file.
        //
        // Temporary file should get the same attributes than the
        // target, except for a modified date, if present. That way,
        // the attributes should be kept when copying the temp file.
        //
        // On Linux, using tmpfile(3), a temporary file is immediately marked for
        // deletion at its creation. Making me worried that the temporary file
        // might not survive a move after the app closes (which I could test, but a
        // path gives me a bit more flexibility in general).
        //
        // However, tmpnam(3), tempnam(3), and mktemp(3) are all deprecated for
        // security and usability issues (e.g., Windows has GetTempPath2W introduced
        // in Windows 11 build 22000 which MSVC/UCRT will eventually use anyway).
        //
        // It's safer to get a temp file, write to it, then overwrite target from
        // temp file. Yes, it's I/O heavy, but should be okay as a first implementation.
        
        // TODO: Check if target is writable (without opening file).
        File tempfile = File.tmpfile(); // nameless...
        
        // Get range of edits to apply when saving.
        // TODO: Test without ptrdiff_t cast
        ptrdiff_t count = cast(ptrdiff_t)historyidx - historysavedidx;
        trace("Saving with %d edits, %d Bytes...", +count, _currentsize);
        
        // Right now, the simplest implement is to write everything.
        // We will eventually handle overwites, inserts, and deletions
        // within the same file...
        enum SAVEBUFSZ = 32 * 1024;
        long pos;
        do
        {
            // Read and apply history.
            ubyte[] result = read(pos, SAVEBUFSZ);
            // TODO: Limit range of edits (using history idx and savedidx).
            result = history.apply(pos, result);
            
            // Write to temp file.
            // Should naturally throw ErrnoException when disk is full
            // (e.g., only wrote buffer partially).
            tempfile.rawWrite(result);
            
            pos += SAVEBUFSZ;
        }
        while (pos < _currentsize);
        
        tempfile.flush();
        tempfile.sync();
        long newsize = tempfile.tell;
        
        // If not all bytes were written, either due to the disk being full
        // or it being our fault, do not continue!
        trace("Wrote %d B out of %d B", newsize, _currentsize);
        if (newsize != _currentsize)
            throw new Exception(text("Expected ", _currentsize, " B, wrote ", newsize, " B"));
        
        tempfile.rewind();
        assert(tempfile.tell == 0, ".rewind() is broken, switch to .seek(0, SEEK_SET)");
        
        // Check disk space again for target, just in case.
        if (getAvailableDiskSpace(parentdir) < _currentsize)
            throw new Exception("Lacking disk space to save target");
        
        // Temporary file should now be fully written, time to overwrite target
        // reading from temporary file.
        // Can't use std.file.copy since we don't know the name of our temporary file.
        // And overwriting it doesn't require us to copy attributes.
        // TODO: Manage target open failures
        scope ubyte[] buffer = new ubyte[SAVEBUFSZ]; // read buffer
        File targetfile = File(target, "wb"); // overwrite target
        do
        {
            ubyte[] result = tempfile.rawRead(buffer);
            // TODO: Manage target write failures
            targetfile.rawWrite(result);
        }
        while (tempfile.eof == false);
        
        // TODO: Consider transforming document type to FileDocument if not FileDocument.
        //       Though, it's not a concern for now.
        // Save index and path for future saves
        historysavedidx = historyidx;
    }
    
    //
    // History management
    //
    
    // Apply historical edits to view buffer.
    ubyte[] historyApply(long basepos, ubyte[] buffer)
    {
        return history.apply(basepos, buffer);
    }
    
    // Add edit to history stack.
    void historyAdd(long pos, void *data, size_t len)
    {
        // TODO: Remove all history entries after index if history index < count
        //       Then add newest entry
        history.add(pos, data, len);
        historyidx++;
        
        // If edit is made at end of file
        if (pos >= _currentsize)
        {
            _currentsize += len;
        }
    }
    
    // Returns true if document was edited (with new changes pending)
    // since the last time it was opened or saved.
    bool edited()
    {
        // If current history index is different from the index where
        // we last saved history data.
        return historyidx != historysavedidx;
    }
    
    // TODO: void historyUndo()
    
    // TODO: void historyRedo()
    
private:
    // NOTE: Reading memory could be set as long.max
    long _currentsize;
    IDocument _document;
    
    // for read(long position, size_t count)
    long _lastposition;
    ubyte[] _readbuf; // Input read buffer
    ubyte[] _read2;   // Output slice
    
    // History index. Managed outside of HistoryStack for simplicity.
    size_t historyidx;
    // Saved history index since last open/save.
    size_t historysavedidx;
    // History stack
    HistoryStack history;
}
