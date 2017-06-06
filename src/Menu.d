module Menu;

import std.stdio;
import std.format : format;
import ddcon, ddhx, Searcher;

//TODO: Setting aliases (o -> offset, w -> width, etc.)
//TODO: Invert with aliases

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
            case "r", "refresh": RefreshAll; break;
            case "q", "quit": Exit; break;
            case "about": ShowAbout; break;
            case "version": ShowInfo; break;
            case "h", "help":
                if (argl > 1)
                switch (e[1]) {
                    case "commands": ShowHelpMenu; break;
                    default:
                        MessageAlt(format("Entry not found: %s", e[1]));
                        break;
                }
                else
                    ShowHelp;
                break;
            default: MessageAlt("Unknown command: " ~ e[0]); break;
        }
    }
}

private void ShowHelpMenu()
{
//TODO: Update man-page
//TODO: Alias "offset" to "set offset" then write it down
    enum str =
`Command Help

Some commands can be shortened to their alias. At the moment, it is not possible to wrap values in quotes.

Please take note that note hex notations such as 0xFF and FFH are acepted.

g|goto - Go to a file position
  Go to a file position in bytes (supports decimal and hexadecimal).
  Aliases like "home" and "end" can be used for the start and end of the file.
  Sypnosis: goto <Position>
  Example:
    Go to byte 333: goto 333
    Go to position 0x8001: goto 0x8001
    Go to the end of the file: goto end

i|info - Display file information
  Display some file information.

o|offset - Change offset type
  Change the current offset view type.
  Synopsis: offset <Type>
  Types:
    Hexadecimal
    Decimal
    Octal
  Example:
    Change type to decimal: offset d

s|search - Search for data
  Search for data, specifying a type is obligatory. Aliases are available and do not require the type. To invert the endianess, add "invert" after specifying the type.
  BUG: Invert does not work with aliases yet.
  Synopsis: search <Type> [invert] <Value>
  Types available:
    1-Byte: byte (Alias: sb)
    2-Byte: short, dw
    4-Byte: int, dd
    8-Byte: long, dq
    UTF-8/ASCII string: string (Alias: ss)
    UTF-16 string: wstring (Alias: ss16)
    UTF-32 string: dstring
  Examples:
    Search for a douleword value: search int 1337
    Search for an UTF-16BE value: search wstring invert Hello!
    Search for a byte (alias): sb ddh
    Search for an inverted 16-bit value: search short invert 0xBEBA

set - Change setting
  Change a setting.
  Synopsis: set <Setting> <Value>
  Types:
    width - Change the number of bytes displayed
  Example:
    Set 2 bytes per row: set width 2
`;
    Clear;
    SetPos(0, 0);
    writeln(str);
    HelpQuit;
}

/// Prints on screen
void ShowHelp()
{
    enum helpstr =
`Welcome to ddhx, an interactive hex file viewer.

To get help on the menu, quit this screen, then enter "help commands".

SHORTCUTS:
  q: Quit
  i: Show file information
  h: This help screen (q to quit this screen)
  F5 or r: Refresh all displays
  ENTER: Enter menu prompt

NAVIGATION:
  Up/Down Arrows: Go backward or forward a line (by width)
  Left/Right Arrow: Go backward or forward a byte
  Home/End: Align by line
  ^Home/^End: Go to begining or end of file
    BUG: Only works in Windows
`;
    Clear;
    writeln(helpstr);
    HelpQuit;
}

private void HelpQuit() {
    write(" q:Return");
    SetPos(0, 0);
    while (1)
    {
        const KeyInfo e = ReadKey;
        switch (e.keyCode)
        {
        case Key.Q:
            Clear;
            UpdateOffsetBar;
            UpdateDisplay;
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