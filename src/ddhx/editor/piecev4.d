/// Editor backend implementing a Piece List over a flat, cache-friendly
/// index, with optional reader-writer locking for multi-threaded clients.
///
/// Design notes (differences from piecev3):
///
/// The piece table lives in two parallel arrays instead of a tree of nodes.
/// `ends` holds the exclusive end offset of every piece and is the only
/// array touched while locating a position: eight offsets per 64-byte cache
/// line, walked by binary search, instead of a pointer chase over scattered
/// red-black nodes. The piece metadata it indexes sits in a second, colder
/// array, and every edit is a single splice: memmove the tail, then add the
/// size delta to the following end offsets. piecev3 had to remove and
/// re-insert every following node to do the same.
///
/// Pieces store offsets relative to their own source only, never an
/// absolute document offset, so `ends` alone describes the document layout.
/// An operation is therefore reversed by splicing its old pieces back in,
/// with no cumulative bookkeeping left to go stale.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.editor.piecev4;

import core.stdc.string : memcpy, memset, memmove;
import core.sync.rwmutex : ReadWriteMutex;

import std.algorithm.comparison : min, max;

import os.mem : syspagesize;

import ddhx.editor.base : IDocumentEditor, IDirtyRange, DirtyRegion, PieceInfo;
import ddhx.document.base : IDocument, DocCaps;
import ddhx.platform : assertion;
import ddhx.logger;

import messages : MSG_DOCUMENT_FIXED_SIZE;

// Other interesting sources:
// - temp: Temporary file if an edit is too large to fit in memory (past a threshold)
private
enum Source : ubyte
{
    source,     /// Original source document
    buffer,     /// In-memory buffer
    pattern,    /// Repeated pattern
    document,   /// File document
}

/// Represents a single piece in the Piece Table.
///
/// Kept at 32 bytes so two pieces share a cache line. `position` means
/// "offset within my own source": a file offset for source and document
/// pieces, an offset into the add buffer for buffer pieces, and a phase
/// within the cycle for pattern pieces.
private
struct Piece
{
    union
    {
        const(void) *data;  /// Buffer or pattern bytes.
        IDocument doc;      /// Document source.
    }
    long position;
    long size;
    uint patlen;    /// Pattern cycle length, only with Source.pattern.
    Source source;

    static Piece makesource(long position, long size)
    {
        Piece piece     = Piece.init;
        piece.source    = Source.source;
        piece.position  = position;
        piece.size      = size;
        return piece;
    }

    // This does not copy any actual data from the pointer, just the fields
    static Piece makebuffer(const(void) *data, long size, long skip = 0)
    {
        Piece piece     = Piece.init;
        piece.source    = Source.buffer;
        piece.position  = skip;
        piece.size      = size;
        piece.data      = data;
        return piece;
    }

    static Piece makepattern(long len, const(void) *data, size_t datlen)
    {
        assertion(datlen <= uint.max, "datlen <= uint.max");
        Piece piece     = Piece.init;
        piece.source    = Source.pattern;
        piece.position  = 0;
        piece.size      = len;
        piece.data      = data;
        piece.patlen    = cast(uint)datlen;
        return piece;
    }

    static Piece makefile(long len, IDocument doc)
    {
        Piece piece     = Piece.init;
        piece.source    = Source.document;
        piece.position  = 0;
        piece.size      = len;
        piece.doc       = doc;
        return piece;
    }
}

/// Return a copy of this piece skipping its first `skip` bytes and keeping
/// `keep` of them.
private
Piece trim(Piece piece, long skip, long keep)
{
    piece.size = keep;
    if (skip == 0)
        return piece;

    final switch (piece.source) {
    case Source.source, Source.buffer, Source.document:
        piece.position += skip;
        break;
    case Source.pattern:
        // Modulo in 64-bit first: huge pattern pieces can be split past
        // 4 GiB, and the resulting in-cycle offset always fits the cycle
        piece.position = (piece.position + skip) % piece.patlen;
        break;
    }
    return piece;
}

/// Piece table as a structure of arrays.
///
/// `ends[i]` is the exclusive document offset where piece `i` stops, so a
/// piece covers `[ends[i-1], ends[i])` and the document size is the last
/// end. Searching only reads `ends`, which is why it is kept apart from the
/// metadata it indexes.
private
struct PieceTable
{
    // NOTE: If we're hitting performance plateau,
    //       fenwick/offset-base scheme might be worth exploring, not a tree.
    //       Likely as an enhancement to v4 than its own module.
    long[] ends;
    Piece[] pieces;
    private size_t count;

    size_t length() const { return count; }

    /// Document size, i.e. the end of the last piece.
    long total() const { return count ? ends[count - 1] : 0; }

    /// Document offset where piece `i` starts.
    long start(size_t i) const { return i ? ends[i - 1] : 0; }

    void clear()
    {
        // Drop references so the GC can reclaim buffers and documents that
        // only the discarded pieces held
        if (count)
            memset(pieces.ptr, 0, count * Piece.sizeof);
        count = 0;
    }

    /// Index of the first piece ending after `offset`, or length() when the
    /// offset is at or past the end of the document.
    size_t find(long offset) const
    {
        size_t lo;
        size_t hi = count;
        while (lo < hi)
        {
            size_t mid = lo + ((hi - lo) / 2);
            if (ends[mid] <= offset)
                lo = mid + 1;
            else
                hi = mid;
        }
        return lo;
    }

    /// Replace pieces `[first, last)` with `items`, fixing up the end
    /// offsets of everything that follows.
    void splice(size_t first, size_t last, scope const(Piece)[] items)
    {
        long base = start(first);
        long oldspan = start(last) - base;
        long newspan;
        foreach (ref const(Piece) piece; items)
            newspan += piece.size;

        size_t oldn = last - first;
        if (items.length != oldn)
            reslot(first, oldn, items.length);

        long cumulative = base;
        foreach (i, ref const(Piece) piece; items)
        {
            cumulative += piece.size;
            pieces[first + i] = piece;
            ends[first + i] = cumulative;
        }

        long delta = newspan - oldspan;
        if (delta == 0)
            return;
        for (size_t i = first + items.length; i < count; ++i)
            ends[i] += delta;
    }

    /// Make room for `newn` entries where `oldn` used to be, shifting the
    /// tail of both arrays.
    private void reslot(size_t at, size_t oldn, size_t newn)
    {
        size_t tail = count - (at + oldn);
        size_t newcount = count - oldn + newn;

        if (newcount > ends.length)
        {
            size_t capacity = max(newcount, ends.length * 2, 16);
            ends.length = capacity;
            pieces.length = capacity;
        }

        if (tail)
        {
            memmove(ends.ptr   + at + newn, ends.ptr   + at + oldn, tail * long.sizeof);
            memmove(pieces.ptr + at + newn, pieces.ptr + at + oldn, tail * Piece.sizeof);
        }

        // Vacated slots keep stale references alive otherwise
        if (newcount < count)
            memset(pieces.ptr + newcount, 0, (count - newcount) * Piece.sizeof);

        count = newcount;
    }
}

/// Operating type.
private
enum OperationType
{
    insert, replace, remove,
}

/// Represents an operation for the history stack (undo-redo).
///
/// An operation is a splice: at piece index `index`, `removed` became
/// `added`. Applying and reversing it are the same call with the two piece
/// lists swapped.
private
struct Operation
{
    /// Starting position of the change.
    long position;
    /// Affected area in size (bytes)
    long affected;
    /// Operation type.
    /// Kind of required since a replace operation can be placed at the end
    /// of the document, increasing the document size.
    OperationType type;
    /// Piece index where the splice starts.
    size_t index;
    /// Pieces the operation put in place.
    Piece[] added;
    /// Pieces the operation took out.
    Piece[] removed;
}

/// Read `dest.length` bytes of a piece, starting `offset` bytes into it.
///
/// Documents may read short when a piece claims more data than its source
/// holds (e.g., the file shrank); memory sources always fill the request.
private
size_t materialize(IDocument basedoc, ref Piece piece, long offset, ubyte[] dest)
{
    final switch (piece.source) {
    case Source.source:
        return basedoc.readAt(piece.position + offset, dest).length;
    case Source.document:
        return piece.doc.readAt(piece.position + offset, dest).length;
    case Source.buffer:
        memcpy(dest.ptr, piece.data + piece.position + offset, dest.length);
        return dest.length;
    case Source.pattern:
        if (piece.patlen == 1) // One byte pattern
        {
            memset(dest.ptr, *cast(ubyte*)piece.data, dest.length);
            return dest.length;
        }
        // Multi-byte pattern: start at the right phase of the cycle
        size_t phase = cast(size_t)((piece.position + offset) % piece.patlen);
        size_t done;
        while (done < dest.length)
        {
            size_t w = min(dest.length - done, piece.patlen - phase);
            memcpy(dest.ptr + done, piece.data + phase, w);
            done += w;
            phase = 0; // Only the first copy is misaligned
        }
        return dest.length;
    }
}

