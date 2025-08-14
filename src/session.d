/// Session management.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module session;

import std.exception : enforce;
import std.format;
import document.base : IDocument;
import transcoder : CharacterSet;
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

enum HistoryType : ubyte
{
    overwrite,
    insertion,
    deletion
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
        enforce(len >= ubyte.sizeof, "length ran out");
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
        
        history = new HistoryStack();
    }
    
    // New session from opened document.
    // Caller has more control for its initial opening operation.
    void attach(IDocument doc)
    {
        _document = doc;
        _currentsize = doc.size(); // init size
    }
    
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
    
    /// View the content with all modifications.
    /// Params:
    ///   position = Base position.
    ///   count = Number of bytes to read.
    /// Returns: Array of bytes with edits.
    ///          The length SHOULD NOT exceed count requested.
    ubyte[] view(long position, size_t count)
    {
        // TODO: Deletion strategy
        //       Because deletion history entries will actively
        //       remove data from the buffer, we'll need to read
        //       more data back, so consider only read to fill in
        //       the blanks at calculated spots.
        
        size_t r; /// final size of rendered view
        
        //
        // Prepare view buffer.
        // If we have a base document, read from it for initial data.
        bool moved   = position != _lastposition;
        bool resized = count != _readbuf.length;
        if (resized)
        {
            _readbuf.length = count;
        }
        if (_document)
        {
            if (resized || moved)
                r = _document.readAt(position, _readbuf).length;
            else
                r = _readbuf.length;
        }
        _lastposition = position;
        
        //
        // Apply history data
        int viewlen = cast(int)_readbuf.length;
        long end = position + count;
        foreach (entry; history.iterate())
        {
            // Edit position starts beyond the view buffer
            // and thus has no influence on it.
            if (entry.address > end)
                continue;
            
            // Edit data doesn't even reach view buffer,
            // but might still influence view buffer (to do...)
            if (entry.address + entry.size < position)
                continue;
            
            // These two indexes serve the area of influence to the buffer.
            // Forcing 32bit indexes to avoid overflows on LP32 targets.
            int bufidx = cast(int)(entry.address - position);
            int endidx = bufidx + cast(uint)entry.size;
            
            // Out of the start and end indexes, make offsets and length to account
            // the entry data+length.
            size_t o; // offset to entry.data
            size_t l = entry.size; // 
            if (bufidx < 0)
            {
                o = +bufidx;
                l -= o;
            }
            else if (endidx >= _readbuf.length)
            {
                l = viewlen - bufidx;
            }
            
            // Adjust the effective size of the view buffer
            HistoryType type = cast(HistoryType)entry.status;
            final switch (type) {
            case HistoryType.overwrite:
                if (l > r)
                    r = l;
                break;
            case HistoryType.insertion:
                break;
            case HistoryType.deletion:
                break;
            }
            
            if (r >= count)
                r = count;
            
            // Copy edit data
            import core.stdc.string : memcpy;
            memcpy(_readbuf.ptr + bufidx, entry.data + o, l);
        }
        
        return _readbuf[0..r];
    }
    
    // Save to target with edits
    void save()
    {
        // NOTE: Caller is responsible to populate target path.
        //       Using assert will stop the program completely,
        //       which would not appear in logs (if enabled).
        //       This also allows the error message to be seen.
        enforce(target != null,    "assert: target is NULL");
        enforce(target.length > 0, "assert: target is EMPTY");
        
        // Careful failsafe
        enforce(writingmode != WritingMode.readonly,
            "Cannot save readonly file");
        
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
        // TODO: Check disk space available separately for temp file.
        //       The temporary file might be on another location/disk.
        string parentdir = dirName(target); // Windows want directory
        ulong avail = getAvailableDiskSpace(parentdir);
        enforce(avail < _currentsize * 2, // temp and target
            text("Need ", (_currentsize * 2) - avail, " B of disk space"));
        
        // Because tmpnam(3), tempnam(3), and mktemp(3) are all deprecated for
        // security and usability issues, a temporary file is used.
        //
        // On Linux, using tmpfile(3), a temporary file is immediately marked for
        // deletion at its creation. So, it should be deleted if the app crashes,
        // which is fine pre-1.0.
        
        // TODO: Check if target is writable (without opening file).
        // TODO: "Cache" temp file
        //       In the event the temporary file is all written out,
        //       but the destination [disk] can't hold the target,
        //       attempt ask again where to save it.
        // Temporary file to write content and edits to.
        // It is nameless, so do not bother getting its filename
        File tempfile = File.tmpfile();
        
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
            ubyte[] result = view(pos, SAVEBUFSZ);
            
            // Write to temp file.
            // Should naturally throw ErrnoException when disk is full
            // (e.g., only wrote buffer partially).
            tempfile.rawWrite(result);
            
            pos += SAVEBUFSZ;
        }
        while (pos < _currentsize);
        
        tempfile.flush();
        tempfile.sync(); // calls OS-specific flush but is it really needed?
        long newsize = tempfile.tell;
        
        // If not all bytes were written, either due to the disk being full
        // or it being our fault, do not continue!
        trace("Wrote %d B out of %d B", newsize, _currentsize);
        enforce(newsize != _currentsize,
            text("Only wrote ", _currentsize, "/", newsize, " B of data"));
        
        tempfile.rewind();
        enforce(tempfile.tell == 0, "assert: File.rewind() != 0");
        
        // Check disk space again for target, just in case.
        // The exception (message) gives it chance to save it elsewhere.
        avail = getAvailableDiskSpace(parentdir);
        enforce(avail < _currentsize,
            text("Need ", _currentsize - avail, " B of disk space"));
        
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
        
        targetfile.flush;
        targetfile.sync;
        
        // Save index and path for future saves
        historysavedidx = historyidx;
        
        // Turn as file document in hopes memory gets freed
        import document.file : FileDocument;
        _document = new FileDocument(target, false);
        import core.memory : GC;
        GC.collect();
    }
    
    //
    // History management
    //
    
    // Returns true if document was edited (with new changes pending)
    // since the last time it was opened or saved.
    bool edited()
    {
        // If current history index is different from the index where
        // we last saved history data.
        return historyidx != historysavedidx;
    }
    
    // Add edit to history stack.
    void historyAdd(long pos, const(void) *data, size_t len, HistoryType type = HistoryType.overwrite)
    {
        // TODO: Remove all history entries after index if history index < count
        //       Then add newest entry
        // TODO: Deletion strategy
        //       If a new deletion is performed at the same position and
        //       targets latest historyidx, then consider removing it.
        history.add(pos, data, len, type);
        historyidx++;
        
        // If edit is made at end of file
        if (pos >= _currentsize)
        {
            _currentsize += len;
        }
    }
    
    // TODO: void historyExtend(const(void) *data, size_t len)
    //       Extend last historical entry with more data
    
    // TODO: void historyUndo()
    
    // TODO: void historyRedo()
    
