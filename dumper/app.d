/// Simple dumper UI, no interactive input.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module dumper.app;

import std.stdio;
import std.file;
import core.stdc.stdlib : malloc;
import ddhx.common;
import ddhx.transcoder;
import ddhx.utils.math;
import ddhx.os.terminal;
import ddhx.display;

private enum CHUNKSIZE = 1024 * 1024;

// NOTE: if path is null, then stdin is used
int dump(string path)
{
    scope buffer = new ubyte[CHUNKSIZE];
    
    // opAssign is bugged on ldc with optimizations
    File file;
    if (path)
    {
        file = File(path, "rb");
        
        if (_opos) file.seek(_opos);
    }
    else
    {
        file = stdin;
        
        // Read blocks until length
        if (_opos)
        {
        Lskip:
            size_t rdsz = min(_opos, CHUNKSIZE);
            if (file.rawRead(buffer[0..rdsz]).length == CHUNKSIZE)
                goto Lskip;
        }
    }
    
    disp_init(false);
    disp_header(_ocolumns);
    ulong address;
    foreach (chunk; file.byChunk(CHUNKSIZE))
    {
        disp_update(address, chunk, _ocolumns);
        
        address += chunk.length;
    }
    
    return 0;
}
