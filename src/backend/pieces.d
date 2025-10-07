module backend.pieces;

import logger;
import backend.base : IDocumentEditor;
import document.base : IDocument;
import std.container.array : Array;
import std.container.rbtree : RedBlackTree;

enum Source
{
    original,   /// Original document
    buffer,     /// In-memory buffer
    temp,       /// Temporary file if edit is too large
}

enum MEMORY_THRESHOLD = 64 * 1024;

struct Piece
{
    Source source;
    union
    {
        struct Original
        {
            long file_offset;
            size_t length;
        }
        Original original;
    }
}

class PieceDocumentEditor : IDocumentEditor
{
    typeof(this) open(IDocument doc)
    {
        throw new Exception(ENOTIMPL);
    }

    long size()
    {
        return logical_size;
    }

    void save(string target)
    {
        throw new Exception(ENOTIMPL);
    }

    ubyte[] view(long position, void* data, size_t size)
    {
        throw new Exception(ENOTIMPL);
    }

    ubyte[] view(long position, ubyte[] buffer)
    {
        throw new Exception(ENOTIMPL);
    }

    bool edited()
    {
        return history_idx != history_idx_saved;
    }

    void replace(long position, const(void)* data, size_t len)
    {
        throw new Exception(ENOTIMPL);
    }

    long undo()
    {
        throw new Exception(ENOTIMPL);
    }

    long redo()
    {
        throw new Exception(ENOTIMPL);
    }

private:
    IDocument basedoc;
    long logical_size;
    
    size_t history_idx;
    size_t history_idx_saved;
    
    ubyte[] add_buffer;
    Array!Piece pieces;
    RedBlackTree!long indexed;
    
    static immutable string ENOTIMPL = "Not implemented";
}

