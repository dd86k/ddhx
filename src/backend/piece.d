/// Editor backend implemention using a Piece List to ease insertion and
/// deletion operations.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module backend.piece;

import std.algorithm.comparison : min, max;
import std.container.array : Array;
import std.container.rbtree : RedBlackTree;
import backend.base : IDocumentEditor;
import document.base : IDocument;
import platform : assertion;
import logger;

// TODO: Piece coalescing
//       Could be useful to save the last piece for each operation.
//       So it could be "extended" for future operations of each category.
//       Invalidated if operation changes.
// TODO: Snapshot commit (idea to explore later)
//       Right now, the idea is to do one edit, and save the snapshot.
//       However, what would we do if we wanted to do multiple operations
//       as one (e.g., a patch)?
//       Need to figure out RBTree cloning. For chunk, maybe save number
//       of history action (e.g., 3 undos for this patch).

// Other interesting sources:
// - temp: Temporary file if an edit is too large to fit in memory (past a threshold)
private
enum Source
{
    source,     /// Original source document
    buffer,     /// In-memory buffer
    pattern,    /// Repeated pattern
    document,   /// File (or other?) document
}

private
struct BufferPiece
{
    /// Pointer to data.
    const(void) *data;
    /// Size of the data inserted into the buffer. Must not change.
    size_t ogsize;
    /// Amount skipped
    size_t skip;
}

// Same as piece, but other meaning
private
struct PatternPiece
{
    /// Pointer to data.
    const(void) *data;
    /// Size of the data inserted into the buffer. Must not change.
    size_t ogsize;
    /// Amount skipped
    size_t skip;
}

private
struct DocumentPiece
{
    IDocument doc;
}

private
struct Piece
{
    Source source;  /// Piece source. (Document, buffer, etc.)
    long position;  /// Original position.
    long size;      /// Piece size
    
    union
    {
        BufferPiece buffer;
        PatternPiece pattern;
        //DocumentPiece doc;
    }
    
    // Make a new buffer piece
    // This does not copy any actually data from the pointer, just the fields
    static Piece makebuffer(long position, const(void) *data, size_t size, size_t skip = 0)
    {
        Piece piece     = void;
        piece.source    = Source.buffer;
        piece.position  = position;
        piece.size      = size;
        piece.buffer.data   = data;
        piece.buffer.ogsize = size;
        piece.buffer.skip   = skip;
        return piece;
    }
    
    // Make a new pattern piece, ditto
    static Piece makepattern(long position, long len, const(void) *data, size_t size, size_t skip = 0)
    {
        Piece piece     = void;
        piece.source    = Source.pattern;
        piece.position  = position;
        piece.size      = len;
        piece.pattern.data   = data;
        piece.pattern.ogsize = size;
        piece.pattern.skip   = skip;
        return piece;
    }
    
    // Make a new doc piece
    /*static Piece makefile(long position, long len, IDocument doc)
    {
        Piece piece     = void;
        piece.source    = Source.pattern;
        piece.position  = position;
        piece.size      = len;
        piece.doc.doc   = doc;
        return piece;
    }*/
}

// For RedBlackTree
private
struct IndexedPiece
{
    /// Cumulative size of ALL previous pieces to help indexing.
    ///
    /// If we have pieces (pos=0,size=15),(pos=15,size=30),(pos=45,size=5),
    /// then they'd have 15, 45, and 50 cumulative sizes respectfully.
    long cumulative;
    Piece piece;
}

/// Tree format
private alias Tree = RedBlackTree!(IndexedPiece, "a.cumulative < b.cumulative");
/// Represents a snapshot of pieces
private
struct Snapshot
{
    /// Start of affected region.
    long start;
    /// End of affected region.
    long end;
    /// Effective logical size of the snapshot.
    long logical_size;
    /// Indexed pieces list.
    Tree pieces;
}

/// Document editor implementing a Piece List with RedBlackTree for indexing.
class PieceDocumentEditor : IDocumentEditor
{
    /// New document editor with a new empty buffer.
    this()
    {
        import os.mem : syspagesize;
        pagesize = syspagesize();
    }
    
    /// Open document.
    /// Params: doc = IDocument-based document.
    /// Returns: Editor instance.
    typeof(this) open(IDocument doc)
    {
        basedoc = doc;
        long docsize = doc.size();
        
        snapshots.clear();
        snapshot_index = 0;
        
        Snapshot snap = Snapshot(0, docsize, docsize,
            new Tree(
                IndexedPiece(
                    docsize,
                    Piece(Source.source, 0, docsize)
                )
            )
        );
        
        addSnapshot(snap);
        return this;
    }
    
    /// Total size of document in bytes with edits.
    /// Returns: Size of current document.
    long size()
    {
        if (snapshots.length == 0)
            return 0;
        return currentSnapshot().logical_size;
    }
    
