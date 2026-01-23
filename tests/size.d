module tests.size;

import std.stdio;
import os.terminal;

@system unittest {
    terminalInit(TermFeat.rawInput); // hack for terminalTell
    scope(exit) terminalRestore();
    
    TerminalSize size = terminalSize();
    writeln("Size: COLS=", size.columns, " ROWS=", size.rows);
    
    /*
    TerminalPosition pos = terminalTell();
    writeln("Position: COL=", pos.column, " ROW=", pos.row);
    */
}