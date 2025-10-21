/// Base interface to implemement a document editor.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module backend.base;

import document.base : IDocument;

interface IDocumentEditor
{
    /// Open with document.
    typeof(this) open(IDocument);
    
    /// Return size of document, with edits, in bytes.
    long size();
    
    /// Save document to file path.
    void save(string target);
    
    // TODO: Change ubyte[] to either const(ubyte)[] or immutable(ubyte)[]
    
    /// View document at position using buffer.
    ubyte[] view(long position, void *data, size_t size);
    /// Ditto.
    ubyte[] view(long position, ubyte[] buffer);
    
    /// Returns true if the document was edited since last open/save.
    bool edited();
    
    /// Replace (overwrite) data.
    void replace(long position, const(void) *data, size_t len);
    /// Insert data.
    void insert(long position, const(void) *data, size_t len);
    /// Delete data.
    void remove(long position, size_t len);
    
    /// Returns: Position
    long undo();
    /// Returns: Postion+Length
    long redo();
}

version (unittest)
{

void editorTests(T : IDocumentEditor)()
{
    import document.memory : MemoryDocument;
    
    // HACK: getSymbolsByUDA(mixin(__MODULE__), TestDoc) didn't work out
    
    // Tests without document
    static immutable void function()[] tests = [
        &test_empty!T,
        &test_edit!T,
        &test_replace!T,
        &test_undo_redo!T,
        &test_save!T,
    ];
    static foreach (test; tests)
        test();
    
    // Tests with document
    static immutable ubyte[] data = [ // 32 bytes, 8 bytes per row
        0xf2, 0x49, 0xe6, 0xea, 0x32, 0xb0, 0x90, 0xcf,
        0x96, 0xf6, 0xba, 0x97, 0x34, 0x2b, 0x5d, 0x0a,
        0x0e, 0xce, 0xb1, 0x6b, 0xe4, 0xc6, 0xd4, 0x36,
        0xe1, 0xe6, 0xd5, 0xb7, 0xad, 0xe3, 0x16, 0x41,
    ];
    static immutable void function(IDocument)[] tests_doc = [
        &test_doc!T,
        &test_doc_edit!T,
    ];
    scope IDocument doc = new MemoryDocument(data);
    foreach (test; tests_doc)
        test(doc);
}

private:

//
// Tests without document
//

// Empty
void test_empty(T : IDocumentEditor)()
{
    scope T e = new T();
    ubyte[32] buffer;
    assert(e.view(0, buffer) == []);
    assert(e.edited() == false);
    assert(e.size() == 0);
}
// Empty with modifications
void test_edit(T : IDocumentEditor)()
{
    scope T e = new T();
    ubyte[32] buffer;
    string data0 = "test";
    e.replace(0, data0.ptr, data0.length);
    assert(e.size() == 4);
    assert(e.edited());
    assert(e.view(0, buffer[0..4]) == data0);
    assert(e.view(0, buffer)     == data0);
}
// Replace
void test_replace(T : IDocumentEditor)()
{
    scope T e = new T();
    ubyte[32] buffer;
    string data0 = "test";
    e.replace(0, data0.ptr, data0.length);
    assert(e.edited());
    assert(e.size() == 4);
    assert(e.view(0, buffer) == "test");
    char c = 's';
    e.replace(3, &c, char.sizeof);
    assert(e.edited());
    assert(e.size() == 4);
    assert(e.view(0, buffer) == "tess");
    e.replace(1, &c, char.sizeof);
    assert(e.edited());
    assert(e.size() == 4);
    assert(e.view(0, buffer) == "tsss");
}
// TODO: Insert
// TODO: Delete
// TODO: Replace+Insert
// TODO: Replace+Delete
// TODO: Insert+Delete
// TODO: Replace+Insert+Delete
// TODO: Replace+Insert+Delete+Undo+Redo
// TODO: Everything (Replace+Insert+Delete+Undo+Redo+Save)
// Undo/Redo
void test_undo_redo(T : IDocumentEditor)()
{
    scope T e = new T();
    string data0 = "test";
    e.replace(0, data0.ptr, data0.length);
    char c = 's';
    // "test" <-> "tess" <-> "tsss"
    e.replace(3, &c, char.sizeof); // "test" -> "tess"
    e.replace(1, &c, char.sizeof); // "tess" -> "tsss"
    
    ubyte[32] buffer;
    assert(e.view(0, buffer) == "tsss");
    assert(e.undo() == 1); // "tsss" -> "tess"
    assert(e.view(0, buffer) == "tess");
    assert(e.undo() == 3); // "tess" -> "test"
    import logger : log;
    assert(e.view(0, buffer) == "test");
    assert(e.undo() == 0);
    assert(e.view(0, buffer) == []);
    
    assert(e.undo() < 0); // past limit
    assert(e.view(0, buffer) == []);
    
    assert(e.redo() == 4);
    assert(e.view(0, buffer) == data0);
    assert(e.redo() == 4);
    assert(e.view(0, buffer) == "tess");
    assert(e.redo() == 2);
    assert(e.view(0, buffer) == "tsss");
    
    assert(e.redo() < 0); // past limit
    assert(e.view(0, buffer) == "tsss");
}
// Save
void test_save(T : IDocumentEditor)()
{
    import std.file : remove, readText;
    import std.conv : text;
    
    scope T e = new T();
    
    string data0 = "test";
    e.replace(0, data0.ptr, data0.length);
    
    static immutable string path = "test_tmp_test0";
    try
    {
        e.save(path);
        string t = readText(path);
        if (t != data0)
            throw new Exception(text(path, ": readText(path) != data0, got: \"", t, "\""));
    }
    catch (Exception ex)
    {
        throw ex;
    }
    try remove(path); // remove and don't complain
    catch (Exception) {}
}

//
// Tests with document
//

void test_doc(T : IDocumentEditor)(IDocument doc)
{
    scope T e = new T().open(doc);
    ubyte[] buffer0; buffer0.length = doc.size();
    ubyte[] buffer1; buffer1.length = doc.size();
    assert(e.edited() == false);
    assert(e.view(0, buffer0) == doc.readAt(0, buffer1));
    assert(e.size() == doc.size());
}
void test_doc_edit(T : IDocumentEditor)(IDocument doc)
{
    scope T e = new T().open(doc);
    ubyte[] buffer0; buffer0.length = doc.size();
    ubyte[] buffer1; buffer1.length = doc.size();
    
    char c = 'c';
    e.replace(2, &c, c.sizeof);
    
    ubyte[] expected = doc.readAt(0, buffer1[0..8]);
    expected[2] = 'c';
    
    assert(e.view(0, buffer0[0..8]) == expected);
}

} // version (unittest)