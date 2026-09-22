/// File document implementation.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.document.file;

import ddhx.document.base;
import os.file;
public import os.file : OFlags, OSFileType;

version (Windows) import core.sync.mutex : Mutex;

/// File document.
class FileDocument : IDocument
{
    private enum DEFAULT_FLAGS = OFlags.read | OFlags.exists;
    
    /// New file document from path.
    this(string path, bool readonly = true) // legacy ctor
    {
        // Opening read-only as default avoids GVFS/network-share failures that reject O_RDWR.
        this(path, (readonly ? OFlags.read : OFlags.readWrite) | OFlags.exists);
    }
    /// New file document from path with flags.
    this(string path, OFlags flags) // non-optional due to previous ctor
    {
        file.open(path, flags);

        // Reject here rather than letting the first size() fail: by then the
        // error is an errno with no mention of which target caused it.
        OSFileType type = file.type();
        if (type == OSFileType.stream || type == OSFileType.directory)
        {
            file.close();
            import std.conv : text;
            throw new Exception(text(path, ": cannot edit a ", type));
        }

        oflags = flags;
        version (Windows) reads = new Mutex();
    }
    ~this() { close(); }
    
    /// File media capabilities.
    ///
    /// Describes the medium: this handle may still have been opened
    /// read-only (see writable()), as saving opens its own write handle.
    /// Returns: Capability flags (DocCaps).
    int caps()
    {
        enum BASE = DocCaps.read | DocCaps.write;
        final switch (file.type()) {
        case OSFileType.regular:
            return BASE | DocCaps.resize | DocCaps.stable | DocCaps.replace;
        case OSFileType.disk:
            // Fixed extent, and a full save would rename a temporary file
            // over the device node, destroying it. In-place writes only.
            return BASE | DocCaps.stable;
        case OSFileType.device, OSFileType.pseudo:
            // Ditto, minus stability: /dev/urandom and procfs files read
            // differently every time, so undo history cannot be trusted.
            return BASE;
        case OSFileType.unknown:
            // Only reached when the platform would not state a type at all,
            // so claim nothing beyond reading and writing in place.
            return BASE;
        case OSFileType.stream, OSFileType.directory:
            return 0; // rejected by the constructor
        }
    }

    /// Medium behind this document.
    /// Returns: File type.
    OSFileType type() { return file.type(); }

    /// Size of document in bytes.
    /// Returns: Size in bytes.
    long size()
    {
        return file.size();
    }
    
    /// Read at this position.
    ///
    /// Positional, so concurrent readers do not fight over one file position.
    /// Params:
    ///     pos = File position.
    ///     buffer = Buffer.
    /// Returns: Slice.
    ubyte[] readAt(long pos, ubyte[] buffer)
    {
        // NOTE: Windows serializes readers anyway
        //       Even when OSFile doesn't use FILE_FLAG_OVERLAPPED,
        //       offset reads are correct on both platforms, but Windows takes
        //       the file object lock to maintain the position it still moves,
        //       so its readers convoy instead of overlapping. Measured with
        //       `ddhx-benchmark reads` (200k reads of 512 B, warm cache): 8
        //       threads on one handle took 827 ms against 350 ms on one
        //       thread, where Posix scaled 6.2x. Doing it here costs an
        //       uncontended lock and beats that convoy twice over.
        version (Windows)
            synchronized (reads) return file.readAt(pos, buffer);
        else
            return file.readAt(pos, buffer);
    }
    
    /// Returns: True whether the file was opened with write access.
    bool writable() { return (oflags & OFlags.write) != 0; }

    /// Write data at a specific position in the file.
    void writeAt(long pos, ubyte[] data)
    {
        file.writeAt(pos, data);
    }

    /// Set file size (truncate or extend).
    void resize(long size)
    {
        file.resize(size);
    }

    /// Flush pending writes to disk.
    void flush()
    {
        file.flush();
    }
    
    /// Close file document.
    void close()
    {
        file.close();
    }
    
private:
    OSFile file;
    OFlags oflags;
    version (Windows) Mutex reads;
}