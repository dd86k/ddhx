/// Simple dumper UI, no interactive input.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module dumper;

import std.stdio;
import std.file;
import core.stdc.stdlib : malloc;
import display;
import transcoder;
import utils.math;

private enum CHUNKSIZE = 1024 * 1024;

// NOTE: if path is null, then stdin is used
int dump(string path, int columns,
    long skip, long length,
    int charset)
{
    scope buffer = new ubyte[CHUNKSIZE];
    
    // opAssign is bugged on ldc with optimizations
    File file;
    if (path)
    {
        file = File(path, "rb");
        
        if (skip) file.seek(skip);
    }
    else
    {
        file = stdin;
        
        // Read blocks until length
        if (skip)
        {
        Lskip:
            size_t rdsz = min(skip, CHUNKSIZE);
            if (file.rawRead(buffer[0..rdsz]).length == CHUNKSIZE)
                goto Lskip;
        }
    }
    
    if (columns == 0)
        columns = 16;
    
    disp_init(false);
    
    disp_header(columns);
    
    ulong address;
    foreach (chunk; file.byChunk(CHUNKSIZE))
    {
        disp_update(address, chunk, columns);
        
        address += chunk.length;
    }
    
    return 0;
}
