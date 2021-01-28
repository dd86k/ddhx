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
void pversion() {
	import core.stdc.stdlib : exit;
	import std.conv : text;
	import std.format : format;
	import std.compiler : version_major, version_minor;
	enum VERSTR = 
		"ddhx " ~ APP_VERSION ~ "  (" ~ __TIMESTAMP__  ~ ")\n" ~
		"Compiler: " ~ __VENDOR__ ~ " v"~format("%d.%03d", version_major, version_minor)~"\n" ~
		"MIT License: "~COPYRIGHT~"\n" ~
		"Project page: <https://git.dd86k.space/dd86k/ddhx>";
	writeln(VERSTR);
	exit(0); // getopt hack
}

int main(string[] args) {
	if (args.length <= 1) { // FILE or OPTION required
		writeln("error: File required");
		return 1;
	}

	long seek;
	GetoptResult r;
	try {
		r = args.getopt(
			config.caseSensitive,
			"w", "Set column width in bytes, 'a' being automatic (default=16)", &ddhx_setting_handle_cli,
			"o", "Set output mode (decimal, hex, or octal)", &HandleOCLI,
			"s", "Seek at position", &seek,
			"version", "Print the version screen and exit", &pversion
		);
	} catch (GetOptException ex) {
		stderr.writefln("%s, aborting", ex.msg);
		return 1;
	}
	
	if (r.helpWanted) {
		r.options[$-1].help = "Print this help screen and exit";
		write(
		"ddhx - Interactive hexadecimal file viewer\n"~
		"Usage: ddhx [OPTIONS] FILE\n"
		);
		foreach (opt; r.options) {
			with (opt)
			if (optShort)
				writefln("%s, %-12s %s", optShort, optLong, help);
			else
				writefln("%-15s %s", optLong, help);
		}
		return 0;
	}

	string file = args[$ - 1];
	
	if (ddhx_file(file)) {
		ddhx_error("ddhx_file");
		return 1;
	}

	g_fpos = seek;
	ddhx_main(); // start ddhx
	return 0;
}