/// Editor backend implemention using a Piece List to ease insertion and
/// deletion operations.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module backend.pieces;

import logger;
import backend.base : IDocumentEditor;
import document.base : IDocument;
import std.container.array : Array;
import std.container.rbtree : RedBlackTree;
import std.exception : enforce;

// Other interesting sources:
// - temp: Temporary file if an edit is too large to fit in memory (past a threshold)
// - file: Insert file
// - pattern: Insert pattern (e.g., 1000x 0xff) - saves memory
private
enum Source
{
    document,   /// Original document
    buffer,     /// In-memory buffer
}

private
struct BufferPiece
{
    const(void) *data;
}

private
struct Piece
{
    Source source;
    long position;
    long size;
    
    union
    {
        BufferPiece buffer;
    }
    
    // Make a new buffer piece
    // This does not copy any actually data from the pointer, just the fields
    static Piece makebuffer(long position, const(void) *data, size_t size)
    {
        Piece piece     = void;
        piece.source    = Source.buffer;
        piece.position  = position;
        piece.size      = size;
        piece.buffer.data = data;
        return piece;
    }
}

// For RedBlackTree
private
struct IndexedPiece
{
    /// Cumulative size of ALL previous pieces to help indexing.
    ///
    /// If we have pieces (pos=0,size=15),(pos=15,size=30),(pos=45,size=5),
    /// then they'd have 15, 45, and 50 cumulative sizes.
    long cumulative;
    Piece piece;
}

// Used in Undo/Redo operations
private
struct History
{
    long start, end;
}

/// Document editor implementing a Piece List with RedBlackTree for indexing.
class PieceDocumentEditor : IDocumentEditor
{
    /// New document editor with a new empty buffer.
    this(int flags = 0)
    {
        import os.mem : syspagesize;
        pagesize = syspagesize();
    }
    
    /// Open document.
    /// Params: doc = IDocument-based document.
    /// Returns: Instance of this.
    typeof(this) open(IDocument doc)
    {
        basedoc = doc;
        snapshots.clear();
        logical_size = doc.size();
        IndexedPiece indexed = IndexedPiece(
            logical_size,
            Piece(Source.document, 0, logical_size)
        );
        Tree snapshot = new Tree(indexed);
        snapshots.insert(snapshot);
        snapshot_index++;
        return this;
    }
    
    long size()
    {
        return logical_size;
    }
    
    void save(string target)
    {
        throw new Exception(ENOTIMPL);
    }
    
    ubyte[] view(long position, void* buffer, size_t size)
    {
        return view(position, (cast(ubyte*)buffer)[0..size]);
    }
    
    ubyte[] view(long position, ubyte[] buffer)
    {
        // If new buffer without any edits.
        if (snapshots.length == 0)
            return [];
        
        /*
        View function for range [P, P + length):

        1. Traverse the tree comparing P against cumulative sizes to find the
           first piece that overlaps
        2. Iterate forward through pieces, accumulating their content into the
           view buffer
        3. Stop when you've covered the entire range
        */
        
        log("Si=%u Sc=%u Hi=%u Hc=%u", snapshot_index, snapshots.length, history_index, history.length);
        
        size_t bi; /// buffer index (for slicing)
        Tree indexes = snapshots[snapshot_index - 1];
        //IndexedPiece previous;
        long previous;
        foreach (index; indexes[])
        {
            if (bi >= buffer.length)
            {
                // TODO: Consider cutting to buffer length
                break;
            }
            
            // Need piece where position fits in cumulative
            if (index.cumulative <= position)
            {
                previous = index.cumulative;
                continue;
            }
            
            long lpos = position + bi; // logical position
            size_t want = buffer.length - bi; // need to fill
            
            import std.algorithm.comparison : min, max;
            
            long piece_start = previous;
            long piece_end   = index.cumulative;
            long read_start  = max(position, piece_start) - piece_start;
            long read_end    = min(position + buffer.length, piece_end) - piece_start;
            long read_length = read_end - read_start;
            
            size_t rdlen = cast(size_t)read_length;
            
            log("PIECE lpos=%d want=%u Ps=%d Pe=%d Rs=%d Re=%d Rl=%d P=%s r=%u",
                lpos, want,
                piece_start, piece_end,
                read_start, read_end, read_length,
                index,
                rdlen);
            
            final switch (index.piece.source) {
            case Source.document:
                assert(basedoc); // need document
                size_t len = basedoc.readAt(index.piece.position + read_start, buffer[bi..bi+rdlen]).length;
                bi += len;
                break;
            case Source.buffer:
                assert(add_buffer); // needs to be init
                assert(add_size);   // need data
                import core.stdc.string : memcpy;
                memcpy(buffer.ptr + bi, index.piece.buffer.data + read_start, rdlen);
                bi += rdlen;
                break;
            }
            
            previous = index.cumulative;
        }
        
        return buffer[0..bi];
    }
    
