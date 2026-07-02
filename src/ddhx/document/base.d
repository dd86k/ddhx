/// Document interface.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.document.base;

/// Document capability flags.
///
/// These describe the medium behind a document, so higher layers can
/// derive their own policies from them: editors disable size-changing
/// operations and history depending on the medium, the view forbids
/// insert mode, and saving picks a strategy.
///
/// Capabilities gate features, not results: a capable document can still
/// fail an individual operation (e.g., an unmapped memory page), which is
/// reported by throwing from that operation.
enum DocCaps
{
    read    = 1,        /// Reading is supported
    write   = 1 << 1,   /// Writing to the medium is supported
    resize  = 1 << 2,   /// Medium can grow or shrink (regular files)
    stable  = 1 << 3,   /// Content only changes through this program
    replace = 1 << 4,   /// Saveable by replacing a file target (temp+rename)
}

/// Base document interface.
interface IDocument
{
    /// Returns: Capability flags for this document type (DocCaps).
    int caps();
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