    void markSaved()
    {
        snapshot_saved = snapshot_index;
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
        // HACK: some edge case bullshit
        if (snapshot_index == 0 && basedoc is null)
            return [];
        
        log("VIEW Si=%u Sc=%u", snapshot_index, snapshots.length);
        
        size_t bi; /// buffer index (for slicing)
        Tree indexes = currentSnapshot().pieces;
        foreach (index; indexes.upperBound(IndexedPiece(position)))
        {
            // View buffer is full
            if (bi >= buffer.length)
                break;
            
            long lpos = position + bi; // logical position
            
            // Calculate piece bounds in document coordinates
            long piece_start = index.cumulative - index.piece.size;
            long piece_end = index.cumulative;
            
            // Skip pieces before our view position
            //if (piece_end <= doc_pos)
            if (piece_end <= lpos)
                continue;
            
            // Calculate how much to read from this piece
            long piece_offset = max(0, lpos - piece_start); // clamp to zero
            long available = piece_end - max(lpos, piece_start);
            //long to_read = min(available, remaining);
            long to_read = min(available, buffer.length - bi);
            
            // Read from the piece
            final switch (index.piece.source) {
            case Source.source:
                basedoc.readAt(index.piece.position + piece_offset, buffer[bi..bi+to_read]);
                break;
            case Source.buffer:
                import core.stdc.string : memcpy;
                memcpy(buffer.ptr + bi, 
                    index.piece.buffer.data + index.piece.buffer.skip + piece_offset,
                    to_read);
                break;
            case Source.pattern:
                import core.stdc.string : memcpy, memset;
                if (index.piece.pattern.ogsize == 1) // One byte pattern
                {
                    log("PATTERN SINGLE read=%d", to_read);
                    memset(buffer.ptr + bi,
                        *cast(ubyte*)index.piece.pattern.data,
                        to_read);
                }
                else // Multi-byte pattern
                {
                    size_t psize = index.piece.pattern.ogsize; // pattern size
                    log("PATTERN MULTI read=%d bi=%u", to_read, bi);
                    // Calculate starting offset within the pattern cycle
                    size_t pattern_offset = (index.piece.pattern.skip + piece_offset) % psize;
                    
                    long p;
                    size_t o = bi;
                    while (p < to_read)
                    {
                        // How much we can copy from current position in pattern
                        size_t available_in_pattern = psize - pattern_offset;
                        size_t w = min(to_read - p, available_in_pattern);
                        
                        memcpy(
                            buffer.ptr + o,
                            index.piece.pattern.data + pattern_offset,
                            w);
                        
                        o += w;
                        p += w;
                        // Align after first copy due to skip
                        pattern_offset = 0;
                    }
                }
                break;
            case Source.document:
                //index.piece.doc.doc.readAt(index.piece.position + piece_offset, buffer[bi..bi+to_read]);
                break;
            }
            
            bi += to_read;
        }
        
        // Soft assert to be able to catch details
        log("bl=%u bi=%u", buffer.length, bi);
        assertion(bi <= buffer.length, "bi <= buffer.length");
        return buffer[0..bi];
    }
    
    bool edited()
    {
        // Right now, just opening a document doesn't mean it has edits.
        bool e = snapshot_index != snapshot_saved;
        return basedoc ? e && snapshot_index > 1 : e;
    }
    
    /// Replace with new data at this position.
    /// Params:
    ///     position = Base position.
    ///     data = Pointer to data.
    ///     len = Length of data.
    void replace(long position, const(void)* data, size_t len)
    in (position >= 0, "position >= 0")
    in (data != null, "data != NULL")
    in (len > 0,  "len > 0")
    {
        log("REPLACE pos=%d len=%u data=%s", position, len, data);
        
        // Make piece
        Piece piece = Piece.makebuffer( position, bufferAdd(data, len), len );
        
        replacePiece(position, piece);
    }
    
    /// Insert new data at this position
    /// Params:
    ///     position = Base position.
    ///     data = Data pointer.
    ///     len = Length of data.
    void insert(long position, const(void)* data, size_t len)
    in (position >= 0, "position >= 0")
    in (data != null, "data != NULL")
    in (len > 0, "len > 0")
    {
        log("INSERT pos=%d len=%u data=%s", position, len, data);
        
        // Make piece
        Piece piece = Piece.makebuffer( position, bufferAdd(data, len), len );
        
        insertPiece(position, piece);
    }
    
    /// Remove data foward from a position for a length of bytes.
    /// Throws: Exception.
    /// Params:
    ///     position = Base position.
    ///     len = Number of bytes to delete.
    void remove(long position, size_t len)
    in (position >= 0, "position >= 0")
    in (len > 0, "len > 0")
    {
        log("REMOVE pos=%d len=%u", position, len);
        
        // Nothing to remove if there is nothing to remove!
        if (snapshots.length == 0)
            return;
        
        Snapshot cur_snap = currentSnapshot();
        
        // Editors should avoid deleting nothing at EOF...
        assertion(position < cur_snap.logical_size, "position < cur_snap.logical_size");
        
        // Clamp removal to actual document size
        long removed = min(len, cur_snap.logical_size - position);
        // End position of removal
        long end = position + removed;
        
        Snapshot new_snap = Snapshot(
            position, 
            end, 
            cur_snap.logical_size - removed,
            new Tree()
        );
        
        long old_cumulative;  // Track position in OLD snapshot
        long new_cumulative;  // Track position in NEW snapshot
        foreach (index; cur_snap.pieces)
        {
            long piece_start = old_cumulative;
            long piece_end   = index.cumulative;
            
            // Pieces that overlap with removal region
            if (piece_start < end && piece_end > position)
            {
                // Keep left portion (before removal starts)
                if (piece_start < position)
                {
                    long keep = position - old_cumulative;
                    Piece left = index.piece;
                    left.size = keep;
                    new_cumulative += keep;
                    new_snap.pieces.insert(IndexedPiece(new_cumulative, left));
                }
                
                // Keep right portion (after removal ends)
                if (piece_end > end)
                {
                    long skip = end - old_cumulative;
                    long keep = piece_end - end;
                    Piece right = trimPiece(index.piece, skip, keep);
                    new_cumulative += keep;
                    new_snap.pieces.insert(IndexedPiece(new_cumulative, right));
                }
                
                // Middle portion gets deleted (not inserted)
            }
            else if (piece_end <= position)
            {
                // Pieces completely before removal - keep as-is
                new_snap.pieces.insert(index);
                new_cumulative = index.cumulative;
            }
            else  // piece_start >= end
            {
                // Pieces completely after removal - use NEW cumulative
                new_cumulative += index.piece.size;
                new_snap.pieces.insert(IndexedPiece(new_cumulative, index.piece));
            }
            
            old_cumulative = index.cumulative;
        }
        
        addSnapshot(new_snap);
    }
    
