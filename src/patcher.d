/// Patch management.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module patcher;

// NOTE: Basic idea
//
//       history (contains patches)
//         List of patches applied in-order.
//
//       chunks
//         Chunks are pre-calculated on overwrite/insertion/deletion.
//         Say they are 4K, they should be 4K-aligned (helps coalescing).
//         Could be a RedBlack tree (std.container.rbtree) since chunks
//         are unique. (based on their position)

import std.container.array  : Array;
import std.container.rbtree : RedBlackTree;
import std.exception : enforce;
import core.stdc.string : memcpy;
import core.stdc.stdlib : malloc, realloc, free;

enum PatchType : short
{
    replace,
    insertion,
    deletion,
}

/// Represents a patch
struct Patch
{
    /// Base position of the patch
    long address;
    /// Type of patch being applied,
    PatchType type;
    /// Status flags
    int status;
    /// Size of patch
    size_t size;
    // Insertion and Overwrite: new data
    // Deletion: old data
    /// New patch data.
    ///
    /// This data is copied by the Patcher when added.
    const(void) *newdata;
    /// Old patch data.
    ///
    /// This data is copied by the Patcher when added.
    const(void) *olddata;
}

// 
class PatchManager
{
    // datasize = Initial and incremental size of data buffer for holding patch data.
    this(size_t initsize = 0, size_t incsize = 4096)
    {
        patch_buffer.length = initsize;
        param_increment = incsize;
    }
    
    private
    void prepare(ref Patch patch)
    {
        // If we can't contain data for patch, increase buffer
        size_t newsize = patch_used + patch.size * 2;
        if (newsize >= patch_buffer.length)
        {
            // Try aligned increment
            size_t tempt = patch_buffer.length + param_increment;
            // If the temptative size is still too small... Add size of patch anyway
            if (tempt < newsize)
                tempt = newsize;
            patch_buffer.length = tempt;
        }
        
        // NOTE: System needs data
        //       data-less inserts (e.g., 1000 of this type) are not supported
        enforce(patch.newdata, "assert: patch.newdata");
        //enforce(patch.olddata, "assert: patch.olddata");
        
        // Copy its data into buffers
        void *buf0 = patch_buffer.ptr + patch_used;
        memcpy(buf0, patch.newdata, patch.size);
        patch.newdata = buf0; // new address
        patch_used += patch.size;
        
        // Copy old data if it has any
        if (patch.olddata)
        {
            void *buf1 = buf0 + patch.size;
            memcpy(buf1, patch.olddata, patch.size);
            patch.olddata = buf1; // new address
            patch_used += patch.size;
        }
    }
    
    // Remove last patch.
    /*
    void remove()
    {
        if (patches.length == 0)
            return; // Nothing to remove
        
        // Remove last patch
        Patch patch = patches.back();
        patches.removeBack();
        
        patch_used -= patch.size;
        if (patch.olddata)
            patch_used -= patch.size;
        
        // TODO: Decrease patch_buffer.length by param_increment
    }
    // Range interface
    public alias removeBack = remove;
    */
    
    size_t count()
    {
        return patches.length;
    }
    
    Patch opIndex(size_t i)
    {
        // Let it throw if out of bounds
        return patches[i];
    }
    
    void insert(size_t i, Patch patch)
    {
        prepare(patch);
        
        if (patches.length == 0 || i >= patches.length)
        {
            patches.insert(patch);
        }
        else if (i < patches.length)
        {
            patches[i] = patch;
        }
    }
    
private:
    /// Size of initial and incremental patch data buffer
    size_t param_increment;
    
    /// Buffer for new and old patch data
    ubyte[] patch_buffer;
    /// Amount of buffer used
    size_t  patch_used;
    
    // NOTE: SList
    //       The .insert alias is mapped to .insertFront, which puts last inserted
    //       elements as the first element, making it useless with foreach (starts
    //       with last inserted element, which we don't want). On top of the fact
    //       that foreach_reverse is unavailable with SList.
    /// History stack
    Array!Patch patches; // Array!T supports slicing
}
unittest
{
    static immutable ubyte[] data0 = [ 0xfe ];
    
    scope PatchManager patches = new PatchManager();
    patches.insert(0, Patch(0, PatchType.replace, 0, 1, data0.ptr, null));
    patches.insert(1, Patch(1, PatchType.replace, 0, 1, data0.ptr, null));
    patches.insert(2, Patch(2, PatchType.replace, 0, 1, data0.ptr, null));
    
    assert(patches[0].address == 0);
    assert(patches[1].address == 1);
    assert(patches[2].address == 2);
    
    patches.insert(2, Patch(10, PatchType.replace, 0, 1, data0.ptr, null));
    assert(patches[2].address == 10);
}

