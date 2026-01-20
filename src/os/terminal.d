/// Terminal/console handling.
///
/// Watch out! Some legacy bits haunt this place.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module os.terminal;

// TODO: Switch capabilities depending on $TERM
//       "xterm", "xterm-color", "xterm-256color", "tmux-256color",
//       "linux", "vt100", "vt220", "wsvt25" (netbsd10), "screen", etc.
//       Or $COLORTERM ("truecolor", etc.)
// TODO: Consider supporting Kitty progressive key inputs
//       Format: \033[CODE;MODIFIERS;EVENTu
//       Example: \033[97;1;3u ('a' released/keyUp)
//       Query: \033[?u (returns support level)
//       Enable: \033[>1u

// NOTE: VT detection on Windows
//       Windows Terminal sets the ENABLE_VIRTUAL_TERMINAL_PROCESSING for the
//       output buffer by default. conhost and others don't, which is a good
//       universal way of detecting VT sequence support.
// NOTE: Useful links for escape codes
//       https://man7.org/linux/man-pages/man0/termios.h.0p.html
//       https://man7.org/linux/man-pages/man3/tcsetattr.3.html
//       https://man7.org/linux/man-pages/man4/console_codes.4.html

private import std.stdio : _IONBF, _IOLBF, _IOFBF, stdin, stdout;
private import core.stdc.stdlib : system;
version (unittest)
{
    private import core.stdc.stdio : printf;
    private extern (C) int putchar(int);
}

version (Windows)
{
    import core.sys.windows.winbase;
    import core.sys.windows.wincon;
    import core.sys.windows.windef; // HANDLE, USHORT, DWORD
    import core.sys.windows.winuser; // For Keycodes
    import std.windows.syserror : WindowsException;
    private enum CP_UTF8 = 65_001;
    // CONSOLE_MODE_INPUT: Used for raw input (so setup and resuming)
    // ENABLE_PROCESSED_INPUT:
    //   If set, allows the weird shift+arrow shit.
    //   If unset, captures Ctrl+C as a keystroke.
    private enum CONSOLE_MODE_INPUT = ENABLE_WINDOW_INPUT | ENABLE_MOUSE_INPUT;
    private __gshared HANDLE hIn, hOut;
    private __gshared DWORD oldCP;   // Old CodePage
    private __gshared WORD  oldAttr; // Old console attributes
    private __gshared DWORD oldMode; // Old console mode
}
else version (Posix)
{
    import core.stdc.stdio : snprintf;
    import core.stdc.errno;
    import core.sys.posix.sys.stat;
    import core.sys.posix.sys.ioctl;
    import core.sys.posix.unistd;
    import core.sys.posix.termios;
    import core.sys.posix.signal;
    import core.sys.posix.unistd : write, STDOUT_FILENO;
    import core.sys.posix.sys.types : ssize_t;
    
    private enum NULL_SIGACTION = cast(sigaction_t*)0;
    private enum SIGWINCH = 28; // Window resize signal
    
    // Bionic depends on the Linux system it's compiled on.
    // But Glibc and Musl have the same settings, so does Bionic.
    // ...And uClibc, at least on Linux.
    // D are missing the bindings for these runtimes.
    version (CRuntime_Musl)
        version = IncludeTermiosLinux;
    version (CRuntime_Bionic)
        version = IncludeTermiosLinux;
    version (CRuntime_UClibc)
        version = IncludeTermiosLinux;
    
    version (IncludeTermiosLinux)
    {
        //siginfo_t
        // termios.h, bits/termios.h
        private alias uint tcflag_t;
        private alias uint speed_t;
        private alias char cc_t;
        private enum NCCS       = 32;
        private enum TCSANOW    = 0;
        private enum TCSAFLUSH  = 2;
        private enum ICANON     = 2;
        private enum ECHO       = 10;
        private enum BRKINT     = 2;
        private enum INPCK      = 20;
        private enum ISTRIP     = 40;
        private enum ICRNL      = 400;
        private enum IXON       = 2000;
        private enum IEXTEN     = 100000;
        private enum CS8        = 60;
        private struct termios {
            tcflag_t c_iflag;
            tcflag_t c_oflag;
            tcflag_t c_cflag;
            tcflag_t c_lflag;
            cc_t c_line;
            cc_t[NCCS] c_cc;
            speed_t __c_ispeed;
            speed_t __c_ospeed;
        }
        private extern (C) int tcgetattr(int fd, termios *termios_p);
        private extern (C) int tcsetattr(int fd, int a, termios *termios_p);
        // ioctl.h
        private enum TIOCGWINSZ    = 0x5413;
        private struct winsize {
            ushort ws_row;
            ushort ws_col;
            ushort ws_xpixel;
            ushort ws_ypixel;
        }
        private extern (C) int ioctl(int fd, ulong request, ...);
    }
    
    private __gshared termios old_ios, new_ios;
}

private
{
    /// Terminal input buffer size
    enum BLEN = 8;
    
    // Bypass current definition because Phobos with GDC 10 (DMD 2.079) is incorrect
    extern (C)
    int sscanf(scope const char* s, scope const char* format, scope ...);
}

private import os.error : OSException;

/// Flags for terminalInit.
enum TermFeat {
    /// Initiate only the basic.
    none        = 0,
    /// Initiate the input system.
    rawInput    = 1,
    /// Alias for rawInput.
    inputSys    = rawInput,
    /// Initiate the alternative screen buffer.
    altScreen   = 1 << 1,
    // Report key up and mouse up events
    //inputUp     = 1 << 8,
}

private __gshared int current_features;

