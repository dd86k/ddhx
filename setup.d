#!rdmd

import std.process;
import std.string : stripRight;
import std.file : write;
import std.path : dirSeparator;

alias SEP = dirSeparator;

enum GITINFO_PATH = "src" ~ SEP ~ "gitinfo.d";

int main(string[] args) {
	final switch (args[1]) {
	case "version":
		auto describe = executeShell("git describe");
		if (describe.status)
			return describe.status;
		
		string ver = stripRight(describe.output);
		write(GITINFO_PATH,
		"// NOTE: This file was automatically generated.\n"~
		"module gitinfo;\n"~
		"enum GIT_DESCRIPTION = \""~ver~"\";");
		return 0;
	}
}