/// Editor backend implemention using a Piece List to ease insertion and
/// deletion operations, and a command history stack for undo-redo operations.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module backend.piecev2;

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
// TODO: CPU cache friendliness
//       Reference: https://skoredin.pro/blog/golang/cpu-cache-friendly-go
//       Instead of an array of structures, having array of fields tend to help
//       processor cache, in particular, architectures with cache lines of 64 Bytes.
//       Checks (needs linux-tools-generic):
//       - perf stat -e cache-misses,cache-references ./myapp
//       - perf record -e cache-misses ./myapp
//         perk report
//       - perf stat -p $pid -e L1-dcache-load-misses,L1-dcache-loads
//       Not a current necessity, as nothing is pushing the backend to extreme scenarios.

// Other interesting sources:
// - temp: Temporary file if an edit is too large to fit in memory (past a threshold)
private
enum Source
{
    source,     /// Original source document
    buffer,     /// In-memory buffer
    pattern,    /// Repeated pattern
    document,   /// File document
}

/// Used with Source.buffer.
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

/// Used with Source.pattern.
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

/// Use with Source.document.
private
struct DocumentPiece
{
    IDocument doc;
}

/// Represents a single piece in the Piece Table.
private
struct Piece // @suppress(dscanner.suspicious.incomplete_operator_overloading)
{
    /// Piece source. (Document, buffer, etc.)
    Source source;
    /// Position within the source material (file offset, buffer offset, etc.)
    /// where this piece's data starts.
    long position;
    /// Size of piece
    long size;
    
    union
    {
        BufferPiece buffer;
        PatternPiece pattern;
        DocumentPiece doc;
    }
    
    // Custom hash function to avoid @safe issues with union
    size_t toHash() const nothrow @safe
    {
        // Hash based on source type and position
        size_t hash = cast(size_t)source;
        hash = hash * 31 + cast(size_t)position;
        hash = hash * 31 + cast(size_t)size;
        return hash;
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
    static Piece makefile(long position, long len, IDocument doc)
    {
        Piece piece     = void;
        piece.source    = Source.document;
        piece.position  = position;
        piece.size      = len;
        piece.doc.doc   = doc;
        return piece;
    }
}

/// Indexed piece used for indexing with the redblack tree.
private
struct IndexedPiece
{
    /// Cumulative size of ALL previous pieces to help indexing.
    ///
    /// If we have pieces (pos=0,size=15),(pos=15,size=30),(pos=45,size=5),
    /// then they'd have 15, 45, and 50 cumulative sizes respectfully.
    long cumulative;
    /// Actual tree piece.
    Piece piece;
}

/// Tree format
private alias Tree = RedBlackTree!(IndexedPiece, "a.cumulative < b.cumulative");

/// Operating type.
private
enum OperationType
{
    insert, replace, remove,
}

/// Represents an operation for the history stack (undo-redo).
private
struct Operation
{
    /// Starting position of the change.
    long position;
    /// Size delta.
    long delta;
    /// Operation type.
    /// Kind of required since a replace operation can be placed at the end
    /// of the document, increasing the document size.
    OperationType type;
    /// Insert at this cumulative
    long cumulative;
    /// Affected area in size (bytes)
    long affected;
    /// Added pieces
    Piece[] added;
    /// Removed pieces
    IndexedPiece[] removed;
}

/// Document editor implementing a Piece List with RedBlackTree for indexing
/// and command history.
class PieceV2DocumentEditor : IDocumentEditor
{
    /// New document editor with a new empty buffer.
    this()
    {
        import os.mem : syspagesize;
        pagesize = syspagesize();
        tree = new Tree();
    }
    
    /// Open document.
    /// Params: doc = IDocument-based document.
    /// Returns: Editor instance.
    typeof(this) open(IDocument doc)
    {
        long docsize = doc.size();
        basedoc = doc;
        
        logical_size = docsize;
        
        // Clear history
        history.clear();
        history_index = history_saved = 0;
        
        // New tree
        tree.clear();
        tree.insert(IndexedPiece(docsize, Piece(Source.source, 0, docsize)));
        
        return this;
    }
    
