module Menu;

import std.stdio;
import Poshub;

/**
 * Internal command prompt.
 */
void EnterMenu()
{
    SetPos(0, 0);
    writef("%*s", WindowWidth, " ");
    SetPos(0, 0);
    write(">");
    const string e = readln()[0..$-1];

    switch (e) { // toUpper...
        case "i", "info": break;
        case "about": break;
        case "version": break;
        case "search": break;
        case "q", "quit": Exit; break;
        default: break;
    }
}

private void Exit()
{
    import core.stdc.stdlib : exit;
    Clear();
    exit(0);
}