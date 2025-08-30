/// Editor engine.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module editor;

import document.base : IDocument;
import logger;
import patcher;
import std.exception : enforce;
import std.format;
import transcoder : CharacterSet;

enum WritingMode
{
    readonly,
    overwrite,
    insert,
}
string writingModeToString(WritingMode mode)
{
    // Noticed most (GUI) text editors have these in caps
    final switch (mode) {
    case WritingMode.readonly:  return "R/O";
    case WritingMode.overwrite: return "OVR";
    case WritingMode.insert:    return "INS";
    }
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
        // TODO: if chunkinc == 0, take page size
        assert(chunkinc > 0, "chunkinc > 0");
        
        patches = new PatchManager(patchbufsz);
        chunks  = new ChunkManager(chunkinc);
    }
    
    // New session from opened document.
    // Caller has more control for its initial opening operation.
    void attach(IDocument doc)
    {
        basedoc = doc;
        logical_size = doc.size(); // init size
    }
    
    /// Current size of the document, including edits
    long currentSize()
    {
        return logical_size;
    }
    
    // Save to target with edits
    // TODO: Separate into its own function
    void save(string target)
    {
        log("target=%s logical_size=%u",
            target, logical_size);
        
        // NOTE: Caller is responsible to populate target path.
        //       Using assert will stop the program completely,
        //       which would not appear in logs (if enabled).
        //       This also allows the error message to be seen.
        enforce(target != null,    "assert: target is NULL");
        enforce(target.length > 0, "assert: target is EMPTY");
        
        // If there are really no edits (as caller should check on its own
        // anyway), then there are no new additional things to modify,
        // so return as saved. Nothing else to do.
        if (edited() == false)
            return;
        
        import std.stdio : File;
        import std.conv  : text;
        import os.file : availableDiskSpace;
        
        // We need enough disk space for the temporary file and the target.
        // TODO: Check disk space available separately for temp file.
        //       The temporary file might be on another location/disk.
        ulong avail = availableDiskSpace(target);
        ulong need  = logical_size * 2;
        log("avail=%u need=%u", avail, need);
        enforce(avail >= need, text(need - avail, " B required"));
        
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
        log("Saving with %d edits, %d Bytes...", +count, logical_size);
        
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
        while (pos < logical_size);
        
        tempfile.flush();
        tempfile.sync(); // calls OS-specific flush but is it really needed?
        long newsize = tempfile.tell;
        
        // If not all bytes were written, either due to the disk being full
        // or it being our fault, do not continue!
        log("Wrote %d B out of %d B", newsize, logical_size);
        enforce(newsize == logical_size,
            text("Only wrote ", logical_size, "/", newsize, " B of data"));
        
        tempfile.rewind();
        enforce(tempfile.tell == 0, "assert: File.rewind() != 0");
        
        // Check disk space again for target, just in case.
        // The exception (message) gives it chance to save it elsewhere.
        avail = availableDiskSpace(target);
        enforce(avail >= logical_size,
            text("Need ", logical_size - avail, " B of disk space"));
        
        // Temporary file should now be fully written, time to overwrite target
        // reading from temporary file.
        // Can't use std.file.copy since we don't know the name of our temporary file.
        // And overwriting it doesn't require us to copy attributes.
        // TODO: Manage target open failures
        ubyte[] buffer; /// read buffer
        buffer.length = SAVEBUFSZ;
        File targetfile = File(target, "wb"); // overwrite target
        do
        {
            ubyte[] result = tempfile.rawRead(buffer);
            // TODO: Manage target write failures
            targetfile.rawWrite(result);
        }
        while (tempfile.eof == false);
        buffer.length = 0; // doesn't cause a realloc,
                           // but curious if GC will pick this up
        
        targetfile.flush();
        targetfile.sync();
        targetfile.close();
        
        // Save index and path for future saves
        historysavedidx = historyidx;
        
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
        enforce(position <= logical_size, "assert: position <= logical_size");
        
        import core.stdc.string : memcpy, memset;
        
        log("* position=%d buffer.length=%u", position, buffer.length);
        
        size_t bp; // buffer position
        while (bp < buffer.length)
        {
            long lpos = position + bp;
            Chunk *chunk = chunks.locate(lpos);
            size_t want = buffer.length - bp;
            log("lpos=%d bp=%u want=%u", lpos, bp, want);
            
            if (chunk) // edited chunk found
            {
                ptrdiff_t chkpos = lpos - chunk.position; // relative pos in chunk
                size_t len = chunk.used < want ? chunk.used : want;
                size_t chkavail = chunk.used - chkpos; // fixes basepos+want >= chkused
                if (len >= chkavail)
                    len = chkavail;
                
                log("chunk.position=%u chunk.used=%u len=%u chkpos=%u",
                    chunk.position, chunk.used, len, chkpos);
                
                memcpy(buffer.ptr + bp, chunk.data + chkpos, len);
                bp += len;
                
                // If we're at End of Chunk, makes sense if chunk is currently
                // growing and buffer couldn't be filled.
                if (len < want) break;
            }
            else if (basedoc) // no chunk but has source doc
            {
                size_t len = basedoc.readAt(lpos, buffer[bp..want]).length;
                log("len=%u", len);
                bp += len;
                
                // If we're at EOF of the source document, this means
                // that there is no more data to populate from document
                if (len < want) break;
            }
            else // no chunks (edits) and no base document
            {
                log("none");
                break;
            }
        }
        log("bp=%u", bp);
        enforce(bp <= buffer.length, "assert: bp <= buffer.length");
        return buffer[0..bp];
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
    void replace(long pos, const(void) *data, size_t len)
    {
        enforce(pos >= 0 && pos <= logical_size,
            "assert: pos < 0 || pos > logical_size");
        
        Patch patch = Patch(pos, PatchType.replace, 0, len, data, null);
        
        // If edit is made at EOF, update total logical size
        if (pos >= logical_size)
        {
            logical_size += len;
            log("logical_size=%d", logical_size);
        }
        
        // TODO: cross-chunk reference check
        
        // Time to locate (or create) a chunk to apply the patch to
        Chunk *chunk = chunks.locate(pos);
        if (chunk) // update chunk
        {
            // If the chunk exists, get old data
            patch.olddata = chunk.data + cast(size_t)(pos - chunk.position);
        }
        else // create new chunk and populate it
        {
            chunk = chunks.create(pos);
            enforce(chunk, "assert: chunks.create(pos) != null");
            
            // If we have a base document, populate chunk with its data
            if (basedoc)
            {
                chunk.orig = chunk.used = basedoc.readAt(
                    chunk.position, (cast(ubyte*)chunk.data)[0..chunk.length]).length;
                
                // If chunk offset inside within used range, then there is old data
                size_t o = cast(size_t)(pos - chunk.position);
                if (o < chunk.used)
                    patch.olddata = cast(ubyte*)chunk.data + o;
            }
        }
        
        // Add patch into set with new and old data
        log("add historyidx=%u patch=%s", historyidx, patch);
        patches.insert(historyidx++, patch);
        //patches.add(patch);
        //historyidx++;
        
        // TODO: Check cross-chunk
        
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
        
        chunk.id++;
        
        log("chunk=%s", *chunk);
    }
    /// Ditto
    public alias overwrite = replace;
    // TODO: insert(long pos, const(void) *data, size_t len)
    // TODO: remove(long pos, const(void) *data, size_t len)
    //       Because delete is (was) a reserved keyword
    
    void undo()
    {
        if (historyidx <= 0)
            return;
        
        Patch patch = patches[historyidx - 1];
        // WTF did i forget
        //enforce(patch.olddata, "assert: patch.olddata != NULL");
        
        Chunk *chunk = chunks.locate(patch.address);
        
        // WTF if that happens
        enforce(chunk, "assert: chunk != NULL");
        
        log("patch=%s chunk=%s", patch, *chunk);
        
        // TODO: If insert/deletion, don't forget to reshift chunks
        // TODO: Check cross-chunk access
        
        // End chunk: Update sizes if applicable
        if (patch.address + patch.size >= chunk.position + chunk.used &&
            patch.address + patch.size >  chunk.position + chunk.orig)
        {
            chunk.used -= patch.size;
            
            logical_size -= patch.size;
        }
        // Apply old data if not truncated by resize
        else if (patch.olddata)
        {
            import core.stdc.string : memcpy;
            ptrdiff_t o = patch.address - chunk.position;
            memcpy(chunk.data + o, patch.olddata, patch.size);
        }
        
        chunk.id--;
        historyidx--;
    }
    
    void redo()
    {
        if (historyidx >= patches.count())
            return;
        
        Patch patch = patches[historyidx];
        // WTF did i forget
        //enforce(patch.olddata, "assert: patch.olddata != NULL");
        
        Chunk *chunk = chunks.locate(patch.address);
        
        // WTF if that happens
        enforce(chunk, "assert: chunk != NULL");
        
        log("patch=%s chunk=%s", patch, *chunk);
        
        // TODO: If insert/deletion, don't forget to reshift chunks
        
        // Apply new data
        import core.stdc.string : memcpy;
        ptrdiff_t o = patch.address - chunk.position;
        
        // TODO: Check cross-chunk
        memcpy(chunk.data + o, patch.newdata, patch.size);
        
        // End chunk: Update sizes if applicable
        if (patch.address + patch.size >= chunk.position + chunk.used &&
            patch.address + patch.size >  chunk.position + chunk.orig)
        {
            chunk.used += patch.size;
            
            logical_size += patch.size;
        }
        
        chunk.id++;
        historyidx++;
    }
    
private:
    // NOTE: Reading memory could be set as long.max
    /// Current logical size including edits.
    long logical_size;
    /// Base document.
    IDocument basedoc;
    
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
    log("Test: New empty buffer");
    
    scope Editor e = new Editor();
    
    ubyte[32] buffer;
    
    log("Initial read");
    assert(e.view(0, buffer[]) == []);
    assert(e.edited() == false);
    assert(e.currentSize() == 0);
    
    log("Write data at position 0");
    string data0 = "test";
    e.replace(0, data0.ptr, data0.length);
    assert(e.edited());
    assert(e.view(0, buffer[0..4]) == data0);
    assert(e.view(0, buffer[])     == data0);
    assert(e.currentSize() == 4);
    
    log("Emulate an overwrite edit");
    char c = 's';
    e.replace(3, &c, char.sizeof);
    assert(e.view(0, buffer[]) == "tess");
    assert(e.currentSize() == 4);
    
    log("Another...");
    e.replace(1, &c, char.sizeof);
    assert(e.view(0, buffer[]) == "tsss");
    assert(e.currentSize() == 4);
    
    static immutable string path = "tmp_empty";
    log("Saving to %s", path);
    e.save(path); // throws if it needs to, stopping tests
    
    // Needs to be readable after saving, obviously
    assert(e.view(0, buffer[]) == "tsss");
    assert(e.currentSize() == 4);
    
    import std.file : remove;
    remove(path);
}

