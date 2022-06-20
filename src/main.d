/// Command-line interface.
///
/// Some of these functions are private for linter reasons
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module main;

import std.stdio, std.mmfile, std.format, std.getopt;
import core.stdc.stdlib : exit;
import ddhx, editor;

//TODO: --only=n
//             text: only display translated text
//             data: only display hex data
//TODO: --memory
//      read all into memory
//      current seeing no need for this

private:

immutable string SECRET = q"SECRET
        +---------------------------------+
  __    | Heard you need help editing     |
 /  \   | data, can I help you with that? |
 -  -   |   [ Yes ] [ No ] [ Go away ]    |
 O  O   +-. .-----------------------------+
 || |/    |/
 | V |
  \_/
SECRET";

immutable string OPT_READONLY	= "R|readonly";
immutable string OPT_SI	= "si";
immutable string OPT_WIDTH	= "w|width";
immutable string OPT_OFFSET	= "o|offset";
immutable string OPT_DATA	= "d|data";
immutable string OPT_DEFAULTCHAR	= "C|char";
immutable string OPT_CHARSET	= "c|charset";
immutable string OPT_VERSION	= "version";
immutable string OPT_VER	= "ver";
immutable string OPT_SECRET	= "assistant";

bool askingHelp(string v) {
	return v == "help" || v == "list";
}

void cliList(string opt) {
	writeln("Values available for option ",opt,":");
	import std.traits : EnumMembers;
	switch (opt) {
	case OPT_OFFSET, OPT_DATA:
		foreach (m; EnumMembers!NumberType) {
			writeln(m);
		}
		break;
	case OPT_CHARSET:
		foreach (m; EnumMembers!CharacterSet) {
			writeln(m);
		}
		break;
	default:
	}
	exit(0);
}

void cliOption(string opt, string val) {
	final switch (opt) {
	case OPT_READONLY:
		editor.edits.mode = EditMode.readOnly;
		return;
	case OPT_WIDTH:
		if (settingsWidth(val))
			break;
		return;
	case OPT_OFFSET:
		if (askingHelp(val))
			cliList(opt);
		if (settingsOffset(val))
			break;
		return;
	case OPT_DATA:
		if (askingHelp(val))
			cliList(opt);
		if (settingsData(val))
			break;
		return;
	case OPT_DEFAULTCHAR:
		if (settingsDefaultChar(val))
			break;
		return;
	case OPT_CHARSET:
		if (askingHelp(val))
			cliList(opt);
		if (settingsCharset(val))
			break;
		return;
	}
	errorPrint(1, "Invalid value for %s: %s", opt, val);
	exit(1);
}

void page(string opt) {
	import std.compiler : version_major, version_minor;
	enum COMPILER_VERSION = format("%d.%03d", version_major, version_minor);
	enum VERSTR = 
		DDHX_ABOUT~"\n"~
		DDHX_COPYRIGHT~"\n"~
		"License: MIT <https://mit-license.org/>\n"~
		"Homepage: <https://git.dd86k.space/dd86k/ddhx>\n"~
		"Compiler: "~__VENDOR__~" "~COMPILER_VERSION;
	final switch (opt) {
	case OPT_VERSION: opt = VERSTR; break;
	case OPT_VER: opt = DDHX_VERSION; break;
	case OPT_SECRET: opt = SECRET; break;
	}
	writeln(opt);
	exit(0);
}

int main(string[] args) {
	bool cliMmfile, cliFile, cliDump, cliStdin;
	string cliSeek, cliLength;
	GetoptResult res = void;
	try {
		res = args.getopt(config.caseSensitive,
		OPT_WIDTH,       "Set column width in bytes ('a'=automatic, default=16)", &cliOption,
		OPT_OFFSET,      "Set offset mode (decimal, hex, or octal)", &cliOption,
		OPT_DATA,        "Set data mode (decimal, hex, or octal)", &cliOption,
		OPT_DEFAULTCHAR, "Set non-printable replacement character (default='.')", &cliOption,
		OPT_CHARSET,     "Set character translation (default=ascii)", &cliOption,
		OPT_READONLY,    "Set file mode to read-only", &cliOption,
		OPT_SI,          "Use SI suffixes instead of IEC", &setting.si,
		"m|mmfile",      "Open file as mmfile (memory-mapped)", &cliMmfile,
		"f|file",        "Force opening file as regular", &cliFile,
		"stdin",         "Open stdin instead of file", &cliStdin,
		"s|seek",        "Seek at position", &cliSeek,
		"D|dump",        "Non-interactive dump", &cliDump,
		"l|length",      "Dump: Length of data to read", &cliLength,
		OPT_VERSION,     "Print the version screen and exit", &page,
		OPT_VER,         "Print only the version and exit", &page,
		OPT_SECRET,      "", &page
		);
	} catch (Exception ex) {
		return errorPrint(1, ex.msg);
	}
	
	if (res.helpWanted) {
		// Replace default help line
		res.options[$-1].help = "Print this help screen and exit";
		writeln("ddhx - Interactive hexadecimal file viewer\n"~
			"  Usage: ddhx [OPTIONS] [FILE|--stdin]\n"~
			"\n"~
			"OPTIONS");
		foreach (opt; res.options) with (opt) {
			if (help == "") continue;
			if (optShort)
				writefln("%s, %-14s %s", optShort, optLong, help);
			else
				writefln("    %-14s %s", optLong, help);
		}
		return 0;
	}
	
	string cliPath = args.length > 1 ? args[1] : "-";
	
	if (cliStdin == false) cliStdin = args.length <= 1;
	
	version (Trace) traceInit;
	
	// Open file
	long skip, length;
	if (cliStdin) {
		if (editor.openStream(stdin))
			return errorPrint;
	} else if (cliFile ? false : cliMmfile) {
		if (editor.openMmfile(cliPath))
			return errorPrint;
	} else {
		if (editor.openFile(cliPath))
			return errorPrint;
	}
	
	// Convert skip value
	if (cliSeek) {
		if (convertToVal(skip, cliSeek))
			return errorPrint;
	}
	
	// App: dump
	if (cliDump) {
		if (cliLength) {
			if (convertToVal(length, cliLength))
				return errorPrint;
		}
		return ddhx.startDump(skip, length);
	}
	
	// App: interactive
	return ddhx.startInteractive(skip);
}