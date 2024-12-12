/// Document interface.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module document.base;

interface IDocument
{
    long size();
    ubyte[] readAt(long at, ubyte[] buf);
}