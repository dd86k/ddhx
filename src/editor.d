/// Implements a file buffer and file I/O.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module editor;

private import std.stdio : File;
private import os.file : OSFile, OFlags, Seek;
private import std.container.slist;
private import std.stdio : File;
private import std.path : baseName;
private import core.stdc.stdio : FILE;
private import utils.memory;
private import std.array : uninitializedArray;
private import core.stdc.stdlib : malloc, calloc, free;
private import core.stdc.string : memcmp;

/// Editor I/O mode.
enum IoMode : ushort
{
    file,       /// Normal file.
    mmfile,     /// Memory-mapped file.
    stream,     /// Standard streaming I/O, often pipes.
    memory,     /// Typically from a stream buffered into memory.
}

// NOTE: Edition mode across files
//       HxD2 keeps the edition mode on a per-file basis.
//       While Notepad++ does not, it may have a dedicated read-only field.

enum EditError
{
    none,
    io,
    memory,
    bufferSize,
}

/// Represents a single edit
struct Edit
{
    long position;	/// Absolute offset of edit
    int offset;     /// Offset to byte group in digits
    int value;	/// Payload
    // or ubyte[8]?
}

/// 
struct Editor
{
    private enum DEFAULT_BUFSZ = 4096;
    
    /// 
    //IoMode iomode;
    
    private union
    {
        OSFile       osfile;
        //OSMmFile     mmfile;
        //File         stream;
        //MemoryStream memstream;
    }
    
    struct Edits
    {
        size_t index;
        size_t count;
        Edit[long] list;
        SList!long history;
        const(char)[] name = "ov";
    }
    Edits edits;
    bool insert;
    bool readonly;
    
    /// 
    private ubyte* rdbuf;
    /// 
    private size_t rdbufsz;
    /// File position
    private long position;
    
    int lasterr;
    
    int seterr(int er)
    {
        return (lasterr = er);
    }
    
    int open(string path, bool exists, bool viewonly)
    {
        readonly = viewonly;
        int flags = readonly ? OFlags.read : OFlags.readWrite;
        if (exists) flags |= OFlags.exists;
        
        if (osfile.open(path, flags))
            return seterr(EditError.io);
        
        return 0;
    }
    
    void close()
    {
        return osfile.close();
    }
    
    //
    //
    //
    
    //TODO: Consider const(char)[] errorMsg()
    //      Clear message buffer on retrieval
    
    bool error()
    {
        return lasterr != 0;
    }
    void clearerr()
    {
        lasterr = 0;
    }
    bool eof()
    {
        return osfile.eof;
    }
    
    void setbuffer(size_t newsize)
    {
        version (Trace) trace("newsize=%u", newsize);
        
        // If there is an exisiting size, must have been allocated before
        if (rdbufsz) free(rdbuf);
        
        // Allocate read buffer
        rdbuf = cast(ubyte*)malloc(newsize);
        if (rdbuf == null)
        {
            lasterr = EditError.memory;
        }
        rdbufsz = newsize;
    }
    
    //
    // Editing
    //
    
    bool dirty()
    {
        return edits.index > 0;
    }
    
    // digit: true value (not a character)
    int addEdit(long editpos, int digit, int groupmax)
    {
        int ndpos; // new digit position
        edits.list.update(editpos,
            // edit does not exist, add it to the list
            // and update history
            () {
                Edit nedit; // New edit
                return nedit;
            },
            // edit exists at this position
            // if so, increase the digit position when able
            (ref Edit oldedit) {
            }
        );
        return ndpos;
    }
    
    void removeEdit(long editpos)
    {
        if (readonly)
            return;
        
    }
    
    void removeLastEdit()
    {
        if (readonly)
            return;
        
    }
    
    /+void editMode(EditMode emode)
    {
        edits.mode = emode;
        final switch (emode) with (EditMode) {
        case overwrite: edits.modeString = "ov"; return;
        case insert:    edits.modeString = "in"; return;
        case readOnly:  edits.modeString = "rd"; return;
        case view:      edits.modeString = "vw"; return;
        }
    }
    