/// Document editor implementing a Piece List over a flat index with
/// command history.
class PieceV4DocumentEditor : IDocumentEditor
{
    /// New document editor with a new empty buffer.
    /// Params: threadsafe = If set, guards the editor with a reader-writer lock.
    this(bool threadsafe = false)
    {
        addbuf.setup(syspagesize() * 16);
        threadSafe(threadsafe);
    }

    /// Enable or disable the reader-writer lock guarding this editor.
    ///
    /// Off by default: a single-threaded client pays nothing for it. With it
    /// on, readers (view, size, dirty regions) run concurrently while every
    /// mutation takes the write lock, so several clients can work on one
    /// document.
    ///
    /// Set this before handing the editor to other threads; toggling it
    /// while they run is itself a race.
    /// Params: v = If set, enables locking.
    /// Returns: Editor instance.
    final typeof(this) threadSafe(bool v)
    {
        // NOTE: ReadWriteMutex over Mutex
        //       Measured with `ddhx-benchmark locks` (4 threads, 5000 ops
        //       each, 1 MiB document), comparing a plain Mutex against both
        //       ReadWriteMutex policies around these same critical sections:
        //
        //       File document, PREFER_WRITERS vs Mutex:
        //         0% writes:  ~8 ms vs ~35 ms
        //        10% writes: ~12 ms vs ~32 ms
        //        50% writes: ~19 ms vs ~25 ms
        //        90% writes: ~20 ms vs ~19 ms
        //
        //       Parallel pread() is what buys this, so the win shrinks to
        //       nothing as writes take over, and on Windows it never appears:
        //       FileDocument.readAt serializes itself there. A Mutex does win
        //       on an in-memory
        //       document, where a read is a short memcpy and the rwmutex
        //       bookkeeping costs more than the work it guards, but by well
        //       under a microsecond per operation. Editing a file is the case
        //       worth optimizing.
        //
        //       PREFER_READERS lost everywhere once writes existed (writers
        //       starve, up to twice as slow as PREFER_WRITERS).
        if (v)
        {
            if (rwlock is null)
                rwlock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        }
        else
            rwlock = null;
        return this;
    }
    /// Ditto.
    /// Returns: true when the editor is guarded by its reader-writer lock.
    final bool threadSafe()
    {
        return rwlock !is null;
    }

    /// Enable or disable coalescing of consecutive same-type operations.
    /// Params: v = If set, enables coalescing.
    void coalescing(bool v)
    {
        lockWrite(); scope(exit) unlockWrite();
        _coalescing = v;
    }

    /// Returns an input range over dirty (non-source) regions.
    /// Params: includeDisplaced = Include displaced pieces.
    /// Returns: A range of dirty (modified) regions.
    IDirtyRange dirtyRegions(bool includeDisplaced = false)
    {
        lockRead(); scope(exit) unlockRead();
        return new PieceV4DirtyRange(table, basedoc, includeDisplaced);
    }

    /// Returns lightweight piece metadata for dirty/displaced pieces.
    /// Params: includeDisplaced = Include displaced pieces.
    /// Returns: A range of dirty (modified) regions.
    PieceInfo[] dirtyPieceInfos(bool includeDisplaced = false)
    {
        lockRead(); scope(exit) unlockRead();
        return dirtyPieceInfosImpl(includeDisplaced);
    }

    /// Open document.
    /// Params: doc = IDocument-based document.
    /// Returns: Editor instance.
    typeof(this) open(IDocument doc)
    {
        lockWrite(); scope(exit) unlockWrite();

        invalidateCoalesce();
        long docsize = doc.size();
        basedoc = doc;

        // Derive editing policy from the document's capabilities
        int dcaps = doc.caps();
        _can_resize = (dcaps & DocCaps.resize) != 0;
        _track_history = (dcaps & DocCaps.stable) != 0;
        _edited = false;

        // Clear history
        history.length = 0;
        history_index = history_saved = 0;

        // New table
        table.clear();
        // Avoids a zero-sized piece, violating checks
        if (docsize > 0)
            table.splice(0, 0, [ Piece.makesource(0, docsize) ]);

        return this;
    }

    /// Currently opened document.
    /// Returns: Document instance, or null when none is opened.
    IDocument document()
    {
        lockRead(); scope(exit) unlockRead();
        return basedoc;
    }

    /// Close document.
    ///
    /// Make sure to save it before closing!
    void close()
    {
        lockWrite(); scope(exit) unlockWrite();

        invalidateCoalesce();
        basedoc = null;

        // reset internals
        table.clear();
        history.length = 0;
        history_index = history_saved = 0;
        addbuf.clear();
        _can_resize = _track_history = true;
        _edited = false;
    }

    /// Total size of document in bytes with edits.
    /// Returns: Size of current document.
    long size()
    {
        lockRead(); scope(exit) unlockRead();
        return table.total();
    }

    void markSaved()
    {
        lockWrite(); scope(exit) unlockWrite();
        history_saved = history_index;
        _edited = false;
    }

    /// Prepare the editor for an in-place save of its source document.
    ///
    /// Converts every source reference, current or in undo/redo history,
    /// whose read range the save would overwrite (or truncate away) into
    /// an in-memory buffer reference. Once done, the save cannot
    /// invalidate anything the editor still points at: remaining source
    /// references only read file ranges the save leaves untouched, so
    /// pieces can be written in any order and history stays usable.
    /// Returns: true when references were preserved; false on failure.
    bool prepareInplaceSave()
    {
        lockWrite(); scope(exit) unlockWrite();

        // A save is a natural coalescing barrier
        invalidateCoalesce();

        // Without a document, there are no source references to preserve
        if (basedoc is null)
            return true;

        // Collect the file ranges the save will overwrite, as [start,end):
        // write ranges of dirty/displaced pieces, and the truncated tail
        long[2][] written;
        foreach (ref info; dirtyPieceInfosImpl(true))
            written ~= [ info.logicalPos, info.logicalPos + info.size ];
        written ~= [ table.total(), long.max ];

        // Sort and merge into disjoint ranges for binary searching
        import std.algorithm.sorting : sort;
        sort!((a, b) => a[0] < b[0])(written);
        long[2][] merged = [ written[0] ];
        foreach (range; written[1 .. $])
        {
            if (range[0] <= merged[$ - 1][1])
                merged[$ - 1][1] = max(merged[$ - 1][1], range[1]);
            else
                merged ~= range;
        }

        // True if [start, end) intersects any written range.
        // Ranges are disjoint and sorted, so only the last range starting
        // before end can overlap.
        bool endangered(long start, long end)
        {
            size_t lo, hi = merged.length;
            while (lo < hi)
            {
                size_t mid = (lo + hi) / 2;
                if (merged[mid][0] < end)
                    lo = mid + 1;
                else
                    hi = mid;
            }
            return lo > 0 && merged[lo - 1][1] > start;
        }

        // Stashed copies keyed by (position, size): the same range is
        // typically referenced by both a tree piece and its history copy,
        // so read and store it only once
        const(void)*[long[2]] stashed;
        bool failed;

        // Convert an endangered source piece to a buffer piece.
        void retarget(ref Piece piece)
        {
            if (piece.source != Source.source)
                return;
            if (endangered(piece.position, piece.position + piece.size) == false)
                return;

            // Cannot address this much memory (32-bit platforms)
            if (cast(ulong)piece.size > size_t.max)
            {
                failed = true;
                return;
            }

            long[2] key = [ piece.position, piece.size ];
            const(void)* data;
            if (const(void)** existing = key in stashed)
            {
                data = *existing;
            }
            else
            {
                // Copy the endangered range out of the file. A short read
                // (file shrank externally) leaves the tail zeroed, which
                // view() would have truncated anyway.
                ubyte[] copy; copy.length = cast(size_t)piece.size;
                basedoc.readAt(piece.position, copy);
                data = copy.ptr;
                stashed[key] = data;
            }

            piece = Piece.makebuffer(data, piece.size);
        }

        foreach (i; 0 .. table.length)
            retarget(table.pieces[i]);

        // History operations, in both undo and redo directions
        foreach (ref Operation op; history)
        {
            foreach (ref Piece piece; op.added)
                retarget(piece);
            foreach (ref Piece piece; op.removed)
                retarget(piece);
        }

        return failed == false;
    }

    ubyte[] view(long position, void* buffer, size_t size)
    {
        lockRead(); scope(exit) unlockRead();
        return viewImpl(position, (cast(ubyte*)buffer)[0..size]);
    }

