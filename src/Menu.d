module Menu;

import std.stdio;
import ddcon;
import ddhx;

//TODO: Number searching: Inverted bool (native to platform)
//TODO: String searching: Inverted bool (native to platform)
//TODO: Settings handler
//      set <option> <value>
//      save

/**
 * Internal command prompt.
 */
void EnterMenu()
{
    import std.array : split;
    import Searcher;
    //import std.algorithm.iteration : splitter, filter;
    ClearMsg;
    SetPos(0, 0);
    write(">");
    //TODO: Remove empty entries.
    //TODO: Wrap arguments with commas
    string[] e = split(readln[0..$-1]);
    //string[] e = splitter(readln[0..$-1], ' ').filter!(a => a != null);

    UpdateOffsetBar;
    if (e.length > 0) {
        switch (e[0]) { // toUpper...
        case "g", "goto":
            if (e.length > 1)
                switch (e[1]) {
                case "e", "end":
                    Goto(CurrentFile.size - Buffer.length);
                    break;
                case "h", "home", "s":
                    Goto(0);
                    break;
                default:
                    GotoStr(e[1]);
                    break;
                }
            break;
            case "s", "search": // Search
                //TODO: Figure a way to figure out signed numbers.
                //      "sbyte" ? (Very possible!
                if (e.length > 1)
                switch (e[1]) {
                case "byte":
                    if (e.length > 2)
                        e[1] = e[2];
                    else
                        MessageAlt("Missing argument. (Byte)");
                    goto SEARCH_BYTE;
                case "short", "ushort":
                    if (e.length > 2) {
                        SearchUShort(e[2]);
                    } else
                        MessageAlt("Missing argument. (UShort)");
                    break;
                case "string":
                    if (e.length > 2)
                        SearchUTF8String(e[2]);
                    else
                        MessageAlt("Missing argument. (String)");
                    break;
                default:
                    if (e.length > 1)
                        MessageAlt("Invalid type.");
                    else
                        MessageAlt("Missing type.");
                    break;
                }
                break;
            case "ss": // Search ASCII/UTF-8 string
                if (e.length > 1)
                    SearchUTF8String(e[1]);
                else
                    MessageAlt("Missing argument. (String)");
                break;
            case "ss16": // Search UTF-16 string
                if (e.length > 1)
                    SearchUTF16String(e[1]);
                else
                    MessageAlt("Missing argument. (String)");
                break;
            case "sb": // Search byte
SEARCH_BYTE:
                if (e.length > 1) {
                    import Utils : unformat;
                    long l;
                    if (unformat(e[1], l)) {
                        SearchByte(l & 0xFF);
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
                    UpdateOffsetBar;
                    UpdateDisplay;
                }
                break;
            case "r", "refresh":
                RefreshAll;
                break;
            case "q", "quit": Exit; break;
            case "about": ShowAbout; break;
            case "version": ShowInfo; break;
            case "h", "help": ShowHelp; break;
            default: MessageAlt("Unknown command: " ~ e[0]); break;
        }
    }
}

void ShowHelp()
{
    //TODO: "Scroll" system and etc. (Important!!)
    //TODO: Make help text a file.
    enum helpstr =
`Shortcuts:
q: Quit
h: This help screen

Commands:
g|goto: Goto <FilePosition>
i|info: Display file information
o|offset: Change offset type

Navigation
Up/Down Arrows: Go backward or forward a line (by width)
Left/Right Arrow: Go backward or forward a byte
Home/End: Align by line
^Home/^End: Go to begining or end of file`;
    Clear;
    SetPos(0, 0);
    writeln(helpstr);
    MessageAlt(" q:Return");
    while (1)
    {
        const KeyInfo e = ReadKey;
        switch (e.keyCode)
        {
        case Key.Q:
            UpdateDisplay;
            UpdateOffsetBar;
            UpdatePositionBar;
            return;
        default:
        }
    }
}

private void ShowAbout()
{
    MessageAlt("Written by dd86k in D. Copyright (c) dd86k 2017");
}

private void ShowInfo()
{
    MessageAlt("Using ddhx version " ~ APP_VERSION);
}