    ubyte[] peek()
    {
        return null;
    }+/
    
    //
    // File operations
    //
    
    bool seek(long pos, Seek seek = Seek.start)
    {
        version (Trace) trace("mode=%s", fileMode);
        position = pos;
        /*final switch (input.mode) with (FileMode) {
        case file:
            position = io.osfile.seek(Seek.start, pos);
            return io.osfile.err;
        case mmfile:
            position = io.mmfile.seek(pos);
            return io.mmfile.err;
        case memory:
            position = io.memory.seek(pos);
            return io.memory.err;
        case stream:
            io.stream.seek(pos);
            position = io.stream.tell;
            return io.stream.error;
        }*/
        osfile.seek(seek, pos);
        return osfile.err;
    }
    
    long tell()
    {
        version (Trace) trace("mode=%s", fileMode);
        /*final switch (input.mode) with (FileMode) {
        case file:      return io.osfile.tell;
        case mmfile:    return io.mmfile.tell;
        case stream:    return io.stream.tell;
        case memory:    return io.memory.tell;
        }*/
        return position;
    }
    
    long size()
    {
        return osfile.size();
    }
    
    ubyte[] read()
    {
        version (Trace) trace("mode=%s", fileMode);
        /*final switch (input.mode) with (FileMode) {
        case file:   return buffer.output = io.osfile.read(buffer.input);
        case mmfile: return buffer.output = io.mmfile.read(buffer.size);
        case stream: return buffer.output = io.stream.rawRead(buffer.input);
        case memory: return buffer.output = io.memory.read(buffer.size);
        }*/
        ubyte[] res = osfile.read(rdbuf, rdbufsz);
        //TODO: Edit res
        return res;
    }
    
    //TODO: Turning into MemoryStream should be optional
    //      e.g., dump -> only read until skip
    //            ddhx -> read all into memory
    //      slurp -> only read skip amount
    //      readAll -> read all into MemoryStream
    //TODO: Rename to convert or toMemoryStream
    /// Read stream into memory.
    /// Params:
    ///     skip = Number of bytes to skip.
    ///     length = Length of data to read into memory.
    /// Returns: Error code.
    /+int slurp(long skip = 0, long length = 0)
    {
        //NOTE: Can't close File, could be stdin
        //      Let attached Editor close stream if need be
        
        import core.stdc.stdio : fread;
        import core.stdc.stdlib : malloc, free;
        import std.algorithm.comparison : min;
        import std.outbuffer : OutBuffer;
        
        enum READ_SIZE = 4096;
        
        version (Trace) trace("skip=%u length=%u", skip, length);
        
        // Skiping
        
        ubyte *tmpbuf = cast(ubyte*)malloc(READ_SIZE);
        if (tmpbuf == null)
        {
            return seterr(EditError.memory);
        }
        scope(exit) free(tmpbuf);
        
        FILE *fp = io.stream.getFP;
        
        if (skip)
        {
            do
            {
                size_t bsize = cast(size_t)min(READ_SIZE, skip);
                skip -= fread(tmpbuf, 1, bsize, fp);
            } while (skip > 0);
        }
        
        // Reading
        
        scope outbuf = new OutBuffer;
        
        // If no length set, just read as much as possible.
        if (length == 0) length = long.max;
        
        // Loop ends when len (read length) is under the buffer's length
        // or requested length.
        do {
            size_t bsize = cast(size_t)min(READ_SIZE, length);
            size_t len = fread(tmpbuf, 1, bsize, fp);
            if (len == 0) break;
            outbuf.put(b[0..len]);
            if (len < bsize) break;
            length -= len;
        } while (length > 0);
        
        version (Trace) trace("outbuf.offset=%u", outbuf.offset);
        
        io.memory.copy(outbuf.toBytes);
        
        version (Trace) trace("io.memory.size=%u", io.memory.size);
        
        input.mode = FileMode.memory;
    }+/
}