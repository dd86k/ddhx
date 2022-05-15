#!/bin/rdmd

import std.process;
import std.string : stripRight;
import std.file : write;
import std.path : dirSeparator;

alias SEP = dirSeparator;
enum PATH = "src" ~ SEP ~ "gitinfo.d";

int main(string[] args) {
	auto describe = executeShell("git describe");
	if (describe.status)
		return describe.status;
	
	string ver = stripRight(describe.output);
	write(PATH,
`// NOTE: This file was automatically generated.
module gitinfo;
/// Project current version described by git.
enum GIT_DESCRIPTION = "`~ver~`";`);
	
	return 0;
}