/// Initiate terminal.
/// Params: features = Feature bits to initiate.
/// Throws: (Windows) WindowsException on OS exception
void terminalInit(int features = 0)
{
    current_features = features;
    
    version (Windows)
    {
        CONSOLE_SCREEN_BUFFER_INFO csbi = void;
        
        // NOTE: There used to be a "hack" using CreateFileA("CONIN$", but that
        //       caused more pain than anything.
        //       So, terminalReadline was introduced that automatically applies the "pause" for
        //       input, where it re-establishes the old mode for STD_INPUT_HANDLE, and "resumes"
        //       using the desired flags.
        //       No more need to re-create stdin using "CONIN$".
        hIn = GetStdHandle(STD_INPUT_HANDLE);
        if (hIn == INVALID_HANDLE_VALUE)
            throw new OSException("GetStdHandle");
        
        if (GetConsoleMode(hIn, &oldMode) == FALSE)
            throw new OSException("SetConsoleMode");
        
        // Init input system
        if (features & TermFeat.inputSys)
        {
            // I don't remember why I set this up to be permanenently
            // enabled instead of just enabling this at the "read input"
            // function.
            if (SetConsoleMode(hIn, CONSOLE_MODE_INPUT) == FALSE)
                throw new OSException("SetConsoleMode");
        }
        
        // Use alternative screen buffer
        if (features & TermFeat.altScreen)
        {
            hOut = CreateConsoleScreenBuffer(
                GENERIC_READ | GENERIC_WRITE,       // dwDesiredAccess
                FILE_SHARE_READ | FILE_SHARE_WRITE, // dwShareMode
                null,                               // lpSecurityAttributes
                CONSOLE_TEXTMODE_BUFFER,            // dwFlags
                null,                               // lpScreenBufferData
            );
            if (hOut == INVALID_HANDLE_VALUE)
                throw new OSException("CreateConsoleScreenBuffer");
            
            // Switch stdout to new buffer
            stdout.flush;
            stdout.windowsHandleOpen(hOut, "wb"); // fixes using Phobos write functions
            if (SetStdHandle(STD_OUTPUT_HANDLE, hOut) == FALSE) // forgot what this fixes
                throw new OSException("SetStdHandle");
            
            // IIRC, this is to allow newlines
            DWORD attr = void;
            if (GetConsoleMode(hOut, &attr) == FALSE)
                throw new OSException("GetConsoleMode");
            attr &= ~ENABLE_WRAP_AT_EOL_OUTPUT;
            if (SetConsoleMode(hOut, attr | ENABLE_PROCESSED_OUTPUT) == FALSE)
                throw new OSException("SetConsoleMode");
            
            // Switch to alternative screen
            if (SetConsoleActiveScreenBuffer(hOut) == FALSE)
                throw new OSException("SetConsoleActiveScreenBuffer");
        }
        else
        {
            hOut = GetStdHandle(STD_OUTPUT_HANDLE);
            if (hOut == INVALID_HANDLE_VALUE)
                throw new OSException("GetStdHandle");
        }
        
        // NOTE: While Windows supports UTF-16LE (1200), UTF-16BE (1201), UTF-32LE (12000),
        //       and UTF-32BE (12001), it's only for "managed applications" (.NET).
        // LINK: https://docs.microsoft.com/en-us/windows/win32/intl/code-page-identifiers
        oldCP = GetConsoleOutputCP();
        if (SetConsoleOutputCP(CP_UTF8) == FALSE)
            throw new OSException("SetConsoleOutputCP");
        
        // Get current attributes (colors)
        if (GetConsoleScreenBufferInfo(hOut, &csbi) == FALSE)
            throw new OSException("GetConsoleScreenBufferInfo");
        oldAttr = csbi.wAttributes;
    }
    else version (Posix)
    {
        // Setup "raw" input system
        if (features & TermFeat.inputSys)
        {
            // If FIFO (pipe), then re-open stdin
            // HACK for stdin.readln()
            stat_t s = void;
            fstat(STDIN_FILENO, &s);
            if (S_ISFIFO(s.st_mode))
                stdin.reopen("/dev/tty", "r");
            
            if (tcgetattr(STDIN_FILENO, &old_ios) < 0)
                throw new OSException("tcgetattr(STDIN_FILENO) failed");
            new_ios = old_ios;
            // input modes
            // remove IXON (enables ^S and ^Q)
            // remove ICRNL (enables ^M)
            // remove BRKINT (causes SIGINT (^C) on break conditions)
            // remove INPCK (enables parity checking)
            // remove ISTRIP (strips the 8th bit) (ASCII-related?)
            new_ios.c_iflag &= ~(IXON | ICRNL | BRKINT | INPCK | ISTRIP);
            // output modes
            // remove OPOST (turns on output post-processing, line newlines)
            //new_ios.c_oflag &= ~(OPOST);
            // local modes
            // remove ICANON (turns on canonical mode (per-line instead of per-byte))
            // remove ECHO (turns on character echo)
            // remove ISIG (enables ^C and ^Z signals) (disables sig gen from keyboard)
            // remove IEXTEN (enables ^V)
            new_ios.c_lflag &= ~(ICANON | ECHO | IEXTEN | ISIG);
            // control modes
            // add CS8 sets Character Size to 8-bit
            new_ios.c_cflag |= CS8;
            // minimum amount of bytes to read,
            // 0 being return as soon as there is data
            //new_ios.c_cc[VMIN] = 0;
            // maximum amount of time to wait for input,
            // 1 being 1/10 of a second (100 milliseconds)
            //new_ios.c_cc[VTIME] = 0;
            if (tcsetattr(STDIN_FILENO, TCSANOW, &new_ios) < 0)
                throw new OSException("tcsetattr(STDIN_FILENO)");
        }
        
        // Use alternative screen buffer
        if (features & TermFeat.altScreen)
        {
            // change to alternative screen buffer
            stdout.write("\033[?1049h");
            stdout.flush;
        }
    } // version (Posix)
    
    // fixes weird cursor positions with alt buffer using (D) stdout,
    // which shouldn't be used, but who knows when someone would.
    stdout.setvbuf(0, _IONBF);
    
    // NOTE: atexit(3) does not work with exceptions or signals (ie, SIGINT).
    //       Avoid using it. Useless.
}

/// Restore older environment.
///
/// Doesn't throw in the case where this is called when exiting.
void terminalRestore()
{
    version (Windows)
    {
        // Neither shells or consoles will reset the codepage, but will reset
        // to the previous mode, that's why it's not called here.
        SetConsoleOutputCP(oldCP); // unconditionally
    }
    else version (Posix)
    {
        // restore main screen buffer
        if (current_features & TermFeat.altScreen)
            terminalWrite("\033[?1049l");
        
        // show cursor
        terminalWrite("\033[?25h");
        
        // restablish input ios
        if (current_features & TermFeat.inputSys)
            cast(void)tcsetattr(STDIN_FILENO, TCSANOW, &old_ios);
    }
}

//
// Resize event
//

private __gshared void function() terminalOnResizeEvent;

/// Set handler for resize events.
///
/// On Windows, (at least for conhost) this is only called when the buffer is
/// resized, not the window.
/// Params: func = Function to call.
void terminalResizeHandler(void function() func)
{
version (Posix)
{
    sigaction_t sa;
    sa.sa_flags     = 0;
    sa.sa_sigaction = &terminalResized;
    if (sigaction(SIGWINCH, &sa, NULL_SIGACTION) < 0)
        throw new OSException("sigaction(SIGWINCH)");
} // Windows: See terminalRead function
    terminalOnResizeEvent = func;
}

version (Posix)
extern (C)
private
void terminalResized(int signo, siginfo_t *info, void *content)
{
    if (terminalOnResizeEvent)
        terminalOnResizeEvent();
}

//
// Etc.
//

/// Pause terminal input. (On POSIX, this restores the old IOS)
private
void terminalPauseInput()
{
    version (Windows)
        SetConsoleMode(hIn, oldMode); // nothrow, called fine in setup
    version (Posix)
        cast(void)tcsetattr(STDIN_FILENO, TCSANOW, &old_ios);
}
/// Resume terminal input. (On POSIX, this restores the old IOS)
private
void terminalResumeInput()
{
    version (Windows)
        SetConsoleMode(hIn, CONSOLE_MODE_INPUT);
    version (Posix)
        cast(void)tcsetattr(STDIN_FILENO, TCSANOW, &new_ios);
}

/// Clear screen
void terminalClear()
{
    version (Windows)
    {
        CONSOLE_SCREEN_BUFFER_INFO csbi = void;
        COORD c;
        GetConsoleScreenBufferInfo(hOut, &csbi);
        const int size = csbi.dwSize.X * csbi.dwSize.Y;
        DWORD num;
        // No need to set attributes.
        if (FillConsoleOutputCharacterA(hOut, ' ', size, c, &num))
            terminalCursor(0, 0);
        else // If that fails, run cls.
            system("cls");
    }
    else version (Posix)
    {
        // \033c is a Reset
        // \033[2J is "Erase whole display"
        terminalWrite("\033[2J");
    } else static assert(0, "Clear: Not implemented");
}