// Emulate editing a document
unittest
{
    import document.memory : MemoryDocument;
    
    log("Test: Editing document");
    
    static immutable ubyte[] data = [ // 32 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90, 0xcf,
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a,
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36,
        0xe1, 0xe6, 0xd5, 0xb7, 0xad, 0xe3, 0x16, 0x41,
    ];
    enum DLEN = data.length;
    
    ubyte[32] buffer;
    
    scope MemoryDocument doc = new MemoryDocument(data);
    
    log("Initial read");
    scope Editor e = new Editor(); e.attach(doc);
    assert(e.edited() == false);
    assert(e.view(0, buffer[])          == data);
    assert(e.view(0, buffer[0..4])      == data[0..4]);
    assert(e.view(DLEN-4, buffer[0..4]) == data[$-4..$]);
    assert(e.currentSize() == data.length);
    
    log("Read past EOF with no edits");
    ubyte[48] buffer2;
    assert(e.view(0,  buffer2[]) == data);
    assert(e.view(16, buffer2[0..16]) == data[16..$]);
    assert(e.currentSize() == data.length);
    
    log("Write data at position 4");
    static immutable string edit0 = "aaaa";
    e.replace(4, edit0.ptr, edit0.length);
    assert(e.edited());
    assert(e.view(4, buffer[0..4]) == edit0);
    assert(e.view(0, buffer[0..4]) == data[0..4]);
    assert(e.view(8, buffer[8..$]) == data[8..$]);
    assert(e.view(2, buffer[0..8]) == data[2..4]~cast(ubyte[])edit0~data[8..10]);
    assert(e.currentSize() == data.length);
    
    log("Read past EOF with edit");
    assert(e.view(0, buffer2[]) == data[0..4]~cast(ubyte[])edit0~data[8..$]);
    assert(e.currentSize() == data.length);
    log("Read past EOF with shift");
    assert(e.view(8, buffer2[]) == data[8..$]);
    assert(e.currentSize() == data.length);
    
    static immutable string path = "tmp_doc";
    log("Saving to %s", path);
    e.save(path); // throws if it needs to, stopping tests
    
    // Needs to be readable after saving, obviously
    assert(e.view(2, buffer[0..8]) == data[2..4]~cast(ubyte[])edit0~data[8..10]);
    assert(e.currentSize() == data.length);
    
    import std.file : remove;
    remove(path);
}

