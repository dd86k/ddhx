/// Dummy editor used in integration testing.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module editor.dummy;

import document.base : IDocument;
import editor.base : IDocumentEditor, IDirtyRange;
import platform : NotImplementedException;

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
        return cast(ubyte[])_data;
    }

    ubyte[] view(long position, ubyte[] buffer)
    {
        return cast(ubyte[])_data;
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

private:
    immutable(ubyte)[] _data;
}