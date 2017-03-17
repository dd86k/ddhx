module main;

import std.stdio, std.file : exists;
import ddhx;

void main(string[] args)
{
	//size_t argc = args.length;

	{
		string file = args[$ - 1];

		if (exists(file))
			CurrentFile = File(file);
		else
		{
			writeln("File \"", file, "\" doesn't exist.");
			return;
		}
	}

    Start();
}