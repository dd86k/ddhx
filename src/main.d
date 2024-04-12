/// Command-line interface.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module main;

import std.compiler : version_major, version_minor;
import std.stdio, std.mmfile, std.format, std.getopt;
import std.conv : text;
import core.stdc.stdlib : exit;
import ddhx, dumper;
import utils.strings;
import display : Format, selectFormat;
import transcoder : CharacterSet;
import logger;

private: // Shuts up the linter

/// Copyright string
immutable string DDHX_COPYRIGHT = "Copyright (c) 2017-2024 dd86k <dd@dax.moe>";
/// App version
immutable string DDHX_VERSION = "0.5.0";
/// Version line
immutable string DDHX_ABOUT = "ddhx "~DDHX_VERSION~" (built: "~__TIMESTAMP__~")";

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

static immutable string COMPILER_VERSION =
    format("%d.%03d", version_major, version_minor);
static immutable string PAGE_VERSION = 
    DDHX_ABOUT~"\n"~
    DDHX_COPYRIGHT~"\n"~
    "License: MIT <https://mit-license.org/>\n"~
    "Homepage: <https://git.dd86k.space/dd86k/ddhx>\n"~
    "Compiler: "~__VENDOR__~" "~COMPILER_VERSION;

void cliPage(string key)
{
    final switch (key) {
    case "ver":         key = DDHX_VERSION; break;
    case "version":     key = PAGE_VERSION; break;
    case "assistant":   key = SECRET; break;
    }
    writeln(key);
    exit(0);
}

string argstdin(string filename)
{
    return filename == "-" ? null : filename;
}
long lparse(string v)
{
    if (v[0] != '+')
        throw new Exception(text("Missing '+' prefix to argument: ", v));
    
    return cparse(v[1..$]);
}

debug enum TRACE = true;
else  enum TRACE = false;

int main(string[] args)
{
    bool otrace = TRACE;
    bool odump;
    bool oreadonly;
    int ofmtdata = Format.hex;
    int ofmtaddr = Format.hex;
    int ocolumns = 16;
    int ocharset = CharacterSet.ascii;
    long oskip;
    long olength;
    
    GetoptResult res = void;
    try
    {
        res = args.getopt(config.caseSensitive,
        "assistant",    "", &cliPage,
        // Editor option
        "c|columns",    "Set column length (default=16, auto=0)", &ocolumns,
        "o|offset",     "Set offset mode ('hex', 'dec', or 'oct')",
            (string _, string fmt) {
                ofmtaddr = selectFormat(fmt);
            },
        "data",         "Set data mode ('hex', 'dec', or 'oct')",
            (string _, string fmt) {
                ofmtdata = selectFormat(fmt);
            },
        //"filler",       "Set non-printable default character (default='.')", &cliOption,
        "C|charset",    "Set character translation (default=ascii)",
            (string _, string charset) {
                switch (charset) with (CharacterSet)
                {
                case "cp437":   ocharset = cp437; break;
                case "ebcdic":  ocharset = ebcdic; break;
                case "mac":     ocharset = mac; break;
                case "ascii":   ocharset = ascii; break;
                default:
                    throw new Exception(text("Invalid charset: ", charset));
                }
            },
        "r|readonly",   "Open file in read-only editing mode", &oreadonly,
        // Editor input mode
        // Application options
        "dump",         "Dump file non-interactively", &odump,
        "s|seek",       "Seek at position",
            (string _, string len) { oskip = cparse(len); },
        "l|length",     "Maximum amount of data to read",
            (string _, string len) { olength = cparse(len); },
        //"I|norc",       "Use defaults and ignore user configuration files", &cliNoRC,
        //"rc",           "Use supplied RC file", &cliRC,
        // Pages
        "version",      "Print the version screen and exit", &cliPage,
        "ver",          "Print only the version and exit", &cliPage,
        "trace",        "Enable tracing. Used in debugging", &otrace,
        );
    }
    catch (Exception ex)
    {
        stderr.writeln("error: ", ex.msg);
        return 1;
    }
    
    if (res.helpWanted)
    {
        // Replace default help line
        res.options[$-1].help = "Print this help screen and exit";
        
        writeln("ddhx - Hex editor\n"~
            "USAGE\n"~
            "  ddhx [OPTIONS] [+POSITION] [+LENGTH] [FILE|-]\n"~
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
        
        return 0;
    }
    
    // Positional arguments
    string filename = void;
    try switch (args.length)
    {
    case 1: // Missing filename, implicit stdin
        filename = null;
        break;
    case 2: // Has filename or -
        filename = argstdin(args[1]);
        break;
    case 3: // Has position and filename
        oskip = lparse(args[1]);
        filename = argstdin(args[2]);
        break;
    case 4: // Has position, length, and filename
        oskip = lparse(args[1]);
        olength = lparse(args[2]);
        filename = argstdin(args[3]);
        break;
    default:
        throw new Exception("Too many arguments");
    }
    catch (Exception ex)
    {
        stderr.writeln("error: ", ex.msg);
        return 2;
    }
    
    if (otrace) traceInit();
    trace("version=%s args=%u", DDHX_VERSION, args.length);
    
    // App: dump
    if (odump)
    {
        //TODO: If args.length < 2 -> open stream
        return dump(filename, ocolumns, oskip, olength, ocharset);
    }
    
    // App: interactive
    return ddhx_start(filename, oreadonly, oskip, olength, ocolumns, ocharset);
}