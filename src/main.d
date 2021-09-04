/*
 * main.d : CLI entry point
 * Some of these functions are private for linter reasons
 */
module main;

import std.stdio, std.mmfile, std.format, std.getopt;
import core.stdc.stdlib : exit;
import ddhx.ddhx, ddhx.terminal, ddhx.settings, ddhx.error, ddhx.utils;

private:

void cliOptionWidth(string, string val) {
	if (optionWidth(val)) {
		writeln("main: invalid 'width' value: ", val);
		exit(1);
	}
}
void cliOptionOffset(string, string val) {
	if (optionOffset(val)) {
		writeln("main: invalid 'offset' value: ", val);
		exit(1);
	}
}
void cliOptionDefaultChar(string, string val) {
	if (optionDefaultChar(val)) {
		writeln("main: invalid 'defaultchar' value: ", val);
		exit(1);
	}
}

void cliVersion() {
	import std.compiler : version_major, version_minor;
	enum VERSTR = 
		DDHX_VERSION~"\n"~
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
	if (args.length <= 1) {
L_NOFILES:
		stderr.writeln("main: Missing file or stream argument");
		return 1;
	}
	
	bool cliMmfile, cliFile, cliDump, cliStdin;
	string cliSeek, cliLength;
	GetoptResult res = void;
	try {
		res = args.getopt(
			config.caseSensitive,
			"w|width", "Set column width in bytes ('a'=terminal width,default=16)", &cliOptionWidth,
			"o|offset", "Set offset mode (decimal, hex, or octal)", &cliOptionOffset,
			"C|defaultchar", "Set default character for non-ascii characters", &cliOptionDefaultChar,
			"m|mmfile", "Force mmfile mode", &cliMmfile,
			"f|file", "Force file mode", &cliFile,
			"stdin", "Force standard input mode", &cliStdin,
			"s|seek", "Seek at position", &cliSeek,
			"D|dump", "Non-interactive dump", &cliDump,
			"l|length", "Dump: Length of data to read", &cliLength,
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
	
	if (args.length <= 1 && cliStdin == false) {
		goto L_NOFILES;
	}
	
	int e = void;
	if (cliStdin) {
		e = ddhxOpenStdin();
	} else if (cliFile ? false : cliMmfile) {
		e = ddhxOpenMmfile(args[1]);
	} else {
		e = ddhxOpenFile(args[1]);
	}
	
	if (e) {
		stderr.writeln("ddhx: ", ddhxErrorMsg);
		return 2;
	}
	
	long seek;
	if (cliSeek) {
		if (unformat(cliSeek, seek) == false) {
			stderr.writeln("main: ", ddhxErrorMsg);
			return 1;
		}
	} else seek = 0;
	
	if (cliDump) {
		long length = void;
		if (cliLength) {
			if (unformat(cliLength, length) == false) {
				stderr.writeln("main: ", ddhxErrorMsg);
				return 1;
			}
		} else length = 0;
		ddhxDump(seek, length);
	} else ddhxInteractive(seek);
	return 0;
}