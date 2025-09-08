module tests.input;

import std.stdio;
import os.terminal;

@system unittest
{
    terminalInit(TermFeat.inputSys);
    scope(exit) terminalRestore();
    terminalOnResize(&onresize);
    
    // This tests (Phobos') stdout
    writeln("Exit by CTRL+C");
    
Lread:
    TermInput input = terminalRead();
    
    writef(
    "TerminalInput: type=%s key=%s",
    cast(InputType)input.type, cast(Key)(cast(short)input.key)
    );
    
    if (input.key & Mod.ctrl)  write("+ctrl");
    if (input.key & Mod.alt)   write("+alt");
    if (input.key & Mod.shift) write("+shift");
    
    writeln;
    
    goto Lread;
}

void onresize()
{
    TerminalSize size = terminalSize();
    writefln("Resized to %dx%d", size.columns, size.rows);
}