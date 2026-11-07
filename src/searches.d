/// Pattern search over a document editor.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module searches;

import core.stdc.stdlib : malloc, free;
import std.algorithm.comparison : min, max;
import ddhx.editor.base : IDocumentEditor;
import ddhx.logger;
import ddhx.platform : assertion;
import messages;
import patterns;
import utils : KiB;

/// Bytes read per search window.
enum SEARCH_CHUNKSIZE = KiB!128;

enum {
    /// Search for different needle value, not an exact one.
    SEARCH_DIFF     = 1,
    /// Search in reverse, not forward.
    SEARCH_REVERSE  = 2,
    /// Instead of returning -1, return the position when the search ended.
    SEARCH_LASTPOS  = 4,
    /// Search is done aligned to the size of the needle.
    SEARCH_ALIGNED  = 8,
    // Wrap search.
    //SEARCH_WRAP     = 16,
    /// Search without touching the terminal: no progress bar, and no
    /// polling for a cancel key. Only the view wrapper reads it, tests use it.
    SEARCH_NON_INTERACTIVE = 32,
    /// Match only on element boundaries, see the element parameter.
    SEARCH_ELEMENT = 64,
    
    /// Search result not found.
    SEARCH_RESULT_NOT_FOUND = -1,
}

/// Result of a search: position of the match (or SEARCH_RESULT_NOT_FOUND)
/// and the length of haystack bytes the match consumed. The length is only
/// non-trivial when the pattern contains `*` - for fixed-width patterns
/// (including `?`), len == needle.data.length.
struct SearchResult
{
    long pos;
    long len;
}

/// What the hit callback tells the search loop to do with a match.
enum SearchAction
{
    /// Stop searching, search() returns this match.
    stop,
    /// Keep searching after (before, in reverse) this match.
    next,
}

