/// History management.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module history;

import std.container.array : Array;
import core.stdc.string : memcpy;

enum HistoryType
{
    overwrite,
    insertion,
    deletion
}

// LP32: 8+4+4+4=20B
// LP64: 8+4+8+8=28B
/// Represents a history entry
struct History // History entry
{
    long address;
    HistoryType type;
    size_t size;
    // Insertion and Overwrite: new data
    // Deletion: old data
    void *data;
}

/// Iterator used in HistoryStack.iterate(size_t,size_t)
struct HistoryIterator
{
    Array!History stack;
    size_t idx;
    size_t end;
    
    bool empty()
    {
        return idx >= end;
    }
    
    History front()
    {
        return stack[idx];
    }
    
    History popFront()
    {
        return stack[idx++];
    }
}

// Manages history
class HistoryStack
{
    // data buffer size of 4096 (for a typical page)
    // entry count size of 128 (4096 / 32) assuming History might be 32B in the future
    this(size_t bufsize = 4096, size_t entrycnt = 128)
    {
        // NOTE: If bufsize=0, no data is allocated, so .ptr will be wrong
        databuf.length = bufsize;
        used        = 0;
        stack       = Array!History();
        stack.reserve(entrycnt);
    }
    
    // Add a new history entry to stack
    void add(long address, const(void) *data, size_t size, HistoryType type = HistoryType.overwrite)
    {
        // Can we fit this edit in our data buffer?
        if (used + size >= databuf.length)
        {
            // Resize to only fit this new edit
            size_t newsize = databuf.length + size;
            databuf.length = newsize;
        }
        
        void *dst = databuf.ptr + used;
        memcpy(dst, data, size); // copy data to our buffer
        stack.insert(History(address, type, size, dst)); // add entry
        used += size;
    }
    
    // TODO: void appendLast(void *newdata, size_t len);
    //       Append data to last history entry
    // TODO: void removeLast()
    
    /// Apply the history to the given buffer.
    ///
    /// Caller is responsible to populate buffer with initiate data for this
    /// function to be effective.
    /// Params:
    ///   buffer = Output buffer, will not change in size
    ///   basepos = Base (start) position relative to buffer
    /// Returns: New size of data, within buffer limits
    deprecated
    size_t apply(ubyte[] buffer, long basepos)
    {
        // Upper len in buffer, or "real" length within buffer
        size_t n;
        
        // Apply oldest to newest entries
        long shift; // affects bufidx by Deletions/Insertions
        foreach (entry; stack)
        {
            // TODO: If Insert or Deletion, update base shift by entry.size
            //       Since it affects all data
            
            // Entry's position relative to buffer's base position
            static if (ptrdiff_t.sizeof < long.sizeof)
            {
                // Overflow check (failsafe)
                // On 32-bit platforms, the difference produced might be beyond
                // the 32-bit limits, causing an overflow.
                // Realistically, a 4 GiB edit might happen, but is outside
                // the scope for a viewing buffer.
                long _ = entry.address - basepos;
                if (_ < ptrdiff_t.min || _ > ptrdiff_t.max)
                    continue;
                ptrdiff_t bufidx = cast(ptrdiff_t)_;
            }
            else
            {
                ptrdiff_t bufidx = cast(ptrdiff_t)(entry.address - basepos);
            }
            
            // End positional index
            ptrdiff_t endidx = bufidx + entry.size;
            
            // Entry's start position (relative to buffer) is completely outside.
            // It is not applicable, skip
            if (bufidx > buffer.length)
                continue;
            
            // Start of entry data starts within buffer
            
            
            // Entry data ends within buffer
            
            
            // Data steps within buffer.
            // For example, if bufidx=-1 and size=3, only the last
            // two bytes reaches buffer[0]+[1].
            if (endidx <= 0)
                continue;
            
            size_t l = endidx - bufidx;
            
            import std.algorithm.comparison : min;
            
            // TODO: fix overrun
            //size_t l = min(entry.len, buffer.length - (p + entry.len));
            // overwrite
            memcpy(buffer.ptr + bufidx, entry.data, entry.size);
            
            size_t u = bufidx + entry.size; // upper
            if (u > n)
                n = u;
        }
        
        return n;
    }
    
    // Returns number of elements in history
    size_t count()
    {
        return stack.length;
    }
    
    HistoryIterator iterate(size_t start = 0, size_t end = 0)
    {
        if (end == 0) end = stack.length;
        return HistoryIterator(stack, start, end);
    }
    
    History opIndex(size_t i)
    {
        return stack[i];
    }
    
private:
    /// Data buffer
    ubyte[] databuf;
    /// Current amount of data used. Safer than pointer algorihtm
    size_t used;

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
    scope HistoryStack history = new HistoryStack();
    
    string data0 = "test";
    assert(data0.length == 4);
    history.add(0, cast(void*)data0.ptr, data0.length);
    assert(history.stack.length == 1);
    history.add(data0.length, cast(void*)data0.ptr, data0.length);
    assert(history.stack.length == 2);
}

// Test basic entries
unittest
{
    scope HistoryStack history = new HistoryStack();
    
    // Insert first entry
    string data0 = "test";
    assert(data0.length == 4);
    history.add(0, cast(void*)data0.ptr, data0.length);
    assert(history.count == 1);
    
    // Insert second entry after the first one
    string data1 = "hello";
    history.add(data0.length, cast(void*)data1.ptr, data1.length);
    assert(history.count == 2);
    
    // Check usage with foreach
    size_t i;
    foreach (entry; history.iterate)
    {
        ++i;
    }
    assert(i == 2);
    
    i = 0;
    foreach (entry; history.iterate(0, 1))
    {
        ++i;
    }
    assert(i == 1);
    
    i = 0;
    foreach (entry; history.iterate(1, 2))
    {
        ++i;
    }
    assert(i == 1);
}

// Test growing data buffer
unittest
{
    scope HistoryStack history = new HistoryStack(0, 128);
    
    string data0 = "test";
    assert(data0.length == 4);
    history.add(0, cast(void*)data0.ptr, data0.length);
    assert(history.databuf.length >= 4);
    assert(history.used == 4);
}