/// Get terminal window size in characters.
/// Returns: Size.
/// Throws: OSException.
TerminalSize terminalSize()
{
    TerminalSize size = void;
    version (Windows)
    {
        CONSOLE_SCREEN_BUFFER_INFO c = void;
        if (GetConsoleScreenBufferInfo(hOut, &c) == FALSE)
            throw new OSException("GetConsoleScreenBufferInfo");
        size.rows    = c.srWindow.Bottom - c.srWindow.Top + 1;
        size.columns = c.srWindow.Right - c.srWindow.Left + 1;
        
        // TODO: Consider support for ESC[18t (Windows)
        // NOTE: Windows Terminal supports ESC[18t
        //       conhost/OpenConsole and ConsoleZ do not.
        
        // TODO: Consider saving changes from ReadConsoleInput
    }
    else version (Posix)
    {
        // NOTE: So far, the ioctl worked on:
        //       - Linux, VTE
        //       - Linux, xterm
        //       - Linux, framebuffer
        //       - FreeBSD, framebuffer
        //       - OpenBSD, framebuffer
        winsize ws = void;
        if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) < 0)
            throw new OSException("ioctl(STDOUT_FILENO, TIOCGWINSZ)");
        size.rows    = ws.ws_row;
        size.columns = ws.ws_col;
        
        // NOTE: LINES and COLUMNS variables mostly depends on shells.
        //       SUPPORTED: Bash, ksh(ksh93), zsh, fish
        //       UNSUPPORTED: sh, csh, dash, cmd, PowerShell
        
        // TODO: Consider ESC [ 18 t for fallback of environment.
        //       Reply: ESC [ 8 ; ROWS ; COLUMNS t
        //       Works on: Windows Terminal, VTE, xterm, NetBSD framebuffer
        //       Doesn't: conhost, ConsoleZ, FreeBSD framebuffer (just eats output?)
    } else static assert(0, "terminalSize: Not implemented");
    return size;
}

/// Set cursor position x and y position respectively from the top left corner,
/// 0-based.
/// Params:
///   x = X position (horizontal)
///   y = Y position (vertical)
void terminalMove(int x, int y)
{
    version (Windows) // 0-based
    {
        COORD c = void;
        c.X = cast(short)x;
        c.Y = cast(short)y;
        if (SetConsoleCursorPosition(hOut, c) == FALSE)
            throw new OSException("SetConsoleCursorPosition");
    }
    else version (Posix) // 1-based, so 0,0 needs to be output as 1,1
    {
        char[16] b = void;
        int r = snprintf(b.ptr, 16, "\033[%d;%dH", ++y, ++x);
        assert(r > 0);
        terminalWrite(b.ptr, r);
    }
}
alias terminalCursor = terminalMove;

struct TerminalPosition
{
    int column, row;
}
TerminalPosition terminalTell()
{
    TerminalPosition pos;
    
    version (Windows)
    {
        CONSOLE_SCREEN_BUFFER_INFO csbi = void;
        if (GetConsoleScreenBufferInfo(hOut, &csbi) == FALSE)
            throw new OSException("GetConsoleScreenBufferInfo");
        pos.column = csbi.dwCursorPosition.X;
        pos.row    = csbi.dwCursorPosition.Y;
    }
    else version (Posix)
    {
        // HACK: Lazy
        if ((current_features & TermFeat.rawInput) == 0)
            throw new Exception("Need raw input");
        
        // Need ICANON+ECHO off
        terminalWrite("\033[6n");
        
        // Read up to 'R' ("ESC[row;colR")
        // Can be tricky since we don't really know how much
        // until read.2 returns, so read per-byte.
        enum BSIZE = 32;
        char[BSIZE] buf = void;
        size_t i;
        while (i < BSIZE - 1)
        {
            if (read(STDIN_FILENO, buf.ptr+i, 1) < 1)
                throw new OSException("read");
            if (buf[i] == 'R') break;
            i++;
        }
        buf[i] = 0;
        
        // Parse
        if (buf[0] != '\033' || buf[1] != '[')
            throw new Exception("Not an escape code");
        int r = sscanf(buf.ptr + 2, "%d;%d", &pos.row, &pos.column);
        if (r < 2)
            throw new Exception("Missing item");
        
        // 1-based, to me, must be 0-based
        pos.row--;
        pos.column--;
    }
    
    return pos;
}

/// Hide the terminal cursor.
void terminalHideCursor()
{
    version (Windows)
    {
        // NOTE: Works in conhost, OpenConsole, and Windows Terminal.
        //       ConsoleZ won't take it.
        //       Anyway, if these were to fail, don't report issue, since it's
        //       more of an optional feature. But might throw and let caller
        //       ignore on their own terms.
        CONSOLE_CURSOR_INFO cci = void;
        cast(void)GetConsoleCursorInfo(hOut, &cci);
        cci.bVisible = FALSE;
        cast(void)SetConsoleCursorInfo(hOut, &cci);
    }
    else version (Posix)
    {
        terminalWrite("\033[?25l");
    }
}
/// Show the terminal cursor.
void terminalShowCursor()
{
    version (Windows)
    {
        CONSOLE_CURSOR_INFO cci = void;
        cast(void)GetConsoleCursorInfo(hOut, &cci);
        cci.bVisible = TRUE;
        cast(void)SetConsoleCursorInfo(hOut, &cci);
    }
    else version (Posix)
    {
        terminalWrite("\033[?25h");
    }
}

/// Terminal color.
enum TermColor
{
    black,
    blue,
    green,
    aqua,
    red,
    purple,
    yellow,
    gray,
    lightgray,
    brightblue,
    brightgreen,
    brightaqua,
    brightred,
    brightpurple,
    brightyellow,
    white,
}

// NOTE: For 24-bit colors, overload with terminalForeground(int r,int g,int b)
/// Set terminal foreground color.
/// Params: col = Color.
void terminalForeground(TermColor col)
{
    version (Windows)
    {
        static immutable ushort[16] FGCOLORS = [ // foreground colors
            // TermColor.black
            0,
            // TermColor.blue
            FOREGROUND_BLUE,
            // TermColor.green
            FOREGROUND_GREEN,
            // TermColor.aqua
            FOREGROUND_BLUE | FOREGROUND_GREEN,
            // TermColor.red
            FOREGROUND_RED,
            // TermColor.purple
            FOREGROUND_BLUE | FOREGROUND_RED,
            // TermColor.yellow
            FOREGROUND_GREEN | FOREGROUND_RED,
            // TermColor.gray
            FOREGROUND_INTENSITY,
            // TermColor.lightgray
            FOREGROUND_GREEN | FOREGROUND_RED | FOREGROUND_BLUE,
            // TermColor.brightblue
            FOREGROUND_INTENSITY | FOREGROUND_BLUE,
            // TermColor.brightgreen
            FOREGROUND_INTENSITY | FOREGROUND_GREEN,
            // TermColor.brightaqua
            FOREGROUND_INTENSITY | FOREGROUND_BLUE | FOREGROUND_GREEN,
            // TermColor.brightred
            FOREGROUND_INTENSITY | FOREGROUND_RED,
            // TermColor.brightpurple
            FOREGROUND_INTENSITY | FOREGROUND_BLUE | FOREGROUND_RED,
            // TermColor.brightyellow
            FOREGROUND_INTENSITY | FOREGROUND_RED | FOREGROUND_GREEN,
            // TermColor.white
            FOREGROUND_INTENSITY | FOREGROUND_GREEN | FOREGROUND_RED | FOREGROUND_BLUE,
        ];
        
        CONSOLE_SCREEN_BUFFER_INFO csbi = void;
        GetConsoleScreenBufferInfo(hOut, &csbi);
        WORD current = csbi.wAttributes;
        
        // Don't throw if failed, optional feature
        cast(void)SetConsoleTextAttribute(hOut, (current & 0xf0) | FGCOLORS[col]);
    }
    else version (Posix)
    {
        static immutable string[16] FGCOLORS = [ // foreground colors
            // TermColor.black
            "\033[30m",
            // TermColor.blue
            "\033[34m",
            // TermColor.green
            "\033[32m",
            // TermColor.aqua
            "\033[36m",
            // TermColor.red
            "\033[31m",
            // TermColor.purple
            "\033[35m",
            // TermColor.yellow
            "\033[33m",
            // TermColor.gray
            "\033[90m",
            // TermColor.lightgray
            "\033[37m",
            // TermColor.brightblue
            "\033[94m",
            // TermColor.brightgreen
            "\033[92m",
            // TermColor.brightaqua
            "\033[96m",
            // TermColor.brightred
            "\033[91m",
            // TermColor.brightpurple
            "\033[95m",
            // TermColor.brightyellow
            "\033[93m",
            // TermColor.white
            "\033[97m",
        ];
        
        terminalWrite(FGCOLORS[col]);
    } // version (Posix)
}