    bool edited()
    {
        return history_index != history_saved;
    }
    
    void replace(long position, const(void)* data, size_t len)
    {
        // Insert a new piece by replacing found piece(s)
        // Cheaping out with an Deletion+Insert is just asking for trouble
        // if there are two snapshots from one operation.
        throw new Exception(ENOTIMPL);
    }
    
    void insert(long position, const(void)* data, size_t len)
    {
        enforce(position <= logical_size, "position <= logical_size (past EOF)");
        enforce(data, "data != NULL");
        enforce(len,  "len > 0");
        
        // Make piece
        void *buf = bufferAdd( data, len );
        Piece piece = Piece.makebuffer( position, buf, len );
        
        // Add to undo stack
        if (history_index < history.length) // replace
            history[history_index] = History(position, position + len);
        else // append
            history.insert( History(position, position + len) );
        history_index++;
        
        // new buffer with no edits yet
        if (snapshots.length == 0)
        {
            // First edit with no document needs to be at position 0.
            enforce(position == 0, "assert: insert(position==0)");
            
            // Start new snapshot series
            log("FIRST IndexedPiece=%s", IndexedPiece( len, piece ));
            snapshots.insert( new Tree( IndexedPiece( len, piece ) ) );
            snapshot_index++;
            
            logical_size = len;
            return;
        }
        
        // Optimization: Insert at SOF, only middle (new) and right pieces affected
        if (position == 0)
        {
            Tree oldtree = snapshots[snapshot_index - 1];
            Tree newtree = new Tree();
            
            // Insert starting piece
            newtree.insert(IndexedPiece(len, piece));
            // Insert other pieces while adjusting their cumulative size
            foreach (indexed; oldtree)
                newtree.insert(IndexedPiece(indexed.cumulative + len, indexed.piece));
            
            logical_size += len;
            
            snapshots.insert( newtree );
            snapshot_index++;
            return;
        }
        // Optimization: Insert at EOF, middle (new) piece needed
        else if (position == logical_size)
        {
            Tree oldtree = snapshots[snapshot_index - 1];
            Tree newtree = new Tree();
            
            logical_size += len;
            
            // Insert other pieces, need to adjust cumulative size
            foreach (indexed; oldtree)
                newtree.insert(IndexedPiece(indexed.cumulative, indexed.piece));
            
            // Insert at end, no need to update nodes
            newtree.insert(IndexedPiece(logical_size, piece));
            
            snapshots.insert( newtree );
            snapshot_index++;
            return;
        }
        
        /*
        Insertion at document position P with N bytes:

        1. Traverse the tree comparing P against cumulative sizes to find
           which piece contains position P
        2. Split that piece if necessary (the piece might span before and after P)
        3. Insert your new piece (with the added content) into the tree
        4. Rebuild/update cumulative sizes for affected nodes
        */
        Tree oldtree = snapshots[snapshot_index - 1];
        Tree newtree = new Tree();
        IndexedPiece previous;
        foreach (index; oldtree)
        {
            if (index.cumulative < position) // add as-is
            {
                previous = index;
                newtree.insert( index );
                continue;
            }
            
            // 2. Get the offset that might land within a piece
            long piece_offset = position - previous.cumulative;
            
            // 3. Insert piece, either if:
            //    (a) It needs splitting a piece or;
            //    (b) Needs to be inserted at the end of one.
            if (piece_offset > 0 && piece_offset < index.piece.size) // insert left, middle, right pieces
            {
                // Adjust found piece... By cutting it into LEFT and RIGHT pieces
                long right_len = index.piece.size - piece_offset;
                Piece left = void, right = void;
                // left:  Piece(found.piece.source, found.piece.offset, piece_offset)
                // right: Piece(found.piece.source, found.piece.offset + piece_offset, found.piece.size - piece_offset)
                final switch (index.piece.source) {
                case Source.document:
                    left  = Piece(Source.document, index.piece.position, piece_offset);
                    right = Piece(Source.document, index.piece.position + piece_offset, right_len);
                    break;
                case Source.buffer:
                    left  = Piece.makebuffer(index.piece.position, index.piece.buffer.data, piece_offset);
                    right = Piece.makebuffer(index.piece.position + piece_offset, index.piece.buffer.data + piece_offset, right_len);
                }
                
                // Now, we need to insert left, new, and right pieces...
                long cumulative = previous.cumulative + piece_offset;
                newtree.insert([
                    IndexedPiece(cumulative, left),
                    IndexedPiece(cumulative + len, piece),
                    IndexedPiece(cumulative + len + right_len, right)
                ]);
            }
            else // Insert at boundary of pieces
            {
                newtree.insert(IndexedPiece(previous.cumulative + len, piece));
            }
        }
        
        logical_size += len;
        
        if (snapshot_index < snapshots.length) // replace
            snapshots[snapshot_index] = newtree;
        else // append
            snapshots.insert( newtree );
        snapshot_index++;
    }
    
