module Menu;

import std.stdio;
import Poshub;
import ddhx;

//TODO: When typing g goto menu directly

/**
 * Internal command prompt.
 */
void EnterMenu(string prefix = null)
{
    import std.array : split;
    SetPos(0, 0);
    writef("%*s", WindowWidth, "");
    SetPos(0, 0);
    write(">");
    string[] e = split(readln[0..$-1], ' ');

    if (e.length > 0)
    switch (e[0]) { // toUpper...
        case "g", "goto":
            if (e.length > 1)
                GotoStr(e[1]);
            break;
        case "search": // Search
            if (e.length > 1)
            switch (e[1][0]) {
                case '\'', '"': goto MENU_STRING;
                default: goto MENU_NUMBER;
            }
            break;
        case "ss": // Search string
MENU_STRING:
//TODO: Search string
            switch (e[1][$ - 2..$ - 1]) {
                default: break; // UTF-8
                case "\"d": break; // UTF-32
                case "\"w": break; // UTF-16
            }
            break;
        case "sb": // Search byte
MENU_NUMBER:
//TODO: Byte string
            if (e.length > 1)
            {
                import Utils : unformat;
                long l;
                if (unformat(e[1], l))
                {
                    if (l < 0 || l > 0xFF)
                    {
                        MessageAlt(
                            "Only byte ranges are supported at the moment."
                        );
                        return;
                    }
                }
            }
            break;
        case "i", "info": PrintFileInfo; break;
        case "o", "offset":
            if (e.length > 1) {
                switch (e[1][0]) {
                    case 'o': CurrentOffset = OffsetType.Octal; break;
                    case 'd': CurrentOffset = OffsetType.Decimal; break;
                    case 'h': CurrentOffset = OffsetType.Hexadecimal; break;
                    default:
                }
            }
            break;
        case "q", "quit": Exit; break;
        case "about": ShowAbout; break;
        case "version": ShowInfo; break;
        case "h", "help": ShowHelp; break;
        default: MessageAlt("Unknown command: " ~ e[0]); break;
    }
}

private void ShowHelp()
{

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

private void ShowAbout()
{
    MessageAlt("Written by dd86k. Copyright (c) 2017 dd86k");
}

private void ShowInfo()
{
    import std.format : format;
    MessageAlt(format("Using ddhx version %s", APP_VERSION));
}