    ubyte[] view(long position, ubyte[] buffer)
    {
        lockRead(); scope(exit) unlockRead();
        return viewImpl(position, buffer);
    }

    bool edited()
    {
        lockRead(); scope(exit) unlockRead();

        // Direct mode: no history to compare against, use the edit flag
        if (_track_history == false)
            return _edited;
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
        lockWrite(); scope(exit) unlockWrite();
        log("REMOVE pos=%d len=%u", position, len);

        if (_can_resize == false)
            throw new Exception(MSG_DOCUMENT_FIXED_SIZE);

        // Nothing to remove; do not record coalescing state for a no-op,
        // or a later remove could coalesce with an unrelated operation
        if (table.total() == 0)
        {
            invalidateCoalesce();
            return;
        }

        if (canCoalesce(OperationType.remove, position, len, null))
        {
            reverseOperation(history[--history_index]);
            // Forward delete removes at the same position (bytes shift
            // left), backward delete ends where the last one started; both
            // end up removing one combined run from `position`
            long combined = _coalesce.size + len;
            removeImpl(position, combined);
            updateCoalesceState(OperationType.remove, position, combined, null);
        }
        else
        {
            removeImpl(position, len);
            updateCoalesceState(OperationType.remove, position, len, null);
        }
    }

    /// Replace with new data at this position.
    /// Params:
    ///     position = Base position.
    ///     data = Pointer to data.
    ///     len = Length of data.
    /// Throws: When document is fixed-size and operation makes it grow.
    void replace(long position, const(void)* data, size_t len)
    in (position >= 0, "position >= 0")
    in (data != null, "data != NULL")
    in (len > 0,  "len > 0")
    {
        lockWrite(); scope(exit) unlockWrite();
        log("REPLACE pos=%d len=%u data=%s", position, len, data);

        // A replace ending past EOF grows the document
        if (_can_resize == false && position + len > table.total())
            throw new Exception(MSG_DOCUMENT_FIXED_SIZE);

        void* newbuf = addbuf.add(data, len);

        if (canCoalesce(OperationType.replace, position, len, newbuf))
        {
            reverseOperation(history[--history_index]);
            long combined = _coalesce.size + len;
            replacePiece(_coalesce.position, Piece.makebuffer(_coalesce.bufferStart, combined));
            updateCoalesceState(OperationType.replace, _coalesce.position, combined, _coalesce.bufferStart);
        }
        else
        {
            replacePiece(position, Piece.makebuffer(newbuf, len));
            updateCoalesceState(OperationType.replace, position, len, newbuf);
        }
    }

    /// Replace data using a pattern.
    /// Params:
    ///     position = Base position.
    ///     len = Length that the pattern will affect.
    ///     data = Pattern data.
    ///     datlen = Pattern data length.
    /// Throws: When document is fixed-size and operation makes it grow.
    void patternReplace(long position, long len, const(void) *data, size_t datlen)
    in (position >= 0, "position >= 0")
    in (len > 0, "len > 0")
    in (data != null, "data != NULL")
    in (datlen > 0, "datlen > 0")
    {
        lockWrite(); scope(exit) unlockWrite();
        invalidateCoalesce();
        log("REPLACE PATTERN pos=%d len=%d data=%s datlen=%u", position, len, data, datlen);

        // A replace ending past EOF grows the document
        if (_can_resize == false && position + len > table.total())
            throw new Exception(MSG_DOCUMENT_FIXED_SIZE);

        replacePiece(position, Piece.makepattern(len, addbuf.add(data, datlen), datlen));
    }

    /// Replace data using a document.
    /// Params:
    ///     position = Base position.
    ///     doc = Document (file, etc.)
    /// Throws: When document is fixed-size and operation makes it grow.
    void fileReplace(long position, IDocument doc)
    in (position >= 0, "position >= 0")
    in (doc !is null, "doc !is null")
    {
        lockWrite(); scope(exit) unlockWrite();
        invalidateCoalesce();
        log("REPLACE FILE pos=%d", position);

        // A replace ending past EOF grows the document
        if (_can_resize == false && position + doc.size() > table.total())
            throw new Exception(MSG_DOCUMENT_FIXED_SIZE);
        replacePiece(position, Piece.makefile(doc.size(), doc));
    }

    /// Insert new data at this position
    /// Params:
    ///     position = Base position.
    ///     data = Data pointer.
    ///     len = Length of data.
    /// Throws: When document is fixed-size and operation makes it grow.
    void insert(long position, const(void)* data, size_t len)
    in (position >= 0, "position >= 0")
    in (data != null, "data != NULL")
    in (len > 0, "len > 0")
    {
        lockWrite(); scope(exit) unlockWrite();
        log("INSERT pos=%d len=%u data=%s", position, len, data);

        if (_can_resize == false)
            throw new Exception(MSG_DOCUMENT_FIXED_SIZE);

        void* newbuf = addbuf.add(data, len);

        if (canCoalesce(OperationType.insert, position, len, newbuf))
        {
            reverseOperation(history[--history_index]);
            long combined = _coalesce.size + len;
            insertPiece(_coalesce.position, Piece.makebuffer(_coalesce.bufferStart, combined));
            updateCoalesceState(OperationType.insert, _coalesce.position, combined, _coalesce.bufferStart);
        }
        else
        {
            insertPiece(position, Piece.makebuffer(newbuf, len));
            updateCoalesceState(OperationType.insert, position, len, newbuf);
        }
    }

    /// Insert data using a pattern.
    /// Params:
    ///     position = Base position.
    ///     len = Length that the pattern will affect.
    ///     data = Pattern data.
    ///     datlen = Pattern data length.
    /// Throws: When document is fixed-size and operation makes it grow.
    void patternInsert(long position, long len, const(void) *data, size_t datlen)
    in (position >= 0, "position >= 0")
    in (len > 0, "len > 0")
    in (data != null, "data != NULL")
    in (datlen > 0, "datlen > 0")
    {
        lockWrite(); scope(exit) unlockWrite();
        invalidateCoalesce();
        log("INSERT PATTERN pos=%d len=%d data=%s datlen=%u", position, len, data, datlen);

        if (_can_resize == false)
            throw new Exception(MSG_DOCUMENT_FIXED_SIZE);

        insertPiece(position, Piece.makepattern(len, addbuf.add(data, datlen), datlen));
    }

    /// Insert data using a document.
    /// Params:
    ///     position = Base position.
    ///     doc = Document (file, etc.)
    /// Throws: When document is fixed-size and operation makes it grow.
    void fileInsert(long position, IDocument doc)
    in (position >= 0, "position >= 0")
    in (doc !is null, "doc !is null")
    {
        lockWrite(); scope(exit) unlockWrite();
        invalidateCoalesce();
        log("INSERT FILE pos=%d", position);

        if (_can_resize == false)
            throw new Exception(MSG_DOCUMENT_FIXED_SIZE);
        insertPiece(position, Piece.makefile(doc.size(), doc));
    }

    /// Undo last modification.
    /// Returns: Suggested position of the cursor for this modification.
    long undo()
    {
        lockWrite(); scope(exit) unlockWrite();
        invalidateCoalesce();
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
        lockWrite(); scope(exit) unlockWrite();
        invalidateCoalesce();
        log("REDO Hi=%u", history_index);

        if (history_index >= history.length)
            return -1;

        Operation op = history[history_index++];
        applyOperation( op );
        return op.position + op.affected;
    }

private:
    /// The piece table, flat and searched by binary search.
    PieceTable table;

    /// History of operations.
    ///
    /// When an insert, replace, or remove operation is performed, its operation
    /// is saved here.
    ///
    /// Opening a document as its base does not count as an operation, but could
    /// be, if explicitly stated as an operation type. But generally, no, it's
    /// nice to undo without having to worry unloading the document by accident.
    Operation[] history;
    size_t history_index;   /// Current history index
    size_t history_saved;   /// History index when last saved

    /// If piece coalescing is enabled.
    bool _coalescing = true; // Enabled by default, important for tests!

    /// Document allows changing size (derived from DocCaps.resize).
    bool _can_resize = true;
    /// Document is stable, so history is recorded (derived from
    /// DocCaps.stable). Without it, the editor runs in direct mode:
    /// edits overlay the live medium and cannot be undone.
    bool _track_history = true;
    /// Pending edits flag when history is not tracked.
    bool _edited;

    /// Source document to apply edits on.
    ///
    /// Nullable.
    IDocument basedoc;

    /// Editor lock, null when the editor is not thread-safe.
    ReadWriteMutex rwlock;

