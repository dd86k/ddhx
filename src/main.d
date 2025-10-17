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
import std.process : environment;
import core.stdc.stdlib : exit, EXIT_SUCCESS, EXIT_FAILURE;
import configuration;
import ddhx;
import doceditor;
import logger;
import backend;

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
        printfield("ddhx",      DDHX_VERSION);
        printfield(null,        DDHX_BUILDINFO);
        printfield("License",   "MIT");
        printfield(null,        DDHX_COPYRIGHT);
        printfield("Homepage",  "https://github.com/dd86k/ddhx");
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
        // TODO: Consider renaming to "help-config"
        //       And print possible locations that configs could be found
        //       by the system
        foreach (conf; configurations)
        {
            writeln(conf.name);
            writeln('\t', conf.description);
            writeln('\t', "Values: ", conf.availvalues);
            writeln('\t', "Default: ", conf.defaultval);
            writeln;
        }
        break;
    case "help-debug":
        import platform : TARGET_TRIPLE;
        import os.path : findConfig;
        import os.mem : syspagesize;
        import std.conv : text;
        printfield("Compiler",  __VENDOR__~" "~DVER!__VERSION__);
        printfield("Target",    TARGET_TRIPLE);
        printfield("Pagesize",  text(syspagesize()));
        string confpath = findConfig("ddhx", ".ddhxrc");
        printfield("Config",    confpath ? confpath : "none");
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
        // TODO: --color/--no-color: Force color option (overrides rc)
        // TODO: --help-configs: list of configurations + descriptions
        res = getopt(args, config.caseSensitive,
        // Secret options
        "assistant",    "", &printpage,
        //
        // Configuration
        //
        "autoresize",   "Automatically resize columns on dimension change",
            ()
            {
                rc.autoresize = true;
            },
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
        "R|readonly",   "Open file as read-only and restrict editing",
            ()
            {
                rc.writemode = WritingMode.readonly;
            },
        "I|norc",       "Use defaults and ignore user configuration files", &onorc,
        "f|rcfile",     "Use supplied file for options", &orc,
        //
        // Pages
        //
        "version",      "Print the version page and exit", &printpage,
        "ver",          "Print only the version and exit", &printpage,
        "help-keys",    "Print default shortcuts and exit", &printpage,
        "help-commands","Print commands page and exit", &printpage,
        "help-configs", "Print configuration page and exit", &printpage,
        "help-debug",   "Print debug page and exit", &printpage,
        );
    }
    catch (Exception ex)
    {
        stderr.writeln("error: ", ex.msg);
        exit(EXIT_FAILURE);
    }
    
    // -h|--help, artifact of std.getopt.
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
    
    if (string logpath = environment.get("DDHX_LOG"))
    {
        logStart(logpath);
    }
    
    // Load config file after defaults when able. Spouting an error here is
    // more important to have a functioning editor, before loading document.
    import std.file : readText;
    initdefaults();
    if (orc) // Load specified RC by path
    {
    Lload:
        loadRC(rc, readText(orc));
    }
    else if (onorc == false) // norc==true means to NOT load user configs
    {
        import os.path : findConfig;
        orc = findConfig("ddhx", ".ddhxrc");
        if (orc) // we got config, load
            goto Lload;
    }
    
    static immutable string MSG_NEWBUF  = "(new buffer)";
    static immutable string MSG_NEWFILE = "(new file)";
    
    // Select editor backend, this allows transitioning between multiple
    // backends (implementations) easier.
    IDocumentEditor editor;
    switch (environment.get("DDHX_BACKEND", "chunk")) {
    case "piece":
        editor = new PieceDocumentEditor();
        break;
    case "chunk":
        size_t chksize;
        if (string strsize = environment.get("DDHX_CHUNKSIZE"))
        {
            import utils : parsebin;
            ulong sz = parsebin(strsize);
            if (sz > 64 * 1024 * 1024) // 64 MiB
                throw new Exception("Chunk size SHOULD be lower than 64 MiB");
            chksize = cast(size_t)sz;
        }
        editor = new ChunkDocumentEditor(0, chksize);
        break;
    default:
        throw new Exception("Backend does not exist");
    }
    assert(editor, "editor?");
    
    // Open buffer or file where (imitating GUN nano):
    // - No args:  New empty buffer
    // - "-":      Read from stdin
    // - FILENAME: Attempt to open FILE
    string target = args.length >= 2 ? args[1] : null;
    string initmsg;
    switch (target) {
    case null:
        // NOTE: Peeking stdin.
        //       We could try peeking stdin (getchar + ungetc(c, stdin)),
        //       but that might introduce unwanted implicit behavior.
        //       It's safer and more consistent to demand "-" for stdin.
        initmsg = MSG_NEWBUF;
        break;
    case "-": // In-memory buffer from stdin
        import document.memory : MemoryDocument;
        target = null; // unset target (no name)
        MemoryDocument doc = new MemoryDocument();
        foreach (const(ubyte)[] chk; stdin.byChunk(4096))
        {
            doc.append(chk);
        }
        editor.open(doc);
        initmsg = MSG_NEWBUF;
        break;
    default: // target is set, to either: file, disk (future), or PID (future)
        import std.file : exists;
        
        // Thanks to the null case, there is no need to check if target
        // is null (unset).
        // NOTE: exists(string) doesn't play well with \\.\PhysicalDriveN
        //
        //       Introducing a special Windows-only drive syntax (e.g, mapping
        //       "C:" to "\\.\PhysicalDrive0") would be simpler than trying to
        //       open the drive and be confused how to handle failures (can't
        //       assume we can save using basename either).
        //
        //       Either way, ddhx doesn't officially currently support disk editing.
        if (exists(target))
        {
            import document.file : FileDocument;
            import std.path : baseName;
            
            bool readonly = rc.writemode == WritingMode.readonly;
            editor.open(new FileDocument(target, readonly));
            
            initmsg = baseName(target);
        }
        else
        {
            initmsg = MSG_NEWFILE;
        }
    }
    assert(initmsg, "Forgot initmsg?");
    
    try startddhx(editor, rc, target, initmsg);
    catch (Exception ex)
    {
        writeln(); // if cursor was at some weird place
        debug stderr.writeln("fatal: ", ex);
        else  stderr.writeln("fatal: ", ex.msg);
        log("%s", ex);
        exit(EXIT_CRITICAL);
    }
}