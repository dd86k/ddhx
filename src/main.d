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
import core.stdc.stdlib : exit, EXIT_SUCCESS, EXIT_FAILURE;
import configuration;
import ddhx;
import doceditor;
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

// print a line with spaces for field and value
void printfield(string field, string line, int spacing = -12)
{
    writefln("%*s %s", spacing, field ? field : "", line);
}

void printpage(string opt)
{
    final switch (opt) {
    case "assistant":
        writeln(SECRET);
        break;
    case "version":
        import platform : TARGET_TRIPLE;
        printfield("ddhx",      DDHX_VERSION);
        printfield(null,        DDHX_BUILDINFO);
        printfield("License",   "MIT");
        printfield(null,        DDHX_COPYRIGHT);
        printfield("Homepage",  "https://github.com/dd86k/ddhx");
        printfield("Compiler",  __VENDOR__~" "~DVER!__VERSION__);
        printfield(null,        TARGET_TRIPLE);
        break;
    case "ver":
        writeln(DDHX_VERSION);
        break;
    case "help-keys":
        enum SPACING = -25;
        printfield("COMMAND", "KEYS", SPACING);
        foreach (command; default_commands)
        {
            if (command.key == 0) // no keys set
                continue;
            
            writef("%*s ", SPACING, command.name);
            import os.terminal : Key, Mod;
            if (command.key & Mod.ctrl)  write("Ctrl+");
            if (command.key & Mod.alt)   write("Alt+");
            if (command.key & Mod.shift) write("Shift+");
            writeln(cast(Key)cast(short)command.key);
        }
        break;
    case "help-commands":
        enum SPACING = -25;
        printfield("COMMAND", "DESCRIPTION", SPACING);
        foreach (command; default_commands)
        {
            printfield(command.name, command.description, SPACING);
        }
        break;
    case "help-configs":
        foreach (conf; configurations)
        {
            writeln(conf.name);
            writeln('\t', conf.description);
            writeln('\t', "Values: ", conf.availvalues);
            writeln('\t', "Default: ", conf.defaultval);
        }
        break;
    }
    exit(EXIT_SUCCESS);
}

void main(string[] args)
{
    enum SECRETCOUNT = 1;
    
    RC rc;
    size_t ochksize = 4096;
    string orc; /// Use this rc file instead
    bool onorc; /// Do not use rc file if it exists, force defaults
    GetoptResult res = void;
    try
    {
        // TODO: --color/--no-color: Force color option (overrides rc)
        // TODO: --help-configs: list of configurations + descriptions
        res = getopt(args, config.caseSensitive,
        // Secret options
        "assistant",    "", &printpage,
        //
        // Runtime configuration
        //
        "c|columns",    "Set columns per row (default: 16)",
            (string _, string val)
            {
                configuration_columns(rc, val);
            },
        "A|addressing", `Set address mode ("hex"/"dec"/"oct", default: "hex")`,
            (string _, string val)
            {
                configuration_addressing(rc, val);
            },
        "address-spacing", "Set address spacing in characters (default: 11)",
            (string _, string val)
            {
                configuration_charset(rc, val);
            },
        /*
        "data",         "Set data mode (default: x8)",
            (string _, string val)
            {
                configRC(rc, "data-type", val);
            },
        */
        //"filler",       "Set non-printable default character (default='.')", &cliOption,
        "C|charset",    `Set character translation (default="ascii")`,
            (string _, string val)
            {
                configRC(rc, "charset", val);
            },
        //
        // Editor configuration
        //
        "R|readonly",   "Open file as read-only and restrict editing",
            ()
            {
                rc.writemode = WritingMode.readonly;
            },
        //"s|seek",       "Seek at position", &rc.seek,
        //"l|length",     "Maximum amount of data to read", &rc.len,
        //"I|norc",       "Use defaults and ignore user configuration files", &onorc,
        //"f|rcfile",     "Use supplied file for options", &orc,
        //
        // Debugging options
        //
        "log",          "Debugging: Enable tracing to this file",
            (string _, string val)
            {
                logStart(val);
            },
        "chunksize",    "Debugging: Set in-memory patch chunks to this size",
            (string _, string val)
            {
                import utils : parsebin;
                ulong sz = parsebin(val);
                if (sz > 64 * 1024 * 1024) // 64 MiB
                    throw new Exception("Chunk size SHOULD be lower than 64 MiB");
                ochksize = cast(size_t)sz;
            },
        //
        // Pages
        //
        "version",      "Print the version page and exit", &printpage,
        "ver",          "Print only the version and exit", &printpage,
        "help-keys",    "Print default shortcuts and exit", &printpage,
        "help-commands","Print commands page and exit", &printpage,
        "help-configs", "Print configuration page and exit", &printpage,
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
        
        // Usage and options
        writeln("Hex editor\n"~
            "USAGE\n"~
            " ddhx [FILE|-] [OPTIONS]\n"~
            " ddhx {-h|--help|--version|--ver}\n"~
            "\n"~
            "OPTIONS");
        foreach (opt; res.options[SECRETCOUNT..$]) with (opt)
        {
            if (optShort)
                write(' ', optShort, ',');
            else
                write("    ");
            writefln(" %*s %s", -20, optLong, help);
        }
        
        exit(EXIT_SUCCESS);
    }
    
    /*
    if (orc) // specified RC path
    {
        loadRC(rc, orc);
    }
    else if (onorc == false) // noRC==false: Allowed to use default config if exists
    {
        // TODO: Find default config and load it
    }
    */
    
    try
    {
        static immutable string MSG_NEWBUF  = "(new buffer)";
        static immutable string MSG_NEWFILE = "(new file)";
        
        string target = args.length >= 2 ? args[1] : null;
        DocEditor editor = new DocEditor(0, ochksize);
        string initmsg;
        
        import document.file : FileDocument;
        import document.memory : MemoryDocument;
        switch (target) {
        case null:
            initmsg = MSG_NEWBUF;
            break;
        case "-": // MemoryDocument
            target = null;
            initmsg = MSG_NEWBUF;
            MemoryDocument doc = new MemoryDocument();
            foreach (const(ubyte)[] chk; stdin.byChunk(4096))
            {
                doc.append(chk);
            }
            editor.attach(doc);
            break;
        default: // assume target is file
            import std.file : exists;
            import std.path : baseName;
            
            if (target && exists(target))
            {
                bool readonly = rc.writemode == WritingMode.readonly;
                editor.attach(new FileDocument(target, readonly));
                
                initmsg = baseName(target);
            }
            else if (target)
            {
                initmsg = MSG_NEWFILE;
            }
            else // new buffer
            {
                initmsg = MSG_NEWBUF;
            }
        }
    
        startddhx(editor, rc, target, initmsg);
    }
    catch (Exception ex)
    {
        writeln(); // if cursor was at some weird place
        debug stderr.writeln("fatal: ", ex);
        else  stderr.writeln("fatal: ", ex.msg);
        log("%s", ex);
        exit(EXIT_CRITICAL);
    }
}