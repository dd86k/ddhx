/// Editor backend implementing an in-memory chunk-based data structure.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module backend.chunks;

// NOTE: Basic idea
//
//       history (contains patches)
//         List of patches applied in-order.
//
//       chunks
//         Chunks are pre-calculated on overwrite/insertion/deletion.
//         Say they are 4K, they should be 4K-aligned (helps coalescing).
//         Could be a RedBlack tree (std.container.rbtree) since chunks
//         are unique. (based on their position)

import std.container.array  : Array;
import platform : assertion;
import core.stdc.string : memcpy;
import core.stdc.stdlib : malloc, free;
import utils : align64down;
import backend.base; // + tests
import document.base : IDocument;
import logger;

/// Type of patch.
enum PatchType : short
{
    replace,    /// Replace these bytes for range.
    insertion,  /// Insert these bytes starting at position.
    deletion,   /// Delete (trim) out this range of bytes.
}

private enum {
    // HACK: for undo
    PATCH_APPEND = 4,
}

/// Represents a patch
struct Patch
{
    /// Base position of the patch
    long address;
    /// Type of patch being applied,
    PatchType type;
    /// Status flags
    int status;
    /// Size of patch
    size_t size;
    // Insertion and Overwrite: new data
    // Deletion: old data
    /// New patch data.
    ///
    /// This data is copied by the Patcher when added.
    const(void) *newdata;
    /// Old patch data.
    ///
    /// This data is copied by the Patcher when added.
    const(void) *olddata;
}

/// Manages the storage of patches.
private
class PatchManager
{
    /// Create a new PatchManager.
    // datasize = Initial and incremental size of data buffer for holding patch data.
    this(size_t initsize = 0, size_t incsize = 0)
    {
        patch_buffer.length = initsize;
        param_increment = incsize;
    }
    
    /// Count of patches in memory.
    /// Returns: Total amount.
    size_t count()
    {
        return patches.length;
    }
    
    Patch opIndex(size_t i) // @suppress(dscanner.style.undocumented_declaration)
    {
        // Let it throw if out of bounds
        return patches[i];
    }
    
    /// Append or overwrite patch at this index.
    ///
    /// This might happen when we undo and start writing new data.
    /// Params:
    ///     i = Index.
    ///     patch = Patch.
    void insert(size_t i, Patch patch)
    {
        prepare(patch);
        
        // If index fits in set, replace patch at index
        if (i < patches.length)
            patches[i] = patch;
        else // Otherwise, add it so set
            patches.insert(patch);
    }
    
    void clear()
    {
        patches.clear();
    }
    
private:
    /// Size of initial and incremental patch data buffer
    size_t param_increment;
    
    /// Buffer for new and old patch data
    ubyte[] patch_buffer;
    /// Amount of buffer used
    size_t  patch_used;
    
    // NOTE: SList
    //       The .insert alias is mapped to .insertFront, which puts last inserted
    //       elements as the first element, making it useless with foreach (starts
    //       with last inserted element, which we don't want). On top of the fact
    //       that foreach_reverse is unavailable with SList.
    /// History stack
    Array!Patch patches; // Array!T supports slicing
    