    void patternReplace(long position, long len, const(void) *data, size_t datlen)
    in (position >= 0, "position >= 0")
    in (len > 0, "len > 0")
    in (data != null, "data != NULL")
    in (datlen > 0, "datlen > 0")
    {
        log("REPLACE PATTERN pos=%d len=%d data=%s datlen=%u", position, len, data, datlen);
        
        // Make piece
        Piece piece = Piece.makepattern( position, len, bufferAdd(data, datlen), datlen );
        
        replacePiece(position, piece);
    }
    
    void patternInsert(long position, long len, const(void) *data, size_t datlen)
    in (position >= 0, "position >= 0")
    in (len > 0, "len > 0")
    in (data != null, "data != NULL")
    in (datlen > 0, "datlen > 0")
    {
        log("INSERT PATTERN pos=%d len=%d data=%s datlen=%u", position, len, data, datlen);
        
        // Make piece
        Piece piece = Piece.makepattern( position, len, bufferAdd(data, datlen), datlen );
        
        insertPiece(position, piece);
    }
    
    void fileReplace(long position, IDocument doc)
    in (position >= 0, "position >= 0")
    in (doc !is null, "doc !is null")
    {
        log("REPLACE FILE pos=%d", position);
        
        throw new Exception("TODO");
        
        // Make piece
        //Piece piece = Piece.makefile( position, doc.size(), doc );
        //replacePiece(position, piece);
    }
    
    void fileInsert(long position, IDocument doc)
    in (position >= 0, "position >= 0")
    in (doc !is null, "doc !is null")
    {
        log("INSERT FILE pos=%d", position);
        
        throw new Exception("TODO");
        
        // Make piece
        //Piece piece = Piece.makefile( position, doc.size(), doc );
        //insertPiece(position, piece);
    }
    
    /// Undo last modification.
    /// Returns: Suggested position of the cursor for this modification.
    long undo()
    {
        if (basedoc)
        {
            // First snapshot is basedoc, unless we allow undoing that.
            if (snapshot_index <= 1)
                return -1;
        }
        else
        {
            if (snapshot_index <= 0)
                return -1;
        }
        
        Snapshot snapshot = snapshots[ --snapshot_index ];
        
        return snapshot.start;
    }
    
    /// Redo last undone modification.
    /// Returns: Suggested position of the cursor for this modification. (Position+Length)
    long redo()
    {
        if (snapshot_index >= snapshots.length)
            return -1;
        
        Snapshot snapshot = snapshots[ snapshot_index++ ];
        
        return snapshot.end;
    }
    
private:
    /// Base document to apply edits on.
    ///
    /// Nullable.
    IDocument basedoc;
    
    // Optimize right-side trim operation
    Piece trimPiece(Piece piece, long skip, long keep)
    {
        // NOTE: piece here is NOT ref and new instance is returned
        piece.position += skip;
        piece.size = keep;
        final switch (piece.source) { // Adjust piece offsets before re-inerting
        case Source.source: break;
        case Source.buffer:
            // NOTE: skip is SET, not added, because the piece is recreated for snapshot
            with (piece)
            assert(buffer.data + buffer.skip <= buffer.data + buffer.ogsize, "data + skip <= data + ogsize");
            //piece.buffer.data += skip;
            piece.buffer.skip = skip;
            break;
        case Source.document: break;
        case Source.pattern:
            piece.pattern.skip = (piece.pattern.skip + skip) % piece.pattern.ogsize;
            break;
        }
        return piece;
    }
    