    /// Remove data foward from a position for a length of bytes.
    /// Throws: Exception.
    /// Params:
    ///     position = Base position.
    ///     len = Number of bytes to delete.
    void remove(long position, size_t len)
    {
        throw new Exception(ENOTIMPL);
    }
    
    /// Undo last modification.
    /// Returns: Suggested position of the cursor for this modification.
    long undo()
    {
        if (history_index <= 0)
            return -1;
        
        snapshot_index--;
        return history[ --history_index ].start;
    }
    
    /// Redo last undone modification.
    /// Returns: Suggested position of the cursor for this modification. (Position+Length)
    long redo()
    {
        if (history_index >= history.length)
            return -1;
        
        snapshot_index++;
        return history[ --history_index ].end;
    }
    
private:
    /// Base document to apply edits on.
    ///
    /// Nullable.
    IDocument basedoc;
    
    /// Logical size of our document.
    long logical_size;
    
    static immutable string ENOTIMPL = "Not implemented";
    
    //
    // Undo-Redo stack
    //
    
    /// History of pieces inserted.
    Array!History history;
    /// History index used when performing an undo or redo.
    size_t history_index;
    /// Index used when saving. This is set to history_index, and is used
    /// to know when the document was edited.
    size_t history_saved;
    
    //
    // Piece list
    //
    
    /// Tree format
    alias Tree = RedBlackTree!(IndexedPiece, "a.cumulative < b.cumulative");
    /// Snapshot system
    ///
    /// When an operation is performed (overwrite, insert, delete), a new
    /// snapshot is created, for easier undo/redo operations.
    ///
    /// NOTE: Snapshot performance.
    ///       
    ///       Due to RedBlackTree's usage of [private struct] Range(T).front()
    ///       (used in opSlice, lowerBounds, upperBounds, etc.), all elements
    ///       are passed *by value*, so it is not possible to modify these
    ///       elements as-is (using foreach + ref) without removing+insertion.
    ///       Which, could mean a shallow dupe (O(n)), remove (O(log n)), and
    ///       insert (O(log n)) possibly all elements -> Might be O(n²).
    ///       
    ///       So, each new snapshots are created from scratch, and this rebuild
    ///       should be around O(n log n), and possibly better.
    ///       
    ///       Other optimizations (deltas, array of pointers, etc.) could be
    ///       explored later, but it's more important to have something that
    ///       works.
    Array!Tree snapshots;
    /// Current snapshot index. Not synced with historical index, because
    /// snapshots can contain a document piece without edits, which counts
    /// towards the total amount of snapshots.
    size_t snapshot_index;
    
    //
    // Add buffer
    //
    
    // 
    ubyte[] add_buffer;
    // Size of add buffer
    size_t add_size;
    // 
    size_t pagesize;
    
    //
    void* bufferAdd(const(void) *data, size_t len)
    {
        if (add_buffer.length == 0)
        {
            add_buffer.length = pagesize;
        }
        
        if (add_size + len >= add_buffer.length)
        {
            add_buffer.length += pagesize;
        }
        
        import core.stdc.string : memcpy;
        void *ptr = add_buffer.ptr + add_size;
        memcpy(ptr, data, len);
        
        add_size += len;
        
        return ptr;
    }
}

