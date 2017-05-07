module main;

import std.stdio;
import ddhx;

//TODO: -sb ffh (+Echo flag) -> Initiate -> Echo result

int main(string[] args)
{
	import std.file : exists, isDir;

	if (args.length <= 1)
	{
		PrintHelp;
		return 0;
	}

	Filepath = args[$ - 1];

	if (exists(Filepath))
	{
		if (isDir(Filepath))
		{
			writeln(`"`, Filepath, `" is a directory. Exiting.`);
			return 4;
		}
		CurrentFile = File(Filepath);
	}
	else
	{
		writeln(`File "`, Filepath, `" doesn't exist. Exiting.`);
		return 3;
	}

    Start();
    return LastErrorCode;
}

private void PrintHelp()
{
	writeln("ddhx\t<File>");
	writeln("ddhx\t{-h|--help|--version}");
}

private void PrintVersion()
{

}