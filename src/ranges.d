/// Editor backend implemention using a Piece List to ease insertion and
/// deletion operations.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ranges;

import utils : scan;

struct Range { long start, end; } // @suppress(dscanner.style.undocumented_declaration)
/// Parse a range expression.
///
/// Only '$' is accepted as an end portion that turns into -1,
/// for special designation.
/// Params: expr = Expression string.
/// Returns: Range structure.
/// Throws: Exception.
Range range(string expr)
{
    if (expr is null || expr.length == 0)
        throw new Exception("Empty range");
    
    import std.string : indexOf;
    
    ptrdiff_t i = indexOf(expr, ':');
    if (i < 0)
        throw new Exception("Missing separator in range");
    if (i == 0)
        throw new Exception("Missing start portion in range");
    if (i+1 == expr.length)
        throw new Exception("Missing end portion in range");
    
    string start = expr[0..i];
    string end   = expr[i+1..$];
    
    return Range(
        scan(start),
        end == "$" ? -1 : scan(end)
    );
}
unittest
{
    // Empty
    try { cast(void)range(""); assert(false); } catch (Exception) {}
    // Separator only
    try { cast(void)range(":"); assert(false); } catch (Exception) {}
    // Missing end
    try { cast(void)range("0:"); assert(false); } catch (Exception) {}
    // Missing start
    try { cast(void)range(":$"); assert(false); } catch (Exception) {}
    
    assert(range("0:0")  == Range( 0, 0 ));
    assert(range("0:1")  == Range( 0, 1 ));
    assert(range("1:1")  == Range( 1, 1 ));
    assert(range("5:25") == Range( 5, 25 ));
    assert(range("010:0x30") == Range( 8, 0x30 ));
    assert(range("5:$")  == Range( 5, -1 ));
}
