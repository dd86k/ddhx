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
    /// Should this read past EOF, do not throw, only partially fill the buffer.
    ubyte[] readAt(long pos, ubyte[] buf);
    /// Write at this position.
    /// If position is past EOF, throw.
    void writeAt(long pos, ubyte[] buf);
    /// Flush buffered data to media (or no-op).
    void flush();
    /// Close document (handles).
    void close();
}