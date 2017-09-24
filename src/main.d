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

    GetoptResult r;
    try {
        r = getopt(args,
            "w|width", "Set the number of bytes per line, 'a' being automatic.", &HandleWCLI,
            "o|offset", "Set offset type.", &HandleOCLI,
            "m|mode", "Set view mode type.", &HandleMCLI,
            "v|version", "Print version information.", &PrintVersion);
    } catch (GetOptException ex) {
        stderr.writeln("Error: ", ex.msg);
        return 1;
    }

    if (r.helpWanted)
    {
        PrintHelp;
        writeln("\nOption             Description");
        foreach (it; r.options) { // "custom" defaultGetoptPrinter
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
        string file = args[$ - 1];

        if (exists(file))
        {
            if (isDir(file))
            {
                writeln(`"`, file, `" is a directory, exiting.`);
                return 1;
            }

            CurrentFile = File(file);

            if ((fsize = CurrentFile.size) == 0)
            {
                stderr.writeln("Empty file, exiting.");
                return 1;
            }
        }
        else
        {
            writeln(`File "`, file, `" doesn't exist, exiting.`);
            return 1;
        }

        Start;
    }

    return 0;
}

private void PrintHelp()
{
    printf("Interactive hexadecimal file viewer.\n");
    printf("Usage:\n");
    printf("  ddhx\t[Options] file\n");
    printf("  ddhx\t{-h|--help|-v|--version}\n");
}

private void PrintVersion()
{
    import core.stdc.stdlib : exit;
    printf("ddhx %s  (%s)\n", &APP_VERSION[0], &__TIMESTAMP__[0]);
    printf("Compiled %s with %s v%d\n", &__FILE__[0], &__VENDOR__[0], __VERSION__);
    printf("MIT License: Copyright (c) dd86k 2017\n");
    printf("Project page: <https://github.com/dd86k/ddhx>\n");
    exit(0); // getopt hack
}