/// Set terminal background color.
/// Params: col = Color.
void terminalBackground(TermColor col)
{
    version (Windows)
    {
        static immutable ushort[16] FGCOLORS = [ // foreground colors
            // TermColor.black
            0,
            // TermColor.blue
            BACKGROUND_BLUE,
            // TermColor.green
            BACKGROUND_GREEN,
            // TermColor.aqua
            BACKGROUND_BLUE | BACKGROUND_GREEN,
            // TermColor.red
            BACKGROUND_RED,
            // TermColor.purple
            BACKGROUND_BLUE | BACKGROUND_RED,
            // TermColor.yellow
            BACKGROUND_GREEN | BACKGROUND_RED,
            // TermColor.gray
            BACKGROUND_INTENSITY,
            // TermColor.lightgray
            BACKGROUND_GREEN | BACKGROUND_RED | BACKGROUND_BLUE,
            // TermColor.brightblue
            BACKGROUND_INTENSITY | BACKGROUND_BLUE,
            // TermColor.brightgreen
            BACKGROUND_INTENSITY | BACKGROUND_GREEN,
            // TermColor.brightaqua
            BACKGROUND_INTENSITY | BACKGROUND_BLUE | BACKGROUND_GREEN,
            // TermColor.brightred
            BACKGROUND_INTENSITY | BACKGROUND_RED,
            // TermColor.brightpurple
            BACKGROUND_INTENSITY | BACKGROUND_BLUE | BACKGROUND_RED,
            // TermColor.brightyellow
            BACKGROUND_INTENSITY | BACKGROUND_RED | BACKGROUND_GREEN,
            // TermColor.white
            BACKGROUND_INTENSITY | BACKGROUND_GREEN | BACKGROUND_RED | BACKGROUND_BLUE,
        ];
        
        CONSOLE_SCREEN_BUFFER_INFO csbi = void;
        GetConsoleScreenBufferInfo(hOut, &csbi);
        WORD current = csbi.wAttributes;
        
        cast(void)SetConsoleTextAttribute(hOut, (current & 0xf) | FGCOLORS[col]);
    }
    else version (Posix)
    {
        static immutable string[16] FGCOLORS = [ // foreground colors
            // TermColor.black
            "\033[40m",
            // TermColor.blue
            "\033[44m",
            // TermColor.green
            "\033[42m",
            // TermColor.aqua
            "\033[46m",
            // TermColor.red
            "\033[41m",
            // TermColor.purple
            "\033[45m",
            // TermColor.yellow
            "\033[43m",
            // TermColor.gray
            "\033[100m",
            // TermColor.lightgray
            "\033[47m",
            // TermColor.brightblue
            "\033[104m",
            // TermColor.brightgreen
            "\033[102m",
            // TermColor.brightaqua
            "\033[106m",
            // TermColor.brightred
            "\033[101m",
            // TermColor.brightpurple
            "\033[105m",
            // TermColor.brightyellow
            "\033[103m",
            // TermColor.white
            "\033[107m",
        ];
        
        terminalWrite(FGCOLORS[col]);
    } // version (Posix)
}

/// Invert color.
void terminalInvertColor()
{
    version (Windows)
    {
        SetConsoleTextAttribute(hOut, oldAttr | COMMON_LVB_REVERSE_VIDEO);
    }
    else version (Posix)
    {
        terminalWrite("\033[7m");
    }
}
/// Reset color.
void terminalResetColor()
{
    version (Windows)
    {
        SetConsoleTextAttribute(hOut, oldAttr);
    }
    else version (Posix)
    {
        terminalWrite("\033[0m");
    }
}


/// Directly write to output.
/// Params:
///     data = Character data.
/// Returns: Number of bytes written.
size_t terminalWrite(const(void)[] data)
{
    return terminalWrite(data.ptr, data.length);
}
/// Directly write to output.
/// Params:
///     data = Character data. (variadic parameter)
/// Returns: Number of bytes written.
size_t terminalWrite(const(void)[][] data...)
{
    size_t r;
    foreach (d; data)
        r += terminalWrite(d.ptr, d.length);
    return r;
}

/// Directly write to output.
/// Params:
///     data = Character data.
///     size = Amount in bytes.
/// Returns: Number of bytes written.
/// Throws: OSException.
size_t terminalWrite(const(void) *data, size_t size)
{
    version (Windows)
    {
        uint written = void;
        BOOL r = WriteFile(hOut, data, cast(uint)size, &written, null);
        if (r == FALSE)
            throw new OSException("WriteFile");
        return written;
    }
    else version (Posix)
    {
        ssize_t written = write(STDOUT_FILENO, data, size);
        if (written < 0)
            throw new OSException("write");
        return written;
    }
}

/// Type a specific character n times using an internal buffer.
/// Params:
///   chr = Character.
///   amount = The amount of times to write it.
/// Returns: amount.
size_t terminalWriteChar(int chr, int amount)
{
    import core.stdc.string : memset;
    enum B = 128;
    char[B] buf = void;
    memset(buf.ptr, chr, B); // fill buf with char
    
    // full buffer chunks
    for (; amount > B; amount -= B)
        terminalWrite(buf.ptr, B);
    
    // leftover
    terminalWrite(buf.ptr, amount);
    
    return amount;
}

/// Flushes terminal output.
void terminalFlush()
{
    version (Windows)
    {
        // No-op. That is because the console output is not buffered.
        // I believe that includes both conhost (OpenConsole) and Windows Terminal.
    }
    else
    {
        fsync(STDOUT_FILENO);
    }
}

/// Perform a non-blocking peek for terminal input.
/// Returns: Number of events.
int terminalHasInput()
{
    version(Windows)
    {
        DWORD events = void;
        if (GetNumberOfConsoleInputEvents(hIn, &events) == FALSE)
            throw new OSException("GetNumberOfConsoleInputEvents");
        return cast(int)events;
    }
    else version(Posix)
    {
        import core.sys.posix.poll : poll, pollfd, POLLIN;
        // Use select/poll with 0 timeout
        pollfd pfd;
        pfd.fd = STDIN_FILENO;
        pfd.events = POLLIN;
        int r = poll(&pfd, 1, 0);
        if (r < 0)
            throw new OSException("poll");
        return r;
    }
}

