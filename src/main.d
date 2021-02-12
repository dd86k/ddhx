/*
 * main.d : CLI entry point
 * Some of these functions are private for linter reasons
 */

module main;

import std.stdio, std.mmfile, std.format, std.getopt;
import core.stdc.stdlib : exit;
import ddhx, ddcon;

private:

//TODO: --dump: Dump to stdout

void handleOptWidth(string, string val) {
	if (ddhx_setting_width(val))
		throw ddhx_exception;
}
void handleOptOutput(string, string val) {
	if (ddhx_setting_output(val))
		throw new Exception(format("Unknown mode parameter: %s", val));
}
void handleOptDefaultChar(string, string val) {
	if (ddhx_setting_defaultchar(val))
		throw ddhx_exception;
}

extern (C)
void pversion() {
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
L_FILE_REQ:
		writeln("ddhx: File required");
		return 1;
	}
	
	coninit;

	long seek;
	GetoptResult r;
	try {
		r = args.getopt(
			config.caseSensitive,
			"w|width", "Set column width in bytes, 'a' being automatic (default=16)", &handleOptWidth,
			"o|offset", "Set offset mode (decimal, hex, or octal)", &handleOptOutput,
			"C|defaultchar", "Set default character for non-ascii characters", &handleOptDefaultChar,
			"s|seek", "Seek at position", &seek,
			"version", "Print the version screen and exit", &pversion
		);
	} catch (Exception ex) {
		stderr.writefln("ddhx: %s", ex.msg);
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
				writefln("%-16s %s", optLong, help);
		}
		return 0;
	}
	
	if (args.length <= 1) // if missing file
		goto L_FILE_REQ;
	
	if (ddhx_file(args[1])) {
		ddhx_error("ddhx_file");
		return 1;
	}

	g_fpos = seek;
	ddhx_main(); // start ddhx
	return 0;
}