    // Prepare patch before adding to list, which means copying its data
    void prepare(ref Patch patch)
    {
        // If we can't contain data for patch, increase buffer
        size_t newsize = patch_used + patch.size * 2;
        if (newsize >= patch_buffer.length)
        {
            // Try aligned increment
            size_t tempt = patch_buffer.length + param_increment;
            // If the temptative size is still too small... Add size of patch anyway
            if (tempt < newsize)
                tempt = newsize;
            patch_buffer.length = tempt;
        }
        
        // NOTE: System needs data
        //       data-less inserts (e.g., 1000 of this type) are not supported
        assertion(patch.newdata, "patch.newdata");
        //assertion(patch.olddata, "patch.olddata");
        
        // Copy its data into buffers
        void *buf0 = patch_buffer.ptr + patch_used;
        memcpy(buf0, patch.newdata, patch.size);
        patch.newdata = buf0; // new address
        patch_used += patch.size;
        
        // Copy old data if it has any
        if (patch.olddata)
        {
            void *buf1 = buf0 + patch.size;
            memcpy(buf1, patch.olddata, patch.size);
            patch.olddata = buf1; // new address
            patch_used += patch.size;
        }
    }
}
unittest
{
    static immutable ubyte[] data0 = [ 0xfe ];
    
    // Just insert patches to see if they are held in memory
    scope PatchManager patches = new PatchManager();
    patches.insert(0, Patch(0, PatchType.replace, 0, 1, data0.ptr, null));
    patches.insert(1, Patch(1, PatchType.replace, 0, 1, data0.ptr, null));
    patches.insert(2, Patch(2, PatchType.replace, 0, 1, data0.ptr, null));
    
    assert(patches[0].address == 0);
    assert(patches[1].address == 1);
    assert(patches[2].address == 2);
    
    patches.insert(2, Patch(10, PatchType.replace, 0, 1, data0.ptr, null));
    assert(patches[2].address == 10);
}

/// Represents a chunk buffer.
///
/// This is used to speedup view rendering by precalculating patches into it.
struct Chunk
{
    /// Actual logical position of chunk.
    ///
    /// Set by ChunkManager.
    long position;
    /// Allocated data.
    ///
    /// Set by ChunkManager.
    void *data;
    /// Capacity of the chunk, its allocated size.
    ///
    /// Set by ChunkManager.
    size_t length;
    /// Amount of data used in this chunk, its logical size.
    size_t used;
    /// Amount of data written by the source document.
    size_t orig;
    /// Patch ID.
    ///
    /// Currently used to count the number of patches applied in this chunk.
    /// This eases memory management. When an undo operation is performed and
    /// id reaches 0, the chunk is deleted.
    uint id;
}

// Manages chunks
//
// Caller is responsible for populating data into chunks
//
// NOTE: For simplicity, chunks are SIZE aligned.
private
class ChunkManager
{
    // chksize = Size of chunk, smaller uses less memory but might be more fragmented.
    this(size_t chksize = 4096)
    {
        assert(chksize > 0, "chksize > 0");
        param_size = chksize;
    }
    
    // Caller must fill chunk data manually
    Chunk* create(long position)
    {
        // Using malloc eases memory management
        void *data = malloc(param_size);
        assertion(data, "ChunkManager.create:malloc");
        
        long basepos = align64down(position, param_size);
        chunks[basepos] = Chunk(basepos, data, param_size, 0, 0, 0);
        
        // ptr returned is in heap anyway, so after its insertion
        return basepos in chunks;
    }
    
    // Locate a chunk in this position
    Chunk* locate(long position)
    {
        return align64down(position, param_size) in chunks;
    }
    
    // Remove chunk
    void remove(Chunk *chunk)
    {
        assertion(chunk,      "chunk != null");
        assertion(chunk.data, "chunk.data != null");
        
        free(chunk.data);
        
        chunks.remove(chunk.position);
    }
    
    void flush()
    {
        chunks.rehash();
    }
    
    // get configured size for chunks
    size_t alignment()
    {
        return param_size;
    }
    
    void clear()
    {
        foreach (key, val; chunks)
        {
            free(val.data);
            chunks.remove(val.position);
        }
    }

private:
    /// Size of chunk and base memory alignment.
    size_t param_size;
    