/// Read an input event. This function is blocking.
/// Throws: (Windows) WindowsException on OS error.
/// Returns: Terminal input.
TermInput terminalRead()
{
    TermInput event;
    
    version (Windows)
    {
        enum ALT_PRESSED  = RIGHT_ALT_PRESSED  | LEFT_ALT_PRESSED;
        enum CTRL_PRESSED = RIGHT_CTRL_PRESSED | LEFT_CTRL_PRESSED;

        INPUT_RECORD ir = void;
        DWORD num = void;
Lread:
        if (ReadConsoleInputA(hIn, &ir, 1, &num) == 0)
            throw new OSException("ReadConsoleInputA");
        if (num == 0)
            goto Lread;
        
        switch (ir.EventType) {
        case KEY_EVENT:
            if (ir.KeyEvent.bKeyDown == FALSE)
                goto Lread;
            
            version (unittest)
            {
                printf(
                "KeyEvent: AsciiChar=%d UnicodeChar=%d wVirtualKeyCode=%d dwControlKeyState=0x%x\n",
                ir.KeyEvent.AsciiChar,
                ir.KeyEvent.UnicodeChar,
                ir.KeyEvent.wVirtualKeyCode,
                ir.KeyEvent.dwControlKeyState
                );
            }
            
            const ushort keycode = ir.KeyEvent.wVirtualKeyCode;
            
            // Filter out single modifier key events
            switch (keycode) {
            case 16, 17, 18: goto Lread; // shift,ctrl,alt
            default:
            }
            
            event.type = InputType.keyDown;
            
            // NOTE: Unavailable shortcuts.
            //       With the "Enable Ctrl key shortcuts", conhost (and possibly
            //       Windows Terminal) will interfere with some Ctrl shortcuts,
            //       like Ctrl+Home and Ctrl+End. Setting it that settings
            //       restores this capability.
            with (ir.KeyEvent) {
            if (dwControlKeyState & ALT_PRESSED)   event.key = Mod.alt;
            if (dwControlKeyState & CTRL_PRESSED)  event.key = Mod.ctrl;
            if (dwControlKeyState & SHIFT_PRESSED) event.key = Mod.shift;
            }
            
            // TODO: ir.KeyEvent.UnicodeChar to multi-byte
            event.kbuffer[0] = ir.KeyEvent.AsciiChar;
            event.ksize      = 1;
            
            // Special keys
            switch (keycode) {
            case VK_INSERT: event.key |= Key.Insert; break;
            case VK_DELETE: event.key |= Key.Delete; break;
            case VK_HOME:   event.key |= Key.Home; break;
            case VK_END:    event.key |= Key.End; break;
            case VK_PRIOR:  event.key |= Key.PageUp; break;
            case VK_NEXT:   event.key |= Key.PageDown; break;
            case VK_LEFT:   event.key |= Key.LeftArrow; break;
            case VK_RIGHT:  event.key |= Key.RightArrow; break;
            case VK_UP:     event.key |= Key.UpArrow; break;
            case VK_DOWN:   event.key |= Key.DownArrow; break;
            default: // Special key range
                const char ascii = ir.KeyEvent.AsciiChar;
                if (keycode >= VK_NUMPAD0 && keycode <= VK_NUMPAD9)
                {
                    event.key = (keycode - VK_NUMPAD0) + '0';
                }
                else if (keycode >= VK_F1 && keycode <= VK_F24)
                {
                    event.key = (keycode - VK_F1) + Key.F1;
                }
                else if (ascii >= 'a' && ascii <= 'z')
                {
                    event.key |= ascii - 32;
                }
                else if (ascii >= 32 && ascii < 127)
                {
                    event.key |= ascii;
                    // HACK: Remove unnatural modifiers (ie, for '@')
                    //       readline depends on this
                    event.key &= ~(Mod.ctrl|Mod.alt);
                }
                else
                    event.key |= keycode;
            }
            return event;
        /*case MOUSE_EVENT:
            if (ir.MouseEvent.dwEventFlags & MOUSE_WHEELED)
            {
                // Up=0x00780000 Down=0xFF880000
                event.type = ir.MouseEvent.dwButtonState > 0xFF_0000 ?
                    Mouse.ScrollDown : Mouse.ScrollUp;
            }*/
        // NOTE: The console buffer is different than window resize
        //       It is misleading. Only updated after a new event enters input queue.
        case WINDOW_BUFFER_SIZE_EVENT:
            if (terminalOnResizeEvent)
                terminalOnResizeEvent();
            goto Lread;
        default: goto Lread;
        }
    }
    else version (Posix)
    {
        // TODO: Mouse reporting in Posix terminals
        //       * X10 compatbility mode (mouse-down only)
        //       Enable: ESC [ ? 9 h
        //       Disable: ESC [ ? 9 l
        //       "sends ESC [ M bxy (6 characters)"
        //       - ESC [ M button column row (1-based)
        //       - 0,0 click: "ESC[M !!"
        //         ! is 0x21, so '!' - 0x21 = 0
        //       - end,end click: "ESC[M q;"
        //         q is 0x71, so 'q' - 0x21 = 0x50 (column 80)
        //         ; is 0x3b, so ';' - 0x21 = 0x1a (row 26)
        //       - button left:   ' '
        //       - button right:  '"'
        //       - button middle: '!'
        //       * Normal tracking mode
        //       Enable: ESC [ ? 1000 h
        //       Disable: ESC [ ? 1000 l
        //       b bits[1:0] 0=MB1 pressed, 1=MB2 pressed, 2=MB3 pressed, 3=release
        //       b bits[7:2] 4=Shift (bit 3), 8=Meta (bit 4), 16=Control (bit 5)
        
    Lread:
        ssize_t r = read(STDIN_FILENO, event.kbuffer.ptr, BLEN);
        // NOTE: EINTR (errno=4)
        //       Emitted when resizing or on ^C.
        if (r < 0)
            goto Lread;
        
        version (unittest)
        {
            printf("stdin: ");
            for (size_t i; i < r; ++i)
            {
                if (i) printf(", ");
                char c = event.kbuffer[i];
                if (c < 32 || c > 126) // non-printable ascii
                    printf("\\0%o", c);
                else
                    printf("'%c'", event.kbuffer[i]);
            }
            cast(void)putchar('\n');
        }
        
        event.ksize = cast(int)r;
        event.type = InputType.keyDown; // Assuming for now
        event.key  = 0; // clear as safety measure
        
        if (r == 0)
        {
            version (unittest) printf("stdin: empty\n");
            goto Lread;
        }
        
        enum ESC = 0x1b;
        
        struct KeyInfo {
            string text;
            int value;
        }
        
        // https://espterm.github.io/docs/espterm-xterm.html
        switch (event.kbuffer[0]) {
        case 0: // Ctrl+Space
            event.key = Key.Spacebar | Mod.ctrl;
            return event;
        case 13:
            event.key = Key.Enter;
            return event;
        case 8:     // ^H (ctrl+backspace)
            event.key = Key.Backspace | Mod.ctrl;
            return event;
        case 9: // Tab without control key
            // Shift+tab -> "\033[Z" (xterm)
            event.key = Key.Tab;
            return event;
        case 127:
            event.key = Key.Backspace;
            return event;
        case ESC: // \x1b / \033
            if (r <= 1) // ESC only
            {
                event.key = Key.Escape;
                return event;
            }
            
            char[] input = event.kbuffer[1..r];
            
            // Next, detect sequence
            switch (event.kbuffer[1]) { // next char after ESC
            case '[': // CSI, Control Sequence Introducer
                // Detect special modifier keys if there are any
                if (r >= 5 && event.kbuffer[2] == '1' && event.kbuffer[3] == ';')
                {
                    // 1;2 -> Shift
                    // 1;3 -> Alt
                    // 1;4 -> Shift+Alt
                    // 1;5 -> Ctrl
                    // 1;6 -> Ctrl+Shift
                    // 1;7 -> Alt+Ctrl
                    // 1;8 -> Shift+Alt+Ctrl
                    switch (event.kbuffer[4]) {
                    case '2': event.key = Mod.shift; break;
                    case '3': event.key = Mod.alt; break;
                    case '4': event.key = Mod.shift|Mod.alt; break;
                    case '5': event.key = Mod.ctrl; break;
                    case '6': event.key = Mod.ctrl|Mod.shift; break;
                    case '7': event.key = Mod.ctrl|Mod.alt; break;
                    case '8': event.key = Mod.ctrl|Mod.alt|Mod.shift; break;
                    default: goto Lread; // Unknown, don't bother misreporting
                    }
                    input = input[4..$];
                }
                else if (r >= 5 && event.kbuffer[2] == '3' && event.kbuffer[3] == ';')
                {
                    // HACK: Lazy, but seems to imitate previous switch (swapped...)
                    switch (event.kbuffer[4]) {
                    case '2': // "ESC[3;2~" -> Shift+Delete
                        event.key = Mod.shift | Key.Delete;
                        return event;
                    case '5': // "ESC[3;5~" -> Ctrl+Delete
                        event.key = Mod.ctrl | Key.Delete;
                        return event;
                    default: goto Lread; // Unknown, don't bother misreporting
                    }
                }
                else
                    input = input[1..$];
                break;
            case 'O': // SS3/G3 character set (application mode)
                // WARNING: Shift+Alt+O will lead here
                input = input[1..$];
                break;
            default: // Alt+KEY
                event.key = Mod.alt | (input[0] - 32);
                return event;
            }
            
            static immutable KeyInfo[] specials = [
                // xterm
                { "A",      Key.UpArrow },
                { "B",      Key.DownArrow },
                { "C",      Key.RightArrow },
                { "D",      Key.LeftArrow },
                { "H",      Key.Home },
                { "F",      Key.End },
                { "1~",     Key.Home },
                { "2~",     Key.Insert },
                { "3~",     Key.Delete },
                { "4~",     Key.End },
                { "5~",     Key.PageUp },
                { "6~",     Key.PageDown },
                { "P",      Key.F1 },
                { "Q",      Key.F2 },
                { "R",      Key.F3 },
                { "S",      Key.F4 },
                { "15~",    Key.F5 },
                { "17~",    Key.F6 },
                { "18~",    Key.F7 },
                { "19~",    Key.F8 },
                { "20~",    Key.F9 },
                { "21~",    Key.F10 },
                { "23~",    Key.F11 },
                { "24~",    Key.F12 },
                { "Z",      Key.Tab | Mod.shift },
                // vt220
                { "11~",    Key.F1 },
                { "12~",    Key.F2 },
                { "13~",    Key.F1 },
                { "14~",    Key.F2 },
                { "7~",     Key.Home },
                { "8~",     Key.End },
            ];
            
            foreach (spec; specials)
            {
                if (input == spec.text)
                {
                    event.key |= spec.value;
                    return event;
                }
            }
            goto Lread;
        default:
        }
        
        // g       -> 'g'
        // shift+g -> 'G'
        // ctrl+g  -> \07
        // alt+g   -> \033 g
        // xterm: Alt+Return -> \033 \015
        // vt220: Alt+Return -> \0215
        int c = event.kbuffer[0];
        if (c >= 'a' && c <= 'z')
            event.key = cast(ushort)(c - 32);
        else if (c >= 'A' && c <= 'Z')
            event.key = c | Mod.shift;
        else if (c < 32) // ctrl key
            event.key = (c + 64) | Mod.ctrl;
        // vt220: alt+a (\0341) to alt+z (\0372)
        else if (c >= 225 && c <= 250)
            event.key = (c - 160) | Mod.alt;
        else
            event.key = c;
            
        return event;
    } // version (Posix)
}

