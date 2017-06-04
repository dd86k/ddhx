module Menu;

import std.stdio;
import ddcon, ddhx, Searcher;

//TODO: Setting aliases (o -> offset, w -> width, etc.)

/**
 * Internal command prompt.
 */
void EnterMenu()
{
    import std.array : split;
    //import std.algorithm.iteration : splitter, filter;
    ClearMsg;
    SetPos(0, 0);
    write(">");
    //TODO: Remove empty entries.
    //TODO: Wrap arguments with commas
    string[] e = split(readln[0..$-1]);
    //string[] e = splitter(readln[0..$-1], ' ').filter!(a => a != null);

    UpdateOffsetBar;
    const size_t argl = e.length;
    if (argl > 0) {
        switch (e[0]) {
        case "g", "goto":
            if (argl > 1)
                switch (e[1]) {
                case "e", "end":
                    Goto(CurrentFile.size - Buffer.length);
                    break;
                case "h", "home":
                    Goto(0);
                    break;
                default:
                    GotoStr(e[1]);
                    break;
                }
            break;
            case "s", "search": // Search
                if (argl > 1) {
                    string value = e[$-1];
                    const bool a2 = argl > 2;
                    bool invert;
                    if (a2)
                        invert = e[2] == "invert";
                    switch (e[1]) {
                    case "byte":
                        if (argl > 2) {
                            e[1] = value;
                            goto SEARCH_BYTE;
                        } else
                            MessageAlt("Missing argument. (Byte)");
                        break;
                    case "short", "ushort", "word", "w":
                        if (argl > 2) {
                            SearchUInt16(value, invert);
                        } else
                            MessageAlt("Missing argument. (Number)");
                        break;
                    case "int", "uint", "doubleword", "dword", "dw":
                        if (argl > 2) {
                            SearchUInt32(value, invert);
                        } else
                            MessageAlt("Missing argument. (Number)");
                        break;
                    case "long", "ulong", "quadword", "qword", "qw":
                        if (argl > 2) {
                            SearchUInt64(value, invert);
                        } else
                            MessageAlt("Missing argument. (Number)");
                        break;
                    case "string":
                        if (argl > 2)
                            SearchUTF8String(value);
                        else
                            MessageAlt("Missing argument. (String)");
                        break;
                    case "wstring":
                        if (argl > 2)
                            SearchUTF16String(value, invert);
                        else
                            MessageAlt("Missing argument. (String)");
                        break;
                    default:
                        if (argl > 1)
                            MessageAlt("Invalid type.");
                        else
                            MessageAlt("Missing type.");
                        break;
                    }
                    break; // "search"
                }
            case "ss": // Search ASCII/UTF-8 string
                if (argl > 1)
                    SearchUTF8String(e[1]);
                else
                    MessageAlt("Missing argument. (String)");
                break;
            case "ss16": // Search UTF-16 string
                if (argl > 1)
                    SearchUTF16String(e[1]);
                else
                    MessageAlt("Missing argument. (String)");
                break;
            case "sb": // Search byte
SEARCH_BYTE:
                if (argl > 1) {
                    import Utils : unformat;
                    long l;
                    if (unformat(e[1], l)) {
                        SearchByte(l & 0xFF);
                    } else {
                        MessageAlt("Could not parse number");
                    }
                }
                break;
            case "i", "info": PrintFileInfo; break;
            case "o", "offset":
                if (argl > 1) {
                    switch (e[1][0]) {
                    case 'o','O': CurrentOffsetType = OffsetType.Octal; break;
                    case 'd','D': CurrentOffsetType = OffsetType.Decimal; break;
                    case 'h','H': CurrentOffsetType = OffsetType.Hexadecimal; break;
                    default:
                        MessageAlt(" Invalid offset type.");
                        break;
                    }
                    UpdateOffsetBar;
                    UpdateDisplay;
                }
                break;
            /*
             * Setting manager
             */
            case "set":
                if (argl > 1) {
                    import SettingHandler;
                    import std.format : format;
                    switch(e[1]) {
                    case "width":
                        if (argl > 2) {
                            HandleWidth(e[2]);
                            PrepBuffer;
                            RefreshAll;
                        }
                        break;
                    default:
                        MessageAlt(format("Unknown setting parameter: %s", e[1]));
                    }
                } else MessageAlt("Missing setting parameter");
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

/// Prints on screen
void ShowHelp()
{
    //TODO: "Scroll" system and etc?
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