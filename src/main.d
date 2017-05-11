module main;

import std.stdio;
import ddhx;

//TODO: -sb ffh (+Echo flag) -> Initiate -> Echo result
//TODO: CLI SWITCHES
// -w: Byte width, -w a OR 0 being automatic (make a handler? (only for a))
// --dump

int main(string[] args)
{
	import std.getopt;

	if (args.length <= 1)
	{
		PrintHelp;
		return 0;
	}

	GetoptResult r;
	try {
		r = getopt(args,
            "version|v", "Print version information.", &PrintVersion);
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
				return 4;
			}
			CurrentFile = File(Filepath);
		}
		else
		{
			writeln(`File "`, Filepath, `" doesn't exist, exiting.`);
			return 3;
		}

		Start();
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
    writefln("ddhx %s (%s) ", APP_VERSION, __TIMESTAMP__);
    writeln("MIT License: Copyright (c) dd86k 2017");
    writeln("Project page: <https://github.com/dd86k/ddhx>");
    writefln("Compiled %s with %s v%s", __FILE__, __VENDOR__, __VERSION__);
    exit(0); // getopt hack
}