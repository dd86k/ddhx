/// Editor engine.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module editor;

import std.exception : enforce;
import std.format;
import document.base : IDocument;
import transcoder : CharacterSet;
import tracer;
import patcher;

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

deprecated
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
class Editor
{
    // New empty session
    this(
        // Initial size of patch bufer
        size_t patchbufsz = 0,
        // Chunk size
        size_t chunkinc = 4096,
    )
    {
        // Defaults
        addresstype = AddressType.hex;
        datatype = DataType.x8;
        charset = CharacterSet.ascii;
        columns = 16;
        writingmode = WritingMode.overwrite;
        
        patches = new PatchManager(patchbufsz);
        chunks  = new ChunkManager(chunkinc);
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
    
    // TODO: Specific structure to hold session data
    //       struct Session {
    //         int writemode;
    //         long cursor_position;
    //         string target;
    //       }
    /// Current writing mode (read-only, insert, overwrite, etc.)
    WritingMode writingmode;
    /// Current cursor position.
    long curpos;
    /// Base viewing position.
    long basepos;
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
        // TODO: If temp unwritable, retry temp file next to target (+suffix)
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
        ubyte[] savebuf = new ubyte[SAVEBUFSZ];
        long pos;
        do
        {
            // Read and apply history.
            ubyte[] result = view(pos, savebuf);
            
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
        
        targetfile.flush();
        targetfile.sync();
        targetfile.close();
        
        // Save index and path for future saves
        historysavedidx = historyidx;
        
        // Turn as file document in hopes memory gets freed
        import document.file : FileDocument;
        _document = new FileDocument(target, false);
        
        // In case base document was a memory buffer
        import core.memory : GC;
        GC.collect();
        GC.minimize();
    }
    
    /// View the content with all modifications.
    /// NOTE: Caller should hold its own buffer when its base position changes.
    /// Params:
    ///   position = Base position for viewing buffer.
    ///   buffer = Viewing buffer.
    /// Returns: Array of bytes with edits.
    ubyte[] view(long position, ubyte[] buffer)
    {
        enforce(buffer,            "assert: buffer");
        enforce(buffer.length > 0, "assert: buffer.length > 0");
        enforce(position >= 0,     "assert: position >= 0");
        enforce(position <= logical_size, "assert: position < logical_size");
        
        import core.stdc.string : memcpy;
        
        ptrdiff_t req = buffer.length;
        size_t i;
        //while (i < req)
        {
            Chunk *chunk = chunks.locate(position);
            
            if (chunk)
            {
                size_t p = cast(size_t)(position - chunk.position);
                size_t l = buffer.length < chunk.used ? buffer.length : chunk.used - p;
                
                memcpy(buffer.ptr + i, chunk.data + p, l);
                
                return buffer[0..l];
            }
            else
            {
                return basedoc ? basedoc.readAt(position, buffer) : [];
            }
        }
        
        return [];
    }
    
    // Returns true if document was edited (with new changes pending)
    // since the last time it was opened or saved.
    bool edited()
    {
        // If current history index is different from the index where
        // we last saved history data.
        return historyidx != historysavedidx;
    }
    
    // Create a new patch where data is being overwritten
    void overwrite(long pos, const(void) *data, size_t len)
    {
        enforce(pos >= 0 && pos <= _currentsize,
            "assert: pos < 0 || pos > _currentsize");
        
        Patch patch = Patch(pos, PatchType.overwrite, 0, len, data);
        
        // If edit is made at EOF, update total logical size
        if (pos >= logical_size)
        {
            logical_size += len;
            trace("logical_size=%d", logical_size);
        }
        
        // TODO: cross-chunk reference check
        
        // Time to locate (or create) a chunk to apply the patch to
        Chunk *chunk = chunks.locate(pos);
        if (chunk)
        {
            // If the chunk exists, get old data
            patch.olddata = chunk.data + cast(size_t)(pos - chunk.position);
        }
        else
        {
            chunk = chunks.create(pos);
            enforce(chunk, "assert: chunks.create(pos) != null");
            
            // If we have a base document, populate chunk with its data
            if (basedoc)
            {
                ubyte *dat = cast(ubyte*)chunk.data;
                chunk.used = basedoc.readAt(
                    chunk.position, dat[0..chunk.length]).length;
            }
        }
        
        // Add patch into set with new and old data
        patches.add(patch);
        historyidx++;
        
        // Update chunk with new patch data
        // NOTE: For now, chunks are aligned because I'm lazy :V
        import core.stdc.string : memcpy;
        size_t chkpos = cast(size_t)(pos - chunk.position);
        memcpy(chunk.data + chkpos, data, len);
        
        // Update chunk used size if overwrite op goes beyond it
        size_t nchksz = chkpos + len;
        if (nchksz >= chunk.used)
        {
            chunk.used = nchksz;
        }
        
        trace("chunk=%s", *chunk);
    }
    // TODO: insert(long pos, const(void) *data, size_t len)
    // TODO: remove(long pos, const(void) *data, size_t len)
    
    // TODO: void undo()
    
    // TODO: void redo()
    
private:
    // NOTE: Reading memory could be set as long.max
    /// Current logical size including edits.
    long logical_size;
    /// Old alias for logical_size.
    alias _currentsize = logical_size;
    /// Base document.
    IDocument basedoc;
    /// Old alias for _document.
    alias _document = basedoc;
    
    /// History index. To track current edit.
    size_t historyidx;
    /// History index since last save.
    size_t historysavedidx;
    
    PatchManager patches;
    ChunkManager chunks;
}

// New buffer
unittest
{
    scope Editor e = new Editor();
    
    ubyte[32] buffer;
    
    // Initial read
    assert(e.view(0, buffer[]) == []);
    assert(e.edited() == false);
    
    // Write data at position 0
    string data0 = "test";
    e.overwrite(0, data0.ptr, data0.length);
    assert(e.edited());
    assert(e.view(0, buffer[0..4]) == data0);
    assert(e.view(0, buffer[])     == data0);
    
    // Emulate an overwrite edit
    char c = 's';
    e.overwrite(3, &c, char.sizeof);
    assert(e.view(0, buffer[]) == "tess");
    
    // Another...
    e.overwrite(1, &c, char.sizeof);
    assert(e.view(0, buffer[]) == "tsss");
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
    enum DLEN = data.length;
    
    ubyte[32] buffer;
    
    scope MemoryDocument doc = new MemoryDocument(data);
    
    // Initial read
    scope Editor e = new Editor(); e.attach(doc);
    assert(e.edited() == false);
    assert(e.view(0, buffer[])          == data);
    assert(e.view(0, buffer[0..4])      == data[0..4]);
    assert(e.view(DLEN-4, buffer[0..4]) == data[$-4..$]);
    
    // Read past EOF with no edits
    ubyte[48] buffer2;
    assert(e.view(0,  buffer2[]) == data);
    assert(e.view(16, buffer2[0..16]) == data[16..$]);
    
    // Write data at position 4
    static immutable string edit0 = "aaaa";
    e.overwrite(4, edit0.ptr, edit0.length);
    assert(e.edited());
    assert(e.view(4, buffer[0..4]) == edit0);
    
    // check edit hasn't introduced artifacts, and the edit itself
    assert(e.view(0, buffer[0..4]) == data[0..4]);
    assert(e.view(8, buffer[8..$]) == data[8..$]);
    assert(e.view(2, buffer[0..8]) == data[2..4]~cast(ubyte[])edit0~data[8..10]);
    
    // Read past EOF with edit
    assert(e.view(0, buffer2[]) == data[0..4]~cast(ubyte[])edit0~data[8..$]);
    assert(e.view(8, buffer2[]) == data[8..$]);
}
