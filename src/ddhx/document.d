/// Handles multiple types of 
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.document;

import ddhx.os.file;
import ddhx.os.error;
import std.file;

private enum DocType
{
    none,
    disk,
    process,
}

struct Document
{
    private union
    {
        OSFile file;
    }
    
    private int doctype;
    
    void openFile(string path, bool readOnly)
    {
        if (isDir(path))
            throw new Exception("Is a directory");
        int e = file.open(path, readOnly ? OFlags.read : OFlags.readWrite);
        if (e)
            throw new Exception(messageFromCode(e));
        doctype = DocType.disk;
    }
    
    //
    
    //void openProcess(int pid, bool readOnly)
    
    ubyte[] read(void *buffer, size_t size)
    {
        switch (doctype) with (DocType) {
        case disk:
            return file.read(cast(ubyte*)buffer, size);
        default:
            throw new Exception("Not implemented: "~__FUNCTION__);
        }
    }
    
    ubyte[] readAt(long location, void *buffer, size_t size)
    {
        switch (doctype) with (DocType) {
        case disk:
            file.seek(Seek.start, location);
            return file.read(cast(ubyte*)buffer, size);
        default:
            throw new Exception("Not implemented: "~__FUNCTION__);
        }
    }
    
    long size()
    {
        switch (doctype) with (DocType) {
        case disk:
            return file.size();
        case process:
            return -1;
        default:
            throw new Exception("Not implemented: "~__FUNCTION__);
        }
    }
}