    void lockRead()    { if (rwlock) rwlock.reader().lock(); }
    void unlockRead()  { if (rwlock) rwlock.reader().unlock(); }
    void lockWrite()   { if (rwlock) rwlock.writer().lock(); }
    void unlockWrite() { if (rwlock) rwlock.writer().unlock(); }

    /// Coalescing state for combining consecutive same-type operations.
    struct CoalesceState
    {
        bool valid;
        OperationType type;
        long position;              /// Start of coalesced region
        long size;                  /// Total size of coalesced region
        const(ubyte)* bufferStart;  /// Start of data in the add buffer (null for remove)
    }
    CoalesceState _coalesce;

    void invalidateCoalesce()
    {
        _coalesce.valid = false;
    }

    bool canCoalesce(OperationType type, long position, long len, const(void)* newBufferPtr)
    {
        if (!_coalescing || !_coalesce.valid)
            return false;
        if (_coalesce.type != type)
            return false;
        if (history_index == 0)
            return false;
        // Don't coalesce when at save point, otherwise edited() would
        // return false after the coalesced op replaces the entry at h_i-1.
        if (history_index == history_saved)
            return false;

        final switch (type)
        {
        case OperationType.insert:
        case OperationType.replace:
            // Forward adjacency: new position is right after the coalesced region
            if (position != _coalesce.position + _coalesce.size)
                return false;
            // Buffer contiguity: new data immediately follows old data in
            // the add buffer. A block boundary breaks this, which only
            // costs an extra history entry.
            if (cast(const(ubyte)*)newBufferPtr != _coalesce.bufferStart + _coalesce.size)
                return false;
            return true;
        case OperationType.remove:
            // Forward delete: removing at the same position (bytes shift left)
            if (position == _coalesce.position)
                return true;
            // Backward delete: new removal ends where old removal started
            if (position + len == _coalesce.position)
                return true;
            return false;
        }
    }

    void updateCoalesceState(OperationType type, long position, long size, const(void)* bufferStart)
    {
        _coalesce.valid = true;
        _coalesce.type = type;
        _coalesce.position = position;
        _coalesce.size = size;
        _coalesce.bufferStart = cast(const(ubyte)*)bufferStart;
    }

    ubyte[] viewImpl(long position, ubyte[] buffer)
    {
        if (table.length == 0 || buffer.length == 0)
            return [];

        log("VIEW Hi=%u Hc=%u", history_index, history.length);

        size_t bi; /// buffer index (for slicing)
        for (size_t i = table.find(position); i < table.length; ++i)
        {
            // View buffer is full
            if (bi >= buffer.length)
                break;

            long lpos = position + bi; // logical position
            long piece_start = table.start(i);
            long piece_end   = table.ends[i];

            // Calculate how much to read from this piece
            long offset = max(0, lpos - piece_start); // clamp to zero
            long available = piece_end - max(lpos, piece_start);
            // Assumes view buffer is ... under 2 GiB
            size_t to_read = cast(size_t)min(available, buffer.length - bi);

            size_t got = materialize(basedoc, table.pieces[i], offset,
                buffer[bi .. bi + to_read]);
            bi += got;

            // Short read: return only what could actually be read
            if (got < to_read)
                break;
        }

        // Soft assert to be able to catch details
        log("bl=%u bi=%u", buffer.length, bi);
        assertion(bi <= buffer.length, "bi <= buffer.length");
        return buffer[0..bi];
    }

    PieceInfo[] dirtyPieceInfosImpl(bool includeDisplaced)
    {
        PieceInfo[] result;
        foreach (i; 0 .. table.length)
        {
            long logicalPos = table.start(i);
            Piece piece = table.pieces[i];
            bool dirty = piece.source != Source.source;
            if (!dirty && includeDisplaced)
                dirty = logicalPos != piece.position;
            if (dirty)
            {
                long srcOff = (piece.source == Source.source) ? piece.position : -1;
                result ~= PieceInfo(logicalPos, piece.size, srcOff);
            }
        }
        return result;
    }

    void removeImpl(long position, long len)
    {
        long total = table.total();

        // Nothing to remove
        if (total == 0)
            return;

        // Editors should avoid deleting nothing at EOF...
        assertion(position < total, "position < size");

        // Clamp removal to actual document size
        long removed = min(len, total - position);
        // End position of removal
        long end = position + removed;

        // Pieces [first, last) overlap the removed region. `last` is derived
        // from end-1 so a piece stopping exactly at `end` stays out.
        size_t first = table.find(position);
        size_t last  = table.find(end - 1) + 1;

        Operation op = Operation(position, removed, OperationType.remove, first);
        op.removed = table.pieces[first .. last].dup;

        // If the first piece extends before the removal, keep its left portion
        long head = table.start(first);
        if (head < position)
            op.added ~= trim(table.pieces[first], 0, position - head);

        // If the last piece extends after the removal, keep its right portion
        long tail_start = table.start(last - 1);
        long tail_end = table.ends[last - 1];
        if (tail_end > end)
            op.added ~= trim(table.pieces[last - 1], end - tail_start, tail_end - end);

        applyOperation(op);
        addOperation(op);
    }

    // This piece is inserted from this position
    void insertPiece(long position, Piece piece)
    {
        assertion(position <= table.total(), "position <= size");

        // Only the first piece ending after the position can contain it.
        // Pieces are contiguous, so its start can only be at or before the
        // position; a boundary insertion (start == position) needs no split,
        // and an EOF insertion finds no piece at all.
        size_t at = table.find(position);

        Operation op = Operation(position, piece.size, OperationType.insert, at);
        if (at < table.length && table.start(at) < position)
        {
            // Insertion point is INSIDE this piece: split it in two
            Piece target = table.pieces[at];
            long offset = position - table.start(at);
            op.removed = [ target ];
            op.added = [ trim(target, 0, offset), piece, trim(target, offset, target.size - offset) ];
        }
        else // Inserting at a boundary (SOF, EOF, or between pieces)
        {
            op.added = [ piece ];
        }

        applyOperation(op);
        addOperation(op);
    }

    // This piece replaces data from this position
    void replacePiece(long position, Piece piece)
    {
        long total = table.total();

        // Replacing past EOF would inflate the logical size while leaving
        // a hole with no piece covering it
        assertion(position <= total, "position <= size");

        long overwritten = min(piece.size, total - position);
        long end = position + overwritten;

        size_t first = table.find(position);
        size_t last  = overwritten > 0 ? table.find(end - 1) + 1 : first;

        Operation op = Operation(position, piece.size, OperationType.replace, first);
        op.removed = table.pieces[first .. last].dup;

        // Keep left portion if it exists (before replacement starts)
        if (first < last)
        {
            long head = table.start(first);
            if (head < position)
                op.added ~= trim(table.pieces[first], 0, position - head);
        }

        op.added ~= piece;

        // Keep right portion if it exists (after replacement ends)
        if (first < last)
        {
            long tail_start = table.start(last - 1);
            long tail_end = table.ends[last - 1];
            if (tail_end > end)
                op.added ~= trim(table.pieces[last - 1], end - tail_start, tail_end - end);
        }

        applyOperation(op);
        addOperation(op);
    }

    /// Apply an operation: its removed pieces become its added pieces.
    void applyOperation(ref Operation op)
    {
        log("APPLY %s at %u: -%u +%u", op.type, op.index, op.removed.length, op.added.length);
        table.splice(op.index, op.index + op.removed.length, op.added);
    }

    /// Reverse an operation: its added pieces become its removed pieces.
    void reverseOperation(ref Operation op)
    {
        log("REVERSE %s at %u: -%u +%u", op.type, op.index, op.added.length, op.removed.length);
        table.splice(op.index, op.index + op.added.length, op.removed);
    }

    /// Add operation to history list
    void addOperation(ref Operation op)
    {
        debug try
        {
            ensureConsistency();
        }
        catch (Exception ex)
        {
            if (logEnabled())
                printTable("CURRENT");
            throw ex;
        }

        // Direct mode (unstable document): the operation is applied to the
        // piece table but not recorded, as the medium changes outside our
        // control and old references would be meaningless to undo to.
        if (_track_history == false)
        {
            _edited = true;
            return;
        }

        if (history_index < history.length) // Branching: discard stale redo tail
        {
            // If the save point lives in the discarded operations, the saved
            // state is no longer reachable, so edited() must stay true until
            // the next markSaved().
            if (history_saved > history_index)
                history_saved = size_t.max;
            history.length = history_index;
        }
        history ~= op;
        history_index++;
    }