/// New empty document
unittest
{
    log("TEST-0001");
    
    scope PieceDocumentEditor e = new PieceDocumentEditor();
    
    ubyte[32] buffer;
    
    log("Initial read");
    assert(e.edited() == false);
    assert(e.size() == 0);
    assert(e.view(0, buffer) == []);
    
    string data = "hi";
    e.insert(0, data.ptr, data.length);
    assert(e.edited());
    assert(e.size() == 2);
    assert(e.view(0, buffer) == data);
}

/// with document
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0002");
    
    static immutable ubyte[] data  = cast(immutable(ubyte)[])"hello";
    static immutable ubyte[] data1 = cast(immutable(ubyte)[])"hi, ";
    
    scope PieceDocumentEditor e = new PieceDocumentEditor().open(new MemoryDocument(data));
    
    ubyte[32] buffer;
    log("Initial read");
    assert(e.edited() == false);
    assert(e.size() == data.length);
    assert(e.view(0, buffer) == data);
    
    e.insert(0, data1.ptr, data1.length);
    assert(e.edited());
    assert(e.size() == data.length + data1.length);
    assert(e.view(0, buffer) == data1~data); // "hi, hello"
}

/// Emulate editing an existing document
/*
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
    
    scope MemoryDocument doc = new MemoryDocument(data);
    
    scope PieceDocumentEditor e = new PieceDocumentEditor().attach(doc);
    assert(e.edited() == false);
    assert(e.view(0, buffer[])          == data);
    assert(e.view(0, buffer[0..4])      == data[0..4]);
    assert(e.view(DLEN-4, buffer[0..4]) == data[$-4..$]);
    assert(e.size() == data.length);
    
    ubyte[48] buffer2;
    assert(e.view(0,  buffer2[]) == data);
    assert(e.view(16, buffer2[0..16]) == data[16..$]);
    assert(e.size() == data.length);
    
    static immutable string edit0 = "aaaa";
    e.replace(4, edit0.ptr, edit0.length);
    assert(e.edited());
    assert(e.view(4, buffer[0..4]) == edit0);
    assert(e.view(0, buffer[0..4]) == data[0..4]);
    assert(e.view(8, buffer[8..$]) == data[8..$]);
    assert(e.view(2, buffer[0..8]) == data[2..4]~cast(ubyte[])edit0~data[8..10]);
    assert(e.size() == data.length);
    
    assert(e.view(0, buffer2[]) == data[0..4]~cast(ubyte[])edit0~data[8..$]);
    assert(e.size() == data.length);
    assert(e.view(8, buffer2[]) == data[8..$]);
    assert(e.size() == data.length);
    
    static immutable string path = "tmp_doc";
    e.save(path); // throws if it needs to, stopping tests
    
    // Needs to be readable after saving, obviously
    assert(e.view(2, buffer[0..8]) == data[2..4]~cast(ubyte[])edit0~data[8..10]);
    assert(e.size() == data.length);
    
    import std.file : remove;
    remove(path);
}

/// Test undo/redo
unittest
{
    log("TEST-0003");
    
    scope PieceDocumentEditor e = new PieceDocumentEditor();
    
    char a = 'a';
    e.replace(0, &a, char.sizeof);
    char b = 'b';
    e.replace(1, &b, char.sizeof);
    
    ubyte[4] buf = void;
    assert(e.view(0, buf[]) == "ab");
    assert(e.size() == 2);
    
    e.undo();
    assert(e.view(0, buf[]) == "a");
    assert(e.size() == 1);
    e.redo();
    assert(e.view(0, buf[]) == "ab");
    assert(e.size() == 2);
    try e.redo(); catch (Exception) {} // over
    assert(e.view(0, buf[]) == "ab");
    assert(e.size() == 2);
    e.undo();
    e.undo();
    assert(e.view(0, buf[]) == []);
    assert(e.size() == 0);
    try e.undo(); catch (Exception) {} // over
    assert(e.view(0, buf[]) == []);
    assert(e.size() == 0);
    e.redo();
    e.redo();
    assert(e.view(0, buf[]) == "ab");
    assert(e.size() == 2);
}

/// Test undo/redo with document
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0004");
    
    scope MemoryDocument doc = new MemoryDocument([ 'd', 'd' ]);
    scope PieceDocumentEditor e = new PieceDocumentEditor().attach(doc);
    
    ubyte[4] buf = void;
    assert(e.view(0, buf[]) == "dd");
    assert(e.size() == 2);
    
    char a = 'a';
    e.replace(0, &a, char.sizeof);
    char b = 'b';
    e.replace(1, &b, char.sizeof);
    
    assert(e.view(0, buf[]) == "ab");
    assert(e.size() == 2);
    
    // Undo and redo once
    e.undo();
    assert(e.view(0, buf[]) == "ad");
    assert(e.size() == 2);
    e.redo();
    assert(e.view(0, buf[]) == "ab");
    assert(e.size() == 2);
    
    // Overdoing redo
    try e.redo(); catch (Exception) {}
    assert(e.view(0, buf[]) == "ab");
    assert(e.size() == 2);
    
    // Undo all
    e.undo();
    e.undo();
    assert(e.view(0, buf[]) == "dd");
    assert(e.size() == 2);
    
    // Overdoing undo
    try e.undo(); catch (Exception) {}
    assert(e.view(0, buf[]) == "dd");
    assert(e.size() == 2);
    
    // Redo all
    e.redo();
    e.redo();
    assert(e.view(0, buf[]) == "ab");
    assert(e.size() == 2);
}

/// Test undo/redo with larger document
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0005");
    
    // new operator memset's to 0
    enum DOC_SIZE = 8000;
    scope PieceDocumentEditor e = new PieceDocumentEditor().attach(new MemoryDocument(new ubyte[DOC_SIZE]));
    
    ubyte[32] buf = void;
    assert(e.view(40, buf[0..4]) == [ 0, 0, 0, 0 ]);
    assert(e.size() == 8000);
    
    char a = 0xff;
    e.replace(41, &a, char.sizeof);
    e.replace(42, &a, char.sizeof);
    assert(e.view(40, buf[0..4]) == [ 0, 0xff, 0xff, 0 ]);
    assert(e.size() == 8000);
    
    e.undo();
    assert(e.view(40, buf[0..4]) == [ 0, 0xff, 0, 0 ]);
    assert(e.size() == 8000);
    
    e.undo();
    assert(e.view(40, buf[0..4]) == [ 0, 0, 0, 0 ]);
    assert(e.size() == 8000);
    
    e.replace(41, &a, char.sizeof);
    e.replace(42, &a, char.sizeof);
    e.replace(43, &a, char.sizeof);
    e.replace(44, &a, char.sizeof);
    e.undo();
    e.undo();
    e.undo();
    e.undo();
    assert(e.view(40, buf[0..8]) == [ 0, 0, 0, 0, 0, 0, 0, 0 ]);
    assert(e.size() == 8000);
}

/// Test appending to a document with undo/redo
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0006");
    
    static immutable ubyte[] data = [ 0xf2, 0x49, 0xe6, 0xea ];
    
    scope PieceDocumentEditor e = new PieceDocumentEditor().attach(new MemoryDocument(data));
    
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
    scope PieceDocumentEditor e = new PieceDocumentEditor().attach(new MemoryDocument(data));
    
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
    scope PieceDocumentEditor e = new PieceDocumentEditor().attach(new MemoryDocument(data));
    
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
    
    scope PieceDocumentEditor e = new PieceDocumentEditor().attach(new MemoryDocument(data));
    
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
    
    scope PieceDocumentEditor e = new PieceDocumentEditor().attach(new MemoryDocument(data));
    
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
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0011");
    
    static immutable ubyte[] data = [ // 16 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90, 0xcf,
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a,
    ];
    
    scope PieceDocumentEditor e = new PieceDocumentEditor().attach(new MemoryDocument(data));
    
    ubyte[16] buffer;
    
    string s = "hi";
    e.replace(7, s.ptr, s.length);
    assert(e.view(0, buffer) == [ // 16 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90,  'h', // <- chunk 0
         'i', 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a, // <- chunk 1
    ]);
}

// TODO: TEST-0012 (test disabled until relevant)
//       Editor can only edit single bytes right now...
/// Append to a chunk so much it overflows to another chunk
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0012");
    
    static immutable ubyte[] data = [ // 7 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90,
    ];
    
    scope PieceDocumentEditor e = new PieceDocumentEditor().attach(new MemoryDocument(data));
    
    ubyte[16] buffer;
    
    string s = "hello";
    e.replace(6, s.ptr, s.length);
    assert(e.view(0, buffer) == [ // 16 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0,  'h',  'e', // <- chunk 0
         'l',  'l',  'l',  'o'                          // <- chunk 1
    ]);
}*/

/// Common tests
//unittest { editorTests!ChunkDocumentEditor(); }