/// List utilities.
///
/// Authors: dd86k <dd@dax.moe>
/// Copyright: © dd86k <dd@dax.moe>
/// License: BSD-3-Clause-Clear
module list;

// Imported from Alicedbg.
// Replaced Alicedbg errors with Exceptions, foreach interfaces, and some other stuff.
// Using this over GC guarantees memory will be freed instead of
// "when pressured" (which is never).

import core.stdc.stdlib : malloc, calloc, realloc, free;

struct List(T)
{
    size_t cap;     /// Currently capacity in number of items
    size_t count;   /// Current item count
    T* buffer;      /// Item buffer
    
    // Disable copies since it can actually cause issues
    // Example seen with writef (segfault)... To be fixed later?
    @disable this(this);

    this(size_t newcapacity)
    {
        init(newcapacity);
    }
    ~this()
    {
        deinit();
    }
    
    void init(size_t newcapacity)
    {
        if (newcapacity == 0)
            throw new Exception("list:itemsize==0");
        T *p = cast(T*) realloc(buffer, T.sizeof * newcapacity);
        if (p == null)
            throw new Exception("list:malloc==null");
        
        cap = newcapacity;
        count = 0;
        buffer = p;
    }
    void deinit()
    {
        if (buffer) free(buffer);
        buffer = null;
    }

    // foreach interfaces
    int opApply(scope int delegate(ref T) dg)
    {
        if (buffer == null)
            return 0;
        for (size_t i; i < count; i++)
        {
            if (int r = dg(buffer[i])) return r;
        }
        return 0;
    }
    int opApply(scope int delegate(size_t, ref T) dg)
    {
        if (buffer == null)
            return 0;
        for (size_t i; i < count; i++)
        {
            if (int r = dg(i, buffer[i])) return r;
        }
        return 0;
    }
    
    T opIndex(size_t idx)
    {
        if (buffer == null)
            init(16);
        if (idx >= count)
            throw new Exception("idx");
        
        return buffer[idx];
    }

    // append
    void opOpAssign(string op)(T item) if (op == "~")
    {
        if (buffer == null)
            init(16);

        // Increase capacity
        if (count >= cap)
        {
            reserve_(cap << 1); // double its capacity
        }
        
        buffer[count++] = item;
    }
    
    void reserve_(size_t newcapacity)
    {
        // The new capacity is already the current capacity, do nothing
        if (newcapacity == cap)
            return;
        
        // Can't afford to lose items in this economy
        if (newcapacity < count)
            throw new Exception("newcapacity < list.count");
        
        // NOTE: MSVC will always assign a new memory block
        void* p = realloc(buffer, T.sizeof * newcapacity);
        if (p == null)
            throw new Exception("list:t==null");
        buffer = cast(T*) p;
        
        // realloc(3) should have copied data to new block
        // Only need to readjust buffer pointer
        cap = newcapacity;
    }
    
    void reset()
    {
        count = 0;
    }
}
unittest
{
    static immutable int[] data = [ 55, 8086, 33 ];
    enum CAP = 4;
    List!int list = List!int(CAP);
    assert(list.buffer);
    assert(list.cap     >= CAP);
    assert(list.count   == 0);
    
    list ~= data[0];
    assert(list.count   == 1);
    assert(list[0]      == data[0]);
    
    list ~= data[1];
    assert(list.count   == 2);
    assert(list[1]      == data[1]);
    
    list ~= data[2];
    assert(list.count   == 3);
    assert(list[2]      == data[2]);
    
    destroy(list);
    assert(list.buffer  == null);
}