    /// Ensure pieces are consistent.
    ///
    /// This is automatically called in debug builds after every operation,
    /// from addOperation, so history can be printed more cleanly.
    debug void ensureConsistency()
    {
        import std.conv : text;
        long previous;
        // 'assertion' msg is lazy evaluated, so feel free to use text(...)
        foreach (i; 0 .. table.length)
        {
            // Piece size must be set
            assertion(table.pieces[i].size > 0,
                text("Piece size unset (piece[", i, "])"));

            // Check for gap introduced by piece size vs. indexed end offset
            long expected = previous + table.pieces[i].size;
            assertion(table.ends[i] == expected,
                text("Gap found (piece[", i, "]): ", table.ends[i], " != ", expected));

            previous = table.ends[i];
        }
    }

    debug void printTable(string name)
    {
        // Messy but whatever
        log("DUMPING %s PIECES --------------------", name);
        foreach (i; 0 .. table.length)
        {
            with (table.pieces[i])
            log("Piece[%u](%10s, %10d, %10d)(%d)", i, source, position, size, table.ends[i]);
        }
    }

    //
    // Add buffer
    //

    AddBuffer addbuf;
}

/// Append-only store for inserted and replaced bytes.
///
/// Data is handed out as raw pointers held by pieces, so blocks are
/// allocated once and never resized: a growing buffer must not move bytes
/// another thread is reading.
private
struct AddBuffer
{
    private ubyte[][] blocks;
    private size_t used;        /// Bytes used in the last block
    private size_t blocksize;

    void setup(size_t granularity)
    {
        blocksize = granularity;
    }

    void clear()
    {
        blocks = null;
        used = 0;
    }

    /// Copy data in and return where it landed.
    void* add(const(void) *data, size_t len)
    {
        if (blocks.length == 0 || len > blocks[$ - 1].length - used)
        {
            blocks ~= new ubyte[max(len, blocksize)];
            used = 0;
        }

        void *ptr = blocks[$ - 1].ptr + used;
        memcpy(ptr, data, len);
        used += len;
        return ptr;
    }
}

/// Dirty range implementation for PieceV4.
///
/// The dirty pieces are snapshotted on construction: the range outlives the
/// call that made it, and the piece table may be edited (by another thread,
/// or by the same one) before it is drained.
private class PieceV4DirtyRange : IDirtyRange
{
    this(ref PieceTable table, IDocument basedoc, bool includeDisplaced)
    {
        this._basedoc = basedoc;
        this._buf.length = BUFFER_SIZE;

        foreach (i; 0 .. table.length)
        {
            Piece piece = table.pieces[i];
            long logical = table.start(i);
            // Source pieces are dirty only when displaced, i.e. their
            // logical position no longer matches their file offset
            bool dirty = piece.source != Source.source ||
                (includeDisplaced && logical != piece.position);
            if (dirty)
                _pieces ~= DirtyPiece(logical, piece);
        }

        if (_pieces.length)
            materializeChunk();
    }

    bool empty()
    {
        return _index >= _pieces.length;
    }

    DirtyRegion front()
    {
        return _current;
    }

    void popFront()
    {
        // If current piece has more data to yield, continue chunking
        _offset += _chunk;
        if (_offset >= _pieces[_index].piece.size)
        {
            _index++;
            _offset = 0;
        }
        if (empty())
            return;
        materializeChunk();
    }

private:
    enum BUFFER_SIZE = 16 * 1024;

    struct DirtyPiece
    {
        long logical;
        Piece piece;
    }

    DirtyPiece[] _pieces;
    size_t _index;
    long _offset;       /// Offset within the current piece
    size_t _chunk;      /// Size of the chunk currently yielded

    IDocument _basedoc;
    ubyte[] _buf;
    DirtyRegion _current;

    void materializeChunk()
    {
        long remaining = _pieces[_index].piece.size - _offset;
        size_t chunk = cast(size_t)min(remaining, BUFFER_SIZE);
        _chunk = chunk;

        // Dirty regions feed saving: a short read here means the source
        // shrank underneath us, and writing garbage would corrupt the save
        size_t got = materialize(_basedoc, _pieces[_index].piece,
            _offset, _buf[0..chunk]);
        assertion(got == chunk, "short read while materializing dirty region");

        _current = DirtyRegion(_pieces[_index].logical + _offset, _buf[0..chunk]);
    }
}

/// New empty document
unittest
{
    log("TEST-0001");

    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor();

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

    // Undo (inserts were coalesced into single "hi example" operation)
    assert(e.undo() == 0);
    assert(e.edited() == false);
    assert(e.size() == 0);
    assert(e.view(0, buffer) == []);
    // Redo
    assert(e.redo() == data.length + insert1.length);
    assert(e.edited());
    assert(e.size() == data.length + insert1.length);
    assert(e.view(0, buffer) == data ~ insert1); // "hi example"

    // Undo twice - only 1 coalesced op to undo
    assert(e.undo() == 0);
    assert(e.undo() < 0);

    // Redo twice - only 1 coalesced op to redo
    assert(e.redo() == data.length + insert1.length);
    assert(e.redo() < 0);
}

/// Insert with document
unittest
{
    log("TEST-0002");

    static immutable string data = "hello";
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
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
    log("TEST-0003");

    static immutable string data = "very good string!";
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
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
    log("TEST-0004");

    static immutable string data = "very good string!";
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
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
    static immutable ubyte[] data = [
    //  0   1   2   3   4  5  6   7   8   9
        4,  7,  9, 13, 17, 3, 4,  5, 13, 15, // 0
    ];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
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
    log("TEST-0006");

    static immutable ubyte[] data = [
    //  0   1   2   3   4   5   6   7   8   9
        0,  1,  2,  3,  4,  5,  6,  7,  8,  9, // 0
       10, 11, 12, 13, 14, 15, 16, 17, 18, 19, // 10
       20, 21, 22, 23, 24, 25, 26, 27, 28, 29, // 20
       30, 31, 32, 33, 34, 35, 36, 37, 38, 39, // 30
       40, 41, 42, 43, 44, 45, 46, 47, 48, 49, // 40
    ];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
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
    log("TEST-0007");

    static immutable ubyte[] data = [
    //  0   1   2   3   4   5   6   7   8   9
        0,  1,  2,  3,  4,  5,  6,  7,  8,  9, // 0
       10, 11, 12, 13, 14, 15, 16, 17, 18, 19, // 10
       20, 21, 22, 23, 24, 25, 26, 27, 28, 29, // 20
       30, 31, 32, 33, 34, 35, 36, 37, 38, 39, // 30
       40, 41, 42, 43, 44, 45, 46, 47, 48, 49, // 40
    ];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
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
    log("TEST-0008");

    static immutable ubyte[] data = [
    //  0   1   2   3   4   5   6   7   8   9
        0,  1,  2,  3,  4,  5,  6,  7,  8,  9, // 0
       10, 11, 12, 13, 14, 15, 16, 17, 18, 19, // 10
       20, 21, 22, 23, 24, 25, 26, 27, 28, 29, // 20
       30, 31, 32, 33, 34, 35, 36, 37, 38, 39, // 30
       40, 41, 42, 43, 44, 45, 46, 47, 48, 49, // 40
    ];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
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
    log("TEST-0009");

    static immutable ubyte[] data = [
    //  0   1   2   3   4   5   6   7   8   9
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 0
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 10
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 20
    ];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
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
    log("TEST-0010");

    static immutable ubyte[] data = [
    //  0   1   2   3   4   5   6   7   8   9
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 0
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 10
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0, // 20
    ];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
        new MemoryDocument(data)
    );

    import std.file : remove, write, tempDir, readText;
    import std.path : buildPath;
    import ddhx.document.file : FileDocument;

    ubyte[64] buffer;

    // Replace file
    static immutable piece_replace_0 = "piecev4_replace_0.tmp";
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
    static immutable piece_insert_0 = "piecev4_insert_0.tmp";
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
    log("TEST-0011");

    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor();

    ubyte dd = 0xdd;
    e.replace(0, &dd, ubyte.sizeof);

    e.undo();

    ubyte p = 0;
    e.patternInsert(0, 5, &p, ubyte.sizeof);

    ubyte[10] buf;
    assert(e.view(0, buf) == [ 0,0,0,0,0 ]);
}