// Test undo/redo
unittest
{
    log("Test: Redo/Undo");
    
    scope Editor e = new Editor();
    
    char a = 'a';
    e.replace(0, &a, char.sizeof);
    char b = 'b';
    e.replace(1, &b, char.sizeof);
    
    ubyte[4] buf = void;
    assert(e.view(0, buf[]) == "ab");
    assert(e.currentSize() == 2);
    
    e.undo();
    assert(e.view(0, buf[]) == "a");
    assert(e.currentSize() == 1);
    e.redo();
    assert(e.view(0, buf[]) == "ab");
    assert(e.currentSize() == 2);
    e.redo();
    assert(e.view(0, buf[]) == "ab");
    assert(e.currentSize() == 2);
    e.undo();
    e.undo();
    assert(e.view(0, buf[]) == []);
    assert(e.currentSize() == 0);
    e.undo();
    assert(e.view(0, buf[]) == []);
    assert(e.currentSize() == 0);
    e.redo();
    e.redo();
    assert(e.view(0, buf[]) == "ab");
    assert(e.currentSize() == 2);
}

// Test undo/redo with doc
unittest
{
    import document.memory : MemoryDocument;
    
    log("Test: Redo/Undo with doc");
    
    scope MemoryDocument doc = new MemoryDocument([ 'd', 'd' ]);
    scope Editor e = new Editor();
    e.attach(doc);
    
    ubyte[4] buf = void;
    assert(e.view(0, buf[]) == "dd");
    assert(e.currentSize() == 2);
    
    char a = 'a';
    e.replace(0, &a, char.sizeof);
    char b = 'b';
    e.replace(1, &b, char.sizeof);
    
    assert(e.view(0, buf[]) == "ab");
    assert(e.currentSize() == 2);
    
    // Undo and redo once
    e.undo();
    assert(e.view(0, buf[]) == "ad");
    assert(e.currentSize() == 2);
    e.redo();
    assert(e.view(0, buf[]) == "ab");
    assert(e.currentSize() == 2);
    
    // Overdoing redo
    e.redo();
    assert(e.view(0, buf[]) == "ab");
    assert(e.currentSize() == 2);
    
    // Undo all
    e.undo();
    e.undo();
    assert(e.view(0, buf[]) == "dd");
    assert(e.currentSize() == 2);
    
    // Overdoing undo
    e.undo();
    assert(e.view(0, buf[]) == "dd");
    assert(e.currentSize() == 2);
    
    // Redo all
    e.redo();
    e.redo();
    assert(e.view(0, buf[]) == "ab");
    assert(e.currentSize() == 2);
}

