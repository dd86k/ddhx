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
  ddhx  [OPTIONS] file
  ddhx  {-h|--help|--version}

Option         Description
  -w           Set the number of bytes per line, 'a' being automatic
  -o           Set offset type
  -s           Seek to position
  --version    Print version screen and quit
  -h, --help   Print help screen and quit`
	);
	exit(0);
}

extern (C)
void pversion() {
	import core.stdc.stdlib : exit;
	writefln(
		"ddhx " ~ APP_VERSION ~ "  (" ~ __TIMESTAMP__  ~ ")\n" ~
		"Compiler: " ~ __VENDOR__ ~ " v%d\n" ~
		"MIT License: "~COPYRIGHT~"\n" ~
		"Project page: <https://git.dd86k.space/dd86k/ddhx>",
		__VERSION__
	);
	exit(0); // getopt hack
}

int main(string[] args) {
	if (args.length <= 1) // FILE or OPTION required
		phelp;

	long seek;
	try {
		args.getopt(
			config.caseSensitive,
			"w", &ddhx_setting_handle_cli,
			config.caseSensitive,
			"o", &HandleOCLI,
			config.caseSensitive,
			"s", &seek,
			config.caseSensitive,
			"h|help", &phelp,
			config.caseSensitive,
			"version", &pversion
		);
	} catch (GetOptException ex) {
		stderr.writefln("%s, aborting", ex.msg);
		return 1;
	}

	string file = args[$ - 1];

	if (file.exists == false) {
		stderr.writefln(`File "%s" doesn't exist, aborting`, file);
		return 2;
	}
	if (file.isDir) {
		stderr.writefln(`"%s" is a directory, aborting`, file);
		return 3;
	}

	g_fhandle = new MmFile((g_fname = file), MmFile.Mode.read, 0, g_fmmbuf);

	if ((g_fsize = g_fhandle.length) <= 0) {
		stderr.writeln("Empty file, aborting");
		return 4;
	}

	ddhx_main(seek); // start ddhx
	return 0;
}