    // NOTE: Eventually use std.container.rbtree.RedBlackTree
    //       Using an AA will eventually lead to complications when managing
    //       neighbour chunks (e.g., coalescing, data inserts and deletions)
    Chunk[long] chunks;
}
unittest
{
    scope ChunkManager chunks = new ChunkManager(32);
    
    assert(chunks.locate(0)  == null);
    assert(chunks.locate(42) == null);
    
    Chunk *chunk0 = chunks.create(0);
    assert(chunk0);
    assert(chunk0.position == 0);
    assert(chunk0.length == 32);
    assert(chunk0.data);
    
    chunk0 = chunks.locate(0);
    assert(chunk0);
    assert(chunk0.position == 0);
    assert(chunk0.length == 32);
    assert(chunk0.data);
    assert(chunks.locate(0)  == chunk0);
    assert(chunks.locate(31) == chunk0);
    assert(chunks.locate(32) == null);
    assert(chunks.locate(33) == null);
    
    Chunk *chunk1 = chunks.create(42);
    assert(chunk1);
    assert(chunk1.position == 32);
    assert(chunk1.length == 32);
    assert(chunk1.data);
    
    chunk1 = chunks.locate(42);
    assert(chunk1);
    assert(chunk1.position == 32);
    assert(chunk1.length == 32);
    assert(chunk1.data);
    
    // Emulate a patch being applied
    chunk1.used = 1;
    (cast(ubyte*)chunk1.data)[0] = 0xff;
    // Later... Re-located
    chunk1 = chunks.locate(42);
    assert((cast(ubyte*)chunk1.data)[0] == 0xff);
    assert(chunk1.used == 1);
}

/// Document editor implemented using in-memory-aligned chunks.
class ChunkDocumentEditor : IDocumentEditor
{
    /// Create a new instance with default allocation sizes.
    this()
    {
        this(0, 0);
    }
    
    /// Create a new instance with specified allocation sizes.
    /// Params:
    ///     pbufsz = Initial size of the data buffer (default=0).
    ///     chkinc = Chunk size (defaults to page size).
    this(size_t pbufsz, size_t chkinc)
    {
        import os.mem : syspagesize;
        size_t pagesize = syspagesize();
        if (chkinc == 0)
            chkinc = pagesize;
        
        patches = new PatchManager(pbufsz, pagesize);
        chunks  = new ChunkManager(chkinc);
    }
    
    /// Open document.
    /// Params: doc = Document.
    /// Returns: Class instance.
    typeof(this) open(IDocument doc)
    {
        basedoc = doc;
        logical_size = doc.size(); // init size
        
        historyidx = historysavedidx = 0;
        
        patches.clear();
        chunks.clear();
        
        return this;
    }
    
    /// Current size of the document, including edits.
    /// Returns: Size in Bytes.
    long size()
    {
        return logical_size;
    }
    /// Ditto
    alias currentSize = size; // Older alias
    
