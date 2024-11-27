/// Document handler.
///
/// 
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.document;

import ddhx.os.file;
import ddhx.os.error;
import ddhx.logger;
import std.file;
import stack;

// NOTE: For performance reasons, edits should be ordered by edit position ascending

private enum DocType
{
    none,
    disk,
    process,
    // Memory buffer on new document but not yet written to disk
    memorybuf,
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

enum WriteMode : ubyte
{
    readOnly,
    insert,
    overwrite
}

/// Represents a single edit
struct Edit
{
    long position;	/// Absolute offset of edit
    ubyte value;     /// Value of digit/nibble
    WriteMode mode; /// Edit mode used (insert, overwrite, etc.)
}

private class NotImplementedException : Exception
{
    this(string func = __FUNCTION__)
    {
        super("Not implemented: "~func);
    }
}

/// Represents a single document instance.
///
/// Every document instance handles the minimum: cursor position,
/// edit management (adding, removing, history), write mode, etc.
struct Document
{
private:
    union
    {
        OSFile file;
    }
    
    DocType doctype;
    
    
    /// Edit history stack
    Stack!Edit _ehistory;
    
    WriteMode writemode;
    
public:
    void openFile(string path, bool readonly)
    {
        if (isDir(path))
            throw new Exception("Is a directory");
        
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
        
        int e = file.open(path, readonly ? OFlags.read : OFlags.readWrite);
        if (e)
            throw new Exception(messageFromCode(e));
        
        doctype = DocType.disk;
        writemode = readonly ? WriteMode.readOnly : WriteMode.overwrite;
    }
    
    //void openProcess(int pid, int flags)
    
    void close()
    {
        assert(false, "todo");
    }
    
    long seek(long location)
    {
        switch (doctype) with (DocType) {
        case disk:
            if (file.seek(Seek.start, location))
                throw new Exception("Failed to seek medium");
            return file.tell();
        default:
            throw new NotImplementedException();
        }
    }
    long tell()
    {
        switch (doctype) with (DocType) {
        case disk:
            return file.tell();
        default:
            throw new NotImplementedException();
        }
    }
    
    ubyte[] read(void *buffer, size_t size)
    {
        switch (doctype) with (DocType) {
        case disk:
            return file.read(buffer, size);
        default:
            throw new NotImplementedException();
        }
    }
    
    ubyte[] readAt(long location, void *buffer, size_t size)
    {
        trace("loc=%d buffer=%s size=%d", location, buffer, size);
        switch (doctype) with (DocType) {
        case disk:
            if (file.seek(Seek.start, location))
                return null;
            return file.read(buffer, size);
        default:
            throw new NotImplementedException();
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
            throw new NotImplementedException();
        }
    }
    
    WriteMode writeMode()
    {
        return writemode;
    }
    WriteMode writeMode(WriteMode mode)
    {
        return writemode = mode;
    }
}