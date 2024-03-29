module tests.input;

import std.stdio;
import os.terminal;

@system unittest {
    enum MODS = Mod.ctrl | Mod.alt | Mod.shift;
    terminalInit(TermFeat.inputSys);
    
    // Tests terminalInit if we haven't screwed with stdout
    writeln("Exit by CTRL+C");
    
    TerminalInput input = void;
L_READ:
    terminalInput(input);
    
    writef(
    "TerminalInput: type=%s key=%s",
    cast(InputType)input.type, cast(Key)(cast(short)input.key)
    );
    
    if (input.key & Mod.ctrl) write("+ctrl");
    if (input.key & Mod.alt) write("+alt");
    if (input.key & Mod.shift) write("+shift");
    
    writeln;
    
    goto L_READ;
}