/// Memory buffer document.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module document.memory;

import document.base : IDocument;

class MemoryDocument : IDocument
{
    void append(const(ubyte)[] data)
    {
        buffer ~= data;
    }
    
    long size()
    {
        return buffer.length;
    }
    
    ubyte[] readAt(long position, ubyte[] buf)
    {
        // no data
        if (buffer is null || buf.length == 0)
            return [];
        
        size_t p = cast(size_t)position;
        if (p >= buffer.length)
            return [];
        
        size_t e = p + buf.length;
        if (e > buffer.length)
            e = buffer.length;
        
        size_t l = e - p;
        return buf[0..l] = buffer[p..e];
    }
    
private:
    ubyte[] buffer;
}

unittest
{
    static immutable ubyte[] data = [ 0, 1, 2 ];
    
    scope MemoryDocument doc = new MemoryDocument();
    
    ubyte[1] buf1;
    assert(doc.readAt(0, buf1[]) == []);
    
    doc.append(data);
    assert(doc.buffer == data);
    
    assert(doc.readAt(0, buf1[]).length == 1);
    assert(buf1[0] == 0);
    assert(doc.readAt(1, buf1[]).length == 1);
    assert(buf1[0] == 1);
    assert(doc.readAt(2, buf1[]).length == 1);
    assert(buf1[0] == 2);
    
    ubyte[3] buf3;
    assert(doc.readAt(0, buf3[]).length == 3);
    assert(buf3[] == data);
    
    ubyte[8] buf8;
    assert(doc.readAt(0, buf8[]).length == 3);
    assert(buf8[0..data.length] == data);
    
    assert(doc.readAt(1000, buf8[]) == []);
}