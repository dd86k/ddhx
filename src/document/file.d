/// File document implementation.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module document.file;

import document.base;
import os.file;

class FileDocument : IDocument
{
    this(string path, bool readonly)
    {
        file.open(path, readonly ? OFlags.read | OFlags.exists : OFlags.readWrite);
    }
    
    long size()
    {
        return file.size();
    }
    
    ubyte[] readAt(long pos, ubyte[] buffer)
    {
        file.seek(Seek.start, pos);
        return file.read(buffer);
    }
    
private:
    OSFile file;
}