/// Represents a chunk buffer.
///
/// This is used to speedup view rendering by precalculating patches into it.
struct Chunk
{
    /// Actual logical position of chunk.
    ///
    /// Set by ChunkManager.
    long position;
    /// Allocated data.
    ///
    /// Set by ChunkManager.
    void *data;
    /// Capacity of the chunk, its allocated size.
    ///
    /// Set by ChunkManager.
    size_t length;
    /// Amount of data used in this chunk, its logical size.
    size_t used;
    /// Amount of data written by the source document.
    size_t orig;
    /// Patch ID.
    ///
    /// Currently used to count the number of patches applied in this chunk.
    /// This eases memory management. When an undo operation is performed and
    /// id reaches 0, the chunk is deleted.
    uint id;
}

// Utility to help with address alignment
private
long align64(long v, size_t alignment)
{
	long mask = alignment - 1;
    // NOTE: v+mask "rounds" up (e.g., v=1,a=4 returns 4)
	return v & ~mask;
}
unittest
{
    assert(align64( 0, 16) == 0);
    assert(align64( 1, 16) == 0);
    assert(align64( 2, 16) == 0);
    assert(align64(15, 16) == 0);
    assert(align64(16, 16) == 16);
    assert(align64(17, 16) == 16);
    assert(align64(31, 16) == 16);
    assert(align64(32, 16) == 32);
    assert(align64(33, 16) == 32);
}

// Manages chunks
//
// Caller is responsible for populating data into chunks
//
// NOTE: For simplicity, chunks are SIZE aligned.
class ChunkManager
{
    // chksize = Size of chunk, smaller uses less memory but might be more fragmented.
    this(size_t chksize = 4096)
    {
        assert(chksize > 0, "chksize > 0");
        param_size = chksize;
    }
    
    // Caller must fill chunk data manually
    Chunk* create(long position)
    {
        // Using malloc eases memory management
        void *data = malloc(param_size);
        enforce(data, "assert: ChunkManager.create:malloc");
        
        long basepos = align64(position, param_size);
        chunks[basepos] = Chunk(basepos, data, param_size, 0, 0, 0);
        
        // ptr returned is in heap anyway, so after its insertion
        return basepos in chunks;
    }
    
    Chunk* locate(long position)
    {
        return align64(position, param_size) in chunks;
    }
    
    void remove(Chunk *chunk)
    {
        enforce(chunk,      "chunk != null");
        enforce(chunk.data, "chunk.data != null");
        
        free(chunk.data);
        
        chunks.remove(chunk.position);
    }
    
    void flush()
    {
        chunks.rehash();
    }

private:
    size_t param_size;
    
    // NOTE: Eventually use std.container.rbtree.RedBlackTree
    //       Using an AA will eventually lead to complications when managing
    //       neighbour chunks (e.g., coalescing, data inserts and deletions)
    Chunk[long] chunks;
}
unittest
{
    scope ChunkManager chunks = new ChunkManager(32);
    
    assert(chunks.locate(0)  == null);
    assert(chunks.locate(42) == null);
    
    Chunk *chunk0 = chunks.create(0);
    assert(chunk0);
    assert(chunk0.position == 0);
    assert(chunk0.length == 32);
    assert(chunk0.data);
    
    chunk0 = chunks.locate(0);
    assert(chunk0);
    assert(chunk0.position == 0);
    assert(chunk0.length == 32);
    assert(chunk0.data);
    
    Chunk *chunk1 = chunks.create(42);
    assert(chunk1);
    assert(chunk1.position == 32);
    assert(chunk1.length == 32);
    assert(chunk1.data);
    
    chunk1 = chunks.locate(42);
    assert(chunk1);
    assert(chunk1.position == 32);
    assert(chunk1.length == 32);
    assert(chunk1.data);
    
    // Emulate a patch being applied
    chunk1.used = 1;
    (cast(ubyte*)chunk1.data)[0] = 0xff;
    // Later... Re-located
    chunk1 = chunks.locate(42);
    assert((cast(ubyte*)chunk1.data)[0] == 0xff);
    assert(chunk1.used == 1);
}
