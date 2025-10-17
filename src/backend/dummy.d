/// Dummy editor used in integration testing.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module backend.dummy;

import document.base : IDocument;
import backend.base : IDocumentEditor;

class DummyDocumentEditor : IDocumentEditor
{
    this(immutable(ubyte)[] data = ['h','e','l','l','o'])
    {
        _data = data;
    }
    
    typeof(this) open(IDocument)
    {
        throw new Exception("Not implemented");
    }

    long size()
    {
        return _data.length;
    }

    void save(string target)
    {
        throw new Exception("Not implemented");
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
        throw new Exception("Not implemented");
    }

    void insert(long position, const(void)* data, size_t len)
    {
        throw new Exception("Not implemented");
    }

    void remove(long position, size_t len)
    {
        throw new Exception("Not implemented");
    }

    long undo()
    {
        throw new Exception("Not implemented");
    }

    long redo()
    {
        throw new Exception("Not implemented");
    }
    
private:
    immutable(ubyte)[] _data;
}