private
struct LineBuffer
{
    size_t insert(size_t i, char[] chr)
    {
        size_t w = graphs(chr);
        
        // Ensure we have enough capacity
        ensureCapacity(i, chr.length);
        
        // Shift existing content to the right to make space
        if (i < length)
        {
            import core.stdc.string : memmove;
            memmove(&buffer[i + chr.length], &buffer[i], length - i);
        }
        
        // Copy new characters into position
        buffer[i .. i + chr.length] = chr[];
        length += chr.length;
        
        cells += w;
        
        return w;
    }
    
    // delete size in bytes (change to grapheme count later)
    size_t deleteAt(size_t i, size_t delsize)
    {
        // Bounds check
        if (i >= length || delsize == 0)
            return 0;
        
        // LAZY: to get diff in cells
        size_t a = graphs(buffer[0..length]);
        
        // Clamp size to available characters
        if (i + delsize > length)
            delsize = length - i;
        
        // Shift remaining content left
        if (i + delsize < length)
        {
            import core.stdc.string : memmove;
            memmove(&buffer[i], &buffer[i + delsize], length - i - delsize);
        }
        
        length -= delsize;
        
        cells = graphs(buffer[0..length]);
        
        return a - cells;
    }
    
    // private but this module can see this function anyway
    void ensureCapacity(size_t i, size_t insize) // incoming size
    {
        // Nothing to do
        if (i + insize < buffer.length)
            return;
        
        // Align up amount of memory to reallocate
        enum ALGN  = 128;
        enum MASK  = ALGN - 1;
        size_t amt = (i + insize + MASK) & ~MASK;
        buffer.length = amt;
    }
    
    /// Count of cells that the multibyte buffer would take to render on screen
    size_t cells;
    /// Current size of content in bytes
    size_t length;
    // Buffer
    char[] buffer;
    
    inout(char)[] opSlice() inout // preserves const
    {
        return buffer[0..length];
    }
    string toString() const
    {
        return cast(immutable)buffer[0..length].idup;
    }
}
unittest
{
    LineBuffer buf;
    
    // Test basic insertion
    assert(buf.insert(0, cast(char[])"hello") == "hello".length);
    assert(buf.length == 5);
    assert(buf.cells  == 5);
    assert(buf[] == "hello");
    
    // Test insertion in middle
    assert(buf.insert(5, cast(char[])" world") == " world".length);
    assert(buf.length == 11);
    assert(buf.cells  == 11);
    assert(buf[] == "hello world");
    
    // Test insertion at arbitrary position
    assert(buf.insert(5, cast(char[])",") == 1);
    assert(buf.length == 12);
    assert(buf.cells  == 12);
    assert(buf[] == "hello, world");
    
    // Test deletion
    assert(buf.deleteAt(5, 2) == 2); // Remove ", "
    assert(buf.length == 10);
    assert(buf.cells  == 10);
    assert(buf[] == "helloworld");
    
    // Test deletion at end
    assert(buf.deleteAt(5, 10) == 5); // Should clamp to available
    assert(buf.length == 5);
    assert(buf.cells  == 5);
    assert(buf[] == "hello");
    
    // Test deletion beyond bounds
    assert(buf.deleteAt(100, 5) == 0); // Should do nothing
    assert(buf.length == 5);
    assert(buf.cells  == 5);
    assert(buf[] == "hello");
    
    // Test capacity expansion
    assert(buf.insert(0, cast(char[])"x") == 1);
    assert(buf.length == 6);
    assert(buf.cells  == 6);
    assert(buf[]== "xhello");
}

