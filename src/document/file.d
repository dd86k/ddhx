/// File document implementation.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module document.file;

import document.base;
import os.file;

/// File document.
class FileDocument : IDocument
{
    /// New file document from path.
    this(string path, bool readonly)
    {
        file.open(path, readonly ? OFlags.read | OFlags.exists : OFlags.readWrite);
    }
    
    /// Size of document in bytes.
    /// Returns: Size in bytes.
    long size()
    {
        return file.size();
    }
    
    /// Read at this position.
    /// Params:
    ///     pos = File position.
    ///     buffer = Buffer.
    /// Returns: Slice.
    ubyte[] readAt(long pos, ubyte[] buffer)
    {
        file.seek(Seek.start, pos);
        return file.read(buffer);
    }
    
    /// Close file document.
    void close()
    {
        file.close();
    }
    
private:
    OSFile file;
}