    /// Save as file to a specified location.
    /// Throws: I/O error or enforcement.
    /// Params: target = File system path.
    void save(string target)
    {
        log("target=%s logical_size=%u", target, logical_size);
        
        // TODO: Speedup saving
        //       In an attempt to speed up saving (ie, with multiple gigabytes),
        //       it might be worth file to only overwrite the target file (if it
        //       exists) with chunks of edited data.
        
        // NOTE: Caller is responsible to populate target path.
        //       Using assert will stop the program completely,
        //       which would not appear in logs (if enabled).
        //       This also allows the error message to be seen.
        assertion(target != null,    "target is NULL");
        assertion(target.length > 0, "target is EMPTY");
        
        import std.stdio : File;
        import std.conv  : text;
        import os.file : availableDiskSpace;
        
        // We need enough disk space for the temporary file and the target.
        // TODO: Check disk space available separately for temp file.
        //       The temporary file might be on another location/disk.
        ulong avail = availableDiskSpace(target);
        ulong need  = logical_size * 2;
        log("avail=%u need=%u", avail, need);
        assertion(avail >= need, text(need - avail, " B required"));
        
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
        log("Saving with %d edits, %d Bytes...", count, logical_size);
        
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
        assertion(newsize == logical_size, text("Only wrote ", logical_size, "/", newsize, " B of data"));
        
        tempfile.rewind();
        assertion(tempfile.tell == 0, "File.rewind() != 0");
        
        // Check disk space again for target, just in case.
        // The exception (message) gives it chance to save it elsewhere.
        avail = availableDiskSpace(target);
        assertion(avail >= logical_size, text("Need ", logical_size - avail, " B of disk space"));
        
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
    
    /// View the content of the document with current modifications.
    /// Params:
    ///   position = Base position for viewing buffer.
    ///   buffer = Viewing buffer pointer.
    ///   size = Size of the view buffer.
    /// Returns: Array of bytes with edits.
    ubyte[] view(long position, void *buffer, size_t size)
    {
        return view(position, (cast(ubyte*)buffer)[0..size]);
    }
    
    /// View the content of the document with all modifications.
    /// Throws: Enforcement.
    /// Params:
    ///   position = Base position for viewing buffer.
    ///   buffer = Viewing buffer.
    /// Returns: Array of bytes with edits.
    ubyte[] view(long position, ubyte[] buffer)
    {
        assertion(buffer,            "buffer");
        assertion(buffer.length > 0, "buffer.length > 0");
        assertion(position >= 0,     "position >= 0");
        assertion(position <= logical_size, "position <= logical_size");
        
        import core.stdc.string : memcpy, memset;
        
        log("* position=%d buffer.length=%u", position, buffer.length);
        
        size_t cksize = chunks.alignment;
        size_t l; // length
        while (l < buffer.length)
        {
            long lpos = position + l;
            Chunk *chunk = chunks.locate(lpos);
            size_t want = buffer.length - l;
            log("lpos=%d l=%u want=%u", lpos, l, want);
            
            if (chunk) // edited chunk found
            {
                // Relative chunk position to requested logical position.
                ptrdiff_t chkpos = cast(ptrdiff_t)(lpos - chunk.position);
                
                // First, we need to see if the required length fits within the
                // chunk.
                if (chkpos + want < chunk.used) // fits within wants, allowed to break
                {
                    log("CHUNK chkpos=%d want=%u", chkpos, want);
                    memcpy(buffer.ptr + l, chunk.data + chkpos, want);
                    l += want;
                    break;
                }
                
                // Otherwise, we fill what we can from chunk and continue to next position
                size_t len = chunk.used - chkpos;
                log("CHUNK.PART chkpos=%d len=%u", chkpos, len);
                memcpy(buffer.ptr + l, chunk.data + chkpos, len);
                l += len;
                
                if (chunk.used < chunk.length) break;
            }
            else if (basedoc) // no chunk but has source doc
            {
                // Only read up to a chunk size to avoid overlapping
                if (want > cksize)
                    want = cksize;
                
                log("DOC want=%u", want);
                size_t len = basedoc.readAt(lpos, buffer[l..l+want]).length;
                log("len=%u", len);
                l += len;
                
                // If we're at EOF of the source document, this means
                // that there is no more data to populate from basedoc
                if (len < want) break;
            }
            else // no chunks (edits) and no base document
            {
                log("NONE");
                break;
            }
        }
        log("l=%u", l);
        
        assertion(l <= buffer.length, "l <= buffer.length");
        return buffer[0..l];
    }
    
    /// Returns true if document was edited (with new changes pending)
    /// since the last time it was opened or saved.
    /// Returns: True if edited since last save.
    bool edited()
    {
        // If current history index is different from the index where
        // we last saved history data.
        return historyidx != historysavedidx;
    }
    
    /// Create a new patch where data is being overwritten.
    /// Throws: Enforcement.
    /// Params:
    ///     pos = Base position.
    ///     data = Data.
    ///     len = Data length.
    void replace(long pos, const(void) *data, size_t len)
    {
        assertion(pos >= 0,            "pos >= 0");
        assertion(pos <= logical_size, "pos <= logical_size");
        
        Patch patch = Patch(pos, PatchType.replace, 0, len, data, null);
        
        // If edit is made at EOF, update total logical size
        if (pos >= logical_size)
        {
            logical_size += len;
            log("logical_size=%d", logical_size);
            patch.status |= PATCH_APPEND;
        }
        
        // TODO: Rewrite this function
        //       It'd be better to rewrite this function that "walks" across
        //       "chunks" (min(chunk.length, len_rem)) which should cover
        //       chunk gaps and chunk overflows.
        
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
            assertion(chunk, "chunks.create(pos) != null");
            
            // If we have a base document, populate chunk with its data
            if (basedoc)
            {
                chunk.orig = chunk.used = basedoc.readAt(
                    chunk.position, (cast(ubyte*)chunk.data)[0..chunk.length]
                ).length;
                
                size_t chkoff = cast(size_t)(pos - chunk.position);
                
                // If chunk offset inside within used range, then there is old data
                if (chkoff < chunk.used)
                    patch.olddata = cast(ubyte*)chunk.data + chkoff;
            }
        }
        
        // TODO: Fix cross-chunk old data reference
        //       Probably with a "copy old data" function which can append
        // Add patch into set with new and old data
        log("add historyidx=%u patch=%s", historyidx, patch);
        patches.insert(historyidx++, patch);
        
        // Update chunk with new patch data
        import core.stdc.string : memcpy;
        size_t chkoff = cast(size_t)(pos - chunk.position);
        log("memcpy chkoff=%u len=%u chklen=%u chkusd=%u chkorg=%u",
            chkoff, len, chunk.length, chunk.used, chunk.orig);
        if (chkoff + len <= chunk.length) // data fits inside chunk
        {
            memcpy(chunk.data + chkoff, data, len);
            
            // If new size is higher than currently used, then it is
            // growsing, update its used size.
            size_t nchksz = chkoff + len;
            if (nchksz >= chunk.used)
            {
                chunk.used = nchksz;
            }
            
            chunk.id++;
        }
        else // data overflows chunk
        {
            throw new Exception("Chunk overflow");
        }
        
        log("chunk=%s", *chunk);
    }
    /// Ditto
    public alias overwrite = replace;
    