// Add enormous pattern of 10 GiB and edit into it
unittest
{
    log("TEST-0012");

    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor();

    enum P0 = 0xda; //    K      M      G
    enum _10GB = 10L * 1024 * 1024 * 1024;
    enum _2GB  =  2L * 1024 * 1024 * 1024;

    // Insert single-byte 10 GiB pattern
    ubyte da = P0;
    e.patternInsert(0, _10GB, &da, ubyte.sizeof);

    // 10 GiB block
    ubyte[10] buf;
    assert(e.view(0, buf)          == [ P0,P0,P0,P0,P0,P0,P0,P0,P0,P0 ]);
    assert(e.view(_10GB - 10, buf) == [ P0,P0,P0,P0,P0,P0,P0,P0,P0,P0 ]);
    assert(e.view(_10GB -  5, buf) == [ P0,P0,P0,P0,P0 ]);
    assert(e.view(_10GB     , buf) == [ ]);

    // Add another 2 GiB pattern
    static immutable string str = "I love you!";
    e.patternInsert(_10GB, _2GB, str.ptr, str.length);
    assert(e.view(_10GB - 10, buf) == [ P0, P0, P0, P0, P0, P0, P0, P0, P0, P0  ]);
    assert(e.view(_10GB -  5, buf) == [ P0, P0, P0, P0, P0, 'I',' ','l','o','v' ]);
    assert(e.view(_10GB     , buf) == [ 'I',' ','l','o','v','e',' ','y','o','u' ]);

    ubyte[] db = [ 'M', 'e', '?' ];
    e.patternReplace(_10GB - 10, 20, db.ptr, db.length);
    assert(e.view(_10GB - 10, buf) == [ 'M','e','?','M','e','?','M','e','?','M' ]);
    assert(e.view(_10GB -  5, buf) == [ '?','M','e','?','M','e','?','M','e','?' ]);
    assert(e.view(_10GB     , buf) == [ 'e','?','M','e','?','M','e','?','M','e' ]);

    //
    ubyte[] dc = [ 'M','a','y','b','e','.','.','.' ];
    e.insert(_10GB - 10, dc.ptr, dc.length);
    assert(e.view(_10GB - 10, buf) == [ 'M','a','y','b','e','.','.','.','M','e' ]);
    assert(e.view(_10GB -  5, buf) == [ '.','.','.','M','e','?','M','e','?','M' ]);
    assert(e.view(_10GB     , buf) == [ '?','M','e','?','M','e','?','M','e','?' ]);
}

/// Common tests
unittest
{
    import ddhx.editor.base : editorTests;
    editorTests!PieceV4DocumentEditor();
}

/// Coalescing: consecutive forward inserts
unittest
{
    log("TEST-0013");

    static immutable ubyte[] data = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
        new MemoryDocument(data)
    );

    ubyte[32] buffer;

    // First insert (not coalesced due to save point guard)
    ubyte a = 0xAA;
    e.insert(5, &a, 1);
    // Second insert (coalesces with first)
    ubyte b = 0xBB;
    e.insert(6, &b, 1);

    assert(e.size() == 12);
    assert(e.view(0, buffer) == [ 0, 1, 2, 3, 4, 0xAA, 0xBB, 5, 6, 7, 8, 9 ]);

    // Single undo should restore original
    e.undo();
    assert(e.size() == 10);
    assert(e.view(0, buffer) == data);
}

/// Coalescing: consecutive forward replaces
unittest
{
    log("TEST-0014");

    static immutable ubyte[] data = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
        new MemoryDocument(data)
    );

    ubyte[32] buffer;

    // First replace
    ubyte a = 0xAA;
    e.replace(3, &a, 1);
    // Second replace (coalesces)
    ubyte b = 0xBB;
    e.replace(4, &b, 1);

    assert(e.size() == 10);
    assert(e.view(0, buffer) == [ 0, 1, 2, 0xAA, 0xBB, 5, 6, 7, 8, 9 ]);

    // Single undo should restore original
    e.undo();
    assert(e.size() == 10);
    assert(e.view(0, buffer) == data);
}

/// Coalescing: forward delete
unittest
{
    log("TEST-0015");

    static immutable ubyte[] data = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
        new MemoryDocument(data)
    );

    ubyte[32] buffer;

    // Forward delete at position 3 twice
    e.remove(3, 1);
    e.remove(3, 1);

    assert(e.size() == 8);
    assert(e.view(0, buffer) == [0, 1, 2, 5, 6, 7, 8, 9]);

    // Single undo should restore original
    e.undo();
    assert(e.size() == 10);
    assert(e.view(0, buffer) == data);
}

/// Coalescing: backward delete
unittest
{
    log("TEST-0016");

    static immutable ubyte[] data = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
        new MemoryDocument(data)
    );

    ubyte[32] buffer;

    // Backward delete (like backspace): delete pos 4, then pos 3
    e.remove(4, 1);
    e.remove(3, 1);

    assert(e.size() == 8);
    assert(e.view(0, buffer) == [0, 1, 2, 5, 6, 7, 8, 9]);

    // Single undo should restore original
    e.undo();
    assert(e.size() == 10);
    assert(e.view(0, buffer) == data);
}

/// Coalescing: non-adjacent breaks coalescing
unittest
{
    log("TEST-0017");

    static immutable ubyte[] data = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
        new MemoryDocument(data)
    );

    ubyte[32] buffer;

    ubyte x = 0xCC;
    e.replace(2, &x, 1);
    // Non-adjacent replace (pos 5 != 2+1)
    ubyte y = 0xDD;
    e.replace(5, &y, 1);

    assert(e.view(0, buffer) == [0, 1, 0xCC, 3, 4, 0xDD, 6, 7, 8, 9]);

    // Two separate undo steps needed
    e.undo();
    assert(e.view(0, buffer) == [0, 1, 0xCC, 3, 4, 5, 6, 7, 8, 9]);
    e.undo();
    assert(e.view(0, buffer) == data);
}

/// Coalescing: type change breaks coalescing
unittest
{
    log("TEST-0018");

    static immutable ubyte[] data = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
        new MemoryDocument(data)
    );

    ubyte[32] buffer;

    ubyte x = 0xCC;
    e.replace(3, &x, 1);
    // Type change: insert instead of replace
    ubyte y = 0xDD;
    e.insert(4, &y, 1);

    assert(e.size() == 11);
    assert(e.view(0, buffer) == [ 0, 1, 2, 0xCC, 0xDD, 4, 5, 6, 7, 8, 9 ]);

    // Two separate undo steps
    e.undo();
    assert(e.size() == 10);
    assert(e.view(0, buffer) == [ 0, 1, 2, 0xCC, 4, 5, 6, 7, 8, 9 ]);
    e.undo();
    assert(e.view(0, buffer) == data);
}

/// Coalescing: undo/redo breaks coalescing
unittest
{
    log("TEST-0019");

    static immutable ubyte[] data = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
        new MemoryDocument(data)
    );

    ubyte[32] buffer;

    ubyte x = 0xAA;
    e.replace(3, &x, 1);
    e.undo();
    e.redo();
    // After undo+redo, coalescing is invalidated
    ubyte y = 0xBB;
    e.replace(4, &y, 1);

    assert(e.view(0, buffer) == [ 0, 1, 2, 0xAA, 0xBB, 5, 6, 7, 8, 9 ]);

    // Two separate undo steps
    e.undo();
    assert(e.view(0, buffer) == [ 0, 1, 2, 0xAA, 4, 5, 6, 7, 8, 9 ]);
    e.undo();
    assert(e.view(0, buffer) == data);
}

/// Coalescing: save point prevents coalescing
unittest
{
    log("TEST-0020");

    static immutable ubyte[] data = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
        new MemoryDocument(data)
    );

    ubyte[32] buffer;

    ubyte x = 0xAA;
    e.replace(3, &x, 1);
    e.markSaved();
    assert(e.edited() == false);
    // Adjacent replace, but save point prevents coalescing
    ubyte y = 0xBB;
    e.replace(4, &y, 1);

    assert(e.edited());
    assert(e.view(0, buffer) == [ 0, 1, 2, 0xAA, 0xBB, 5, 6, 7, 8, 9 ]);

    // Two separate undo steps, with edited() correctness
    e.undo();
    assert(e.edited() == false);
    assert(e.view(0, buffer) == [ 0, 1, 2, 0xAA, 4, 5, 6, 7, 8, 9 ]);
    e.undo();
    assert(e.edited());
    assert(e.view(0, buffer) == data);
}

/// Coalescing: multi-step coalesce (typing "hello" char-by-char)
unittest
{
    log("TEST-0021");

    static immutable ubyte[] data = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
        new MemoryDocument(data)
    );

    ubyte[32] buffer;

    // Type "hello" char-by-char at position 5
    string hello = "hello";
    foreach (i, c; hello)
    {
        ubyte b = cast(ubyte)c;
        e.insert(cast(long)(5 + i), &b, 1);
    }

    assert(e.size() == 15);
    assert(e.view(0, buffer) == [ 0, 1, 2, 3, 4, 'h', 'e', 'l', 'l', 'o', 5, 6, 7, 8, 9 ]);

    // Single undo clears all 5 chars
    e.undo();
    assert(e.size() == 10);
    assert(e.view(0, buffer) == data);
}

