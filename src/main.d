/// Command-line interface.
///
/// Some of these functions are private for linter reasons
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module main;

import std.stdio, std.mmfile, std.format, std.getopt;
import core.stdc.stdlib : exit;
import ddhx;

private:

immutable string SECRET = q"SECRET
        +---------------------------------+
  __    | Heard you need help editing     |
 /  \   | data, can I help you with that? |
 -  -   |  [ Yes ] [ No ] [ Go away ]     |
 O  O   +-. .-----------------------------+
 || |/    |/
 | V |
  \_/
SECRET";

immutable string OPT_WIDTH       = "w|width";
immutable string OPT_OFFSET      = "o|offset";
immutable string OPT_DEFAULTCHAR = "C|char";
immutable string OPT_CHARSET     = "c|charset";

void cliOption(string opt, string val) {
	final switch (opt) {
	case OPT_WIDTH:
		if (settingWidth(val) == 0)
			return;
		opt = "width";
		break;
	case OPT_OFFSET:
		if (settingOffset(val) == 0)
			return;
		opt = "offset";
		break;
	case OPT_DEFAULTCHAR:
		if (settingDefaultChar(val) == 0)
			return;
		opt = "default character";
		break;
	case OPT_CHARSET:
		if (settingCharset(val) == 0)
			return;
		opt = "character set";
		break;
	}
	printError(1, "invalid value for %s: %s", opt, val);
	exit(1);
}

void cliVersion() {
	import std.compiler : version_major, version_minor;
	enum VERSTR = 
		VERSION_LINE~"\n"~
		COPYRIGHT~"\n"~
		"License: MIT <https://mit-license.org/>\n"~
		"Homepage: <https://git.dd86k.space/dd86k/ddhx>\n"~
		"Compiler: "~__VENDOR__~" "~format("%d.%03d", version_major, version_minor);
	writeln(VERSTR);
	exit(0); // getopt hack
}

void cliVer() {
	writeln(VERSION);
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
		OPT_WIDTH, "Set column width in bytes ('a'=automatic,default=16)", &cliOption,
		OPT_OFFSET, "Set offset mode (decimal, hex, or octal)", &cliOption,
		OPT_DEFAULTCHAR, "Set default character for non-printable characters (default=.)", &cliOption,
		OPT_CHARSET, "Set character translation (default=ascii)", &cliOption,
		"m|mmfile", "Open file as mmfile (memory-mapped)", &cliMmfile,
		"f|file", "Force opening file as regular", &cliFile,
		"stdin", "Open stdin instead of file, the '-' switch also works", &cliStdin,
		"s|seek", "Seek at position", &cliSeek,
		"D|dump", "Non-interactive dump", &cliDump,
		"l|length", "Dump: Length of data to read", &cliLength,
		"version", "Print the version screen and exit", &cliVersion,
		"ver", "Print only the version and exit", &cliVer,
		"assistant", "", &cliSecret
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
	
	// Open file
	long seek, length;
	if (cliStdin) {
		if (openStdin())
			goto L_ERROR;
	} else if (cliFile ? false : cliMmfile) {
		if (openMmfile(cliInput))
			goto L_ERROR;
	} else {
		if (openFile(cliInput))
			goto L_ERROR;
	}
	
	// Manage seek
	if (cliSeek) {
		if (convert(seek, cliSeek))
			goto L_ERROR;
	}
	
	// Open app
	if (cliDump) {
		if (cliLength) {
			if (convert(length, cliLength))
				goto L_ERROR;
		}
		enterDump(seek, length);
	} else enterInteractive(seek);
	return 0;

L_ERROR:
	return printError(1, errorMsg);
}