    void insert(long, const(void)*, size_t)
    {
        throw new Exception("Not implemented");
    }
    
    void remove(long pos, size_t len)
    {
        throw new Exception("Not implemented");
    }
    
    /// Undo last edit.
    /// Throws: Enforcement.
    /// Returns: Base position of edit, or -1 if no more edits.
    long undo()
    {
        if (historyidx <= 0)
            return -1;
        
        Patch patch = patches[historyidx - 1];
        // WTF did i forget
        //assertion(patch.olddata, "patch.olddata != NULL");
        
        Chunk *chunk = chunks.locate(patch.address);
        
        // WTF if that happens
        assertion(chunk, "chunk != NULL");
        
        log("patch=%s chunk=%s", patch, *chunk);
        
        // TODO: If insert/deletion, don't forget to reshift chunks
        
        // HACK: With overwrites, the last byte could be overwritten
        //       and its size unchanged.
        
        // End chunk: Update sizes if applicable
        if (patch.address + patch.size >= chunk.position + chunk.used &&
            patch.address + patch.size >  chunk.position + chunk.orig &&
            patch.status & PATCH_APPEND)
        {
            chunk.used   -= patch.size;
            logical_size -= patch.size;
        }
        // Apply old data if not truncated by resize
        else if (patch.olddata)
        {
            import core.stdc.string : memcpy;
            ptrdiff_t o = cast(ptrdiff_t)(patch.address - chunk.position);
            memcpy(chunk.data + o, patch.olddata, patch.size);
        }
        
        chunk.id--;
        historyidx--;
        
        return patch.address;
    }
    
