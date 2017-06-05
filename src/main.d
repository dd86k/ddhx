/*
 * main.d : CLI entry point
 * Some of these functions are private for linter reasons
 */

module main;

import std.stdio;
import ddhx;
import SettingHandler;

//TODO: CLI SWITCHES
// -o: override default offset viewing type
// --dump: Dump into file (like xxd)
// -sb: Search byte, e.g. -sb ffh -> init -> Echo result

private int main(string[] args)
{
    import std.getopt : getopt, GetoptResult, GetOptException;

    if (args.length <= 1)
    {
        PrintHelp;
        return 0;
    }

    GetoptResult r;
    try {
        r = getopt(args,
            "w|width", "Set the width of the display in bytes, 'a' is automatic.", &HandleWCLI,
            //"o|offset", "Set the offset viewing type.", &HandleOCLI,
            "v|version", "Print version information.", &PrintVersion);
    } catch (GetOptException ex) {
        stderr.writeln("Error: ", ex.msg);
        return 1;
    }

    if (r.helpWanted)
    {
        PrintHelp;
        writeln("\nOption             Description");
        foreach (it; r.options)
        { // "custom" defaultGetoptPrinter
            writefln("%*s, %-*s%s%s",
                4,  it.optShort,
                12, it.optLong,
                it.required ? "Required: " : " ",
                it.help);
        }
    }
    else
    {
        import std.file : exists, isDir;
        Filepath = args[$ - 1];

        if (exists(Filepath))
        {
            if (isDir(Filepath))
            {
                writeln(`"`, Filepath, `" is a directory, exiting.`);
                return 1;
            }

            CurrentFile = File(Filepath);

            if (CurrentFile.size == 0)
            {
                stderr.writeln("0-Byte file, exiting.");
                return 1;
            }
        }
        else
        {
            writeln(`File "`, Filepath, `" doesn't exist, exiting.`);
            return 1;
        }

        Start;
    }
    return LastErrorCode;
}

private void PrintHelp() // ..And description.
{
    writeln("Interactive hexadecimal file viewer.");
    writeln("Usage:");
    writeln("  ddhx\t[Options] <File>");
    writeln("  ddhx\t{-h|--help|--version}");
}

private void PrintVersion()
{
    import core.stdc.stdlib : exit;
debug {
    writefln("ddhx %s-debug  (%s) ", APP_VERSION, __TIMESTAMP__);
    writefln("Compiled %s with %s v%s", __FILE__, __VENDOR__, __VERSION__);
} else
    writefln("ddhx %s  (%s) ", APP_VERSION, __TIMESTAMP__);
    writeln("MIT License: Copyright (c) dd86k 2017");
    writeln("Project page: <https://github.com/dd86k/ddhx>");
    exit(0); // getopt hack, or 2x optional string values could work
}