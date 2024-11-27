/// Simple element stacker with overwrite capability.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module stack;

struct Stack(T)
{
    size_t index;
    size_t count;
    T[] list;
    
    bool dirty()
    {
        return index > 0;
    }
    
    void clear()
    {
        
    }
    
    void markCleared()
    {
        
    }
    
    void push(T value)
    {
        // 
        if (index == count)
        {
            list ~= value;
            ++count;
        }
        else // Overwrite
        {
            list[index] = value;
        }
        
        ++index;
    }
    
    void undo()
    {
        if (index == 0) return;
        --index;
    }
    
    T[] getAll()
    {
        return list;
    }
}
unittest
{
    Stack!size_t addresses;
    
    assert(addresses.dirty() == false);
    
    addresses.push(3);
    
    assert(addresses.dirty());
    
    addresses.undo();
    
    assert(addresses.dirty() == false);
    
    addresses.push(0x300);
    addresses.push(0x400);
    addresses.push(0x500);
    
    assert(addresses.getAll() == [ 0x300, 0x400, 0x500 ]);
}