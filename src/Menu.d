module Menu;

import std.stdio;
import Poshub;
import ddhx;

/**
 * Internal command prompt.
 */
void EnterMenu()
{
    SetPos(0, 0);
    writef("%*s", WindowWidth, "");
    SetPos(0, 0);
    write(">");
    const string e = readln()[0..$-1];

    switch (e) { // toUpper...
        case "i", "info": PrintFileInfo; break;
        case "about": ShowAbout; break;
        case "version": break;
        case "search": break;
        case "q", "quit": Exit; break;
        default: break;
    }
}

private void PrintFileInfo()
{
    import Utils : formatsize;
    import std.format : format;
    import std.file : getAttributes;
    const uint a = getAttributes(Filepath);
    char[7] c;
    version (Windows)
    { import core.sys.windows.winnt; // FILE_ATTRIBUTE_*
        c[0] = a & FILE_ATTRIBUTE_READONLY ? 'r' : '-';
        c[1] = a & FILE_ATTRIBUTE_HIDDEN ? 'h' : '-';
        c[2] = a & FILE_ATTRIBUTE_SYSTEM ? 's' : '-';
        c[3] = a & FILE_ATTRIBUTE_ARCHIVE ? 'a' : '-';
        c[4] = a & FILE_ATTRIBUTE_TEMPORARY ? 't' : '-';
        c[5] = a & FILE_ATTRIBUTE_COMPRESSED ? 'c' : '-';
        c[6] = a & FILE_ATTRIBUTE_ENCRYPTED ? 'e' : '-';
    }
    else version (Posix)
    {

    }
    MessageAlt(format("%s %s %s",
        c, // File attributes
        formatsize(CurrentFile.size), // File formatted size
        CurrentFile.name)
    );
}