private:
    // NOTE: Reading memory could be set as long.max
    long _currentsize;
    /// Base document
    IDocument _document;
    
    // for read(long position, size_t count)
    long _lastposition;
    ubyte[] _readbuf; // Input read buffer
    
    /// History index. To track current edit.
    size_t historyidx;
    /// History index since last save.
    size_t historysavedidx;
    /// History stack.
    HistoryStack history;
}

// New buffer
unittest
{
    scope Session sesh = new Session();
    
    // Initial read
    assert(sesh.view(0, 32) == []);
    assert(sesh.edited() == false);
    
    // Write data
    string data0 = "test";
    sesh.historyAdd(0, data0.ptr, data0.length, HistoryType.overwrite);
    assert(sesh.edited());
    assert(sesh.view(0, 4)  == "test");
    assert(sesh.view(0, 32) == "test");
    
    // Emulate an overwrite edit
    char c = 's';
    sesh.historyAdd(3, &c, char.sizeof, HistoryType.overwrite);
    assert(sesh.view(0, 32) == "tess");
    
    // Another...
    sesh.historyAdd(1, &c, char.sizeof, HistoryType.overwrite);
    assert(sesh.view(0, 32) == "tsss");
    
    assert(sesh.view(0, 1) == "t");
    assert(sesh.view(1, 1) == "s");
    assert(sesh.view(2, 1) == "s");
    assert(sesh.view(3, 1) == "s");
}

// Emulate editing a document
unittest
{
    import document.memory : MemoryDocument;
    
    static immutable ubyte[] data = [ // 32 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90, 0xcf,
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a,
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36,
        0xe1, 0xe6, 0xd5, 0xb7, 0xad, 0xe3, 0x16, 0x41,
    ];
    enum L = data.length;
    scope MemoryDocument doc = new MemoryDocument();
    doc.append(data);
    
    // Initial read
    scope Session sesh = new Session();
    sesh.attach(doc);
    assert(sesh.edited() == false);
    assert(sesh.view(0, data.length) == data);
    assert(sesh.view(0, 4) == data[0..4]);
    assert(sesh.view(L-4, 4) == data[L-4..$]);
    
    // Write data
    string data0 = "test";
    sesh.historyAdd(4, data0.ptr, data0.length, HistoryType.overwrite);
    assert(sesh.edited());
    
    // check edit hasn't introduced artifacts, and the edit itself
    assert(sesh.view(0, 4) == data[0..4]);
    import std.stdio : writefln;
    writefln("%(%d,%)", sesh.view(8, L));
    assert(sesh.view(8, L) == data[8..$]);
    assert(sesh.view(4, 4) == "test");
    assert(sesh.view(2, 8) == "\xe6\xea"~"test"~"\x96\xf6");
    
    // test out of bound stuff
    assert(sesh.view(4, 2) == "te");
    assert(sesh.view(6, 2) == "st");
    assert(sesh.view(2, 4) == "\xe6\xeate");
    assert(sesh.view(6, 4) == "st\x96\xf6");
}

// TODO: benchmark view function with 1,000 edits