/// Search for data.
///
/// This function does not rely on the cursor position nor does it change it,
/// because command implementations might use the result differently.
///
/// Returning the position allows for specific error messages when a search
/// returns -1 (error: not found), or forced to return where the position is
/// after the search is concluded.
/// Params:
///     editor = Document to search.
///     needle = Data to compare against.
///     position = Starting position.
///     flags = Operation flags.
///     onhit = Called for every match. Returning SearchAction.next resumes
///             the scan past the match, so matches never overlap.
///             A null callback stops at the first match.
///     end = Matches must end before this position (exclusive).
///     element = Element size for SEARCH_ELEMENT.
///     progress = Called after each window with the bytes scanned and the
///                document size. Throw from it to cancel.
/// Returns: SearchResult with pos=SEARCH_RESULT_NOT_FOUND on no match.
///          SEARCH_LASTPOS overrides SEARCH_RESULT_NOT_FOUND. On no-match
///          (including LASTPOS), len is 0. When onhit consumed every match,
///          the search ran to the end, so this is a no-match result.
SearchResult search(IDocumentEditor editor, Pattern needle, long position, int flags,
    SearchAction delegate(SearchResult) onhit = null, long end = long.max,
    size_t element = 1, void delegate(long done, long total) progress = null)
{
    assertion(needle, "Need needle");
    
    // Throwing on malloc failure is weird... but uses less memory than a search buffer would
    ubyte[] hay = (cast(ubyte*)malloc(SEARCH_CHUNKSIZE))[0..SEARCH_CHUNKSIZE];
    if (hay is null)
        throw new Exception(MSG_OUT_OF_MEMORY);
    scope(exit) free(hay.ptr);
    
    log("position=%d flags=%#x needle=[%(%#x,%)]", position, flags, needle);
    
    int diff = flags & SEARCH_DIFF;
    size_t alignment = flags & SEARCH_ALIGNED ? needle.data.length : 1;
    if (flags & SEARCH_ELEMENT)
    {
        alignment = element;
        // Round start to a boundary, up when forward, down when reversed
        long rem = position % cast(long)alignment;
        if (rem > 0) // negative start means nothing to search
            position += flags & SEARCH_REVERSE ? -rem : cast(long)alignment - rem;
    }
    long docsize = editor.size();
    long stop = end < docsize ? end : docsize;

    // Distance to skip on top of what the loop already advances, to resume
    // scanning right after (or before) a match, so matches never overlap
    // while staying on an alignment boundary.
    long resume(long matchlen)
    {
        long step = matchlen > 0 ? matchlen : 1;
        long align_ = cast(long)alignment;
        if (align_ > 1) // round up to the next alignment boundary
            step = ((step + align_ - 1) / align_) * align_;
        return step - align_;
    }
    
    debug import std.datetime.stopwatch : StopWatch;
    debug StopWatch sw;
    debug sw.start;
    
    // Shortest match length, and whether '*' makes it variable
    long minlen;
    bool variable;
    foreach (ushort c; needle.data)
    {
        if (c == PATTERN_GLOB_MANY)
            variable = true;
        else
            minlen++;
    }
    // A needle of only '*' matches zero bytes, and replacing those never ends
    if (minlen == 0)
        throw new Exception(MSG_EMPTY_NEEDLE);
    // Remembers what follows each '*' within a window, see PatternMatcher
    PatternMatcher matcher;
    if (variable)
        matcher = PatternMatcher(needle);
    // Bytes a window keeps past its last scanned start, room for '*' to grow
    enum long CHUNK = SEARCH_CHUNKSIZE;
    long tail = min(variable ? max(minlen, CHUNK / 2) : minlen, CHUNK);

    if (flags & SEARCH_REVERSE)
    {
        // Highest start whose shortest match still ends by stop, stepped
        // down whole alignments to stay on a boundary
        if (position > stop - minlen)
        {
            long over = position - (stop - minlen);
            long align_ = cast(long)alignment;
            position -= ((over + align_ - 1) / align_) * align_;
        }

        // Each window ends past the highest start, so it holds the bytes a
        // match needs, and overlaps the previous window by that much.
        while (position >= 0)
        {
            long wend = min(position + tail, stop);
            long base = max(wend - CHUNK, 0L);
            ubyte[] haystack = editor.view(base, hay[0 .. cast(size_t)(wend - base)]);
            if (haystack.length < minlen)
                break; // needle longer than a window
            if (variable)
                matcher.reset(haystack);

            // Use signed long for o to avoid size_t underflow when
            // alignment > 1 and o < alignment.
            long o = position - base;
            for (; o >= 0; o -= cast(long) alignment, position -= cast(long) alignment)
            {
                ptrdiff_t mlen = variable ? matcher.match(cast(size_t) o)
                    : matchPattern(haystack, needle, cast(size_t) o, 0);
                bool matched = mlen >= 0;
                if ((diff == 0 && !matched) || (diff && matched))
                    continue;
                SearchResult hit = SearchResult(position,
                    matched ? cast(long) mlen : cast(long) needle.data.length);
                if (onhit is null || onhit(hit) == SearchAction.stop)
                    return hit;
                long skip = resume(hit.len);
                o -= skip;
                position -= skip;
            }
            
            // 1. After that loop to avoid flickerin between status-progress
            // 2. In reverse mode, it's towards zero, so base decrements
            //    If we wanted a reverse progress bar, just pass base, but would be confusing
            if (progress !is null) progress(docsize - base, docsize);
        }

        // Scan ended at the start of the document, for SEARCH_LASTPOS
        position = 0;
    }
    else // forward
    {
        // Each window scans starts up to tail bytes before its end, so a match
        // fits in it, and the next window begins at the first start left.
        // The last window, ending at stop, scans every start that fits.
        while (position < stop)
        {
            size_t want = cast(size_t) min(CHUNK, stop - position);
            ubyte[] haystack = editor.view(position, hay[0 .. want]);
            if (haystack.length < minlen)
                break; // tail shorter than needle
            if (variable)
                matcher.reset(haystack);

            bool last = haystack.length < want || position + want >= stop;
            long top = cast(long) haystack.length - (last ? minlen : tail);
            for (long o; o <= top; o += cast(long) alignment, position += cast(long) alignment)
            {
                ptrdiff_t mlen = variable ? matcher.match(cast(size_t) o)
                    : matchPattern(haystack, needle, cast(size_t) o, 0);
                bool matched = mlen >= 0;
                if ((diff == 0 && !matched) || (diff && matched))
                    continue;
                SearchResult hit = SearchResult(position,
                    matched ? cast(long) mlen : cast(long) needle.data.length);
                if (onhit is null || onhit(hit) == SearchAction.stop)
                    return hit;
                long skip = resume(hit.len);
                o += skip;
                position += skip;
            }

            if (progress !is null)
                progress(min(position, docsize), docsize);
            if (last)
                break;
        }

        // Scan ended at the end of the document, for SEARCH_LASTPOS
        position = stop;
    }
    
    debug sw.stop();
    debug log("search=%s", sw.peek());
    
    return SearchResult(flags & SEARCH_LASTPOS ? position : SEARCH_RESULT_NOT_FOUND, 0);
}
// Forward search: memcmp must not read past haystack when needle.length > 1.
// Old bound (o < haystack.length) let the last comparison overread.
unittest
{
    import std.system : Endian;
    import ddhx.editor.dummy : DummyDocumentEditor;

    // "AABBCC" - needle "CC" should be found at position 4.
    IDocumentEditor editor = new DummyDocumentEditor(cast(immutable(ubyte)[]) "AABBCC");

    Pattern needle = pattern(Endian.littleEndian, "utf8:CC");
    SearchResult result = search(editor, needle, 0, SEARCH_ALIGNED | SEARCH_NON_INTERACTIVE);
    assert(result.pos == 4, "forward aligned: expected 4");
    assert(result.len == 2, "forward aligned: len should equal needle length");
}
// Forward search: needle that does not exist must return not-found
// without reading past the buffer.
unittest
{
    import std.system : Endian;
    import ddhx.editor.dummy : DummyDocumentEditor;

    IDocumentEditor editor = new DummyDocumentEditor(cast(immutable(ubyte)[]) "AABB");

    Pattern needle = pattern(Endian.littleEndian, "utf8:ZZ");
    SearchResult result = search(editor, needle, 0, SEARCH_ALIGNED | SEARCH_NON_INTERACTIVE);
    assert(result.pos == SEARCH_RESULT_NOT_FOUND, "forward aligned not-found");
}
// Reverse search with alignment > 1: the loop must terminate without
// size_t underflow when the offset is not a multiple of alignment.
// 7-byte data makes maxOff=5 (odd), so with alignment=2 the loop
// counter hits 1 then would underflow with unsigned arithmetic.
unittest
{
    import std.system : Endian;
    import ddhx.editor.dummy : DummyDocumentEditor;

    IDocumentEditor editor = new DummyDocumentEditor(cast(immutable(ubyte)[]) "ABCDEFG");

    Pattern needle = pattern(Endian.littleEndian, "utf8:ZZ");
    SearchResult result = search(editor, needle, 6, SEARCH_REVERSE | SEARCH_ALIGNED | SEARCH_NON_INTERACTIVE);
    assert(result.pos == SEARCH_RESULT_NOT_FOUND, "reverse aligned underflow");
}
// Reverse search: initial offset is clamped so memcmp stays in bounds,
// and the match (not at offset 0) is still found.
unittest
{
    import std.system : Endian;
    import ddhx.editor.dummy : DummyDocumentEditor;

    IDocumentEditor editor = new DummyDocumentEditor(cast(immutable(ubyte)[]) "ABCDEF");

    Pattern needle = pattern(Endian.littleEndian, "utf8:CD");
    SearchResult result = search(editor, needle, 5, SEARCH_REVERSE | SEARCH_NON_INTERACTIVE);
    assert(result.pos == 2, "reverse from end: expected 2");
    assert(result.len == 2);
}