/// Close-open test
unittest
{
    log("TEST-0022");

    static immutable ubyte[] data = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ];
    MemoryDocument memdoc = new MemoryDocument(data);

    ubyte[32] buffer;

    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(memdoc);
    assert(e.view(0, buffer) == data);

    e.close();
    assert(e.view(0, buffer) == []);

    e.open(memdoc);
    assert(e.view(0, buffer) == data);
}

/// dirtyRegions: replace produces correct dirty regions
unittest
{
    log("TEST-0023");

    static immutable ubyte[] data = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
        new MemoryDocument(data)
    );

    ubyte x = 0xAA;
    e.replace(3, &x, 1);

    IDirtyRange dirty = e.dirtyRegions();
    assert(!dirty.empty());
    DirtyRegion region = dirty.front();
    assert(region.position == 3);
    assert(region.data == [0xAA]);
    dirty.popFront();
    assert(dirty.empty());
}

/// Test empty document
unittest
{
    log("TEST-0024");

    static immutable ubyte[] data = [];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
        new MemoryDocument(data)
    );

    ubyte[32] buffer;
    assert(e.view(0, buffer) == []);

    static immutable ubyte[] newdata = [ 0, 1, 2, 3, 4 ];
    e.insert(0, newdata.ptr, newdata.length);
    assert(e.view(0, buffer) == newdata);
}

/// History branching: a new edit after undo discards the stale redo tail
unittest
{
    log("TEST-0025");

    static immutable ubyte[] data = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
        new MemoryDocument(data)
    );

    ubyte[32] buffer;

    // Three separate operations (non-adjacent, so no coalescing)
    ubyte a = 0xAA;
    ubyte b = 0xBB;
    ubyte c = 0xCC;
    e.replace(0, &a, 1);
    e.replace(3, &b, 1);
    e.replace(6, &c, 1);

    // Undo twice, then branch off with a new edit; only one history slot
    // gets overwritten, the second undone operation must be discarded
    e.undo();
    e.undo();
    ubyte d = 0xDD;
    e.replace(9, &d, 1);

    assert(e.redo() < 0); // Nothing left to redo
    assert(e.size() == 10);
    assert(e.view(0, buffer) == [ 0xAA, 1, 2, 3, 4, 5, 6, 7, 8, 0xDD ]);
}

/// History branching: save point in discarded redo tail stays dirty
unittest
{
    log("TEST-0026");

    static immutable ubyte[] data = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
        new MemoryDocument(data)
    );

    ubyte[32] buffer;

    ubyte a = 0xAA;
    ubyte b = 0xBB;
    e.replace(0, &a, 1);
    e.replace(3, &b, 1);
    e.markSaved();
    assert(e.edited() == false);

    // Branch: history index lands back on the saved index, but the content
    // no longer matches what was saved
    e.undo();
    ubyte c = 0xCC;
    e.replace(6, &c, 1);
    assert(e.edited());
    assert(e.view(0, buffer) == [ 0xAA, 1, 2, 3, 4, 5, 0xCC, 7, 8, 9 ]);

    // Saving again resumes normal tracking
    e.markSaved();
    assert(e.edited() == false);
}

/// Split a buffer piece twice: buffer offsets must accumulate
unittest
{
    log("TEST-0027");

    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor();

    ubyte[32] buffer;

    string data = "ABCDEFGH";
    e.insert(0, data.ptr, data.length);

    // First removal splits the buffer piece, trimming its right side
    e.remove(1, 2); // "ADEFGH"
    assert(e.view(0, buffer) == "ADEFGH");

    // Second removal (non-coalescable) splits the trimmed piece again
    e.remove(3, 2); // "ADEH"
    assert(e.view(0, buffer) == "ADEH");
}

/// Inserts larger than a page must not overflow the add buffer
unittest
{
    log("TEST-0028");

    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor();

    size_t biglen = (syspagesize() * 2) + 500;
    ubyte[] big = new ubyte[biglen];
    foreach (i, ref ubyte bb; big)
        bb = cast(ubyte)i;

    e.insert(0, big.ptr, big.length);

    // Force the add buffer to grow again; this must not clobber the data
    // referenced by the first piece
    ubyte z = 0x55;
    e.insert(0, &z, 1);

    ubyte[8] buffer;
    assert(e.size() == biglen + 1);
    assert(e.view(0, buffer) == cast(ubyte[])[ 0x55 ] ~ big[0..7]);
    assert(e.view(biglen - 7, buffer) == big[$-8..$]);
}

/// Remove on an empty document is a no-op and must not poison coalescing
unittest
{
    log("TEST-0029");

    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor();

    string data = "ABCD";
    e.insert(0, data.ptr, data.length);
    e.remove(0, 4); // document now empty
    e.undo();
    e.redo(); // empty again, with history and coalescing invalidated

    // These have nothing to remove; the second one must not coalesce with
    // a phantom operation and reverse the remove above
    e.remove(0, 1);
    e.remove(0, 1);

    ubyte[8] buffer;
    assert(e.size() == 0);
    assert(e.view(0, buffer) == []);
}

/// Split a huge pattern piece past the 4 GiB mark
unittest
{
    log("TEST-0030");

    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor();

    enum _10GB = 10L * 1024 * 1024 * 1024;
    enum _5GB  =  5L * 1024 * 1024 * 1024;

    static immutable string pat = "AB";
    e.patternInsert(0, _10GB, pat.ptr, pat.length);

    // Replacing deep inside the pattern splits it with a skip over 4 GiB
    ubyte z = 'z';
    e.replace(_5GB + 1, &z, 1);

    ubyte[4] buffer;
    assert(e.size() == _10GB);
    assert(e.view(_5GB - 1, buffer) == "BAzA");
}

/// Replacing past EOF is rejected (would leave a hole in the document)
unittest
{
    import ddhx.platform : Assertion;

    log("TEST-0031");

    static immutable ubyte[] data = [ 0, 1, 2, 3, 4 ];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
        new MemoryDocument(data)
    );

    ubyte x = 0xAA;
    bool caught;
    try e.replace(6, &x, 1);
    catch (Assertion) caught = true;
    assert(caught);

    // Replacing AT EOF is fine and extends the document
    e.replace(5, &x, 1);
    ubyte[8] buffer;
    assert(e.size() == 6);
    assert(e.view(0, buffer) == [ 0, 1, 2, 3, 4, 0xAA ]);
}

version (unittest)
private import ddhx.document.memory : MemoryDocument;

/// Test document with restricted capabilities, standing in for the
/// future disk and process document types.
version (unittest)
private class TestCapsDocument : MemoryDocument
{
    this(const(ubyte)[] data, int documentCaps)
    {
        super(data);
        _caps = documentCaps;
    }
    override int caps() { return _caps; }
    private int _caps;
}

/// Fixed-size media (disk-like: no resize, stable): size-changing
/// operations are rejected, in-bounds edits and history work
unittest
{
    import std.exception : assertThrown;

    log("TEST-0032");

    scope TestCapsDocument doc = new TestCapsDocument(
        cast(const(ubyte)[])"ABCDEFGH",
        DocCaps.read | DocCaps.write | DocCaps.stable);
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(doc);

    static immutable string two = "XY";
    assertThrown!Exception(e.insert(0, two.ptr, two.length));
    assertThrown!Exception(e.remove(0, 2));
    assertThrown!Exception(e.patternInsert(0, 4, two.ptr, two.length));
    assertThrown!Exception(e.fileInsert(0, doc));
    // Replaces ending past EOF would grow the document
    assertThrown!Exception(e.replace(7, two.ptr, two.length));
    assertThrown!Exception(e.patternReplace(6, 4, two.ptr, two.length));
    assert(e.size() == 8);
    assert(e.edited() == false);

    // In-bounds replace works, and history is recorded (stable medium)
    e.replace(0, two.ptr, two.length);
    ubyte[8] buffer;
    assert(e.view(0, buffer) == "XYCDEFGH");
    assert(e.edited());
    assert(e.undo() >= 0);
    assert(e.view(0, buffer) == "ABCDEFGH");
    assert(e.edited() == false);
}

/// Unstable media (process-like: no stable): direct mode, edits overlay
/// the live medium and there is no history
unittest
{
    import std.exception : assertThrown;

    log("TEST-0033");

    scope TestCapsDocument doc = new TestCapsDocument(
        cast(const(ubyte)[])"ABCDEFGH",
        DocCaps.read | DocCaps.write);
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(doc);

    static immutable string two = "XY";
    e.replace(0, two.ptr, two.length);
    ubyte[8] buffer;
    assert(e.view(0, buffer) == "XYCDEFGH");
    assert(e.edited());

    // No history to undo or redo, and the edit stays applied
    assert(e.undo() < 0);
    assert(e.view(0, buffer) == "XYCDEFGH");
    assert(e.redo() < 0);

    e.markSaved();
    assert(e.edited() == false);

    // Also fixed size here (no resize capability)
    assertThrown!Exception(e.insert(0, two.ptr, two.length));

    // Policy resets when the editor is reused with a capable document
    e.close();
    e.open(new MemoryDocument(cast(const(ubyte)[])"ABCDEFGH"));
    e.insert(0, two.ptr, two.length);
    assert(e.undo() >= 0);
}

