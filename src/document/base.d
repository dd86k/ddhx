/// Document interface.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module document.base;

/// Base document interface.
interface IDocument
{
    /// Returns: Size in bytes.
    long size();
    /// Read at this position.
    ubyte[] readAt(long at, ubyte[] buf);
}