    /// Total size of document in bytes with edits.
    /// Returns: Size of current document.
    long size()
    {
        return logical_size;
    }
    
    void markSaved()
    {
        history_saved = history_index;
    }
    
    ubyte[] view(long position, void* buffer, size_t size)
    {
        return view(position, (cast(ubyte*)buffer)[0..size]);
    }
    
    ubyte[] view(long position, ubyte[] buffer)
    {
        if (logical_size == 0)
            return [];
        //if (his_index == 0 && basedoc is null)
            //return [];
        
        log("VIEW Hi=%u Hc=%u", history_index, history.length);
        
        size_t bi; /// buffer index (for slicing)
        foreach (index; tree.upperBound(IndexedPiece(position)))
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
            // Assumes view buffer is ... under 2 GiB
            size_t to_read = cast(size_t)min(available, buffer.length - bi);
            
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
                    size_t pattern_offset = cast(size_t)((index.piece.pattern.skip + piece_offset) % psize);
                    
                    size_t p;
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
                index.piece.doc.doc.readAt(index.piece.position + piece_offset, buffer[bi..bi+to_read]);
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
        // Just having a document open does not mean we have active edits.
        return history_index != history_saved;
    }
    
    /// Remove data foward from a position for a length of bytes.
    /// Throws: Exception.
    /// Params:
    ///     position = Base position.
    ///     len = Number of bytes to delete.
    void remove(long position, long len)
    in (position >= 0, "position >= 0")
    in (len > 0, "len > 0")
    {
        log("REMOVE pos=%d len=%u", position, len);
        
        // Nothing to remove
        if (logical_size == 0)
            return;
        
        // Editors should avoid deleting nothing at EOF...
        assertion(position < logical_size, "position < cur_snap.logical_size");
        
        // Clamp removal to actual document size
        long removed = min(len, logical_size - position);
        // End position of removal
        long end = position + removed;
        
        // Create operation with required info, read tree only
        Operation op = Operation(position, -removed, OperationType.remove, position, removed);
        // Walk tree and RECORD what needs to change (tree remains unchanged!)
        long cumulative;
        foreach (idx; tree)
        {
            long piece_start = cumulative;
            long piece_end = idx.cumulative;
            
            // Does this piece overlap with the removal region?
            if (piece_start < end && piece_end > position)
            {
                // Record this piece for removal
                op.removed ~= idx;
                
                // If piece extends before removal region, keep left portion
                if (piece_start < position)
                {
                    Piece left = idx.piece;
                    left.size = position - piece_start;
                    op.added ~= left;
                }
                
                // If piece extends after removal region, keep right portion
                if (piece_end > end)
                {
                    long skip = end - piece_start;
                    long keep = piece_end - end;
                    Piece right = trimPiece(idx.piece, skip, keep);
                    right.size = keep;
                    op.added ~= right;
                }
            }
            
            cumulative = idx.cumulative;
        }
        
        applyOperation(op);
        addOperation(op);
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
        Piece piece = Piece.makebuffer( 0, bufferAdd(data, len), len );
        replacePiece(position, piece);
    }
    
    void patternReplace(long position, long len, const(void) *data, size_t datlen)
    in (position >= 0, "position >= 0")
    in (len > 0, "len > 0")
    in (data != null, "data != NULL")
    in (datlen > 0, "datlen > 0")
    {
        log("REPLACE PATTERN pos=%d len=%d data=%s datlen=%u", position, len, data, datlen);
        Piece piece = Piece.makepattern( 0, len, bufferAdd(data, datlen), datlen );
        replacePiece(position, piece);
    }
    