// Count number of visible printed characters (for a terminal) from a narrow
// mutlibyte string.
private
size_t graphs(inout(char)[] s)
{
    if (s is null || s.length == 0)
        return 0;
    
    size_t width;
    size_t i;
    while (i < s.length)
    {
        import std.uni : graphemeStride;
        size_t stride = graphemeStride(s, i);
        dchar c = s[i];  // First char of grapheme
        
        // Rough heuristic for wide chars
        if (c >= 0x1100 && (
            (c >= 0x1100 && c <= 0x115F) ||  // Hangul
            (c >= 0x2E80 && c <= 0x9FFF) ||  // CJK
            (c >= 0xAC00 && c <= 0xD7A3) ||  // Hangul Syllables
            (c >= 0xFF00 && c <= 0xFF60)))   // Fullwidth
            width += 2;
        else
            width += 1;
        
        i += stride;
    }
    
    return width;
}
unittest
{
    assert(graphs(null)         == 0);
    assert(graphs("")           == 0);
    assert(graphs("hello")      == "hello".length);
    assert(graphs("🥴")         == 1); // WOOZY, U+1F974
}

private enum {
    _RL_BUFCHANGED = 1 << 16, /// Buffer content changed
}
private 
struct ReadlineState
{
    /// Original cursor position.
    /// Pre-Windows 10 doesn't have '\r' and even then.
    TerminalPosition orig;
    /// Caret (cursor) position.
    size_t caret;
    /// Base position. View/camera.
    size_t base;
}
// Render line on-screen
private
void readlineRender(ref ReadlineState state, char[] buffer, size_t characters, int flags)
{
    import std.algorithm : min, max;
    
    // NOTE: Could also be an imposed max size (like for a text field)
    TerminalSize tsize = terminalSize();
    
    terminalMove(state.orig.column, state.orig.row);
    
    int width = tsize.columns;
    int avail = width - state.orig.column;
    
    // Adjust view
    if (state.caret < state.base)
        state.base = state.caret;
    else if (state.caret >= avail)
        state.base = state.caret - avail;
    
    // Valid, but is of Take!R type
    /*import std.utf : byDchar;
    import std.range : drop, take;
    auto visible = buffer.byDchar.drop(state.base).take(avail);*/
    
    // Write buffer
    size_t visible = min(avail, buffer.length);
    int w = cast(int)terminalWrite(buffer[state.base .. state.base + visible]);
    if (w < width) // fill
        terminalWriteChar(' ', width - w - state.orig.column);
    
    // Position caret on screen
    int x = state.orig.column + cast(int)state.caret;
    if (x >= width) // outside buffer
        x = width - 1;
    terminalMove(x, state.orig.row);
    
    terminalFlush(); // fbcons on Linux/BSDs need this
}

// Flags to better define behavior versus relying on current_features.
enum {
    /// Uses legacy readln method.
    RL_LEGACY = 1,
    /// Use history feature. Enables saving lines and using up/down arrows.
    RL_HISTORY = 2,
}
/// Read a line.
/// Params: flags = Read flags.
/// Returns: String without newline.
string readline(int flags = 0)
{
    // Cheap line-oriented if we're not using alternate screen buffer,
    // because there isn't any rendering worries. Legacy bit.
    // To be removed later.
    if (flags & RL_LEGACY)
    {
        import std.stdio : readln;
        import std.string : chomp;
        if (current_features & TermFeat.rawInput)
            terminalPauseInput();
        terminalShowCursor();
        string line = readln().chomp();
        terminalHideCursor();
        if (current_features & TermFeat.rawInput)
            terminalResumeInput();
        return line;
    }
    
    // TODO: History
    //       Can be saved and selected from there.
    
    // Prep work
    ReadlineState rl_state;
    rl_state.orig = terminalTell();
    
    // HACK: Cheap way to clear line + setup cursor
    //       Removes responsability from caller
    terminalWriteChar(' ', terminalSize().columns-rl_state.orig.column-1);
    with (rl_state.orig) terminalMove(column, row);
    terminalFlush(); // Needed on fbcons
    
    LineBuffer line;    /// Line buffer
    int rl_flags = void;
Lread: // Emulate line buffer
    rl_flags = flags;
    // NOTE: Only stdout (Phobos) is setup with _IONBF
    TermInput input = terminalRead();
    if (input.type != InputType.keyDown)
        goto Lread;
    switch (input.key) {
    // NOTE: Is ^C is something else in other locales?
    //       TermInput could be updated with a new event type
    case Mod.ctrl | Key.C, Key.Escape: // \033 (ESC)
        throw new Exception("Cancelled");
    case Key.Enter:
        goto Lout;
    case Key.LeftArrow:
        if (rl_state.caret == 0)
            goto Lread;
        --rl_state.caret; // TODO: multibyte jump
        break;
    case Key.RightArrow:
        if (rl_state.caret >= line.length)
            goto Lread;
        ++rl_state.caret; // TODO: multibyte jump
        break;
    case Mod.ctrl | Key.LeftArrow:
        if (rl_state.caret == 0)
            goto Lread;
        size_t i = rl_state.caret;
        while (--i > 0)
        {
            // TODO: Need "isspace(...)" multibyte function
            if (line.buffer[i] == ' ')
                break;
        }
        rl_state.caret = i;
        break;
    case Mod.ctrl | Key.RightArrow:
        if (rl_state.caret >= line.length)
            goto Lread;
        size_t i = rl_state.caret;
        while (++i < line.length)
        {
            // TODO: Need "isspace(...)" multibyte function
            if (line.buffer[i] == ' ')
                break;
        }
        rl_state.caret = i;
        break;
    // TODO: Line History
    case Key.UpArrow:
    case Key.DownArrow:
        goto Lread;
    case Key.Home:
        rl_state.caret = 0;
        break;
    case Key.End:
        rl_state.caret = line.length;
        break;
    case Key.Delete: // front delete character
        if (rl_state.caret >= line.length) // nothing to delete
            goto Lread;
        
        line.deleteAt(rl_state.caret, 1);
        rl_flags |= _RL_BUFCHANGED;
        break;
    case Mod.ctrl | Key.Delete: // front delete word
        if (rl_state.caret >= line.length) // nothing to delete
            goto Lread;
        size_t i = rl_state.caret;
        while (++i < line.length)
        {
            // TODO: Need "isspace(...)" multibyte function
            if (line.buffer[i] == ' ')
                break;
        }
        line.deleteAt(rl_state.caret, i - rl_state.caret);
        rl_flags |= _RL_BUFCHANGED;
        break;
    case Key.Backspace: // back delete character
        if (rl_state.caret == 0) // nothing to delete
            goto Lread;
        
        line.deleteAt(--rl_state.caret, 1);
        rl_flags |= _RL_BUFCHANGED;
        break;
    case Mod.ctrl | Key.Backspace: // back delete word
        if (rl_state.caret == 0) // nothing to delete
            goto Lread;
        size_t i = rl_state.caret;
        while (--i > 0)
        {
            // TODO: Need "isspace(...)" multibyte function
            if (line.buffer[i] == ' ')
                break;
        }
        line.deleteAt(i, rl_state.caret - i);
        rl_state.caret = i;
        rl_flags |= _RL_BUFCHANGED;
        break;
    case Key.Tab: // TODO: Auto-complete
        goto Lread;
    // Ignore list
    case Key.PageDown, Key.PageUp, Key.Insert:
        goto Lread;
    default: // insert char
        // Ignore function keys by range instead of polluting switch-case
        if (input.key >= Key.F1 && input.key <= Key.F24)
            goto Lread;
        
        // Attempt to exclude weirder cases
        if (input.key & (Mod.ctrl|Mod.alt))
            goto Lread;
        
        // If size is 1 (ASCII) and is outside of ASCII range, skip
        import core.stdc.ctype : isprint;
        if (!isprint(input.kbuffer[0]))
            goto Lread;
        
        rl_state.caret +=
            line.insert(rl_state.caret, input.kbuffer[0..input.ksize]);
        rl_flags |= _RL_BUFCHANGED;
    }
    readlineRender(rl_state, line[], line.cells, rl_flags);
    goto Lread;
    
Lout:
    // TODO: If RL_HISTORY, save into history
    return line.toString();
}

