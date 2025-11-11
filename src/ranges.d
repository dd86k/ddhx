/// Implements range expressions.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ranges;

import utils : scan;

/// Special values
enum RangeSentinel {
    eof     = -1,   /// End of file (document): '$'
    cursor  = -2,   /// Cursor position: '.'
}
enum {
    RANGE_RELATIVE = 1,     /// If set, end is a length value
}

/// Represents an inclusive range.
struct Range
{
    long start;     /// Start.
    long end;       /// End or length if RANGE_RELATIVE is set.
    int flags;      /// Flags.
}
/// Parse a range expression.
///
/// Only '$' is accepted as an end portion that turns into -1,
/// for special designation to the caller.
/// Params: expr = Expression string.
/// Returns: Range structure.
/// Throws: Exception.
Range range(string expr)
{
    if (expr is null || expr.length == 0)
        throw new Exception("Empty range");
    
    import std.string : indexOf;
    
    Range r;
    
    ptrdiff_t i = indexOf(expr, ':');
    if (i < 0)
    {
        // Assume length-only range expression if separator missing
        r.start = RangeSentinel.cursor;
        r.end   = scan(expr);
        if (r.end == 0)
            throw new Exception("Length cannot be zero");
        r.end--;
        r.flags = RANGE_RELATIVE;
        return r;
    }
    if (i == 0)
        throw new Exception("Missing start in range");
    if (i+1 == expr.length)
        throw new Exception("Missing end in range");
    
    // Process start
    string a = expr[0..i];
    switch (a) {
    case "$": r.start = RangeSentinel.eof; break;
    case ".": r.start = RangeSentinel.cursor; break;
    default:  r.start = scan(a);
    }
    
    // Process end
    string b = expr[i+1..$];
    switch (b) {
    case "$": r.end = RangeSentinel.eof; break;
    case ".": r.end = RangeSentinel.cursor; break;
    default:
        if (b[0] == '+')
        {
            if (b.length < 2)
                throw new Exception("Missing length in range");
            r.end   = scan(b[1..$]);
            r.flags = RANGE_RELATIVE;
        }
        else
            r.end = scan(b);
    }
    
    return r;
}
unittest
{
    // Empty
    try { cast(void)range(""); assert(false); } catch (Exception) {}
    // Separator only
    try { cast(void)range(":"); assert(false); } catch (Exception) {}
    // Missing end
    try { cast(void)range("0:"); assert(false); } catch (Exception) {}
    try { cast(void)range("0:+"); assert(false); } catch (Exception) {}
    // Missing start
    try { cast(void)range(":$"); assert(false); } catch (Exception) {}
    
    assert(range("0:0")  == Range( 0, 0 ));
    assert(range("0:1")  == Range( 0, 1 ));
    assert(range("1:1")  == Range( 1, 1 ));
    assert(range("5:25") == Range( 5, 25 ));
    assert(range("010:0x30") == Range( 8, 0x30 ));
    assert(range("5:$")     == Range( 5, RangeSentinel.eof ));
    assert(range("$:0x20")  == Range( RangeSentinel.eof, 0x20 ));
    assert(range(".:0x20")  == Range( RangeSentinel.cursor, 0x20 ));
    assert(range(".:$")     == Range( RangeSentinel.cursor, RangeSentinel.eof ));
    
    // Relative
    assert(range(".:+0x100") == Range( RangeSentinel.cursor, 0x100,   RANGE_RELATIVE ));
    assert(range("0x100")    == Range( RangeSentinel.cursor, 0x100-1, RANGE_RELATIVE ));
}