    void fileReplace(long position, IDocument doc)
    in (position >= 0, "position >= 0")
    in (doc !is null, "doc !is null")
    {
        log("REPLACE FILE pos=%d", position);
        Piece piece = Piece.makefile( 0, doc.size(), doc );
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
        Piece piece = Piece.makebuffer( 0, bufferAdd(data, len), len );
        insertPiece(position, piece);
    }
    
    void patternInsert(long position, long len, const(void) *data, size_t datlen)
    in (position >= 0, "position >= 0")
    in (len > 0, "len > 0")
    in (data != null, "data != NULL")
    in (datlen > 0, "datlen > 0")
    {
        log("INSERT PATTERN pos=%d len=%d data=%s datlen=%u", position, len, data, datlen);
        Piece piece = Piece.makepattern( 0, len, bufferAdd(data, datlen), datlen );
        insertPiece(position, piece);
    }
    
    void fileInsert(long position, IDocument doc)
    in (position >= 0, "position >= 0")
    in (doc !is null, "doc !is null")
    {
        log("INSERT FILE pos=%d", position);
        Piece piece = Piece.makefile( 0, doc.size(), doc );
        insertPiece(position, piece);
    }
    
    /// Undo last modification.
    /// Returns: Suggested position of the cursor for this modification.
    long undo()
    {
        log("UNDO Hi=%u", history_index);
        
        if (history_index <= 0)
            return -1;
        
        Operation op = history[--history_index];
        reverseOperation( op );
        return op.position;
    }
    
    /// Redo last undone modification.
    /// Returns: Suggested position of the cursor for this modification. (Position+Length)
    long redo()
    {
        log("REDO Hi=%u", history_index);
        
        if (history_index >= history.length)
            return -1;
        
        Operation op = history[history_index++];
        applyOperation( op );
        return op.position + op.affected;
    }
    
private:
    /// The piece table indexed using a self-balancing tree.
    Tree tree;
    
    /// Tracked logical size of document.
    long logical_size;
    
    /// History of operations.
    ///
    /// When an insert, replace, or remove operation is performed, its operation
    /// is saved here.
    ///
    /// Opening a document as its base does not count as an operation, but could
    /// be, if explicitly stated as an operation type. But generally, no, it's
    /// nice to undo without having to worry unloading the document by accident.
    Array!Operation history;
    size_t history_index;   /// Current history index
    size_t history_saved;   /// History index when last saved
    
    /// Source document to apply edits on.
    ///
    /// Nullable.
    IDocument basedoc;
    
    // Optimize right-side trim operation
    Piece trimPiece(Piece piece, long skip, long keep)
    {
        // NOTE: piece struct is NOT ref and new instance is returned
        // NOTE: skip/keep are calculated from caller, because the piece is recreated for snapshot
        piece.position += skip;
        piece.size = keep;
        final switch (piece.source) { // Adjust piece offsets before re-inerting
        case Source.source: break;
        case Source.buffer:
            assertion(skip <= uint.max, "skip <= uint.max"); // bad hack, to be reminded later
            with (piece)
            assertion(buffer.skip <= buffer.ogsize, "buffer.skip <= buffer.ogsize");
            piece.buffer.skip = cast(size_t)skip;
            break;
        case Source.document: break; // like source
        case Source.pattern:
            assertion(skip <= uint.max, "skip <= uint.max"); // bad hack, to be reminded later
            piece.pattern.skip = cast(size_t)(piece.pattern.skip + skip) % piece.pattern.ogsize;
            break;
        }
        return piece;
    }
    