    // This piece is inserted from this position
    void insertPiece(long position, Piece piece)
    {
        long len = piece.size;
        
        // Optimization: No snapshots, no documents opened
        if (snapshots.length == 0)
        {
            assertion(position == 0, "insert(position==0)");
            Snapshot snap = Snapshot( 0, len, len, new Tree(IndexedPiece(len, piece)) );
            addSnapshot(snap);
            return;
        }
        
        Snapshot cur_snap = currentSnapshot();
        assertion(position <= cur_snap.logical_size, "position <= current.logical_size");
        
        Snapshot new_snap = Snapshot( position, position+len, cur_snap.logical_size+len, new Tree() );
        
        // Optimization: Insert at SOF
        if (position == 0)
        {
            foreach (index; cur_snap.pieces)
                new_snap.pieces.insert( IndexedPiece(index.cumulative + len, index.piece) );
            new_snap.pieces.insert( IndexedPiece(len, piece) );
            addSnapshot(new_snap);
            return;
        }
        
        // Optimization: Insert at EOF
        if (position == cur_snap.logical_size)
        {
            foreach (index; cur_snap.pieces)
                new_snap.pieces.insert(IndexedPiece(index.cumulative, index.piece));
            new_snap.pieces.insert(IndexedPiece(cur_snap.logical_size+len, piece));
            addSnapshot(new_snap);
            return;
        }
        
        // General case: insert in the middle
        long old_cumulative;
        long new_cumulative;
        bool inserted;
        foreach (index; cur_snap.pieces)
        {
            // Before insertion point - keep as-is
            if (index.cumulative <= position)
            {
                new_snap.pieces.insert(index);
                old_cumulative = index.cumulative;
                new_cumulative = index.cumulative;
                continue;
            }
            
            // This piece contains or is after the insertion point
            long piece_offset = position - old_cumulative;
            
            // Need to split this piece
            if (!inserted && piece_offset > 0 && piece_offset < index.piece.size)
            {
                // Split into left, new, right pieces
                long right_len = index.piece.size - piece_offset;
                Piece left = void, right = void;
                
                final switch (index.piece.source) {
                case Source.source:
                    left  = Piece(Source.source, index.piece.position, piece_offset);
                    right = Piece(Source.source, index.piece.position + piece_offset, right_len);
                    break;
                case Source.buffer:
                    left  = Piece.makebuffer(
                        index.piece.position,
                        index.piece.buffer.data,
                        piece_offset,
                        index.piece.buffer.skip);
                    right = Piece.makebuffer(
                        index.piece.position + piece_offset,
                        index.piece.buffer.data,
                        right_len,
                        index.piece.buffer.skip + piece_offset);
                    break;
                case Source.pattern:
                    left  = Piece.makepattern(
                        index.piece.position,
                        piece_offset,
                        index.piece.pattern.data,
                        index.piece.pattern.ogsize,
                        index.piece.pattern.skip);
                    right = Piece.makepattern(
                        index.piece.position + piece_offset,
                        right_len,
                        index.piece.pattern.data,
                        index.piece.pattern.ogsize,
                        (index.piece.pattern.skip + piece_offset) % index.piece.pattern.ogsize);
                    break;
                case Source.document:
                    throw new Exception("TODO");
                    /*left  = Piece.makefile(
                        index.piece.position,
                        piece_offset,
                        index.piece.doc.doc);
                    right = Piece.makefile(
                        index.piece.position + piece_offset,
                        right_len,
                        index.piece.doc.doc);*/
                    break;
                }
                
                // Insert left, new, right
                new_cumulative += piece_offset;
                new_snap.pieces.insert(IndexedPiece(new_cumulative, left));
                
                new_cumulative += len;
                new_snap.pieces.insert(IndexedPiece(new_cumulative, piece));
                
                new_cumulative += right_len;
                new_snap.pieces.insert(IndexedPiece(new_cumulative, right));
                
                inserted = true;
            }
            else
            {
                // Insert new piece at boundary if not yet inserted
                if (!inserted)
                {
                    new_cumulative += len;
                    new_snap.pieces.insert(IndexedPiece(new_cumulative, piece));
                    inserted = true;
                }
                
                // Then insert current piece with adjusted cumulative
                new_cumulative += index.piece.size;
                new_snap.pieces.insert(IndexedPiece(new_cumulative, index.piece));
            }
            
            old_cumulative = index.cumulative;
        }
        
        addSnapshot(new_snap);
    }
    
