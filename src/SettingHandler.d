module SettingHandler;

import std.stdio;
import ddhx;
import Utils : unformat;
import core.stdc.stdlib : exit;
import std.format : format;

private enum
    ENOPARSE = "Could not parse number",
    ETRANGE = "Number %d out of range (1-%d)";

/**
 * Handles the Width setting from getopt.
 * Params:
 *   opt = Usually "w|width"
 *   val = Value to assign
 */
void HandleWCLI(string opt, string val)
{
    HandleWidth(val, true);
}

/**
 * Handles the Width setting.
 * Params:
 *   val = Value to assign
 *   cli = From CLI (Assumes false by default)
 */
void HandleWidth(string val, bool cli = false)
{
    switch (val[0]) {
    case 'a': // Automatic
        version (Windows) {
//TODO: Fix with CLI, returns 65535 (why can't Windows work?)
        if (!cli) BytesPerRow = getBytesPerRow;
        } else {
        BytesPerRow = getBytesPerRow;
        }
        break;

    case 'd': // Default
        BytesPerRow = 16;
        break;
    
    default:
        long l;
        if (unformat(val, l)) {
            if (l < 1 || l > ushort.max) {
                if (cli) {
                    writefln(ETRANGE, l, ushort.max);
                    exit(1);
                } else
                    MessageAlt("Number out of range");
                    return;
            }
            BytesPerRow = l & 0xFFFF;
        } else {
            if (cli) {
                writeln(ENOPARSE);
                exit(1);
            } else 
                MessageAlt(ENOPARSE);
        }
    }
}

/**
 * Handle offset CLI option.
 * Params:
 *   opt = Option
 *   val = Option value
 */
void HandleOCLI(string opt, string val)
{
    HandleOffset(val, true);
}

/**
 * Handle offset setting.
 * Params:
 *   val = Value
 *   cli = From CLI?
 */
void HandleOffset(string val, bool cli = false)
{
    switch (val[0]) {
    case 'o','O': CurrentOffsetType = OffsetType.Octal; break;
    case 'd','D': CurrentOffsetType = OffsetType.Decimal; break;
    case 'h','H': CurrentOffsetType = OffsetType.Hexadecimal; break;
    default:
        if (cli) {
            writef("Unknown mode parameter: %s", val);
            exit(1);
        } else {
            MessageAlt(format(" Invalid offset type: %s", val));
        }
        break;
    }
}

private ushort getBytesPerRow()
{
    import ddcon : WindowWidth;
    final switch (CurrentDisplayMode)
    {
        case DisplayMode.Default:
            return cast(ushort)((WindowWidth - 11) / 4);
        case DisplayMode.Text, DisplayMode.Data:
            return cast(ushort)((WindowWidth - 11) / 3);
    }
}