// Test undo/redo with larger doc
unittest
{
    import document.memory : MemoryDocument;
    
    log("Test: Redo/Undo with large doc");
    
    // all memset to 0
    enum DOC_SIZE = 8000;
    scope MemoryDocument doc = new MemoryDocument(new ubyte[DOC_SIZE]);
    scope Editor e = new Editor();
    e.attach(doc);
    
    ubyte[32] buf = void;
    assert(e.view(40, buf[0..4]) == [ 0, 0, 0, 0 ]);
    assert(e.currentSize() == 8000);
    
    char a = 0xff;
    e.replace(41, &a, char.sizeof);
    e.replace(42, &a, char.sizeof);
    assert(e.view(40, buf[0..4]) == [ 0, 0xff, 0xff, 0 ]);
    assert(e.currentSize() == 8000);
    
    e.undo();
    assert(e.view(40, buf[0..4]) == [ 0, 0xff, 0, 0 ]);
    assert(e.currentSize() == 8000);
    
    e.undo();
    assert(e.view(40, buf[0..4]) == [ 0, 0, 0, 0 ]);
    assert(e.currentSize() == 8000);
    
    e.replace(41, &a, char.sizeof);
    e.replace(42, &a, char.sizeof);
    e.replace(43, &a, char.sizeof);
    e.replace(44, &a, char.sizeof);
    e.undo();
    e.undo();
    e.undo();
    e.undo();
    assert(e.view(40, buf[0..8]) == [ 0, 0, 0, 0, 0, 0, 0, 0 ]);
    assert(e.currentSize() == 8000);
}
