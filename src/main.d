/// CLI entry point.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module main;

// NOTE: Avoid putting putting editor behavior and tests in this module.
//       Apart from collecting CLI options, main module should
//       not have unittests, since DUB will actively omit this
//       module (and package modules) when running 'dub test'.

import std.stdio, std.getopt;
import ddhx;
import configuration;
import core.stdc.stdlib : exit, EXIT_SUCCESS, EXIT_FAILURE;
import logger;

private:

template DVER(uint ver)
{
    enum DVER =
        cast(char)((ver / 1000) + '0') ~ "." ~
        cast(char)(((ver % 1000) / 100) + '0') ~
        cast(char)(((ver % 100) / 10) + '0') ~
        cast(char)((ver % 10) + '0');
}

enum EXIT_CRITICAL = 2;

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

immutable string OPTION_SECRET  = "assistant";
immutable string OPTION_VERSION = "version";
immutable string OPTION_VER     = "ver";

// print a line with spaces for field and value
void versionline(string field, string line)
{
    writefln("%*s %s", -12, field ? field : "", line);
}

void printpage(string opt)
{
    final switch (opt) {
    case OPTION_SECRET:
        writeln(SECRET);
        break;
    case OPTION_VERSION:
        versionline("ddhx", DDHX_VERSION);
        versionline(null,   DDHX_COPYRIGHT);
        versionline(null,   DDHX_BUILDINFO);
        versionline("Compiler", __VENDOR__~" "~DVER!__VERSION__);
        versionline("Homepage", "https://github.com/dd86k/ddhx");
        break;
    case OPTION_VER:
        writeln(DDHX_VERSION);
        break;
    }
    exit(EXIT_SUCCESS);
}

void main(string[] args)
{
    enum SECRETCOUNT = 1;
    
    RC rc;
    string orc; /// Use this rc file instead
    bool onorc; /// Do not use rc file if it exists, force defaults
    GetoptResult res = void;
    try
    {
        // TODO: --color/--no-color, respecting $TERM
        res = getopt(args, config.caseSensitive,
        // Secret options
        "assistant",    "", &printpage,
        // Editor option
        "c|columns",    "Set columns per row (default depends on --data)",
            (string _, string val)
            {
                configRC(rc, "columns", val);
            },
        "address",      "Set address mode ('hex', 'dec', or 'oct')",
            (string _, string val)
            {
                configRC(rc, "address-type", val);
            },
        /*
        "data",         "Set data mode (default: x8)",
            (string _, string val)
            {
                configRC(rc, "data-type", val);
            },
        */
        //"filler",       "Set non-printable default character (default='.')", &cliOption,
        "C|charset",    "Set character translation (default='ascii')",
            (string _, string val)
            {
                configRC(rc, "charset", val);
            },
        "r|readonly",   "Open file in read-only editing mode",
            ()
            {
                import editor : WritingMode;
                rc.writemode = WritingMode.readonly;
            },
        // Application options
        //"s|seek",       "Seek at position", &rc.seek,
        //"l|length",     "Maximum amount of data to read", &rc.len,
        "I|norc",       "Use defaults and ignore user configuration files", &onorc,
        "rc",           "Use supplied RC file", &orc,
        // NOTE: Available in releases just in case there is a need
        "log",          "Enable tracing to this file",
            (string _, string val)
            {
                logStart(val);
            },
        // Pages
        "version",      "Print the version page and exit", &printpage,
        "ver",          "Print only the version and exit", &printpage,
        );
    }
    catch (Exception ex)
    {
        stderr.writeln("error: ", ex.msg);
        exit(EXIT_FAILURE);
    }
    
    if (res.helpWanted)
    {
        // Replace default help line
        res.options[$-1].help = "Print this help page and exit";
        
        writeln("Hex editor\n"~
            "USAGE\n"~
            "  ddhx [FILE|-] [OPTIONS]\n"~
            "  ddhx {-h|--help|--version|--ver}\n"~
            "\n"~
            "OPTIONS");
        foreach (opt; res.options[SECRETCOUNT..$]) with (opt)
        {
            if (optShort)
                write(' ', optShort, ',');
            else
                write("    ");
            writefln(" %-14s  %s", optLong, help);
        }
        exit(EXIT_SUCCESS);
    }
    
    if (orc) // specified RC path
    {
        loadRC(rc, orc);
    }
    else if (onorc == false)
    {
        // TODO: Find default config and load it
    }
    
    // TODO: Move args processing up here.
    //       Give ddhx only IDocument object.
    //       If dumping (not interactive session), then define behavior in other module.
    // Force exceptions to be printed on stderr and exit with code.
    // I believe it defaults printing to stdout.
    try startddhx(args.length >= 2 ? args[1] : null, rc);
    catch (Exception ex)
    {
        stderr.writeln(ex);
        log("%s", ex);
        exit(EXIT_CRITICAL);
    }
}