/// New empty document
/*unittest
{
    log("TEST-0001");
    
    scope PieceDocumentEditor e = new PieceDocumentEditor();
    
    ubyte[32] buffer;
    
    log("Initial read");
    assert(e.view(0, buffer[]) == []);
    assert(e.edited() == false);
    assert(e.size() == 0);
    
    log("Write data at position 0");
    string data0 = "test";
    e.replace(0, data0.ptr, data0.length);
    assert(e.edited());
    assert(e.view(0, buffer[0..4]) == data0);
    assert(e.view(0, buffer[])     == data0);
    assert(e.size() == 4);
    
    log("Emulate an overwrite edit");
    char c = 's';
    e.replace(3, &c, char.sizeof);
    assert(e.view(0, buffer[]) == "tess");
    assert(e.size() == 4);
    
    log("Another...");
    e.replace(1, &c, char.sizeof);
    assert(e.view(0, buffer[]) == "tsss");
    assert(e.size() == 4);
    
    static immutable string path = "tmp_empty";
    log("Saving to %s", path);
    e.save(path); // throws if it needs to, stopping tests
    
    // Needs to be readable after saving, obviously
    assert(e.view(0, buffer[]) == "tsss");
    assert(e.size() == 4);
    
    import std.file : remove;
    remove(path);
}

/// Emulate editing an existing document
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0002");
    
    static immutable ubyte[] data = [ // 32 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90, 0xcf,
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a,
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36,
        0xe1, 0xe6, 0xd5, 0xb7, 0xad, 0xe3, 0x16, 0x41,
    ];
    enum DLEN = data.length;
    
    ubyte[32] buffer;
    
    scope MemoryDocument doc = new MemoryDocument(data);
    
    scope PieceDocumentEditor e = new PieceDocumentEditor().attach(doc);
    assert(e.edited() == false);
    assert(e.view(0, buffer[])          == data);
    assert(e.view(0, buffer[0..4])      == data[0..4]);
    assert(e.view(DLEN-4, buffer[0..4]) == data[$-4..$]);
    assert(e.size() == data.length);
    
    ubyte[48] buffer2;
    assert(e.view(0,  buffer2[]) == data);
    assert(e.view(16, buffer2[0..16]) == data[16..$]);
    assert(e.size() == data.length);
    
    static immutable string edit0 = "aaaa";
    e.replace(4, edit0.ptr, edit0.length);
    assert(e.edited());
    assert(e.view(4, buffer[0..4]) == edit0);
    assert(e.view(0, buffer[0..4]) == data[0..4]);
    assert(e.view(8, buffer[8..$]) == data[8..$]);
    assert(e.view(2, buffer[0..8]) == data[2..4]~cast(ubyte[])edit0~data[8..10]);
    assert(e.size() == data.length);
    
    assert(e.view(0, buffer2[]) == data[0..4]~cast(ubyte[])edit0~data[8..$]);
    assert(e.size() == data.length);
    assert(e.view(8, buffer2[]) == data[8..$]);
    assert(e.size() == data.length);
    
    static immutable string path = "tmp_doc";
    e.save(path); // throws if it needs to, stopping tests
    
    // Needs to be readable after saving, obviously
    assert(e.view(2, buffer[0..8]) == data[2..4]~cast(ubyte[])edit0~data[8..10]);
    assert(e.size() == data.length);
    
    import std.file : remove;
    remove(path);
}

/// Test undo/redo
unittest
{
    log("TEST-0003");
    
    scope PieceDocumentEditor e = new PieceDocumentEditor();
    
    char a = 'a';
    e.replace(0, &a, char.sizeof);
    char b = 'b';
    e.replace(1, &b, char.sizeof);
    
    ubyte[4] buf = void;
    assert(e.view(0, buf[]) == "ab");
    assert(e.size() == 2);
    
    e.undo();
    assert(e.view(0, buf[]) == "a");
    assert(e.size() == 1);
    e.redo();
    assert(e.view(0, buf[]) == "ab");
    assert(e.size() == 2);
    try e.redo(); catch (Exception) {} // over
    assert(e.view(0, buf[]) == "ab");
    assert(e.size() == 2);
    e.undo();
    e.undo();
    assert(e.view(0, buf[]) == []);
    assert(e.size() == 0);
    try e.undo(); catch (Exception) {} // over
    assert(e.view(0, buf[]) == []);
    assert(e.size() == 0);
    e.redo();
    e.redo();
    assert(e.view(0, buf[]) == "ab");
    assert(e.size() == 2);
}

/// Test undo/redo with document
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0004");
    
    scope MemoryDocument doc = new MemoryDocument([ 'd', 'd' ]);
    scope PieceDocumentEditor e = new PieceDocumentEditor().attach(doc);
    
    ubyte[4] buf = void;
    assert(e.view(0, buf[]) == "dd");
    assert(e.size() == 2);
    
    char a = 'a';
    e.replace(0, &a, char.sizeof);
    char b = 'b';
    e.replace(1, &b, char.sizeof);
    
    assert(e.view(0, buf[]) == "ab");
    assert(e.size() == 2);
    
    // Undo and redo once
    e.undo();
    assert(e.view(0, buf[]) == "ad");
    assert(e.size() == 2);
    e.redo();
    assert(e.view(0, buf[]) == "ab");
    assert(e.size() == 2);
    
    // Overdoing redo
    try e.redo(); catch (Exception) {}
    assert(e.view(0, buf[]) == "ab");
    assert(e.size() == 2);
    
    // Undo all
    e.undo();
    e.undo();
    assert(e.view(0, buf[]) == "dd");
    assert(e.size() == 2);
    
    // Overdoing undo
    try e.undo(); catch (Exception) {}
    assert(e.view(0, buf[]) == "dd");
    assert(e.size() == 2);
    
    // Redo all
    e.redo();
    e.redo();
    assert(e.view(0, buf[]) == "ab");
    assert(e.size() == 2);
}

/// Test undo/redo with larger document
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0005");
    
    // new operator memset's to 0
    enum DOC_SIZE = 8000;
    scope PieceDocumentEditor e = new PieceDocumentEditor().attach(new MemoryDocument(new ubyte[DOC_SIZE]));
    
    ubyte[32] buf = void;
    assert(e.view(40, buf[0..4]) == [ 0, 0, 0, 0 ]);
    assert(e.size() == 8000);
    
    char a = 0xff;
    e.replace(41, &a, char.sizeof);
    e.replace(42, &a, char.sizeof);
    assert(e.view(40, buf[0..4]) == [ 0, 0xff, 0xff, 0 ]);
    assert(e.size() == 8000);
    
    e.undo();
    assert(e.view(40, buf[0..4]) == [ 0, 0xff, 0, 0 ]);
    assert(e.size() == 8000);
    
    e.undo();
    assert(e.view(40, buf[0..4]) == [ 0, 0, 0, 0 ]);
    assert(e.size() == 8000);
    
    e.replace(41, &a, char.sizeof);
    e.replace(42, &a, char.sizeof);
    e.replace(43, &a, char.sizeof);
    e.replace(44, &a, char.sizeof);
    e.undo();
    e.undo();
    e.undo();
    e.undo();
    assert(e.view(40, buf[0..8]) == [ 0, 0, 0, 0, 0, 0, 0, 0 ]);
    assert(e.size() == 8000);
}

/// Test appending to a document with undo/redo
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0006");
    
    static immutable ubyte[] data = [ 0xf2, 0x49, 0xe6, 0xea ];
    
    scope PieceDocumentEditor e = new PieceDocumentEditor().attach(new MemoryDocument(data));
    
    ubyte d = 0xff;
    e.replace(data.length    , &d, ubyte.sizeof);
    e.replace(data.length + 1, &d, ubyte.sizeof);
    e.replace(data.length + 2, &d, ubyte.sizeof);
    e.replace(data.length + 3, &d, ubyte.sizeof);
    
    ubyte[32] buf = void;
    assert(e.view(0, buf[0..8]) == [ 0xf2, 0x49, 0xe6, 0xea, 0xff, 0xff, 0xff, 0xff ]);
}

/// Test reading past edited chunk sizes
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0007");
    
    static immutable ubyte[] data = [ // 32 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90, 0xcf,
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a,
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36,
        0xe1, 0xe6, 0xd5, 0xb7, 0xad, 0xe3, 0x16, 0x41,
    ];
    
    // Chunk size of 16 forces .view() to get more information beyond
    // edited chunk by reading the original doc for the view buffer.
    scope PieceDocumentEditor e = new PieceDocumentEditor().attach(new MemoryDocument(data));
    
    ubyte[32] buf = void;
    assert(e.view(0, buf) == data);
    
    ubyte ff = 0xff;
    e.replace(19, &ff, ubyte.sizeof);
    assert(e.view(0, buf) == [ // 32 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90, 0xcf, // <-+- doc
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a, // <-´
        0x0e, 0xce, 0xb1, 0xff, 0xe4, 0xc6, 0xd4, 0x36, // <-+- chunk
        0xe1, 0xe6, 0xd5, 0xb7, 0xad, 0xe3, 0x16, 0x41, // <-´
    ]);
}

/// Rendering edit chunk before source document
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0008");
    
    static immutable ubyte[] data = [ // 32 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90, 0xcf,
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a,
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36,
        0xe1, 0xe6, 0xd5, 0xb7, 0xad, 0xe3, 0x16, 0x41,
    ];
    
    // Chunk size of 16 forces .view() to get more information beyond
    // edited chunk by reading the original doc for the view buffer.
    scope PieceDocumentEditor e = new PieceDocumentEditor().attach(new MemoryDocument(data));
    
    ubyte[32] buf = void;
    assert(e.view(0, buf) == data);
    
    ubyte ff = 0xff;
    e.replace(3, &ff, ubyte.sizeof);
    assert(e.view(0, buf) == [ // 32 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xff, 0x32, 0xb0, 0x90, 0xcf, // <-+- chunk
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a, // <-´
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36, // <-+- doc
        0xe1, 0xe6, 0xd5, 0xb7, 0xad, 0xe3, 0x16, 0x41, // <-´
    ]);
}

/// Rendering source document before chunk mid-view
///
/// This is an issue when the view function starts with the source
/// document, but doesn't see the edited chunk ahead, skipping it
/// entirely, especially with an offset
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0009");
    
    static immutable ubyte[] data = [ // 32 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90, 0xcf,
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a,
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36,
        0xe1, 0xe6, 0xd5, 0xb7, 0xad, 0xe3, 0x16, 0x41,
    ];
    
    scope PieceDocumentEditor e = new PieceDocumentEditor().attach(new MemoryDocument(data));
    
    ubyte[32] buf = void;
    assert(e.view(16, buf[0..16]) == data[16..$]);
    
    ubyte ff = 0xff;
    e.replace(cast(int)data.length-1, &ff, ubyte.sizeof);
    
    assert(e.view(16,  buf[0..16]) == [
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36, // <- doc
        0xe1, 0xe6, 0xd5, 0xb7, 0xad, 0xe3, 0x16, 0xff, // <- chunk
    ]);
}

/// Append data to end of chunk with a source document
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0010");
    
    static immutable ubyte[] data = [ // 28 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90, 0xcf,
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a,
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36,
        0xe1, 0xe6, 0xd5, 0xb7, 
    ];
    
    scope PieceDocumentEditor e = new PieceDocumentEditor().attach(new MemoryDocument(data));
    
    ubyte[32] buf = void;
    assert(e.view(16, buf[0..16]) == data[16..$]);
    
    ubyte ff = 0xff;
    e.replace(cast(int)data.length, &ff, ubyte.sizeof);
    
    assert(e.view(0,  buf) == [ // 29 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90, 0xcf,
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a,
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36,
        0xe1, 0xe6, 0xd5, 0xb7, 0xff
    ]);
    assert(e.view(8,  buf) == [
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a,
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36,
        0xe1, 0xe6, 0xd5, 0xb7, 0xff
    ]);
    assert(e.view(16,  buf) == [
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36,
        0xe1, 0xe6, 0xd5, 0xb7, 0xff
    ]);
    assert(e.view(24,  buf) == [
        0xe1, 0xe6, 0xd5, 0xb7, 0xff
    ]);
}

// TODO: TEST-0011 (test disabled until relevant)
//       Editor can only edit single bytes right now...
//       If you enable this test, it might pass and silently fail
/// Replace data across two chunks
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0011");
    
    static immutable ubyte[] data = [ // 16 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90, 0xcf,
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a,
    ];
    
    scope PieceDocumentEditor e = new PieceDocumentEditor().attach(new MemoryDocument(data));
    
    ubyte[16] buffer;
    
    string s = "hi";
    e.replace(7, s.ptr, s.length);
    assert(e.view(0, buffer) == [ // 16 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90,  'h', // <- chunk 0
         'i', 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a, // <- chunk 1
    ]);
}

// TODO: TEST-0012 (test disabled until relevant)
//       Editor can only edit single bytes right now...
/// Append to a chunk so much it overflows to another chunk
unittest
{
    import document.memory : MemoryDocument;
    
    log("TEST-0012");
    
    static immutable ubyte[] data = [ // 7 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90,
    ];
    
    scope PieceDocumentEditor e = new PieceDocumentEditor().attach(new MemoryDocument(data));
    
    ubyte[16] buffer;
    
    string s = "hello";
    e.replace(6, s.ptr, s.length);
    assert(e.view(0, buffer) == [ // 16 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0,  'h',  'e', // <- chunk 0
         'l',  'l',  'l',  'o'                          // <- chunk 1
    ]);
}*/