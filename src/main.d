/*
 * main.d : CLI entry point
 * Some of these functions are private for linter reasons
 */

module main;

import std.stdio;
import ddhx;
import SettingHandler;

//TODO: CLI SWITCHES
// --dump: Dump into stdout (which then user can redirect)
// -sb: Search byte, e.g. -sb ffh -> init -> Echo result

private int main(string[] args)
{
    import std.getopt : getopt, GetoptResult, GetOptException, config;

    if (args.length <= 1) // We need a file!
    {
        PrintHelp;
        return 0;
    }

    __gshared GetoptResult r;
    try {
        r = getopt(args,
            "w", "Set the number of bytes per line, 'a' being automatic.", &HandleWCLI,
            "o", "Set offset type.", &HandleOCLI,
            "v|version", "Print version information.", &PrintVersion);
    } catch (GetOptException ex) {
        stderr.writeln("Error: ", ex.msg);
        return 1;
    }

    if (r.helpWanted)
    {
        PrintHelp;
    }
    else
    {
        import std.file : exists, isDir;
        string file = args[$ - 1];

        if (exists(file))
        {
            if (isDir(file))
            {
                stderr.writeln(`E: "`, file, `" is a directory, exiting`);
                return 3;
            }

            CurrentFile = File(file);

            if ((fsize = CurrentFile.size) == 0)
            {
                stderr.writeln("E: Empty file, exiting");
                return 4;
            }
        }
        else
        {
            stderr.writeln(`E: File "`, file, `" doesn't exist, exiting`);
            return 2;
        }

        Start; // start ddhx
    }

    return 0;
}

extern (C)
private void PrintHelp()
{
    puts(
`Interactive hexadecimal file viewer.
Usage:
  ddhx  [Options] file
  ddhx  {-h|--help|-v|--version}

Option             Description
  -w               Set the number of bytes per line, 'a' being automatic
  -o               Set offset type
  -v, --version    Print version screen and quit
  -h, --help       Print help screen and quit`
    );
}

extern (C)
private void PrintVersion()
{
    import core.stdc.stdlib : exit;
    printf(
        "ddhx " ~ APP_VERSION ~ "  (" ~ __TIMESTAMP__  ~ ")\n" ~
        "Compiled ddhx with " ~ __VENDOR__ ~ " v%d\n" ~
        "MIT License: Copyright (c) dd86k 2017\n" ~
        "Project page: <https://github.com/dd86k/ddhx>\n",
        __VERSION__
    );
    exit(0); // getopt hack
}