    /// Apply an operation to the tree (either forward for redo, or backward for undo)
    /// APPLY/REDO:
    ///   1. Remove old pieces (from removed_pieces array)
    ///   2. Add new pieces (from added_pieces array, calculating cumulatives)
    ///   3. Adjust cumulatives of all pieces after insertion point
    ///   4. Update logical size
    void applyOperation(Operation op)
    {
        log("op=%s", op);
        
        // REDO: Apply the operation forward
        
        // Step 1: Remove pieces that were directly modified/split
        // (Typically 0-2 pieces)
        foreach (piece; op.removed)
            tree.removeKey(piece);
        
        // Step 2: Adjust ALL pieces after insertion point FIRST
        // (before adding new pieces so they don't get double-adjusted)
        adjustCumulatives(op.cumulative, op.delta);
        
        /// Step 3: Add new pieces with calculated cumulatives
        long cumulative = op.removed.length > 0 ?
            // >0 removals: Account for left piece by its starting position
            op.removed[0].cumulative - op.removed[0].piece.size :
            // no pieces removed, start from insertion point
            op.cumulative;
        foreach (piece; op.added)
        {
            cumulative += piece.size;
            tree.insert(IndexedPiece(cumulative, piece));
        }
        
        // Step 4: Update document size
        logical_size += op.delta;
    }
    
    /// Reverse an operation
    /// REVERSE/UNDO:
    ///   1. Remove new pieces (reverse of step 2)
    ///   2. Restore old pieces (from removed_pieces array with their stored cumulatives)
    ///   3. Adjust cumulatives of all pieces after insertion point (negative delta)
    ///   4. Update logical size
    void reverseOperation(Operation op)
    {
        log("op=%s", op);
        
        // UNDO: Reverse the operation
        
        // Step 1: Remove the pieces that were added
        // We reconstruct their cumulative positions
        long cumulative = op.removed.length > 0 ?
            // >0 removals: Account for left piece by its starting position
            op.removed[0].cumulative - op.removed[0].piece.size :
            // no pieces removed, start from insertion point
            op.cumulative;
        foreach (piece; op.added)
        {
            cumulative += piece.size;
            // Find and remove the piece at this exact cumulative
            foreach (idx; tree.equalRange(IndexedPiece(cumulative)))
            {
                tree.removeKey(idx);
                break; // Only remove the first match
            }
        }
        
        // Step 3: Adjust ALL pieces after the operation (reverse)
        adjustCumulatives(op.cumulative, -op.delta);
        
        // Step 2: Restore the original pieces
        // These were stored with their exact cumulative values
        foreach (piece; op.removed)
            tree.insert(piece);
        
        // Step 4: Update document size
        logical_size -= op.delta;
    }
    
    /// Add operation to history list
    void addOperation(Operation op)
    {
        debug try
        {
            ensureConsistency();
        }
        catch (Exception ex)
        {
            if (logEnabled())
                printTable(op, "CURRENT");
            throw ex;
        }
        
        if (history_index < history.length) // Replace
            history[history_index] = op;
        else // Insert
            history.insert(op);
        history_index++;
    }
    
    /// Ensure pieces are consistent
    debug void ensureConsistency()
    {
        import std.conv : text;
        long previous_cumulative;
        long total_size; // cumulative size of *pieces*, to be compared to snapshot size
        size_t piece_count;
        // NOTE: 'enforce' msg is lazy evaluated, so feel free to use text(...)
        foreach (indexed; tree)
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
        assertion(previous_cumulative == logical_size,
            text("Cumulative mismatch: ", previous_cumulative, " != ", logical_size));
        
        // Cumulative piece size must match logical size of snapshot
        assertion(total_size == logical_size,
            text("Logical size mismatch: ", total_size, " != ", logical_size));
    }
    
    debug void printTable(Operation op, string name)
    {
        // Messy but whatever
        log("DUMPING %s PIECES --------------------", name);
        size_t n;
        foreach (index; tree)
        {
            with (index.piece)
            log("Piece[%u](%10s, %10d, %10d)(%d)", n++, source, position, size, index.cumulative);
        }
    }
    
