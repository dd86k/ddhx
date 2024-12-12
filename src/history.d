/// History management.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module history;

import std.container.array : Array;

struct History // History entry
{
    long address;
    size_t len;
    void *newbuf;
    // TODO: Old data
    // TODO: Operation (insert, delete, overwrite)
}
// Manages history
struct HistoryStack
{
    this(size_t size)
    {
        data.length = size;
        next        = data.ptr;
    }
    
    // Add a new history entry to stack
    void add(long address, void *newdata, size_t len)
    {
        // If we're lacking the space in the data buffer,
        // double its size
        if (next + len >= data.ptr + data.length)
        {
            data.length *= 2;
        }
        
        import core.stdc.string : memcpy;
        stack.insert(History(address, len, next));
        memcpy(next, newdata, len);
        next += len;
    }
    
    // NOTE: For simplicity, apply function is here
    // Apply edit history to buffer depending on its base address
    ubyte[] apply(long basepos, ubyte[] buffer, size_t count = 0)
    {
        // If no count were specified, then it's every entry
        if (count == 0)
            count = stack.length;
        
        foreach (entry; stack[0..count])
        {
            // e.g. cell[1]: pos + 1
            // If edit address (e.g., 0x1234) - base address (0x1230)
            // corresponds to cell offset 4, apply edit
            // base address = 0x100 for count = 64 (0x150)
            // edit[0].address = 0x90  -> not applied
            // edit[0].address = 0x110 -> cell 16 (0x10 = edit.address - basepos)
            // edit[0].address = 0x160 -> not applied
            long p = entry.address - basepos;
            if (p < buffer.length)
            {
                import std.algorithm.comparison : min;
                import core.stdc.string : memcpy;
                // TODO: fix overrun
                //size_t l = min(entry.len, buffer.length - (p + entry.len));
                size_t l = entry.len;
                memcpy(buffer.ptr + p, entry.newbuf, l);
            }
            else if (p == buffer.length)
            {
                buffer ~= *cast(ubyte*)entry.newbuf;
            }
        }
        
        return buffer;
    }
    
    // Returns number of elements in history
    size_t count()
    {
        return stack.length;
    }
    
private:
    /// Data buffer
    ubyte[] data;
    /// Pointer to next entry
    ubyte  *next;

    // NOTE: SList
    //       The .insert alias is mapped to .insertFront, which puts last inserted
    //       elements as the first element, making it useless with foreach (starts
    //       with last inserted element, which we don't want). On top of the fact
    //       that foreach_reverse is unavailable with SList.
    /// History stack
    Array!History stack; // Array!T supports slicing
}
unittest
{
    HistoryStack history = HistoryStack(4096);
    
    // Add first entry
    string data0 = "test";
    history.add(0, cast(void*)data0.ptr, data0.length);
    assert(history.stack.length == 1);
    
    // Check first entry
    ubyte[32] buffer;
    history.apply(0, buffer[]);
    assert(buffer[0..data0.length] == data0);
    
    buffer[] = 0; // reset
    
    // Add second entry and check all
    enum POS = 10;
    string data1 = "hello";
    history.add(POS, cast(void*)data1.ptr, data1.length);
    history.apply(0, buffer[]);
    assert(history.stack.length == 2);
    assert(buffer[0..data0.length] == data0);
    assert(buffer[POS..POS+data1.length] == data1);
    
    buffer[] = 0; // reset
    
    // Only apply first entry
    history.apply(0, buffer[], 1);
    assert(buffer[0..data0.length] == data0);
}