/// Terminal input type.
enum InputType
{
    keyDown,
    keyUp,
    mouseDown,
    mouseUp,
}

/// Key modifier
enum Mod // More readable than templates: CTRL!(ALT!(SHIFT!('a')))
{
    ctrl  = 1 << 24,
    shift = 1 << 25,
    alt   = 1 << 26,
}

/// Translated keycode.
///
/// 31..24: Modifiers
/// 23..16: Special keys
/// 15..0: Character
enum Key // These are fine for now
{
    // Special legacy keys (<32)
    Undefined = 0,
    Backspace = 8,
    Tab = 9,
    Enter = 13,
    Escape = 27,
    
    // ASCII (32..127)
    Spacebar = 32,
    Exclamation = 32,
    Plus = 43,
    Minus = 45,
    D0 = 48,
    D1 = 49,
    D2 = 50,
    D3 = 51,
    D4 = 52,
    D5 = 53,
    D6 = 54,
    D7 = 55,
    D8 = 56,
    D9 = 57,
    Colon = 58,
    SemiColon = 59,
    A = 65,
    B = 66,
    C = 67,
    D = 68,
    E = 69,
    F = 70,
    G = 71,
    H = 72,
    I = 73,
    J = 74,
    K = 75,
    L = 76,
    M = 77,
    N = 78,
    O = 79,
    P = 80,
    Q = 81,
    R = 82,
    S = 83,
    T = 84,
    U = 85,
    V = 86,
    W = 87,
    X = 88,
    Y = 89,
    Z = 90,
    
    // Special keys
    PageUp      = 0x01_0000,
    PageDown,
    End,
    Home,
    LeftArrow,
    UpArrow,
    RightArrow,
    DownArrow,
    Select,
    Print,
    Execute,
    PrintScreen,
    Insert,
    Delete,
    Help,
    Multiply,
    Add,
    Separator,
    Subtract,
    Decimal,
    Divide,
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,
    F13,
    F14,
    F15,
    F16,
    F17,
    F18,
    F19,
    F20,
    F21,
    F22,
    F23,
    F24,
    __specialmax // for unittest
}
static assert(Key.__specialmax < 0x01_00_0000);

/// Terminal input structure
struct TermInput
{
    union {
    struct
    {
        int key;            /// Keyboard input with possible Mod flags.
        int ksize;          /// Size of the filled input buffer
        char[8] kbuffer;    /// Input buffer for the character
    }
    struct
    {
        ushort mouseX; /// Mouse column coord
        ushort mouseY; /// Mouse row coord
    }
    } // union
    int type; /// Terminal input event type
}

/// Terminal size structure
struct TerminalSize
{
    /// Terminal width in character columns
    int columns;
    /// Terminal height in character rows
    int rows;
}

// If string has this needle, remove it (single instance) and return slice without needle.
private
string strhas(string needle, string haystack)
{
    import std.string : indexOf;
    
    ptrdiff_t i = indexOf(haystack, needle);
    if (i < 0) return null;
    
    return haystack[0..i]~haystack[i+needle.length..$];
}
unittest
{
    assert(strhas("ctrl+", "a")            == null);
    assert(strhas("ctrl+", "ctrl+a")       == "a");
    assert(strhas("ctrl+", "ctrl+shift+a") == "shift+a");
    assert(strhas("ctrl+", "shift+ctrl+a") == "shift+a");
}

/// Return key value from string interpretation.
/// Throws: Exception.
/// Params:
///     value = String value.
/// Returns: Keys.
int terminalKeybind(string value)
{
    import std.string : startsWith;
    
    if (value.length == 0)
        throw new Exception("Expected key, got empty");
    
    int mod; /// modificators
    
    if (string v = strhas("ctrl+", value))
    {
        mod |= Mod.ctrl;
        value = v;
    }
    
    if (string v = strhas("alt+", value))
    {
        mod |= Mod.alt;
        value = v;
    }
    
    if (string v = strhas("shift+", value))
    {
        mod |= Mod.shift;
        value = v;
    }
    
    // Second check with modifiers sliced out
    if (value.length == 0)
        throw new Exception("Expected key, got empty");
    
    if (value.length == 1)
    {
        int c = value[0];
        // ISSUE: Yes, adjusts to Key.* enum, but 'a' is also valid...
        //        Keeping this for compatibility
        if (c >= 'a' && c <= 'z') // lower ascii
            return mod | (c - 32);
        else if (c >= 32 && c < 127) // printable
            return mod | c;
    }
    
    switch (value) {
    case "insert":      return mod | Key.Insert;
    case "home":        return mod | Key.Home;
    case "page-up":     return mod | Key.PageUp;
    case "page-down":   return mod | Key.PageDown;
    case "delete":      return mod | Key.Delete;
    case "left-arrow":  return mod | Key.LeftArrow;
    case "right-arrow": return mod | Key.RightArrow;
    case "up-arrow":    return mod | Key.UpArrow;
    case "down-arrow":  return mod | Key.DownArrow;
    case "tab":         return mod | Key.Tab;
    case "backspace":   return mod | Key.Backspace;
    case "f1":          return mod | Key.F1;
    case "f2":          return mod | Key.F2;
    case "f3":          return mod | Key.F3;
    case "f4":          return mod | Key.F4;
    case "f5":          return mod | Key.F5;
    case "f6":          return mod | Key.F6;
    case "f7":          return mod | Key.F7;
    case "f8":          return mod | Key.F8;
    case "f9":          return mod | Key.F9;
    case "f10":         return mod | Key.F10;
    case "f11":         return mod | Key.F11;
    case "f12":         return mod | Key.F12;
    default:
    }
    
    throw new Exception("Unknown key");
}
// Older alias
alias terminal_keybind = terminalKeybind;
unittest
{
    assert(terminal_keybind("a")             == Key.A);
    assert(terminal_keybind("alt+a")         == Mod.alt+Key.A);
    assert(terminal_keybind("ctrl+a")        == Mod.ctrl+Key.A);
    assert(terminal_keybind("ctrl+shift+a")  == Mod.ctrl+Mod.shift+Key.A);
    assert(terminal_keybind("shift+ctrl+a")  == Mod.ctrl+Mod.shift+Key.A);
    assert(terminal_keybind("shift+a")       == Mod.shift+Key.A);
    assert(terminal_keybind("ctrl+0")        == Mod.ctrl+Key.D0);
    assert(terminal_keybind("ctrl+insert")   == Mod.ctrl+Key.Insert);
    assert(terminal_keybind("ctrl+home")     == Mod.ctrl+Key.Home);
    assert(terminal_keybind("page-up")       == Key.PageUp);
    assert(terminal_keybind("shift+page-up") == Mod.shift+Key.PageUp);
    assert(terminal_keybind("delete")        == Key.Delete);
    assert(terminal_keybind("f1")            == Key.F1);
    assert(terminal_keybind(":")             == ':');
    assert(terminal_keybind(":")             == Key.Colon);
}
