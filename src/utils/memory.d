/// Memory utilities.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module utils.memory;

import std.stdio : File;
import std.container.array;

//TODO: Use OutBuffer or Array!ubyte when writing changes?
struct MemoryStream
{
    private ubyte[] buffer;
    private long position;
    
    bool err, eof;
    
    void cleareof()
    {
        eof = false;
    }
    void clearerr()
    {
        err = false;
    }
    
    void copy(ubyte[] data)
    {
        buffer = new ubyte[data.length];
        buffer[0..$] = data[0..$];
    }
    void copy(File stream)
    {
        buffer = buffer.init;
        //TODO: use OutBuffer+reserve (if possible to get filesize)
        foreach (ubyte[] a; stream.byChunk(4096))
        {
            buffer ~= a;
        }
    }
    
    long seek(long pos)
    {
        /*final switch (origin) with (Seek) {
        case start:*/
            return position = pos;
        /*    return 0;
        case current:
            position += pos;
            return 0;
        case end:
            position = size - pos;
            return 0;
        }*/
    }
    
    ubyte[] read(size_t size)
    {
        long p2 = position + size;
        
        if (p2 > buffer.length)
            return buffer[position..$];
        
        return buffer[position..p2];
    }
    
    // not inout ref, just want to read
    ubyte[] opSlice(size_t n1, size_t n2)
    {
        return buffer[n1..n2];
    }
    
    long size() { return buffer.length; }
    
    long tell() { return position; }
}
