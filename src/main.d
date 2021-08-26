/*
 * main.d : CLI entry point
 * Some of these functions are private for linter reasons
 */
module main;

import std.stdio, std.mmfile, std.format, std.getopt;
import core.stdc.stdlib : exit;
import ddhx, ddcon, settings, error;

private:

//TODO: --dump [start[,length]]: Dump to stdout

void cliOptionWidth(string opt, string val) {
	if (optionWidth(val)) {
		writeln("main: invalid 'width' value: ", val);
		exit(1);
	}
}
void cliOptionOffset(string opt, string val) {
	if (optionOffset(val)) {
		writeln("main: invalid 'offset' value: ", val);
		exit(1);
	}
}
void cliOptionDefaultChar(string opt, string val) {
	if (optionDefaultChar(val)) {
		writeln("main: invalid 'defaultchar' value: ", val);
		exit(1);
	}
}

void cliVersion() {
	import std.compiler : version_major, version_minor;
	enum VERSTR = 
		"ddhx "~DDHX_VERSION~"  ("~__TIMESTAMP__~")\n"~
		"Compiler: "~__VENDOR__~" v"~format("%d.%03d", version_major, version_minor)~"\n"~
		"MIT License: "~DDHX_COPYRIGHT~"\n"~
		"Project page: <https://git.dd86k.space/dd86k/ddhx>";
	writeln(VERSTR);
	exit(0); // getopt hack
}

void cliVer() {
	writeln(DDHX_VERSION);
	exit(0);
}

int main(string[] args) {
	if (args.length <= 1) { // FILE or OPTION required
L_FILE_REQ:
		writeln("main: File required");
		return 0;
	}
	
	coninit;

	long seek;
	GetoptResult res = void;
	try {
		res = args.getopt(
			config.caseSensitive,
			"w|width", "Set column width in bytes ('a'=terminal width,default=16)", &cliOptionWidth,
			"o|offset", "Set offset mode (decimal, hex, or octal)", &cliOptionOffset,
			"C|defaultchar", "Set default character for non-ascii characters", &cliOptionDefaultChar,
			"s|seek", "Seek at position", &seek,
			"version", "Print the version screen and exit", &cliVersion,
			"ver", "Print only the version and exit", &cliVer
		);
	} catch (Exception ex) {
		stderr.writefln("main: %s", ex.msg);
		return 1;
	}
	
	if (res.helpWanted) {
		res.options[$-1].help = "Print this help screen and exit";
		write("ddhx - Interactive hexadecimal file viewer\n"~
			"  Usage: ddhx [OPTIONS] FILE\n\n");
		foreach (opt; res.options) {
			with (opt)
			if (optShort)
				writefln("%s, %-14s %s", optShort, optLong, help);
			else
				writefln("    %-14s %s", optLong, help);
		}
		return 0;
	}
	
	if (args.length <= 1) // if missing file
		goto L_FILE_REQ;
	
	if (ddhxLoad(args[1])) {
		stderr.writeln(ddhxErrorMsg);
		return 1;
	}
	
	ddhxStart(seek); // start ddhx
	return 0;
}