    /// Redo last edit.
    /// Throws: Enforcement.
    /// Returns: Base position + length of edit, or -1 if no more edits.
    long redo()
    {
        if (historyidx >= patches.count())
            return -1;
        
        Patch patch = patches[historyidx];
        // WTF did i forget
        //assertion(patch.olddata, "patch.olddata != NULL");
        
        Chunk *chunk = chunks.locate(patch.address);
        
        // WTF if that happens
        assertion(chunk, "chunk != NULL");
        
        log("patch=%s chunk=%s", patch, *chunk);
        
        // TODO: If insert/deletion, don't forget to reshift chunks
        
        // Apply new data
        import core.stdc.string : memcpy;
        ptrdiff_t o = cast(ptrdiff_t)(patch.address - chunk.position);
        
        memcpy(chunk.data + o, patch.newdata, patch.size);
        
        // End chunk: Update sizes if applicable
        if (patch.address + patch.size >= chunk.position + chunk.used &&
            patch.address + patch.size >  chunk.position + chunk.orig &&
            patch.status & PATCH_APPEND)
        {
            chunk.used += patch.size;
            logical_size += patch.size;
        }
        
        chunk.id++;
        historyidx++;
        
        return patch.address + patch.size;
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

/// New empty document
unittest
{
    log("TEST-0001");
    
    scope ChunkDocumentEditor e = new ChunkDocumentEditor();
    
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

/// Emulate editing an existing document
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0002");
    
    static immutable ubyte[] data = [ // 32 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90, 0xcf,
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a,
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36,
        0xe1, 0xe6, 0xd5, 0xb7, 0xad, 0xe3, 0x16, 0x41,
    ];
    enum DLEN = data.length;
    
    ubyte[32] buffer;
    
    scope ChunkDocumentEditor e = new ChunkDocumentEditor().open(new MemoryDocument(data));
    assert(e.edited() == false);
    assert(e.view(0, buffer[])          == data);
    assert(e.view(0, buffer[0..4])      == data[0..4]);
    assert(e.view(DLEN-4, buffer[0..4]) == data[$-4..$]);
    assert(e.currentSize() == data.length);
    
    ubyte[48] buffer2;
    assert(e.view(0,  buffer2[]) == data);
    assert(e.view(16, buffer2[0..16]) == data[16..$]);
    assert(e.currentSize() == data.length);
    
    static immutable string edit0 = "aaaa";
    e.replace(4, edit0.ptr, edit0.length);
    assert(e.edited());
    assert(e.view(4, buffer[0..4]) == edit0);
    assert(e.view(0, buffer[0..4]) == data[0..4]);
    assert(e.view(8, buffer[8..$]) == data[8..$]);
    assert(e.view(2, buffer[0..8]) == data[2..4]~cast(ubyte[])edit0~data[8..10]);
    assert(e.currentSize() == data.length);
    
    assert(e.view(0, buffer2[]) == data[0..4]~cast(ubyte[])edit0~data[8..$]);
    assert(e.currentSize() == data.length);
    assert(e.view(8, buffer2[]) == data[8..$]);
    assert(e.currentSize() == data.length);
    
    static immutable string path = "tmp_doc";
    e.save(path); // throws if it needs to, stopping tests
    
    // Needs to be readable after saving, obviously
    assert(e.view(2, buffer[0..8]) == data[2..4]~cast(ubyte[])edit0~data[8..10]);
    assert(e.currentSize() == data.length);
    
    import std.file : remove;
    remove(path);
}

/// Test undo/redo
unittest
{
    log("TEST-0003");
    
    scope ChunkDocumentEditor e = new ChunkDocumentEditor();
    
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
    try e.redo(); catch (Exception) {} // over
    assert(e.view(0, buf[]) == "ab");
    assert(e.currentSize() == 2);
    e.undo();
    e.undo();
    assert(e.view(0, buf[]) == []);
    assert(e.currentSize() == 0);
    try e.undo(); catch (Exception) {} // over
    assert(e.view(0, buf[]) == []);
    assert(e.currentSize() == 0);
    e.redo();
    e.redo();
    assert(e.view(0, buf[]) == "ab");
    assert(e.currentSize() == 2);
}

/// Test undo/redo with document
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0004");
    
    scope ChunkDocumentEditor e = new ChunkDocumentEditor().open(new MemoryDocument([ 'd', 'd' ]));
    
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
    try e.redo(); catch (Exception) {}
    assert(e.view(0, buf[]) == "ab");
    assert(e.currentSize() == 2);
    
    // Undo all
    e.undo();
    e.undo();
    assert(e.view(0, buf[]) == "dd");
    assert(e.currentSize() == 2);
    
    // Overdoing undo
    try e.undo(); catch (Exception) {}
    assert(e.view(0, buf[]) == "dd");
    assert(e.currentSize() == 2);
    
    // Redo all
    e.redo();
    e.redo();
    assert(e.view(0, buf[]) == "ab");
    assert(e.currentSize() == 2);
}

/// Test undo/redo with larger document
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0005");
    