    /// Adjust cumulative values for all pieces after a given cumulative position.
    /// This is needed because inserting/removing pieces shifts all subsequent pieces.
    ///
    /// Example: If we insert 5 bytes at cumulative 100, then piece at cumulative 150
    /// needs to become 155, piece at 200 becomes 205, etc.
    void adjustCumulatives(long position, long delta)
    {
        if (delta == 0)
            return;
        
        // Collect all pieces that need adjustment (cumulative > from_cumulative)
        IndexedPiece[] to_adjust;
        foreach (idx; tree.upperBound(IndexedPiece(position)))
        {
            to_adjust ~= idx;
        }
        
        // Remove and re-insert with adjusted cumulatives
        // Note: We must remove first, then insert, to avoid collisions in the tree
        foreach (idx; to_adjust)
            tree.removeKey(idx);
        
        foreach (idx; to_adjust)
            tree.insert(IndexedPiece(idx.cumulative + delta, idx.piece));
    }
    
    // This piece is inserted from this position
    void insertPiece(long position, Piece piece)
    {
        assertion(position <= logical_size, "position <= current.logical_size");
        
        // 
        Operation op = Operation(position, piece.size, OperationType.insert);
        op.affected = piece.size;
        long cumulative;
        IndexedPiece split_piece;
        bool needs_split;
        long split_offset;
        foreach (idx; tree) // for cumulative
        {
            long piece_start = cumulative;
            long piece_end = idx.cumulative;
            
            if (piece_end <= position)
            {
                // This piece is entirely before the insertion point
                cumulative = idx.cumulative;
            }
            else if (piece_start < position && position < piece_end)
            {
                // Insertion point is INSIDE this piece - we need to split it
                split_piece = idx;
                split_offset = position - piece_start;
                needs_split = true;
                op.cumulative = piece_start + split_offset;
                break;
            }
            else
            {
                // Insertion point is at a piece boundary (or before all pieces)
                op.cumulative = cumulative;
                break;
            }
            
            cumulative = idx.cumulative;
        }
        
        // Handle EOF insertion (position equals current document size)
        if (needs_split == false && cumulative == position)
        {
            op.cumulative = cumulative;
        }
        
        // Build the operation based on whether we need to split
        if (needs_split)
        {
            // Record the piece we're removing (with its cumulative for exact restoration)
            op.removed ~= split_piece;
            
            // Create left portion of split piece
            Piece left = split_piece.piece;
            left.size = split_offset;
            
            // Create right portion of split piece (adjusting position/offsets)
            //Piece right = trimPiece(split_piece.piece, split_offset);
            Piece right = trimPiece(split_piece.piece, split_offset, split_piece.piece.size - split_offset);
            
            // Store all three pieces in order (cumulatives calculated during apply)
            op.added ~= left;
            op.added ~= piece;
            op.added ~= right;
        }
        else // Inserting at a boundary (SOF, EOF, or between pieces)
        {
            op.added ~= piece; // Just add the new piece
        }
        
        applyOperation(op);
        addOperation(op);
    }
    