    // This piece replaces data from this position
    void replacePiece(long position, Piece piece)
    {
        long len = piece.size;
        
        // Optimization: No snapshots, no documents opened
        if (snapshots.length == 0)
        {
            assertion(position == 0, "position == 0");
            Snapshot snap = Snapshot( 0, len, len, new Tree(IndexedPiece(len, piece)) );
            addSnapshot(snap);
            return;
        }
        
        Snapshot cur_snap = currentSnapshot();
        assertion(position <= cur_snap.logical_size, "position <= current.logical_size");
        
        // Optimization: Replace at EOF (treat as insert)
        if (position == cur_snap.logical_size)
        {
            Snapshot snap = Snapshot( position, position+len, cur_snap.logical_size+len, new Tree() );
            foreach (idx; cur_snap.pieces)
                snap.pieces.insert(IndexedPiece(idx.cumulative, idx.piece));
            snap.pieces.insert(IndexedPiece(cur_snap.logical_size+len, piece));
            addSnapshot(snap);
            return;
        }
        
        // Calculate how much we're actually overwriting
        long overwritten = min(len, cur_snap.logical_size - position);
        long delta = len - overwritten;  // can be negative, zero, or positive
        long end = position + overwritten;  // end of region being replaced
        
        Snapshot new_snap = Snapshot( 
            position, 
            position + len, 
            cur_snap.logical_size + delta,
            new Tree() 
        );
        
        long old_cumulative;
        long new_cumulative;
        bool inserted;
        
        foreach (index; cur_snap.pieces)
        {
            long piece_start = old_cumulative;
            long piece_end = index.cumulative;
            
            // Pieces completely before replacement
            if (piece_end <= position)
            {
                new_snap.pieces.insert(index);
                old_cumulative = index.cumulative;
                new_cumulative = index.cumulative;
                continue;
            }
            
            // Pieces that overlap with replacement region
            if (piece_start < end && piece_end > position)
            {
                // Keep left portion (before replacement starts)
                if (piece_start < position)
                {
                    long keep = position - piece_start;
                    Piece left = index.piece;
                    left.size = keep;
                    new_cumulative += keep;
                    new_snap.pieces.insert(IndexedPiece(new_cumulative, left));
                }
                
                // Insert the new piece (only once)
                if (!inserted)
                {
                    new_cumulative += len;
                    new_snap.pieces.insert(IndexedPiece(new_cumulative, piece));
                    inserted = true;
                }
                
                // Keep right portion (after replacement ends)
                if (piece_end > end)
                {
                    long skip = end - piece_start;
                    long keep = piece_end - end;
                    Piece right = trimPiece(index.piece, skip, keep);
                    new_cumulative += keep;
                    new_snap.pieces.insert(IndexedPiece(new_cumulative, right));
                }
            }
            else  // piece_start >= end
            {
                // Pieces completely after replacement
                new_cumulative += index.piece.size;
                new_snap.pieces.insert(IndexedPiece(new_cumulative, index.piece));
            }
            
            old_cumulative = index.cumulative;
        }
        
        addSnapshot(new_snap);
    }
    
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
    ///       elements as-is (even with foreach + ref) without remove+insert.
    ///       Which, could mean a shallow dupe (O(n)), remove (O(log n)), and
    ///       insert (O(log n)) possibly all elements -> Might be O(n²).
    ///       
    ///       So, each new snapshots are created from scratch, and this rebuild
    ///       should be around O(n log n), or possibly better.
    ///       
    ///       Other optimizations (deltas, array of pointers, etc.) could be
    ///       explored later, but it's more important to have something that
    ///       works.
    Array!Snapshot snapshots;
    /// Current snapshot index. Not synced with historical index, because
    /// snapshots can contain a document piece without edits, which counts
    /// towards the total amount of snapshots.
    size_t snapshot_index;
    /// Snapshot index used when saving.
    ///
    /// Used to know if document when was document saved vs. current index.
    size_t snapshot_saved;
    
    /// Get the current snapshot.
    /// Returns: Snapshot
    Snapshot currentSnapshot()
    {
        // Zero-check is cheap hack...
        return snapshots[ snapshot_index == 0 ? 0 : snapshot_index-1 ];
    }
    
    /// Add snapshot to our list.
    /// Params: snapshot = New snapshot
    void addSnapshot(Snapshot snapshot)
    {
        // Ensuring the consistency of the incoming new set of pieces
        // makes testing more consistent in behavior, to avoid incrementing
        // the snapshot index variable needlessly.
        debug
        {
            try ensureConsistency(snapshot);
            catch (Exception ex)
            {
                // If logs are enabled, print tables
                if (logEnabled())
                {
                    if (snapshot_index < snapshots.length)
                        printTable(snapshots[snapshot_index], "OLD");
                    printTable(snapshot, "NEW");
                }
                throw ex; // rethrew for visibility
            }
        }
        
        if (snapshot_index < snapshots.length) // replace
            snapshots[snapshot_index] = snapshot;
        else // append
            snapshots.insert( snapshot );
        snapshot_index++;
    }
    
    /// Ensure pieces are consistency in the latest added snapshot
    debug void ensureConsistency(Snapshot snapshot)
    {
        import std.conv : text;
        long previous_cumulative;
        long total_size; // cumulative size of *pieces*, to be compared to snapshot size
        size_t piece_count;
        // NOTE: 'enforce' msg is lazy evaluated, so feel free to use text(...)
        foreach (indexed; snapshot.pieces)
        {
            // Cumulative needs to be monotonically increasing, although
            // redblack tree handles this
            assertion(previous_cumulative < indexed.cumulative,
                text("Cumulative mismatch (piece[", piece_count, "]): ",
                    previous_cumulative, " >= ", indexed.cumulative));
            
            // Piece size must be set
            assertion(indexed.piece.size > 0,
                text("Piece size unset (piece[", piece_count, "])"));
            
            // Check for gap introduced by piece size vs. indexed cumulative size
            long piece_cumulative = previous_cumulative + indexed.piece.size;
            assertion(indexed.cumulative == piece_cumulative,
                text("Gap found (piece[", piece_count, "]): ",
                    indexed.cumulative, " != ", piece_cumulative));
            
            piece_count++;
            total_size += indexed.piece.size;
            previous_cumulative = indexed.cumulative;
        }
        
        // Last cumulative must match logical size of snapshot
        assertion(previous_cumulative == snapshot.logical_size,
            text("Cumulative mismatch: ", previous_cumulative, " != ", snapshot.logical_size));
        
        // Cumulative piece size must match logical size of snapshot
        assertion(total_size == snapshot.logical_size,
            text("Logical size mismatch: ", total_size, " != ", snapshot.logical_size));
    }
    
    debug void printTable(Snapshot snapshot, string name)
    {
        // Messy but whatever
        log("DUMPING %s PIECES\n--------------------", name);
        size_t n;
        foreach (index; snapshot.pieces)
        {
            with (index.piece)
            log("Piece[%u](%10s, %10d, %10d)(%d)", n++, source, position, size, index.cumulative);
        }
    }
    
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
    