    // new operator memset's to 0
    enum DOC_SIZE = 8000;
    scope ChunkDocumentEditor e = new ChunkDocumentEditor().open(new MemoryDocument(new ubyte[DOC_SIZE]));
    
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

/// Test appending to a document with undo/redo
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0006");
    
    static immutable ubyte[] data = [ 0xf2, 0x49, 0xe6, 0xea ];
    
    scope ChunkDocumentEditor e = new ChunkDocumentEditor().open(new MemoryDocument(data));
    
    ubyte d = 0xff;
    e.replace(data.length    , &d, ubyte.sizeof);
    e.replace(data.length + 1, &d, ubyte.sizeof);
    e.replace(data.length + 2, &d, ubyte.sizeof);
    e.replace(data.length + 3, &d, ubyte.sizeof);
    
    ubyte[32] buf = void;
    assert(e.view(0, buf[0..8]) == [ 0xf2, 0x49, 0xe6, 0xea, 0xff, 0xff, 0xff, 0xff ]);
}

/// Test reading past edited chunk sizes
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0007");
    
    static immutable ubyte[] data = [ // 32 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90, 0xcf,
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a,
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36,
        0xe1, 0xe6, 0xd5, 0xb7, 0xad, 0xe3, 0x16, 0x41,
    ];
    
    // Chunk size of 16 forces .view() to get more information beyond
    // edited chunk by reading the original doc for the view buffer.
    scope ChunkDocumentEditor e = new ChunkDocumentEditor(0, 16).open(new MemoryDocument(data));
    
    ubyte[32] buf = void;
    assert(e.view(0, buf) == data);
    
    ubyte ff = 0xff;
    e.replace(19, &ff, ubyte.sizeof);
    assert(e.view(0, buf) == [ // 32 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90, 0xcf, // <-+- doc
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a, // <-´
        0x0e, 0xce, 0xb1, 0xff, 0xe4, 0xc6, 0xd4, 0x36, // <-+- chunk
        0xe1, 0xe6, 0xd5, 0xb7, 0xad, 0xe3, 0x16, 0x41, // <-´
    ]);
}

/// Rendering edit chunk before source document
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0008");
    
    static immutable ubyte[] data = [ // 32 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90, 0xcf,
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a,
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36,
        0xe1, 0xe6, 0xd5, 0xb7, 0xad, 0xe3, 0x16, 0x41,
    ];
    
    // Chunk size of 16 forces .view() to get more information beyond
    // edited chunk by reading the original doc for the view buffer.
    scope ChunkDocumentEditor e = new ChunkDocumentEditor(0, 16).open(new MemoryDocument(data));
    
    ubyte[32] buf = void;
    assert(e.view(0, buf) == data);
    
    ubyte ff = 0xff;
    e.replace(3, &ff, ubyte.sizeof);
    assert(e.view(0, buf) == [ // 32 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xff, 0x32, 0xb0, 0x90, 0xcf, // <-+- chunk
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a, // <-´
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36, // <-+- doc
        0xe1, 0xe6, 0xd5, 0xb7, 0xad, 0xe3, 0x16, 0x41, // <-´
    ]);
}

