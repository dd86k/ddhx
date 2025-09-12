/// Memory-mapped file document implementation.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module document.mmfile;

import std.stdio : File;
import std.mmfile : MmFile;
import os.error : OSException;
import document.base : IDocument;

/// Memory-mapped flags.
enum MMFlags
{
    exists  = 1,        /// File must exist.
    read    = 1 << 1,   /// Read access.
    write   = 1 << 2,   /// Write access.
    
    readWrite = read | write,
}

// NOTE: WARNING: MmFile can be dangerous to play with
//       * size=0 loads the ENTIRE file in memory (e.g., all of 71 GiB).
//         If size is stated, it only loads up to size, and no further
//         data is accessible, eliminating the benefit.
//       * Seeking past specified size (for an opened file) will TRUNCATE
//         the file (to size) without flushing.
//       * Setting an initial window size should help with memory usage,
//         but does not help the seeking issue.
/// A re-imagination and updated version of std.mmfile that features
/// some minor enhancements, such as APIs similar to File.
public class MmFileDocument : MmFile, IDocument
{
    private void *address;
    
    /// New mmfile.
    this(string path, int flags)
    {
        super(path,
            flags & MMFlags.read ?
                MmFile.Mode.read : flags & MMFlags.exists ?
                    MmFile.Mode.readWrite : MmFile.Mode.readWriteNew,
            0,
            address);
    }
    
    /// Read at position.
    /// Params:
    ///     position = Offset position.
    ///     buffer = 
    /// Returns: Slice.
    ubyte[] readAt(long position, ubyte[] buffer)
    {
        return buffer = cast(ubyte[])this[position..position+buffer.length];
    }
    
    /// Total size of mapped file.
    /// Returns: Size in bytes.
    long size()
    {
        return long.max;
    }
}
