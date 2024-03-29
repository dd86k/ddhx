/// Command-line interface.
///
/// Some of these functions are private for linter reasons
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module main;

import std.stdio, std.mmfile, std.format, std.getopt;
import core.stdc.stdlib : exit;
import ddhx, editor, dump, reverser;

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

// CLI command options

immutable string OPT_COLUMNS    = "c|"~COMMAND_COLUMNS;
immutable string OPT_INSERT     = COMMAND_INSERT;
immutable string OPT_OVERWRITE  = COMMAND_OVERWRITE;
immutable string OPT_READONLY   = "R|"~COMMAND_READONLY;
immutable string OPT_VIEW       = COMMAND_VIEW;
immutable string OPT_SI         = COMMAND_SI;
immutable string OPT_IEC        = COMMAND_IEC;
immutable string OPT_OFFSET     = "o|"~COMMAND_OFFSET;
immutable string OPT_DATA       = "d|"~COMMAND_DATA;
immutable string OPT_FILLER     = "F|"~COMMAND_FILLER;
immutable string OPT_CHARSET    = "C|"~COMMAND_CHARSET;

// CLI common options

immutable string OPT_VERSION    = "version";
immutable string OPT_VER        = "ver";
immutable string OPT_SECRET     = "assistant";

bool askingHelp(string v) { return v == "help"; }

void cliList(string opt)
{
    writeln("Available values for ",opt,":");
    import std.traits : EnumMembers;
    switch (opt) {
    case OPT_OFFSET, OPT_DATA:
        foreach (m; EnumMembers!NumberType)
            writeln("\t=", m);
        break;
    case OPT_CHARSET:
        foreach (m; EnumMembers!CharacterSet)
            writeln("\t=", m);
        break;
    default:
    }
    exit(0);
}

void cliOption(string opt, string val)
{
    final switch (opt) {
    case OPT_INSERT:
        editor.editMode = EditMode.insert;
        return;
    case OPT_OVERWRITE:
        editor.editMode = EditMode.overwrite;
        return;
    case OPT_READONLY:
        editor.editMode = EditMode.readOnly;
        return;
    case OPT_VIEW:
        editor.editMode = EditMode.view;
        return;
    case OPT_COLUMNS:
        if (settingsColumns(val))
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
    case OPT_FILLER:
        if (settingsFiller(val))
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

void page(string opt)
{
    import std.compiler : version_major, version_minor;
    static immutable string COMPILER_VERSION = format("%d.%03d", version_major, version_minor);
    static immutable string VERSTR = 
        DDHX_ABOUT~"\n"~
        DDHX_COPYRIGHT~"\n"~
        "License: MIT <https://mit-license.org/>\n"~
        "Homepage: <https://git.dd86k.space/dd86k/ddhx>\n"~
        "Compiler: "~__VENDOR__~" "~COMPILER_VERSION;
    final switch (opt) {
    case OPT_VERSION: opt = VERSTR; break;
    case OPT_VER:     opt = DDHX_VERSION; break;
    case OPT_SECRET:  opt = SECRET; break;
    }
    writeln(opt);
    exit(0);
}

int main(string[] args)
{
    bool cliMmfile, cliFile, cliDump, cliStdin;
    bool cliNoRC;
    string cliSeek, cliLength, cliRC, cliReverse;
    GetoptResult res = void;
    try {
        //TODO: Change &cliOption to {}
        res = args.getopt(config.caseSensitive,
        OPT_COLUMNS,     "Set column size (automatic='a', default=16)", &cliOption,
        OPT_OFFSET,      "Set offset mode (decimal, hex, or octal)", &cliOption,
        OPT_DATA,        "Set binary mode (decimal, hex, or octal)", &cliOption,
        OPT_FILLER,      "Set non-printable default character (default='.')", &cliOption,
        OPT_CHARSET,     "Set character translation (default=ascii)", &cliOption,
        OPT_INSERT,      "Open file in insert editing mode", &cliOption,
        OPT_OVERWRITE,   "Open file in overwrite editing mode", &cliOption,
        OPT_READONLY,    "Open file in read-only editing mode", &cliOption,
        OPT_VIEW,        "Open file in view editing mode", &cliOption,
        OPT_SI,          "Use SI binary suffixes instead of IEC", &setting.si,
        "m|mmfile",      "Open file as mmfile (memory-mapped)", &cliMmfile,
        "f|file",        "Force opening file as regular", &cliFile,
        "stdin",         "Open stdin instead of file", &cliStdin,
        "s|seek",        "Seek at position", &cliSeek,
        "D|dump",        "Dump file non-interactive onto screen", &cliDump,
        "l|length",      "Dump: Length of data to read", &cliLength,
        "I|norc",        "Use detaults and ignore user configuration files", &cliNoRC,
        "rc",            "Use supplied RC file", &cliRC,
        "r|reverse",     "Reverse operation: From hex, output binary to this file", &cliReverse,
        OPT_VERSION,     "Print the version screen and exit", &page,
        OPT_VER,         "Print only the version and exit", &page,
        OPT_SECRET,      "", &page
        );
    }
    catch (Exception ex)
    {
        return errorPrint(1, ex.msg);
    }
    
    if (res.helpWanted)
    {
        // Replace default help line
        res.options[$-1].help = "Print this help screen and exit";
        writeln("ddhx - Interactive hexadecimal file viewer\n"~
            "  Usage: ddhx [OPTIONS] [FILE|--stdin]\n"~
            "\n"~
            "OPTIONS");
        foreach (opt; res.options) with (opt)
        {
            if (help == "") continue;
            if (optShort)
                writefln("%s, %-14s %s", optShort, optLong, help);
            else
                writefln("    %-14s %s", optLong, help);
        }
        return 0;
    }
    
    version (Trace)
        traceInit(DDHX_ABOUT);
    
    long skip, length;
    
    // Convert skip value
    if (cliSeek)
    {
        version (Trace) trace("seek=%s", cliSeek);
        
        if (convertToVal(skip, cliSeek))
            return errorPrint();
        
        if (skip < 0)
            return errorPrint(1, "Skip value must be positive");
    }
    
    // Open file or stream
    //TODO: Open MemoryStream
    if ((args.length <= 1 || cliStdin) && editor.openStream(stdin))
        return errorPrint;
    else if (cliFile ? false : cliMmfile && editor.openMmfile(args[1]))
        return errorPrint;
    else if (args.length > 1 && editor.openFile(args[1]))
        return errorPrint;
    
    // Parse settings
    if (cliNoRC == false && loadSettings(cliRC))
        return errorPrint;
    
    // App: dump
    if (cliDump)
    {
        if (cliLength && convertToVal(length, cliLength))
            return errorPrint;
        return dump.start(skip, length);
    }
    
    // App: reverse
    if (cliReverse)
    {
        return reverser.start(cliReverse);
    }
    
    // App: interactive
    return ddhx.start(skip);
}