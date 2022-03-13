module tests.input;

import std.stdio;
import ddhx.terminal;

@system unittest {
	enum MODS = Mod.ctrl | Mod.alt | Mod.shift;
	terminalInit(false);
	
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