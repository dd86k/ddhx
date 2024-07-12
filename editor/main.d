/// Editor main entry.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module editor.main;

import std.stdio, std.getopt;
import editor.app;
import ddhx.common;
import ddhx.logger;
import ddhx.document;
import ddhx.transcoder : CharacterSet, selectCharacterSet;
import ddhx.formatter : Format, selectFormat;
import ddhx.utils.strings : cparse;
import core.stdc.stdlib : exit;

private:

immutable string SECRET = q"SECRET
        +----------------------------+
  __    | Heard you need help.       |
 /  \   | Can I help you with that?  |
 _  _   | [ Yes ] [ No ] [ Go away ] |
 O  O   +-. .------------------------+
 || |/    |/
 | V |
  \_/
SECRET";

int main(string[] args)
{
    int openflags;
    GetoptResult res = void;
    try
    {
        res = args.getopt(config.caseSensitive,
        "assistant",    "", () {
            writeln(SECRET);
            exit(0);
        },
        // Editor option
        "c|columns",    "Set column length (default=16, auto=0)", &_ocolumns,
        "o|offset",     "Set offset mode ('hex', 'dec', or 'oct')",
            (string _, string fmt) {
                _oaddrfmt = selectFormat(fmt);
            },
        "data",         "Set data mode ('hex', 'dec', or 'oct')",
            (string _, string fmt) {
                _odatafmt = selectFormat(fmt);
            },
        //"filler",       "Set non-printable default character (default='.')", &cliOption,
        "C|charset",    "Set character translation (default=ascii)",
            (string _, string charset) {
                _ocharset = selectCharacterSet(charset);
            },
        "r|readonly",   "Open file in read-only editing mode", () {
            openflags |= DocOpenFlags.readonly;
        },
        // Editor input mode
        // Application options
        "s|seek",       "Seek at position",
            (string _, string len) {
                _opos = cparse(len);
            },
        "l|length",     "Maximum amount of data to read",
            (string _, string len) {
                _olength = cparse(len);
            },
        //"I|norc",       "Use defaults and ignore user configuration files", &cliNoRC,
        //"rc",           "Use supplied RC file", &cliRC,
        // Pages
        "version",      "Print the version screen and exit", () {
            static immutable string page = "ddhx"~POSTFIX_PAGE_VERSION;
            writeln(page);
            exit(0);
        },
        "ver",          "Print only the version and exit", () {
            writeln(DDHX_VERSION);
            exit(0);
        },
        "trace",        "Enable tracing log file", &_otrace,
        );
    }
    catch (Exception ex)
    {
        stderr.writeln("error: ", ex.msg);
        exit(1);
    }
    
    if (res.helpWanted)
    {
        // Replace default help line
        res.options[$-1].help = "Print this help screen and exit";
        
        writeln("ddhx - Hex editor\n"~
            "USAGE\n"~
            "  ddhx [FILE|-]\n"~
            "  ddhx {-h|--help|--version|--ver]\n"~
            "\n"~
            "OPTIONS");
        foreach (opt; res.options[1..$]) with (opt)
        {
            if (optShort)
                write(' ', optShort, ',');
            else
                write("    ");
            writefln(" %-14s  %s", optLong, help);
        }
        exit(0);
    }
    
    if (_otrace) traceInit();
    trace("version=%s args=%u", DDHX_VERSION, args.length);
    
    // If file not mentioned, app will assume stdin
    string filename = args.length > 1 ? args[1] : null;
    trace("filename=%s openflags=%x", filename, openflags);
    
    // TODO: Support streams (for editor, that's slurping all of stdin)
    if (filename == null)
    {
        stderr.writeln("error: Filename required. No current support for streams.");
        return 0;
    }
    
    Document doc;
    try doc.openFile(filename, openflags);
    catch (Exception ex)
    {
        stderr.writeln("error: ", ex.msg);
        return 1;
    }
    
    startEditor(doc);
    return 0;
}