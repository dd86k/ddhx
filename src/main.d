/*
 * main.d : CLI entry point
 * Some of these functions are private for linter reasons
 */

module main;

import std.stdio, std.mmfile;
import core.stdc.stdlib : exit;
import ddhx, settings;
import std.file : exists, isDir;
import std.getopt;

private:

//TODO: CLI SWITCHES
// --dump: Dump into stdout (which then user can redirect)
// -sb: Search byte, e.g. -sb ffh -> init -> Echo result

extern (C)
void phelp() {
	writeln(
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
	exit(0);
}

extern (C)
void pversion() {
	import core.stdc.stdlib : exit;
	writefln(
		"ddhx " ~ APP_VERSION ~ "  (" ~ __TIMESTAMP__  ~ ")\n" ~
		"Compiler: " ~ __VENDOR__ ~ " v%d\n" ~
		"MIT License: Copyright (c) dd86k 2017-2019\n" ~
		"Project page: <https://git.dd86k.space/dd86k/ddhx>",
		__VERSION__
	);
	exit(0); // getopt hack
}

int main(string[] args) {

	if (args.length <= 1) // FILE required
		phelp;

	GetoptResult r = void;
	try {
		r = getopt(args,
			"w", "Set the number of bytes per line, 'a' being automatic.", &HandleWCLI,
			"o", "Set offset type.", &HandleOCLI,
			"version", "Print version information.", &pversion);
	} catch (GetOptException ex) {
		stderr.writefln("%s, aborting", ex.msg);
		return 1;
	}

	if (r.helpWanted)
		phelp;

	string file = args[$ - 1];

	if (file.exists) {
		if (file.isDir) {
			stderr.writefln(`"%s" is a directory, aborting`, file);
			return 3;
		}

		MMFile = new MmFile((fname = file), MmFile.Mode.read, 0, mmbuf);

		if ((fsize = MMFile.length) <= 0) {
			stderr.writeln("Empty file, aborting");
			return 4;
		}
	} else {
		stderr.writefln(`File "%s" doesn't exist, aborting`, file);
		return 2;
	}

	Start; // start ddhx
	return 0;
}