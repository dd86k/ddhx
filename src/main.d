module main;

import std.stdio, std.file : exists, isDir;
import ddhx;

int main(string[] args)
{
	{
		string filename = args[$ - 1];

		if (exists(filename))
        {
            if (isDir(filename))
            {
                writeln("\"", filename, "\" is a directory.");
                return 4;
            }
			else CurrentFile = File(filename);
        }
		else
		{
			writeln("File \"", filename, "\" doesn't exist.");
			return 3;
		}
	}

    Start();
    return LastErrorCode;
}