//
// PieceV4-specific tests
//

/// Layout: the index stays packed and the metadata stays small
unittest
{
    log("TEST-0034");

    // Eight end offsets per 64-byte cache line, two pieces per line
    static assert(long.sizeof == 8, "end offsets must be 8 bytes");
    static assert(Piece.sizeof <= 32, "Piece must fit half a cache line");
    static assert(Piece.alignof <= 8, "Piece must not need over-alignment");

    // The index alone describes the layout: ends[i] is the running total of
    // piece sizes, and no piece holds an absolute document offset
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor();
    e.coalescing(false);

    string data = "ABCDEFGH";
    e.insert(0, data.ptr, data.length);
    ubyte x = 'z';
    e.replace(4, &x, 1);

    long running;
    foreach (i; 0 .. e.table.length)
    {
        running += e.table.pieces[i].size;
        assert(e.table.ends[i] == running);
    }
    assert(running == e.size());
}

/// Binary search: many scattered pieces resolve to the right bytes
unittest
{
    log("TEST-0035");

    enum SIZE = 256;
    ubyte[SIZE] source;
    foreach (i, ref ubyte b; source)
        b = cast(ubyte)i;

    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
        new MemoryDocument(source[])
    );
    e.coalescing(false); // keep every edit its own piece

    // Scatter 64 one-byte replaces, splitting the source into ~129 pieces
    ubyte marker = 0xEE;
    for (long i = 0; i < SIZE; i += 4)
        e.replace(i, &marker, 1);
    assert(e.table.length == 128);

    ubyte[SIZE] expected = source;
    for (size_t i = 0; i < SIZE; i += 4)
        expected[i] = marker;

    ubyte[SIZE] buffer;
    assert(e.size() == SIZE);
    assert(e.view(0, buffer) == expected[]);

    // Every offset must land on the piece covering it, including the ones
    // right on a piece boundary
    ubyte[16] window;
    for (long pos; pos < SIZE - 16; ++pos)
        assert(e.view(pos, window) == expected[cast(size_t)pos .. cast(size_t)pos + 16]);

    // Undoing all of it splices the source piece back into one
    foreach (_; 0 .. SIZE / 4)
        e.undo();
    assert(e.table.length == 1);
    assert(e.view(0, buffer) == source[]);
}

/// Locking is off by default and can be toggled
unittest
{
    log("TEST-0036");

    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor();
    assert(e.threadSafe() == false);

    e.threadSafe(true);
    assert(e.threadSafe());

    // Editing still behaves the same with the lock on
    string data = "ABCD";
    e.insert(0, data.ptr, data.length);
    ubyte[8] buffer;
    assert(e.view(0, buffer) == data);

    e.threadSafe(false);
    assert(e.threadSafe() == false);
    assert(e.view(0, buffer) == data);

    // And the constructor takes it directly
    scope PieceV4DocumentEditor e2 = new PieceV4DocumentEditor(true);
    assert(e2.threadSafe());
}

/// Concurrent writers: every insert lands, none are lost
unittest
{
    import core.thread : Thread;

    log("TEST-0037");

    enum THREADS = 4;
    enum ROUNDS  = 64;

    PieceV4DocumentEditor e = new PieceV4DocumentEditor(true);

    Thread[THREADS] writers;
    foreach (ref Thread t; writers)
    {
        t = new Thread({
            ubyte b = 0x41;
            foreach (_; 0 .. ROUNDS)
                e.insert(0, &b, 1);
        });
    }
    foreach (Thread t; writers) t.start();
    foreach (Thread t; writers) t.join(); // rethrows assertion failures

    ubyte[THREADS * ROUNDS] buffer;
    assert(e.size() == THREADS * ROUNDS);
    ubyte[] got = e.view(0, buffer);
    assert(got.length == buffer.length);
    foreach (ubyte b; got)
        assert(b == 0x41);
}

/// Concurrent readers never observe a half-spliced document
unittest
{
    import core.thread : Thread;
    import core.atomic : atomicLoad, atomicStore;

    log("TEST-0038");

    enum READERS = 3;
    enum ROUNDS  = 200;

    static immutable ubyte[] data = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ];
    PieceV4DocumentEditor e = new PieceV4DocumentEditor(true).open(
        new MemoryDocument(data)
    );

    shared bool stop;
    Thread[READERS] readers;
    foreach (ref Thread t; readers)
    {
        t = new Thread({
            ubyte[64] buffer;
            while (atomicLoad(stop) == false)
            {
                // The document only grows here, so a consistent view sits
                // between the sizes seen before and after it
                long before = e.size();
                ubyte[] got = e.view(0, buffer);
                long after = e.size();
                assert(got.length >= min(before, cast(long)buffer.length));
                assert(got.length <= min(after, cast(long)buffer.length));
            }
        });
    }
    foreach (Thread t; readers) t.start();

    ubyte b = 0x7f;
    foreach (_; 0 .. ROUNDS)
        e.insert(0, &b, 1);

    atomicStore(stop, true);
    foreach (Thread t; readers) t.join();

    assert(e.size() == data.length + ROUNDS);
}

/// Concurrent readers over a file document: reads are serialized, so the
/// shared file position of one reader cannot derail another
unittest
{
    import core.thread : Thread;
    import std.file : remove, write, tempDir;
    import std.path : buildPath;
    import ddhx.document.file : FileDocument;

    log("TEST-0039");

    enum SIZE    = 4096;
    enum READERS = 4;
    enum ROUNDS  = 128;
    enum WINDOW  = 64;

    ubyte[SIZE] content;
    foreach (i, ref ubyte c; content)
        c = cast(ubyte)i;

    string path = buildPath(tempDir(), "piecev4_concurrent.tmp");
    write(path, content[]);
    FileDocument doc = new FileDocument(path, true);

    PieceV4DocumentEditor e = new PieceV4DocumentEditor(true).open(doc);

    // Each reader needs its own closure frame, hence the maker function
    Thread reader(long seed)
    {
        return new Thread({
            ubyte[WINDOW] buffer;
            foreach (round; 0 .. ROUNDS)
            {
                long pos = (seed * (round + 1)) % (SIZE - WINDOW);
                ubyte[] got = e.view(pos, buffer);
                assert(got.length == WINDOW);
                foreach (j, ubyte b; got)
                    assert(b == cast(ubyte)(pos + j));
            }
        });
    }

    Thread[READERS] readers;
    foreach (i, ref Thread t; readers)
        t = reader((cast(long)i + 1) * 37);
    foreach (Thread t; readers) t.start();
    foreach (Thread t; readers) t.join();

    e.close();
    doc.close();
    remove(path);
}

/// Every operation reverses exactly, in any mix and to any depth
unittest
{
    log("TEST-0040");

    static immutable ubyte[] data = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ];
    scope PieceV4DocumentEditor e = new PieceV4DocumentEditor().open(
        new MemoryDocument(data)
    );
    e.coalescing(false);

    ubyte[64] buffer;
    ubyte[][] states = [ e.view(0, buffer).dup ];

    ubyte b = 0x11;
    ubyte[3] three = [ 0x22, 0x33, 0x44 ];

    e.insert(0, &b, 1);             states ~= e.view(0, buffer).dup;
    e.replace(4, three.ptr, 3);     states ~= e.view(0, buffer).dup;
    e.remove(2, 3);                 states ~= e.view(0, buffer).dup;
    e.patternInsert(1, 7, &b, 1);   states ~= e.view(0, buffer).dup;
    e.patternReplace(3, 5, three.ptr, 3); states ~= e.view(0, buffer).dup;
    e.remove(0, 4);                 states ~= e.view(0, buffer).dup;
    e.insert(e.size(), &b, 1);      states ~= e.view(0, buffer).dup;

    // Unwind to the original document
    foreach_reverse (i; 1 .. states.length)
    {
        assert(e.view(0, buffer) == states[i]);
        e.undo();
    }
    assert(e.view(0, buffer) == states[0]);
    assert(e.undo() < 0);

    // And replay it
    foreach (i; 1 .. states.length)
    {
        e.redo();
        assert(e.view(0, buffer) == states[i]);
    }
    assert(e.redo() < 0);
}
