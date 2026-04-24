/// Dummy editor used in integration testing.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.editor.dummy;

import ddhx.document.base : IDocument;
import ddhx.editor.base : IDocumentEditor, IDirtyRange, PieceInfo;
import ddhx.platform : NotImplementedException;

class DummyDocumentEditor : IDocumentEditor
{
    this(immutable(ubyte)[] data = ['h','e','l','l','o'])
    {
        _data = data;
    }
    
    typeof(this) open(IDocument)
    {
        throw new NotImplementedException();
    }
    
    void close()
    {
        throw new NotImplementedException();
    }

    long size()
    {
        return _data.length;
    }
    
    void markSaved()
    {
        // Do nothing
    }

    ubyte[] view(long position, void* data, size_t size)
    {
        return view(position, (cast(ubyte*)data)[0..size]);
    }

    ubyte[] view(long position, ubyte[] buffer)
    {
        if (position < 0 || position >= _data.length)
            return [];
        size_t start = cast(size_t) position;
        size_t avail = _data.length - start;
        size_t len = buffer.length < avail ? buffer.length : avail;
        buffer[0..len] = cast(ubyte[]) _data[start .. start + len];
        return buffer[0..len];
    }

    bool edited()
    {
        return false;
    }

    void replace(long position, const(void)* data, size_t len)
    {
        throw new NotImplementedException();
    }

    void insert(long position, const(void)* data, size_t len)
    {
        throw new NotImplementedException();
    }

    void remove(long position, long len)
    {
        throw new NotImplementedException();
    }

    long undo()
    {
        throw new NotImplementedException();
    }

    long redo()
    {
        throw new NotImplementedException();
    }

    void coalescing(bool) {}
    
    void patternInsert(long, long, const(void)*, size_t)
    {
        throw new NotImplementedException();
    }
    
    void patternReplace(long, long, const(void)*, size_t)
    {
        throw new NotImplementedException();
    }
    
    void fileInsert(long, IDocument)
    {
        throw new NotImplementedException();
    }
    
    void fileReplace(long, IDocument)
    {
        throw new NotImplementedException();
    }

    IDirtyRange dirtyRegions(bool includeDisplaced = false)
    {
        throw new NotImplementedException();
    }

    PieceInfo[] dirtyPieceInfos(bool includeDisplaced = false)
    {
        throw new NotImplementedException();
    }

private:
    immutable(ubyte)[] _data;
}