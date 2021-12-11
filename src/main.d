/*
 * main.d : CLI entry point
 * Some of these functions are private for linter reasons
 */
module main;

import std.stdio, std.mmfile, std.format, std.getopt;
import core.stdc.stdlib : exit;
import ddhx.ddhx, ddhx.terminal, ddhx.settings, ddhx.error, ddhx.utils;

private:

//  |----------------------||----------------------|
immutable string SECRET = q"SECRET
    We live in a world in which hostile thoughts and
       ideas are constantly present in the media,
      pressing in on our consciousness. Events are
         often also outside of our control.
  
             Outside of *our* control,
            but not outside of control.
        Others use these concepts and events to
           create this anxiety on others.
                   ____________
                  /            \
                  \   .-""-.   /
                   \ < (()) > /
                    \ `-..-' /
                     \      /
                      \____/

            Practice basic media safety.
        Control your information environment.
                 Act, don't react. 
SECRET";

void cliOptionWidth(string, string val) {
	if (optionWidth(val)) {
		printError(1, "invalid value for width: %s", val);
		exit(1);
	}
}
void cliOptionOffset(string, string val) {
	if (optionOffset(val)) {
		printError(1, "invalid value for offset: %s", val);
		exit(1);
	}
}
void cliOptionDefaultChar(string, string val) {
	if (optionDefaultChar(val)) {
		printError(1, "invalid value for defaultchar: %s", val);
		exit(1);
	}
}

void cliVersion() {
	import std.compiler : version_major, version_minor;
	enum VERSTR = 
		DDHX_VERSION_LINE~"\n"~
		DDHX_COPYRIGHT~"\n"~
		"License: MIT <https://mit-license.org/>\n"~
		"Homepage: <https://git.dd86k.space/dd86k/ddhx>\n"~
		"Compiler: "~__VENDOR__~" "~format("%d.%03d", version_major, version_minor);
	writeln(VERSTR);
	exit(0); // getopt hack
}

void cliVer() {
	writeln(DDHX_VERSION);
	exit(0);
}

void cliSecret() {
	write(SECRET);
	exit(0);
}

int main(string[] args) {
	bool cliMmfile, cliFile, cliDump, cliStdin;
	string cliSeek, cliLength;
	GetoptResult res = void;
	try {
		res = args.getopt(config.caseSensitive,
		"w|width", "Set column width in bytes ('a'=automatic,default=16)", &cliOptionWidth,
		"o|offset", "Set offset mode (decimal, hex, or octal)", &cliOptionOffset,
		"C|defaultchar", "Set default character for non-ascii characters", &cliOptionDefaultChar,
		"m|mmfile", "Force mmfile mode, recommended for large files", &cliMmfile,
		"f|file", "Force file mode", &cliFile,
		"stdin", "Force standard input mode", &cliStdin,
		"s|seek", "Seek at position", &cliSeek,
		"D|dump", "Non-interactive dump", &cliDump,
		"l|length", "Dump: Length of data to read", &cliLength,
		"version", "Print the version screen and exit", &cliVersion,
		"ver", "Print only the version and exit", &cliVer,
		"awake", "", &cliSecret
		);
	} catch (Exception ex) {
		return printError(1, ex.msg);
	}
	
	if (res.helpWanted) {
		res.options[$-1].help = "Print this help screen and exit";
		write("ddhx - Interactive hexadecimal file viewer\n"~
			"  Usage: ddhx [OPTIONS] FILE\n\n");
		foreach (opt; res.options) {
			with (opt) {
				if (help == "") continue;
				if (optShort)
					writefln("%s, %-14s %s", optShort, optLong, help);
				else
					writefln("    %-14s %s", optLong, help);
			}
		}
		return 0;
	}
	
	if (cliStdin == false) cliStdin = args.length <= 1;
	string cliInput = cliStdin ? "-" : args[1];
	
	version (Trace) traceInit;
	
	long seek, length;
	if (cliStdin) {
		if (ddhxOpenStdin())
			goto L_ERROR;
	} else if (cliFile ? false : cliMmfile) {
		if (ddhxOpenMmfile(cliInput))
			goto L_ERROR;
	} else {
		if (ddhxOpenFile(cliInput))
			goto L_ERROR;
	}
	
	if (cliSeek) {
		if (unformat(cliSeek, seek) == false)
			goto L_ERROR;
	}
	
	if (cliDump) {
		if (cliLength) {
			if (unformat(cliLength, length) == false)
				goto L_ERROR;
		}
		ddhxDump(seek, length);
	} else ddhxInteractive(seek);
	return 0;

L_ERROR:
	return printError(1, ddhxErrorMsg);
}