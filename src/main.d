module main;

import ddhx;

int main(string[] args)
{
	import std.stdio, std.file : exists, isDir;
	{
		string filename = args[$ - 1];

		if (exists(filename))
        {
            if (isDir(filename))
            {
                writeln(`"`, filename, `" is a directory. Exiting.`);
                return 4;
            }
			CurrentFile = File(filename);
        }
		else
		{
			writeln(`File "`, filename, `" doesn't exist. Exiting.`);
			return 3;
		}
	}

    Start();
    return LastErrorCode;
}