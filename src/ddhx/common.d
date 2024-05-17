module ddhx.common;

import std.stdio, std.format, std.compiler;
import std.conv, std.getopt;
import core.stdc.stdlib : exit;
import ddhx.formatter : Format, selectFormat;
import ddhx.transcoder : CharacterSet, selectCharacterSet;
import ddhx.utils.strings : cparse;
import ddhx.logger;

__gshared:

debug enum TRACE = true;
else  enum TRACE = false;

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

/// 
bool _otrace = TRACE;
/// Read-only buffer
bool _oreadonly;
/// Group size of one element in bytes
int _ogrpsize = 1;
/// Data formatting
int _odatafmt = Format.hex;
/// Address formatting
int _oaddrfmt = Format.hex;
/// Address space padding in digits
int _oaddrpad = 11;
/// Size of column (one row) in bytes
int _ocolumns = 16;
/// Character set
int _ocharset = CharacterSet.ascii;
/// 
char _ofillchar = '.';
/// Skip/seek position
long _opos;
/// Total length to read
long _olength;

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

bool cliTestStdin(string path)
{
    return path == "-";
}
long cliParsePos(string v)
{
    if (v[0] != '+')
        throw new Exception(text("Missing '+' prefix to argument: ", v));
    
    return cparse(v[1..$]);
}

void cliOptColumn(string v)
{
    
}

string[] commonopts(string[] args)
{
    GetoptResult res = void;
    try
    {
        res = args.getopt(config.caseSensitive,
        "assistant",    "", &cliPage,
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
        "r|readonly",   "Open file in read-only editing mode", &_oreadonly,
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
        "version",      "Print the version screen and exit", &cliPage,
        "ver",          "Print only the version and exit", &cliPage,
        "trace",        "Enable tracing. Used in debugging", &_otrace,
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
    
    return args;
}
