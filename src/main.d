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
    import platform : TARGET_TRIPLE;
    final switch (opt) {
    case OPTION_SECRET:
        writeln(SECRET);
        break;
    case OPTION_VERSION:
        versionline("ddhx", DDHX_VERSION);
        versionline(null,   DDHX_COPYRIGHT);
        versionline(null,   DDHX_BUILDINFO);
        versionline("Compiler", __VENDOR__~" "~DVER!__VERSION__);
        versionline(null,   TARGET_TRIPLE);
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
    size_t ochksize = 4096;
    string orc; /// Use this rc file instead
    bool onorc; /// Do not use rc file if it exists, force defaults
    GetoptResult res = void;
    try
    {
        // TODO: --color/--no-color, respecting $TERM
        res = getopt(args, config.caseSensitive,
        // Secret options
        "assistant",    "", &printpage,
        //
        // Runtime configuration
        //
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
        "address-spacing", "Set address spacing in characters",
            (string _, string val)
            {
                configRC(rc, "address-spacing", val);
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
        //
        // Editor configuration
        //
        "R|readonly",   "Open file in read-only editing mode",
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
            writefln(" %*s %s", -17, optLong, help);
        }
        
        // TODO: Find a painless way to show keybinds here
        
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
        string target = args.length >= 2 ? args[1] : null;
        DocEditor editor = new DocEditor(0, ochksize);
        string initmsg;
        
        import document.file : FileDocument;
        import document.memory : MemoryDocument;
        switch (target) {
        case null:
            initmsg = "new buffer";
            break;
        case "-": // MemoryDocument
            target = null;
            initmsg = "new buffer";
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
                initmsg = "(new file)";
            }
            else // new buffer
            {
                initmsg = "(new buffer)";
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