/// Rendering source document before chunk mid-view
///
/// This is an issue when the view function starts with the source
/// document, but doesn't see the edited chunk ahead, skipping it
/// entirely, especially with an offset
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0009");
    
    static immutable ubyte[] data = [ // 32 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90, 0xcf,
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a,
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36,
        0xe1, 0xe6, 0xd5, 0xb7, 0xad, 0xe3, 0x16, 0x41,
    ];
    
    scope ChunkDocumentEditor e = new ChunkDocumentEditor(0, 8).open(new MemoryDocument(data));
    
    ubyte[32] buf = void;
    assert(e.view(16, buf[0..16]) == data[16..$]);
    
    ubyte ff = 0xff;
    e.replace(cast(int)data.length-1, &ff, ubyte.sizeof);
    
    assert(e.view(16,  buf[0..16]) == [
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36, // <- doc
        0xe1, 0xe6, 0xd5, 0xb7, 0xad, 0xe3, 0x16, 0xff, // <- chunk
    ]);
}

/// Append data to end of chunk with a source document
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0010");
    
    static immutable ubyte[] data = [ // 28 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90, 0xcf,
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a,
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36,
        0xe1, 0xe6, 0xd5, 0xb7, 
    ];
    
    scope ChunkDocumentEditor e = new ChunkDocumentEditor(0, 16).open(new MemoryDocument(data));
    
    ubyte[32] buf = void;
    assert(e.view(16, buf[0..16]) == data[16..$]);
    
    ubyte ff = 0xff;
    e.replace(cast(int)data.length, &ff, ubyte.sizeof);
    
    assert(e.view(0,  buf) == [ // 29 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90, 0xcf,
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a,
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36,
        0xe1, 0xe6, 0xd5, 0xb7, 0xff
    ]);
    assert(e.view(8,  buf) == [
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a,
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36,
        0xe1, 0xe6, 0xd5, 0xb7, 0xff
    ]);
    assert(e.view(16,  buf) == [
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36,
        0xe1, 0xe6, 0xd5, 0xb7, 0xff
    ]);
    assert(e.view(24,  buf) == [
        0xe1, 0xe6, 0xd5, 0xb7, 0xff
    ]);
}

// TODO: TEST-0011 (test disabled until relevant)
//       Editor can only edit single bytes right now...
//       If you enable this test, it might pass and silently fail
/// Replace data across two chunks
/*unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0011");
    
    static immutable ubyte[] data = [ // 16 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90, 0xcf,
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a,
    ];
    
    scope ChunkDocumentEditor e = new ChunkDocumentEditor(0, 8).attach(new MemoryDocument(data));
    
    ubyte[16] buffer;
    
    string s = "hi";
    e.replace(7, s.ptr, s.length);
    assert(e.view(0, buffer) == [ // 16 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90,  'h', // <- chunk 0
         'i', 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a, // <- chunk 1
    ]);
}*/

// TODO: TEST-0012 (test disabled until relevant)
//       Editor can only edit single bytes right now...
/// Append to a chunk so much it overflows to another chunk
/*unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0012");
    
    static immutable ubyte[] data = [ // 7 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90,
    ];
    
    scope ChunkDocumentEditor e = new ChunkDocumentEditor(0, 8).attach(new MemoryDocument(data));
    
    ubyte[16] buffer;
    
    string s = "hello";
    e.replace(6, s.ptr, s.length);
    assert(e.view(0, buffer) == [ // 16 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0,  'h',  'e', // <- chunk 0
         'l',  'l',  'l',  'o'                          // <- chunk 1
    ]);
}*/

/// Common tests
unittest { editorTests!ChunkDocumentEditor(); }