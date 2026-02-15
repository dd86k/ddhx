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
import formatting : WritingMode;
import logger;
import editor;
import document.file : FileDocument;

private:

template DVER(uint ver)
{
    enum DVER =
        cast(char)((ver / 1000) + '0') ~ "." ~
        cast(char)(((ver % 1000) / 100) + '0') ~
        cast(char)(((ver % 100) / 10) + '0') ~
        cast(char)((ver % 10) + '0');
}

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
        import os.mem : syspagesize;
        import std.conv : text;
        printfield("ddhx",      DDHX_VERSION);
        printfield(null,        DDHX_BUILDINFO);
        printfield("License",   "MIT");
        printfield(null,        DDHX_COPYRIGHT);
        printfield("Homepage",  "https://github.com/dd86k/ddhx");
        printfield("Compiler",  __VENDOR__~" "~DVER!__VERSION__);
        printfield("Target",    TARGET_TRIPLE);
        printfield("Pagesize",  text(syspagesize()));
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
            writeln(cast(Key)(command.key & 0xff_ffff));
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
    case "help-config":
        import std.path : buildPath;
        import std.file : exists;
        import os.path : findConfig, getHomeFolder, getUserConfigFolder, getSystemFolder;
        
        enum SPACING0 = -10;
        
        static immutable string ACTIVE   = "(active)";
        static immutable string INACTIVE = "        ";
        
        string confpath = findConfig("ddhx", ".ddhxrc");
        
        // Bastardized way of printing Type, State, and Path
        // The state is actively checked against path, null is allowed there
        writeln("Paths");
        string homedir = getHomeFolder();
        if (homedir) // available
        {
            string homepath = buildPath(homedir, ".ddhxrc");
            bool active = homepath == confpath;
            writefln("%*s %s %s", SPACING0, "  User", active ? ACTIVE : INACTIVE, homepath);
        }
        string appdir  = getUserConfigFolder();
        if (appdir) // available
        {
            string apppath = buildPath(appdir, "ddhx", ".ddhxrc");
            bool active = apppath == confpath;
            writefln("%*s %s %s", SPACING0, "  App", active ? ACTIVE : INACTIVE, apppath);
        }
        string sysdir  = getSystemFolder();
        if (sysdir)
        {
            string syspath = buildPath(sysdir, "ddhx", ".ddhxrc");
            bool active = syspath == confpath;
            writefln("%*s %s %s", SPACING0, "  System", active ? ACTIVE : INACTIVE, syspath);
        }
        writeln;
        
        // Print config fields/values
        enum SPACING1 = -20;
        foreach (conf; configurations)
        {
            writefln("%*s%s", SPACING1, conf.name, conf.description);
            writefln("%*sValues: %s", SPACING1, "", conf.availvalues);
            writefln("%*sDefault: %s", SPACING1, "", conf.defaultval);
            writeln;
        }
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
        // TODO: --mirror-cursor
        res = getopt(args, config.caseSensitive,
        // Secret options
        "assistant",    "", &printpage,
        //
        // Configuration
        //
        "autoresize",   "Automatically resize columns on dimension change",
            ()
            {
                // NOTE: Not a deprecated switch I guess
                rc.columns = COLUMNS_AUTO;
            },
        "c|columns",    "Set columns per row (default: 16)",
            (string _, string val)
            {
                configure_columns(rc, val);
            },
        "A|address", `Set address mode ("hex"/"dec"/"oct", default: "hex")`,
            (string _, string val)
            {
                configure_address(rc, val);
            },
        "D|data", `Set data mode ("x8","x16",etc., default: "x8")`,
            (string _, string val)
            {
                configure_data(rc, val);
            },
        "address-spacing", "Set address spacing in characters (default: 11)",
            (string _, string val)
            {
                configure_address_spacing(rc, val);
            },
        //"filler",       "Set non-printable default character (default='.')", &cliOption,
        "C|charset",    `Set character translation (default="ascii")`,
            (string _, string val)
            {
                configure_charset(rc, val);
            },
        "gray-zeros",   "Gray out zeros",
            {
                configure_gray_zeros(rc, "on");
            },
        //
        // Misc
        //
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
        "help-config",  "Print configuration page and exit", &printpage,
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
        import std.process : thisProcessID;
        log("PID=%d", thisProcessID());
    }
    
    // Load config file after defaults when able. Spouting an error here is
    // more important to have a functioning editor, before loading document.
    import std.file : readText;
    initdefaults();
    if (orc) // Load specified RC by path
    {
    Lrc:
        log(`config_file="%s"`, orc);
        loadRC(rc, readText(orc));
    }
    else if (onorc == false) // norc==true means to NOT load user configs
    {
        import os.path : findConfig;
        orc = findConfig("ddhx", ".ddhxrc");
        if (orc) // we got config path, load it
            goto Lrc;
    }
    
    static immutable string MSG_NEWBUF  = "(new buffer)";
    static immutable string MSG_NEWFILE = "(new file)";
    
    // Select editor backend, this allows transitioning between multiple
    // backends (implementations) easier.
    IDocumentEditor editor = spawnEditor( environment.get("DDHX_BACKEND") );
    log("backend=%s", editor);
    
    string target = args.length >= 2 ? args[1] : null;
    
    // Create a session here.
    // Messy, but needed to start tracking files...
    Session *session = create_session(editor, rc, target);
    
    // Open buffer or file where (imitating GNU nano):
    // - No args:  New empty buffer
    // - "-":      Read from stdin
    // - FILENAME: Attempt to open FILE
    log(`target="%s"`, target);
    string initmsg;
    switch (target) {
    case null: // no filename
        import os.terminal : terminalInputIsPipe;
        if (terminalInputIsPipe())
            goto case "-";
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
    default: // target is set, to either: file, disk (todo), or PID (todo)
        import std.path : baseName;
        import document.base : IDocument;
        
        try
        {
            // NOTE: File permissions
            //       It is wrong to eagerly check permissions because they can
            //       change at any given moment.
            //       To bypass GVFS restrictions, open as read-only (O_RDONLY).
            IDocument doc = new FileDocument(target);
            editor.open(doc);
            session.documents ~= doc; // front-end tracks opened documents
            
            initmsg = baseName(target);
            if (rc.writemode == WritingMode.readonly)
            {
                initmsg ~= " [readonly]";
            }
        }
        catch (Exception ex)
        {
            debug log("%s", ex);
            else  log("%s", ex.msg);
            // TODO: Wouldn't it be wise to check if file exists?
            initmsg = MSG_NEWFILE;
        }
    }
    log(`initmsg="%s"`, initmsg);
    assert(initmsg, "Forgot initmsg?");
    
    try start_session(session, initmsg);
    catch (Exception ex)
    {
        writeln(); // if cursor was at some weird place, start at newline
        debug stderr.writeln("fatal: ", ex);
        else  stderr.writeln("fatal: ", ex.msg);
        log("%s", ex);
        exit(2);
    }
}