    // SOF
    string data = "hi";
    e.insert(0, data.ptr, data.length);
    assert(e.edited());
    assert(e.size() == 2);
    assert(e.view(0, buffer) == data);
    
    // EOF
    string insert1 = " example";
    e.insert(data.length, insert1.ptr, insert1.length);
    assert(e.edited());
    assert(e.size() == data.length + insert1.length);
    assert(e.view(0, buffer) == data ~ insert1); // "hi example"
    
    // Undo
    assert(e.undo() == data.length);
    assert(e.edited());
    assert(e.size() == 2);
    assert(e.view(0, buffer) == data);
    // Redo
    assert(e.redo() == data.length + insert1.length);
    assert(e.edited());
    assert(e.size() == data.length + insert1.length);
    assert(e.view(0, buffer) == data ~ insert1); // "hi example"
    
    // Undo three times - Cursor positions should be start of change
    assert(e.undo() == data.length);
    assert(e.undo() == 0);
    assert(e.undo() < 0);
    
    // Redo three times - Curspor positions should be end of change
    assert(e.redo() == data.length);
    assert(e.redo() == data.length + insert1.length);
    assert(e.redo() < 0);
}

/// Insert with document
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0002");
    
    static immutable string data = "hello";
    scope PieceDocumentEditor e = new PieceDocumentEditor().open(
        new MemoryDocument(cast(ubyte[])data)
    );
    
    ubyte[32] buffer;
    log("Initial read");
    assert(e.edited() == false);
    assert(e.size() == data.length);
    assert(e.view(0, buffer) == data);
    
    // Insert to SOF
    string insert1 = "hi, ";
    e.insert(0, insert1.ptr, insert1.length);
    assert(e.edited());
    assert(e.size() == insert1.length + data.length);
    assert(e.view(0, buffer) == insert1 ~ data); // "hi, hello"
    
    // Insert to EOF
    string insert2 = " example";
    e.insert(insert1.length + data.length, insert2.ptr, insert2.length);
    assert(e.edited());
    assert(e.size() == insert1.length + data.length + insert2.length);
    assert(e.view(0, buffer) == insert1 ~ data ~ insert2); //  
    
    // Undo last insertion, where area affected starts at EOF
    assert(e.undo() == insert1.length + data.length);
    assert(e.edited());
    assert(e.size() == insert1.length + data.length);
    assert(e.view(0, buffer) == insert1 ~ data); // "hi, hello"
    
    // Redo last insertion, where area affected ends at EOF+data
    assert(e.redo() == insert1.length + data.length + insert2.length);
    assert(e.edited());
    assert(e.size() == insert1.length + data.length + insert2.length);
    assert(e.view(0, buffer) == insert1 ~ data ~ insert2); // "hi, hello example"
    
    // Undo three times - Undo insert2, insert1, and test it won't go too far
    assert(e.undo() == insert1.length + data.length); // "hi, hello example" ->  "hi, hello"
    assert(e.undo() == 0); // "hi, hello" -> "hello"
    assert(e.undo() < 0); // No undo operations available
    
    // Redo all
    assert(e.redo() == insert1.length); // insert1 + doc (notice: SOF edit)
    assert(e.redo() == insert1.length + data.length + insert2.length); // insert1 + doc + insert2
    assert(e.redo() < 0); // No redo operations available
}

/// Replace with document
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0003");
    
    static immutable string data = "very good string!";
    scope PieceDocumentEditor e = new PieceDocumentEditor().open(
        new MemoryDocument(cast(ubyte[])data)
    );
    
    ubyte[32] buffer;
    
    string ovr1 = "long";
    e.replace(5, ovr1.ptr, ovr1.length);
    assert(e.edited());
    assert(e.size() == data.length);
    assert(e.view(0, buffer) == "very long string!");
}

/// Remove with document
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0004");
    
    static immutable string data = "very good string!";
    scope PieceDocumentEditor e = new PieceDocumentEditor().open(
        new MemoryDocument(cast(ubyte[])data)
    );
    
    e.remove(9, " string".length);
    assert(e.edited());
    string result = "very good!";
    ubyte[32] buffer;
    assert(e.size() == result.length);
    assert(e.view(0, buffer) == result);
}

/// Offset view
unittest
{
    import document.memory : MemoryDocument;
    
    static immutable ubyte[] data = [
    //  0   1   2   3   4  5  6   7   8   9
        4,  7,  9, 13, 17, 3, 4,  5, 13, 15, // 0
    ];
    scope PieceDocumentEditor e = new PieceDocumentEditor().open(
        new MemoryDocument(data)
    );
    
    log("TEST-0005");
    
    ubyte b = 0xff;
    e.replace(4, &b, ubyte.sizeof);
    
    static immutable ubyte[] data0 = [ // 5 * 10 bytes
    //  0   1   2   3   4  5  6   7   8   9
        4,  5,  8, 16, 18, 1, 2,  5,  8, 10, // 0
    ];
    e.insert(10, data0.ptr, data0.length);
    
    ubyte[32] buffer;
    assert(e.edited());
    assert(e.size() == 20);
    assert(e.view(0, buffer) == [
    //  0   1   2   3    4  5  6   7   8   9
        4,  7,  9, 13, 255, 3, 4,  5, 13, 15, // 0
        4,  5,  8, 16,  18, 1, 2,  5,  8, 10, // 10
    ]);
    assert(e.view(0, buffer[0..10]) == [ // lower 10 bytes
    //  0   1   2   3    4  5  6   7   8   9
        4,  7,  9, 13, 255, 3, 4,  5, 13, 15, // 0
    ]);
    assert(e.view(10, buffer) == [ // upper 10 bytes
    //  0   1   2   3    4  5  6   7   8   9
        4,  5,  8, 16,  18, 1, 2,  5,  8, 10, // 10
    ]);
    assert(e.view(16, buffer) == [ // upper 16 bytes
    //  6   7   8   9
        2,  5,  8, 10, // 10
    ]);
}

