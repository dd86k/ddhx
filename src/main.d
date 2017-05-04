module main;

import ddhx;

int main(string[] args)
{
	import std.stdio, std.file : exists, isDir;
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