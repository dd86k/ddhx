/// Implements edits.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module edits;

import std.container.slist;

enum WriteMode
{
    readOnly,
    insert,
    overwrite
}

/// Represents a single edit
struct Edit
{
    WriteMode mode;
    long position;	/// Absolute offset of edit
    long value;     /// 
    int size;       /// Size of payload in bytes
}

struct EditHistory
{
    size_t index;
    size_t count;
    SList!long history;
    const(char)[] name = "ov";
    int status;
    
    bool dirty()
    {
        return status != 0;
    }
    
    void markSave()
    {
        status = 1;
    }
    
    void add(long value, long address, WriteMode mode)
    {
        
    }
    
    void undo()
    {
        
    }
    
    //Edit[] get(long low, long high)
}