    // This piece replaces data from this position
    void replacePiece(long position, Piece piece)
    {
        long overwritten = min(piece.size, logical_size - position);
        long end = position + overwritten;
        long delta = piece.size - overwritten;
        
        Operation op = Operation(
            position,
            delta,
            OperationType.replace,
            position,
            piece.size,
        );
        bool inserted;
        long cumulative;
        foreach (idx; tree)
        {
            long piece_start = cumulative;
            long piece_end = idx.cumulative;
            
            if (piece_start < end && piece_end > position)
            {
                // Record piece being replaced
                op.removed ~= idx;
                
                // Keep left portion if it exists (before replacement starts)
                if (piece_start < position)
                {
                    Piece left = idx.piece;
                    left.size = position - piece_start;
                    op.added ~= left;
                }
                
                // Insert new piece exactly once (at first overlapping piece)
                if (inserted == false)
                {
                    op.added ~= piece;
                    inserted = true;
                }
                
                // Keep right portion if it exists (after replacement ends)
                if (piece_end > end)
                {
                    long skip = end - piece_start;
                    long keep = piece_end - end;
                    Piece right = trimPiece(idx.piece, skip, keep);
                    right.size = keep;
                    op.added ~= right;
                }
            }
            
            cumulative = idx.cumulative;
        }
        
        // If no pieces overlapped (EOF replacement/insertion), just add new piece
        if (inserted == false)
            op.added ~= piece;
        
        applyOperation(op);
        addOperation(op);
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
    
    scope PieceV2DocumentEditor e = new PieceV2DocumentEditor();
    
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
    scope PieceV2DocumentEditor e = new PieceV2DocumentEditor().open(
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
    scope PieceV2DocumentEditor e = new PieceV2DocumentEditor().open(
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
    scope PieceV2DocumentEditor e = new PieceV2DocumentEditor().open(
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
    scope PieceV2DocumentEditor e = new PieceV2DocumentEditor().open(
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
    scope PieceV2DocumentEditor e = new PieceV2DocumentEditor().open(
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
    scope PieceV2DocumentEditor e = new PieceV2DocumentEditor().open(
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
    scope PieceV2DocumentEditor e = new PieceV2DocumentEditor().open(
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
    scope PieceV2DocumentEditor e = new PieceV2DocumentEditor().open(
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
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 0
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 10
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 20
    ];
    scope PieceV2DocumentEditor e = new PieceV2DocumentEditor().open(
        new MemoryDocument(data)
    );
    
    import std.file : remove, write, tempDir, readText;
    import std.path : buildPath;
    import document.file : FileDocument;
    
    ubyte[64] buffer;
    
    // Replace file
    static immutable piece_replace_0 = "piece_replace_0.tmp";
    string path_replace = buildPath(tempDir(), piece_replace_0);
    write(path_replace, "file replace");
    assert(readText(path_replace) == "file replace");
    FileDocument filedoc0 = new FileDocument(path_replace, true);
    e.fileReplace(10, filedoc0); // open readonly
    assert(e.view(0, buffer) == [
    //  0   1   2   3   4   5   6   7   8   9
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  // 0
       'f','i','l','e',' ','r','e','p','l','a', // 10
       'c','e', 0,  0,  0,  0,  0,  0,  0,  0,  // 20
    ]);
    
    // Insert file
    static immutable piece_insert_0 = "piece_insert_0.tmp";
    string path_insert = buildPath(tempDir(), piece_insert_0);
    write(path_insert, "file insert");
    FileDocument filedoc1 = new FileDocument(path_insert, true);
    e.fileInsert(30, filedoc1); // open readonly
    assert(e.view(0, buffer) == [
    //  0   1   2   3   4   5   6   7   8   9
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  // 0
       'f','i','l','e',' ','r','e','p','l','a', // 10
       'c','e', 0,  0,  0,  0,  0,  0,  0,  0,  // 20
       'f','i','l','e',' ','i','n','s','e','r', // 30
       't'
    ]);
    
    // NOTE: Removing opened file on Windows crashes.
    //       So, close them.
    filedoc0.close();
    filedoc1.close();
    remove(path_replace);
    remove(path_insert);
}

// Add data on empty doc, undo, and insert pattern
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0011");
    
    scope PieceV2DocumentEditor e = new PieceV2DocumentEditor();
    
    ubyte dd = 0xdd;
    e.replace(0, &dd, ubyte.sizeof);
    
    e.undo();
    
    ubyte p = 0;
    e.patternInsert(0, 5, &p, ubyte.sizeof);
    
    ubyte[10] buf;
    assert(e.view(0, buf) == [ 0,0,0,0,0 ]);
}

// TODO: Test: Large pattern (>4 GiB) + view past that with edits

// Add enormous pattern of 10 GiB, seek to it, insert data, test undo-redo
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0011");
    
    scope PieceV2DocumentEditor e = new PieceV2DocumentEditor();
}


/// Common tests
unittest
{
    import backend.base : editorTests;
    editorTests!PieceV2DocumentEditor();
}