/// Mix replace, insert, and deletions
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0006");
    
    static immutable ubyte[] data = [
    //  0   1   2   3   4   5   6   7   8   9
        0,  1,  2,  3,  4,  5,  6,  7,  8,  9, // 0
       10, 11, 12, 13, 14, 15, 16, 17, 18, 19, // 10
       20, 21, 22, 23, 24, 25, 26, 27, 28, 29, // 20
       30, 31, 32, 33, 34, 35, 36, 37, 38, 39, // 30
       40, 41, 42, 43, 44, 45, 46, 47, 48, 49, // 40
    ];
    scope PieceDocumentEditor e = new PieceDocumentEditor().open(
        new MemoryDocument(data)
    );
    
    ubyte[50] buffer;
    assert(e.edited() == false);
    assert(e.size() == 50);
    assert(e.view(0, buffer) == data);
    
    // Remove 10-19 row
    e.remove(10, 10);
    assert(e.edited());
    assert(e.size() == 40);
    assert(e.view(0, buffer) == [
    //  0   1   2   3   4   5   6   7   8   9
        0,  1,  2,  3,  4,  5,  6,  7,  8,  9, // 0
       20, 21, 22, 23, 24, 25, 26, 27, 28, 29, // 10
       30, 31, 32, 33, 34, 35, 36, 37, 38, 39, // 20
       40, 41, 42, 43, 44, 45, 46, 47, 48, 49, // 30
    ]);
    
    // Replace one byte values, which tends to be problematic
    ubyte replace0 = 86;
    e.replace(20, &replace0, ubyte.sizeof);
    assert(e.edited());
    assert(e.size() == 40);
    assert(e.view(0, buffer) == [
    //  0   1   2   3   4   5   6   7   8   9
        0,  1,  2,  3,  4,  5,  6,  7,  8,  9, // 0
       20, 21, 22, 23, 24, 25, 26, 27, 28, 29, // 10
       86, 31, 32, 33, 34, 35, 36, 37, 38, 39, // 20
       40, 41, 42, 43, 44, 45, 46, 47, 48, 49, // 30
    ]);
    
    e.replace(21, &replace0, ubyte.sizeof);
    assert(e.edited());
    assert(e.size() == 40);
    assert(e.view(0, buffer) == [
    //  0   1   2   3   4   5   6   7   8   9
        0,  1,  2,  3,  4,  5,  6,  7,  8,  9, // 0
       20, 21, 22, 23, 24, 25, 26, 27, 28, 29, // 10
       86, 86, 32, 33, 34, 35, 36, 37, 38, 39, // 20
       40, 41, 42, 43, 44, 45, 46, 47, 48, 49, // 30
    ]);
    
    // Replace at position 0, just in case
    e.replace(0, &replace0, ubyte.sizeof);
    assert(e.edited());
    assert(e.size() == 40);
    assert(e.view(0, buffer) == [
    //  0   1   2   3   4   5   6   7   8   9
       86,  1,  2,  3,  4,  5,  6,  7,  8,  9, // 0
       20, 21, 22, 23, 24, 25, 26, 27, 28, 29, // 10
       86, 86, 32, 33, 34, 35, 36, 37, 38, 39, // 20
       40, 41, 42, 43, 44, 45, 46, 47, 48, 49, // 30
    ]);
    
    // Insert new data at start
    static immutable ubyte[] insert0 = [
    //  0   1   2   3   4   5   6   7   8   9
       99, 88, 77, 66, 55, 44, 33, 22, 11, 00, // 10
    ];
    e.insert(0, insert0.ptr, insert0.length);
    assert(e.edited());
    assert(e.size() == 50);
    assert(e.view(0, buffer) == [
    //  0   1   2   3   4   5   6   7   8   9
       99, 88, 77, 66, 55, 44, 33, 22, 11,  0, // 0
       86,  1,  2,  3,  4,  5,  6,  7,  8,  9, // 10
       20, 21, 22, 23, 24, 25, 26, 27, 28, 29, // 20
       86, 86, 32, 33, 34, 35, 36, 37, 38, 39, // 30
       40, 41, 42, 43, 44, 45, 46, 47, 48, 49, // 40
    ]);
    assert(e.view(0, buffer[0..20]) == [
    //  0   1   2   3   4   5   6   7   8   9
       99, 88, 77, 66, 55, 44, 33, 22, 11,  0,
       86,  1,  2,  3,  4,  5,  6,  7,  8,  9,
    ]);
    assert(e.view(30, buffer) == [
    //  0   1   2   3   4   5   6   7   8   9
       86, 86, 32, 33, 34, 35, 36, 37, 38, 39,
       40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
    ]);
}

