module Menu;

import std.stdio : readln, write;
import core.stdc.stdio : printf;
import ddcon, ddhx, Searcher;
import std.format : format;
import SettingHandler;

//TODO: count command (stat)
//TODO: Invert aliases
/*TODO: Aliases
    si: Search int
    sl: Search long
    utf8: search utf-8 string, etc.
*/

/**
 * Internal command prompt.
 */
void EnterMenu(string init = null)
{
    import std.array : split;
    //import std.algorithm.iteration : splitter, filter;
    ClearMsg;
    SetPos(0, 0);
    printf(">");
    if (init)
        write(init);
    //TODO: Wrap arguments with commas and remove empty entries
    string[] e = (init ~ readln[0..$-1]).split; // split ' ', no empty entries

    UpdateOffsetBar;
    const size_t argl = e.length;
    if (argl == 0) return;

    switch (e[0]) {
    case "g", "goto":
        if (argl > 1)
            switch (e[1]) {
            case "e", "end":
                Goto(fsize - BufferLength);
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
        case "sw": // Search UTF-16 string
            if (argl > 1)
                SearchUTF16String(e[1]);
            else
                MessageAlt("Missing argument. (String)");
            break;
        //TODO: UTF-32 search alias
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
                import SettingHandler : HandleOffset;
                HandleOffset(e[1]);
                UpdateOffsetBar;
                UpdateDisplayRaw;
            }
            break;
        case "clear":
            Clear;
            UpdateOffsetBar;
            UpdateDisplayRaw;
            UpdateInfoBarRaw;
            break;
        /*
            * Setting manager
            */
        case "set":
            if (argl > 1) {
                import std.format : format;
                switch (e[1]) {
                case "width", "w":
                    if (argl > 2) {
                        HandleWidth(e[2]);
                        PrepBuffer;
                        RefreshAll;
                    }
                    break;
                case "offset", "o":
                    if (argl > 2) {
                        HandleOffset(e[2]);
                        Clear;
                        RefreshAll;
                    }
                    break;
                default:
                    MessageAlt(format("Unknown setting parameter: %s", e[1]));
                    break;
                }
            } else MessageAlt("Missing setting parameter");
            break;
        case "r", "refresh": RefreshAll; break;
        case "q", "quit": Exit; break;
        case "about": ShowAbout; break;
        case "version": ShowInfo; break;
        default: MessageAlt("Unknown command: " ~ e[0]); break;
    }
}

private void ShowAbout()
{
    MessageAlt("Written by dd86k. Copyright (c) dd86k 2017-2018");
}

private void ShowInfo()
{
    MessageAlt("Using ddhx version " ~ APP_VERSION);
}