// Reverse search: a match at the very start of the document is found.
// The old loop bound (o > 0) never tested offset 0.
unittest
{
    import std.system : Endian;
    import ddhx.editor.dummy : DummyDocumentEditor;

    IDocumentEditor editor = new DummyDocumentEditor(cast(immutable(ubyte)[]) "ABCDEF");

    Pattern needle = pattern(Endian.littleEndian, "utf8:AB");
    SearchResult result = search(editor, needle, 5, SEARCH_REVERSE | SEARCH_NON_INTERACTIVE);
    assert(result.pos == 0, "reverse to start: expected 0");
    assert(result.len == 2);
}
// Reverse search: no match, and SEARCH_LASTPOS stays on the document.
unittest
{
    import std.system : Endian;
    import ddhx.editor.dummy : DummyDocumentEditor;

    IDocumentEditor editor = new DummyDocumentEditor(cast(immutable(ubyte)[]) "ABCDEF");

    Pattern needle = pattern(Endian.littleEndian, "utf8:ZZ");
    SearchResult result = search(editor, needle, 5,
        SEARCH_REVERSE | SEARCH_LASTPOS | SEARCH_NON_INTERACTIVE);
    assert(result.pos == 0, "reverse lastpos: expected 0");
}
// SEARCH_LASTPOS: a tail shorter than the needle ends the scan at EOF, not -1,
// which sent skip-front from the last element to the start of the document.
unittest
{
    import ddhx.editor.dummy : DummyDocumentEditor;

    IDocumentEditor editor = new DummyDocumentEditor(cast(immutable(ubyte)[]) "AAAABBBBCC");

    Pattern needle = Pattern.fromBytes(cast(const(ubyte)[]) "BBBB");
    enum FLAGS = SEARCH_LASTPOS | SEARCH_DIFF | SEARCH_ALIGNED | SEARCH_NON_INTERACTIVE;
    assert(search(editor, needle, 8, FLAGS).pos == 10);
    assert(search(editor, needle, 10, FLAGS).pos == 10);

    editor = new DummyDocumentEditor(cast(immutable(ubyte)[]) "BB");
    assert(search(editor, needle, 2, FLAGS | SEARCH_REVERSE).pos == 0);
}
// Hit callback: every occurrence is reported, in order, and the search
// concludes as a no-match once the callback consumed them all.
unittest
{
    import std.system : Endian;
    import ddhx.editor.dummy : DummyDocumentEditor;

    IDocumentEditor editor = new DummyDocumentEditor(cast(immutable(ubyte)[]) "AABBAABB");

    Pattern needle = pattern(Endian.littleEndian, "utf8:AA");
    SearchResult[] hits;
    SearchResult result = search(editor, needle, 0, SEARCH_NON_INTERACTIVE,
        (SearchResult r) { hits ~= r; return SearchAction.next; });
    assert(result.pos == SEARCH_RESULT_NOT_FOUND, "scan must run to the end");
    assert(hits.length == 2, "expected two matches");
    assert(hits[0].pos == 0 && hits[0].len == 2);
    assert(hits[1].pos == 4 && hits[1].len == 2);
}
// End bound: a match crossing or past the bound is not found.
unittest
{
    import std.system : Endian;
    import ddhx.editor.dummy : DummyDocumentEditor;

    IDocumentEditor editor = new DummyDocumentEditor(cast(immutable(ubyte)[]) "AABAABAA");

    Pattern needle = pattern(Endian.littleEndian, "utf8:AA");
    long[] positions;
    search(editor, needle, 0, SEARCH_NON_INTERACTIVE,
        (SearchResult r) { positions ~= r.pos; return SearchAction.next; }, 4);
    assert(positions == [0], "match at 3 crosses the bound");
    positions = null;
    search(editor, needle, 0, SEARCH_NON_INTERACTIVE,
        (SearchResult r) { positions ~= r.pos; return SearchAction.next; }, 5);
    assert(positions == [0, 3]);
    SearchResult r = search(editor, needle, 1, SEARCH_NON_INTERACTIVE | SEARCH_LASTPOS, null, 3);
    assert(r.pos == 3 && r.len == 0, "LASTPOS reports the bound");
}
// Element alignment: matches only start on element boundaries.
unittest
{
    import std.system : Endian;
    import ddhx.editor.dummy : DummyDocumentEditor;

    IDocumentEditor editor = new DummyDocumentEditor(cast(immutable(ubyte)[]) "xAA.AAAA");

    Pattern needle = pattern(Endian.littleEndian, "utf8:AA");
    long[] positions;
    enum int F = SEARCH_NON_INTERACTIVE | SEARCH_ELEMENT;
    search(editor, needle, 0, F,
        (SearchResult r) { positions ~= r.pos; return SearchAction.next; }, long.max, 2);
    assert(positions == [4, 6], "odd offsets 1 and 5 are skipped");
    // Start is rounded up forward, down in reverse
    assert(search(editor, needle, 5, F, null, long.max, 2).pos == 6);
    assert(search(editor, needle, 5, F | SEARCH_REVERSE, null, long.max, 2).pos == 4);
    assert(search(editor, needle, 3, F | SEARCH_REVERSE, null, long.max, 2).pos
        == SEARCH_RESULT_NOT_FOUND);
    // Reverse clamp near the end keeps the boundary: 3-byte needle fits at 5 at most
    Pattern three = pattern(Endian.littleEndian, "utf8:AAA");
    assert(search(editor, three, 6, F | SEARCH_REVERSE, null, long.max, 2).pos == 4);
}
// Reverse past the first window: a match at the start position, and one
// crossing a window edge, are both found.
unittest
{
    import std.system : Endian;
    import ddhx.editor.dummy : DummyDocumentEditor;

    enum long C = SEARCH_CHUNKSIZE;
    enum int F = SEARCH_REVERSE | SEARCH_NON_INTERACTIVE;
    ubyte[] data = new ubyte[cast(size_t)(C * 2 + C / 2)];
    IDocumentEditor editor;

    data[cast(size_t)(C + 100)] = 'X';
    editor = new DummyDocumentEditor(data.idup);
    Pattern x = pattern(Endian.littleEndian, "utf8:X");
    assert(search(editor, x, C + 100, F).pos == C + 100, "match at start");

    // Every offset as an edge: XY must be found wherever the scan starts
    data[] = 0;
    long at = C + 7;
    data[cast(size_t)at] = 'X'; data[cast(size_t)at + 1] = 'Y';
    editor = new DummyDocumentEditor(data.idup);
    Pattern xy = pattern(Endian.littleEndian, "utf8:XY");
    foreach (long start; [at, at + 1, at + C - 2, at + C - 1, at + C, cast(long)data.length - 1])
        assert(search(editor, xy, start, F).pos == at, "edge crossing");
    assert(search(editor, xy, at - 1, F).pos == SEARCH_RESULT_NOT_FOUND);
}
// Reverse end bound: matches must end by it, '*' ones included.
unittest
{
    import std.system : Endian;
    import ddhx.editor.dummy : DummyDocumentEditor;

    enum int F = SEARCH_REVERSE | SEARCH_NON_INTERACTIVE;
    IDocumentEditor editor = new DummyDocumentEditor(cast(immutable(ubyte)[]) "AAAAAAAA");
    Pattern three = pattern(Endian.littleEndian, "utf8:AAA");
    assert(search(editor, three, 3, F, null, 4).pos == 1);
    assert(search(editor, three, 3, F, null, 2).pos == SEARCH_RESULT_NOT_FOUND);

    editor = new DummyDocumentEditor(cast(immutable(ubyte)[]) "AXYBAXB.");
    Pattern glob = pattern(Endian.littleEndian, "utf8:A", "*", "utf8:B");
    assert(search(editor, glob, 3, F, null, 4) == SearchResult(0, 4));
    assert(search(editor, glob, 3, F, null, 3).pos == SEARCH_RESULT_NOT_FOUND);
    assert(search(editor, glob, 7, F).pos == 4);
}
// Reverse with a needle longer than a window ends, not found.
unittest
{
    import ddhx.editor.dummy : DummyDocumentEditor;

    IDocumentEditor editor = new DummyDocumentEditor(new immutable(ubyte)[SEARCH_CHUNKSIZE * 2]);
    Pattern big = Pattern.fromBytes(new ubyte[SEARCH_CHUNKSIZE + 1]);
    assert(search(editor, big, SEARCH_CHUNKSIZE, SEARCH_REVERSE | SEARCH_NON_INTERACTIVE).pos
        == SEARCH_RESULT_NOT_FOUND);
}
// Forward wildcard matches crossing or starting at a window edge are found.
unittest
{
    import std.system : Endian;
    import ddhx.editor.dummy : DummyDocumentEditor;

    enum long C = SEARCH_CHUNKSIZE;
    enum int F = SEARCH_NON_INTERACTIVE;
    Pattern one  = pattern(Endian.littleEndian, "utf8:A", "?", "utf8:B");
    Pattern star = pattern(Endian.littleEndian, "utf8:A", "*", "utf8:B");
    IDocumentEditor editor;
    ubyte[] data = new ubyte[cast(size_t)(C * 3)];
    foreach (long at; [C - 3, C - 2, C - 1, C, C + 1])
    {
        data[] = 0;
        data[cast(size_t)at .. cast(size_t)at + 3] = cast(ubyte[]) "AxB";
        editor = new DummyDocumentEditor(data.idup);
        assert(search(editor, one, 0, F) == SearchResult(at, 3));
        assert(search(editor, star, 0, F) == SearchResult(at, 3));

        data[] = 0;
        data[cast(size_t)at .. cast(size_t)at + 2] = cast(ubyte[]) "AB";
        editor = new DummyDocumentEditor(data.idup);
        assert(search(editor, star, 0, F) == SearchResult(at, 2));
    }
}
// A needle as long as a window is found both ways.
unittest
{
    import ddhx.editor.dummy : DummyDocumentEditor;

    enum size_t C = SEARCH_CHUNKSIZE;
    ubyte[] data = new ubyte[C * 2];
    uint x = 1;
    foreach (ref ubyte b; data) // no repeats at other offsets
        b = cast(ubyte)((x = x * 1_103_515_245 + 12_345) >> 16);
    IDocumentEditor editor = new DummyDocumentEditor(data.idup);
    Pattern big = Pattern.fromBytes(data[5 .. C + 5]);
    assert(search(editor, big, 0, SEARCH_NON_INTERACTIVE) == SearchResult(5, C));
    assert(search(editor, big, C, SEARCH_REVERSE | SEARCH_NON_INTERACTIVE) == SearchResult(5, C));
}
// A needle of only '*' is refused, it matches zero bytes everywhere.
unittest
{
    import std.system : Endian;
    import ddhx.editor.dummy : DummyDocumentEditor;

    IDocumentEditor editor = new DummyDocumentEditor(cast(immutable(ubyte)[]) "ABCD");
    foreach (int f; [0, SEARCH_REVERSE])
    {
        try
        {
            search(editor, pattern(Endian.littleEndian, "*"), 1, f | SEARCH_NON_INTERACTIVE);
            assert(false);
        }
        catch (Exception e)
            assert(e.msg == MSG_EMPTY_NEEDLE);
    }
}
// Hit callback: matches never overlap, the scan resumes past the match.
unittest
{
    import std.system : Endian;
    import ddhx.editor.dummy : DummyDocumentEditor;

    IDocumentEditor editor = new DummyDocumentEditor(cast(immutable(ubyte)[]) "AAAA");

    Pattern needle = pattern(Endian.littleEndian, "utf8:AA");
    long[] positions;
    search(editor, needle, 0, SEARCH_NON_INTERACTIVE,
        (SearchResult r) { positions ~= r.pos; return SearchAction.next; });
    assert(positions == [ 0L, 2L ], "expected non-overlapping matches");
}
// Hit callback: stopping returns that match, like a callback-less search.
unittest
{
    import std.system : Endian;
    import ddhx.editor.dummy : DummyDocumentEditor;

    IDocumentEditor editor = new DummyDocumentEditor(cast(immutable(ubyte)[]) "AABBAABB");

    Pattern needle = pattern(Endian.littleEndian, "utf8:AA");
    int calls;
    SearchResult result = search(editor, needle, 1, SEARCH_NON_INTERACTIVE,
        (SearchResult r) { ++calls; return SearchAction.stop; });
    assert(calls == 1);
    assert(result.pos == 4 && result.len == 2);
}
// Hit callback: reverse direction reports matches from the end backward.
unittest
{
    import std.system : Endian;
    import ddhx.editor.dummy : DummyDocumentEditor;

    IDocumentEditor editor = new DummyDocumentEditor(cast(immutable(ubyte)[]) "AABBAABB");

    Pattern needle = pattern(Endian.littleEndian, "utf8:AA");
    long[] positions;
    search(editor, needle, 7, SEARCH_REVERSE | SEARCH_NON_INTERACTIVE,
        (SearchResult r) { positions ~= r.pos; return SearchAction.next; });
    assert(positions == [ 4L, 0L ], "expected matches in reverse order");
}
