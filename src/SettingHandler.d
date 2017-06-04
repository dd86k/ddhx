module SettingHandler;

import std.stdio;
import ddhx;
import Utils : unformat;
import core.stdc.stdlib : exit;

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
    import ddcon : WindowWidth;
    if (val[0] == 'a') {
        version (Windows) {
//TODO: Fix with CLI, returns 65535 (why can't Windows work?)
        if (!cli)
            BytesPerRow = cast(ushort)(((WindowWidth - 10) / 4) - 1);
        } else {
        BytesPerRow = cast(ushort)(((WindowWidth - 10) / 4) - 1);
        }
    } else {
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