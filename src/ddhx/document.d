/// Handles multiple types of 
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.document;

import ddhx.os.file;
import ddhx.os.error;
import ddhx.logger;
import std.file;

private enum DocType
{
    none,
    disk,
    process,
}

// For any type of opening
enum DocOpenFlags
{
    readonly = 1,
    create = 2,
}

/*
private enum FileStatus
{
    /// Document doesn't exist, and on save, it will be created
    newfile = 1 << 8,
    // Document is read-only
    //readonly = 1 << 9,
}
*/

struct Document
{
    private union
    {
        OSFile file;
    }
    
    private int status;
    
    void openFile(string path, int flags)
    {
        if (isDir(path))
            throw new Exception("Is a directory");
        
        status = DocType.disk;
        
        /*
        // 
        if (exists(path) == false)
        {
            if (flags & DocOpenFlags.readonly)
                throw new Exception("Cannot create new read-only document");
            
            // Create empty file
            
            return;
        }
        */
        
        int e = file.open(path, flags & DocOpenFlags.readonly ? OFlags.read : OFlags.readWrite);
        if (e)
            throw new Exception(messageFromCode(e));
    }
    
    //void openProcess(int pid, int flags)
    
    ubyte[] read(void *buffer, size_t size)
    {
        switch (cast(ubyte)status) with (DocType) {
        case disk:
            return file.read(cast(ubyte*)buffer, size);
        default:
            throw new Exception("Not implemented: "~__FUNCTION__);
        }
    }
    
    ubyte[] readAt(long location, void *buffer, size_t size)
    {
        trace("loc=%d buffer=%s size=%d", location, buffer, size);
        switch (cast(ubyte)status) with (DocType) {
        case disk:
            if (file.seek(Seek.start, location))
                return null;
            return file.read(cast(ubyte*)buffer, size);
        default:
            throw new Exception("Not implemented: "~__FUNCTION__);
        }
    }
    
    //TODO: WriteAt
    
    long size()
    {
        switch (cast(ubyte)status) with (DocType) {
        case disk:
            return file.size();
        case process:
            return -1;
        default:
            throw new Exception("Not implemented: "~__FUNCTION__);
        }
    }
}