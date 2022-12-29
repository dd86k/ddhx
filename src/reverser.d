module reverser;

import std.stdio;
import editor;
import os.file;
import error;

int start(string outpath)
{
    // editor: hex input
    // outfile: binary output
    enum BUFSZ = 4096;
    ubyte[BUFSZ] data = void;
    
    OSFile binfd = void;
    if (binfd.open(outpath, OFlags.write))
    {
        stderr.writefln("error: %s", systemMessage(binfd.syscode()));
        return 2;
    }
    
L_READ:
    ubyte[] r = editor.read(data);
    
    if (editor.err)
    {
        return 3;
    }
    
    foreach (ubyte b; r)
    {
        if (b >= '0' && b <= '9')
        {
            outnibble(binfd, b - 0x30);
        }
        else if (b >= 'a' && b <= 'f')
        {
            outnibble(binfd, b - 0x57);
        }
        else if (b >= 'A' && b <= 'F')
        {
            outnibble(binfd, b - 0x37);
        }
    }
    
    if (editor.eof)
    {
        outfinish(binfd);
        return 0;
    }
    
    goto L_READ;
}

private:

__gshared bool  low;
__gshared ubyte data;

void outnibble(ref OSFile file, int nibble)
{
    if (low == false)
    {
        data = cast(ubyte)(nibble << 4);
        low = true;
        return;
    }
    
    low = false;
    ubyte b = cast(ubyte)(data | nibble);
    file.write(&b, 1);
}

void outfinish(ref OSFile file)
{
    if (low == false) return;
    
    file.write(&data, 1);
}