/// Delete multiple pieces
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0007");
    
    static immutable ubyte[] data = [
    //  0   1   2   3   4   5   6   7   8   9
        0,  1,  2,  3,  4,  5,  6,  7,  8,  9, // 0
       10, 11, 12, 13, 14, 15, 16, 17, 18, 19, // 10
       20, 21, 22, 23, 24, 25, 26, 27, 28, 29, // 20
       30, 31, 32, 33, 34, 35, 36, 37, 38, 39, // 30
       40, 41, 42, 43, 44, 45, 46, 47, 48, 49, // 40
    ];
    scope PieceDocumentEditor e = new PieceDocumentEditor().open(
        new MemoryDocument(data)
    );
    
    // Emulate usage and check just in check it's the state we want
    ubyte[64] buffer;
    ubyte data0 = 0xee;
    e.replace( 2, &data0, ubyte.sizeof);
    e.replace(12, &data0, ubyte.sizeof);
    e.insert (22, &data0, ubyte.sizeof);
    e.insert (32, &data0, ubyte.sizeof);
    assert(e.edited());
    assert(e.size() == data.length + 2); // 2x 1-byte inserts
    assert(e.view(0, buffer) == [
    //  0   1    2   3   4   5   6   7   8   9
        0,  1,0xee,  3,  4,  5,  6,  7,  8,  9, // 10
       10, 11,0xee, 13, 14, 15, 16, 17, 18, 19, // 20
       20, 21,0xee, 22, 23, 24, 25, 26, 27, 28,
       29, 30,0xee, 31, 32, 33, 34, 35, 36, 37,
       38, 39,  40, 41, 42, 43, 44, 45, 46, 47,
       48, 49,
    ]);
    
    // Remove everything from that range, starting with piece with first replace
    e.remove(2, 33);
}

// Delete+Overwrite
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0008");
    
    static immutable ubyte[] data = [
    //  0   1   2   3   4   5   6   7   8   9
        0,  1,  2,  3,  4,  5,  6,  7,  8,  9, // 0
       10, 11, 12, 13, 14, 15, 16, 17, 18, 19, // 10
       20, 21, 22, 23, 24, 25, 26, 27, 28, 29, // 20
       30, 31, 32, 33, 34, 35, 36, 37, 38, 39, // 30
       40, 41, 42, 43, 44, 45, 46, 47, 48, 49, // 40
    ];
    scope PieceDocumentEditor e = new PieceDocumentEditor().open(
        new MemoryDocument(data)
    );
    
    // Remove range 10-19
    e.remove(10, 10);
    
    // Insert at that starting position
    ubyte r0 = 0xdd;
    e.insert(10, &r0, ubyte.sizeof);
}

// Patterns
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0009");
    
    static immutable ubyte[] data = [
    //  0   1   2   3   4   5   6   7   8   9
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 0
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 10
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 20
    ];
    scope PieceDocumentEditor e = new PieceDocumentEditor().open(
        new MemoryDocument(data)
    );
    
    ubyte f0 = 10;
    e.patternReplace(10, 10, &f0, ubyte.sizeof);
    
    ubyte[64] buffer;
    assert(e.edited());
    assert(e.size() == data.length);
    assert(e.view(0, buffer) == [
    //  0   1   2   3   4   5   6   7   8   9
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 0
       10, 10, 10, 10, 10, 10, 10, 10, 10, 10, // 10
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 20
    ]);
    
    ubyte[2] f1 = [ 'N', 'O' ];
    e.patternInsert(20, 10, f1.ptr, f1.length);
    
    assert(e.edited());
    assert(e.size() == data.length+10);
    assert(e.view(0, buffer) == [
    //  0   1   2   3   4   5   6   7   8   9
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 0
       10, 10, 10, 10, 10, 10, 10, 10, 10, 10, // 10
      'N','O','N','O','N','O','N','O','N','O', // 20
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 30
    ]);
    
    // Test if patterns hold up if cut
    ubyte r0 = 4;
    e.replace(10 , &r0, ubyte.sizeof);
    assert(e.view(0, buffer) == [ // single-byte pattern
    //  0   1   2   3   4   5   6   7   8   9
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 0
        4, 10, 10, 10, 10, 10, 10, 10, 10, 10, // 10
      'N','O','N','O','N','O','N','O','N','O', // 20
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 30
    ]);
    e.replace(20 , &r0, ubyte.sizeof);
    log("FAILING = %s", e.view(0, buffer));
    assert(e.view(0, buffer) == [ // multi-byte pattern
    //  0   1   2   3   4   5   6   7   8   9
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 0
        4, 10, 10, 10, 10, 10, 10, 10, 10, 10, // 10
        4,'O','N','O','N','O','N','O','N','O', // 20
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 30
    ]);
    e.replace(29 , &r0, ubyte.sizeof);
    assert(e.view(0, buffer) == [
    //  0   1   2   3   4   5   6   7   8   9
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 0
        4, 10, 10, 10, 10, 10, 10, 10, 10, 10, // 10
        4,'O','N','O','N','O','N','O','N',  4, // 20
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 30
    ]);
}

// Files
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0010");
    
    static immutable ubyte[] data = [
    //  0   1   2   3   4   5   6   7   8   9
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 10
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 20
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 30
    ];
    scope PieceDocumentEditor e = new PieceDocumentEditor().open(
        new MemoryDocument(data)
    );
    
    // TODO: FILE
}

/// Common tests
unittest
{
    import backend.base : editorTests;
    editorTests!PieceDocumentEditor();
}