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

// NOTE: VT detection on Windows
//       Windows Terminal sets the ENABLE_VIRTUAL_TERMINAL_PROCESSING for the
//       output buffer by default. conhost and others don't, which is a good
//       universal way of detecting VT sequence support.
// Useful links for escape codes
// https://man7.org/linux/man-pages/man0/termios.h.0p.html
// https://man7.org/linux/man-pages/man3/tcsetattr.3.html
// https://man7.org/linux/man-pages/man4/console_codes.4.html

import std.stdio : _IONBF, _IOLBF, _IOFBF, stdin, stdout;

import core.stdc.stdlib : system;
import core.stdc.string : memmove, memset;

import os.error : OSException;

version (Windows)
{
    import core.sys.windows.winbase;
    import core.sys.windows.wincon;
    import core.sys.windows.windef; // HANDLE, USHORT, DWORD
    import core.sys.windows.winuser; // For Keycodes
    import core.sys.windows.winnls : WideCharToMultiByte;
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
    
    private enum VINTR = 3; // Verified in ConsoleZ, CMD, and Windows Terminal
}
else version (Posix)
{
    import core.stdc.stdio : snprintf;
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
    
    version (NetBSD)
    {
        import core.stdc.config : c_long;
        private enum IOC_OUT = cast(c_long)0x40000000;
        private enum IOCPARM_MASK = 0x1fff;
        private enum IOCPARM_SHIFT = 16;
        private enum IOCGROUP_SHIFT = 8;
        // #define	_IOC(inout, group, num, len) \
        //    ((inout) | (((len) & IOCPARM_MASK) << IOCPARM_SHIFT) | \
        //    ((group) << IOCGROUP_SHIFT) | (num))
        // #define	_IOR(g,n,t)	_IOC(IOC_OUT,	(g), (n), sizeof(t))
        // #define	TIOCGWINSZ	_IOR('t', 104, struct winsize)	/* get window size */
        // #define	TIOCGSIZE	TIOCGWINSZ
        private enum TIOCGWINSZ =
            IOC_OUT | ((winsize.sizeof & IOCPARM_MASK) << IOCPARM_SHIFT) |
            ('t' << IOCGROUP_SHIFT) | 104;
    }
    
    version (OpenBSD)
    {
        // sys/sys/iccom.h
        private enum uint IOC_OUT       = 0x40000000;
        private enum uint IOCPARM_MASK  = 0x1fff;
        private enum uint _IOC(uint inout_, uint group, uint num, uint len) =
            inout_ | ((len & IOCPARM_MASK) << 16) | (group << 8) | num;
        // sys/sys/ttycom.h
        private enum uint TIOCGWINSZ = _IOC!(IOC_OUT, 't', 104, winsize.sizeof);
    }
    
    private __gshared termios old_ios, new_ios;
    private __gshared int vintr, vquit;
}

private
{
    // Bypass current definition because Phobos with GDC 10 (DMD 2.079) is incorrect
    extern (C)
    int sscanf(scope const char* s, scope const char* format, scope ...);
}

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

/// Determines is stdin is a FIFO/Pipe.
///
/// Safe to call before terminalInit.
/// Returns: True if FIFO/Pipe.
bool terminalInputIsPipe()
{
version (Windows)
{
    HANDLE h = GetStdHandle(STD_INPUT_HANDLE);
    if (h == INVALID_HANDLE_VALUE)
        throw new OSException("GetStdHandle");
    return GetFileType(h) == FILE_TYPE_PIPE;
}
else // POSIX
{
    stat_t s = void;
    if (fstat(STDIN_FILENO, &s) < 0)
        throw new OSException("fstat");
    return S_ISFIFO(s.st_mode);
}
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
        
        hIn = GetStdHandle(STD_INPUT_HANDLE);
        if (hIn == INVALID_HANDLE_VALUE)
            throw new OSException("GetStdHandle");
        
        if (GetFileType(hIn) == FILE_TYPE_PIPE)
        {
            hIn = CreateFileA("CONIN$",
                GENERIC_READ|GENERIC_WRITE,
                0,
                null,
                OPEN_EXISTING,
                0,
                null);
            if (hIn == INVALID_HANDLE_VALUE)
                throw new OSException("CreateFileA");
            //stdin.windowsHandleOpen(hIn, "rb");
        }
        
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
            
            vintr = new_ios.c_cc[VINTR];
            vquit = new_ios.c_cc[VQUIT];
        }
        
        // Use alternative screen buffer
        if (features & TermFeat.altScreen)
        {
            // change to alternative screen buffer
            terminalWrite("\033[?1049h");
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

// We COULD put resize event as a signal in terminalRead, but either
// mechanics are fine.

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
        
        // Windows Terminal supports ESC[18t, but conhost/OpenConsole and ConsoleZ do not.
        // Only use if GetConsoleScreenBufferInfo disappears
    }
    else version (Posix)
    {
        // So far, the ioctl worked on pretty much everything:
        // - Linux: VTE, Konsole, framebuffer
        // - FreeBSD: framebuffer
        // - NetBSD: framebuffer
        // - OpenBSD: framebuffer
        winsize ws = void;
        if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) < 0)
            throw new OSException("ioctl(STDOUT_FILENO, TIOCGWINSZ)");
        size.rows    = ws.ws_row;
        size.columns = ws.ws_col;
        
        // LINES and COLUMNS variables mostly depends on shell. Typically useless
        // SUPPORTED: Bash, ksh(ksh93), zsh, fish
        // UNSUPPORTED: sh, csh, dash, cmd, PowerShell
        
        // ESC [ 8 ; ROWS ; COLUMNS t
        // Does not work with FreeBSD (teken) (useless)
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
        char[32] b = void;
        int r = snprintf(b.ptr, b.length, "\033[%d;%dH", ++y, ++x);
        assert(r > 0);
        terminalWrite(b.ptr, r);
    }
}
alias terminalCursor = terminalMove;

deprecated
struct TerminalPosition
{
    int column, row;
}
deprecated("Don't use terminalTell") // Thanks, FreeBSD
TerminalPosition terminalTell()      // Keep this around, though
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
        // NOTE: FreeBSD and DSR
        //
        //       FreeBSD's terminal emulator library, teken, does not implement
        //       the tf_respond callback function, which would implement DSR
        //       (Device Status Report), and most importantly, the CPR
        //       (Report Cursor Position) escape codes. It is left
        //       unimplemented for a security-related reason.
        //
        //       This includes both the ANSI ("\033[6n") and the DEC
        //       ("\033[?6n") variants.
        //
        //       Looks like vt (freebsd-src/main/sys/dev/vt/) doesn't even have
        //       any function to grab or report the position of the cursor.
        //
        //       Source: freebsd-src/sys/teken/libteken/teken.3
        
        // Standard Device Status Report codes, even xterm.js supports it
        enum DSR = "\033[6n";
        
        terminalWrite(DSR);
        terminalFlush(); // Important for framebuffers notably
        
        enum BSIZE = 32;
        char[BSIZE] buf = void;
        
        ssize_t i = read(STDIN_FILENO, buf.ptr, buf.sizeof);
        if (i < 0)
            throw new OSException("read");
        buf[i] = 0;
        
        // Parse
        if (i < 5 || buf[0] != '\033' || buf[1] != '[')
            throw new Exception("Not an escape code");
        int r = sscanf(buf.ptr + 2, "%d;%d", &pos.row, &pos.column);
        if (r < 2)
            throw new Exception("Missing item");
        
        // 1-based, but to me, they must be 0-based
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
        static immutable ushort[16] BGCOLORS = [ // background colors
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
        
        cast(void)SetConsoleTextAttribute(hOut, (current & 0xf) | BGCOLORS[col]);
    }
    else version (Posix)
    {
        static immutable string[16] BGCOLORS = [ // background colors
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
        
        terminalWrite(BGCOLORS[col]);
    } // version (Posix)
}

/// Invert color.
void terminalInvertColor()
{
    version (Windows)
    {
        // NOTE: COMMON_LVB_REVERSE_VIDEO
        //       While it works for conhost on Windows 10 and later, this flag is a CJK-only
        //       feature before 10.
        //       The weird bonus is a slight render speed bonus of ~0.5 ms.
        //       (maybe the flag peeks and pokes attributes itself...)
        SetConsoleTextAttribute(hOut, cast(ubyte)(oldAttr << 4 | oldAttr >> 4));
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
int terminalPeek()
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
alias terminalHasInput = terminalPeek; // alias

version (Posix)
{
/// Expected length of a UTF-8 sequence from its lead byte, or 0 if the
/// byte is a continuation byte or otherwise not a valid lead.
private
size_t _utf8len(char c)
{
    if (c < 0x80)           return 1; // ASCII
    if ((c & 0xE0) == 0xC0) return 2;
    if ((c & 0xF0) == 0xE0) return 3;
    if ((c & 0xF8) == 0xF0) return 4;
    return 0; // 0x80..0xBF continuation, or 0xF8..0xFF invalid
}

/// Determine the byte length of the first complete terminal input
/// sequence in buf. Returns 1 for non-ESC bytes, and the full
/// CSI/SS3/Alt sequence length for escape sequences.
private
size_t _seqlen(const(char)[] buf)
{
    if (buf.length == 0)
        return 0;
    
    // NOTE: NetBSD (wsvt25) and OpenBSD (vt220) Alt+key
    //       Their terminal driver (at least framebuffer) encodes Alt+I by setting
    //       the 8th bit (e.g., 'i' | 0x80 = 0xe9). This is old behaviour *and*
    //       coincidentally a UTF-8 leading byte, tripping any UTF decoding functions.
    //
    //       Making a specific NetBSD/OpenBSD hack would be irresponsible, it would be
    //       bad future-proofing. On top of the fact that this changes if a different
    //       emulator is used (ESC-prefix meta over high bit).
    //
    //       Detecting this from the environment would be messy and maybe error-prone.
    if (buf[0] != 0x1b) // not ESCAPE
    {
        // High-bit bytes that don't form a complete, valid UTF-8 sequence
        // must be consumed as a single raw byte. Some terminals (e.g. the
        // NetBSD console) encode Alt+key by setting the 8th bit: Alt+I emits
        // 'i' | 0x80 = 0xE9, which happens to look like a 3-byte UTF-8 lead.
        // Handing an incomplete sequence to graphemeStride makes it decode
        // past the end of the buffer and throw.
        size_t need = _utf8len(buf[0]);
        if (need == 0 || need > buf.length)
            return 1; // invalid lead byte or truncated sequence
        for (size_t i = 1; i < need; ++i)
            if ((buf[i] & 0xC0) != 0x80)
                return 1; // bad continuation byte

        // Valid UTF-8 start: use graphemeStride to handle base char +
        // combining marks as one unit (e.g. 'e' + U+0300 -> 'è').
        import std.uni : graphemeStride;
        return graphemeStride(buf, 0);
    }

    if (buf.length == 1)
        return 1; // standalone ESC (nothing followed in this read)

    if (buf[1] == '[') // CSI: ESC [ ...
    {
        // Final byte of a CSI sequence is in 0x40..0x7E
        for (size_t i = 2; i < buf.length; i++)
        {
            if (buf[i] >= 0x40 && buf[i] <= 0x7E)
                return i + 1;
        }
        // No final byte found (truncated?), consume what we have
        return buf.length;
    }
    else if (buf[1] == 'O') // SS3: ESC O X
    {
        return buf.length >= 3 ? 3 : buf.length;
    }
    else
        return 2; // Alt+key: ESC <char>
}
unittest
{
    // Regular bytes
    assert(_seqlen("a") == 1);
    assert(_seqlen("ab") == 1);

    // Standalone ESC
    assert(_seqlen("\x1b") == 1);

    // CSI sequences
    assert(_seqlen("\x1b[A") == 3);         // arrow up
    assert(_seqlen("\x1b[A\x1b[A") == 3);   // two arrows, first is 3
    assert(_seqlen("\x1b[1;2A") == 6);       // shift+up
    assert(_seqlen("\x1b[5~") == 4);         // page up
    assert(_seqlen("\x1b[15~") == 5);        // F5

    // SS3
    assert(_seqlen("\x1bOP") == 3);     // F1 (app mode)

    // Alt+key
    assert(_seqlen("\x1bg") == 2);      // Alt+g

    // UTF-8 multi-byte sequences (precomposed)
    assert(_seqlen("\xC3\xA9") == 2);       // é (U+00E9, 2-byte)
    assert(_seqlen("\xC3\xA8") == 2);       // è (U+00E8, 2-byte)
    assert(_seqlen("\xE2\x82\xAC") == 3);   // € (U+20AC, 3-byte)
    assert(_seqlen("\xF0\x9F\xA5\xB4") == 4); // 🥴 (U+1F974, 4-byte)
    // UTF-8 followed by more data, only first sequence
    assert(_seqlen("\xC3\xA9abc") == 2);
    // Decomposed: 'e' + U+0300 combining grave = 3 bytes as one grapheme
    assert(_seqlen("e\xCC\x80") == 3);      // è (decomposed)
    assert(_seqlen("e\xCC\x80abc") == 3);   // è + trailing data

    // High-bit raw bytes (e.g. NetBSD Alt+key sets the 8th bit): not valid
    // UTF-8 on their own, must be consumed one byte at a time, never decoded.
    assert(_seqlen("\xE9") == 1);           // Alt+I -> 'i'|0x80, lone 3-byte lead
    assert(_seqlen("\xE9\xE9") == 1);       // two of them
    assert(_seqlen("\x80") == 1);           // lone continuation byte
    assert(_seqlen("\xFF") == 1);           // invalid lead byte
    assert(_seqlen("\xC3") == 1);           // truncated 2-byte sequence
    assert(_seqlen("\xC3z") == 1);          // bad continuation byte
}
} // version (Posix)

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
        if (ReadConsoleInputW(hIn, &ir, 1, &num) == FALSE)
            throw new OSException("ReadConsoleInputW");
        if (num == 0)
            goto Lread;
        
        switch (ir.EventType) {
        case KEY_EVENT:
            if (ir.KeyEvent.bKeyDown == FALSE)
                goto Lread;
            
            version (unittest)
            {
                import std.stdio : writefln;
                writefln(
                "KeyEvent: AsciiChar=%d UnicodeChar=%d wVirtualKeyCode=%d dwControlKeyState=0x%x",
                ir.KeyEvent.AsciiChar,
                ir.KeyEvent.UnicodeChar,
                ir.KeyEvent.wVirtualKeyCode,
                ir.KeyEvent.dwControlKeyState
                );
            }
            
            // Special pseudo signal generation.
            // Ctrl+Break is always treated as a signal and we're not capturing,
            // let it kill us.
            switch (ir.KeyEvent.AsciiChar) {
            case VINTR:
                event.type = InputType.signal;
                event.signal = TerminalSignal.interrupted;
                return event;
            default:
            }
            
            const ushort keycode = ir.KeyEvent.wVirtualKeyCode;
            
            // Filter out single modifier key events
            switch (keycode) { // VK_MENU is alt here for menubar accelerator key
            case VK_SHIFT, VK_CONTROL, VK_MENU: goto Lread;
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
            
            // Unicode (UTF-16LE) to UTF-8 to match POSIX behaviour
            event.ksize = WideCharToMultiByte(
                CP_UTF8,            // CodePage
                0,                  // dwFlags
                &ir.KeyEvent.UnicodeChar,       // lpWideCharStr
                1,                  // cchWideChar
                event.kbuffer.ptr,  // lpMultiByteStr
                cast(int)event.kbuffer.sizeof,  // cbMultiByte
                null,               // lpDefaultChar
                null);              // lpUsedDefaultChar
            if (event.ksize == 0)
                throw new OSException("WideCharToMultiByte");
            // Unable to get ¶ (182) and § (167) (RAlt+O/P), that's fine for now
            
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
                // NOTE: UnicodeChar (not AsciiChar) is used so accented and
                //       other non-ASCII keys (e.g. AltGr-composed characters
                //       on European layouts) decode to their real codepoint,
                //       matching POSIX and terminalKeybind's UTF-8 decoding
                //       instead of being mangled through the ANSI codepage.
                const wchar wc = ir.KeyEvent.UnicodeChar;
                if (keycode >= VK_NUMPAD0 && keycode <= VK_NUMPAD9)
                {
                    event.key = (keycode - VK_NUMPAD0) + '0';
                }
                else if (keycode >= VK_F1 && keycode <= VK_F24)
                {
                    event.key = (keycode - VK_F1) + Key.F1;
                }
                else if (wc >= 'a' && wc <= 'z')
                {
                    event.key |= wc - 32;
                }
                else if (wc >= 32 && wc < 127)
                {
                    event.key |= wc;
                    // HACK: Remove unnatural modifiers (ie, for '@')
                    //       readline depends on this
                    event.key &= ~(Mod.ctrl|Mod.alt);
                }
                else if (wc >= 0x80 && (wc < 0xD800 || wc > 0xDFFF)) // BMP, non-surrogate
                {
                    event.key |= wc;
                    // Same AltGr HACK as above, e.g. AltGr+key on European layouts
                    event.key &= ~(Mod.ctrl|Mod.alt);
                }
                else
                    event.key |= keycode;
            }
            return event;
        case MOUSE_EVENT:
            version (unittest)
            {
                import std.stdio : writefln;
                writefln(
                "MouseEvent: X=%d Y=%d dwButtonState=%x dwControlKeyState=%x dwEventFlags=%x",
                ir.MouseEvent.dwMousePosition.X, ir.MouseEvent.dwMousePosition.Y,
                ir.MouseEvent.dwButtonState,
                ir.MouseEvent.dwControlKeyState,
                ir.MouseEvent.dwEventFlags
                );
            }
            
            if (ir.MouseEvent.dwEventFlags & MOUSE_WHEELED)
            {
                // Up=0xFF880000 Down=0x00780000
                // Because ddhx doesn't yet understand mouseUp/Down, translate
                // to keyUp/Down
                /*with (InputType)
                    event.type = ir.MouseEvent.dwButtonState > 0x00780000 ? mouseUp : mouseDown;*/
                event.type = InputType.keyDown;
                event.key  = ir.MouseEvent.dwButtonState > 0x00780000 ? Key.UpArrow : Key.DownArrow;
                return event;
            }
            
            break;
        // NOTE: The console buffer is different than window resize
        //       It is misleading. Only updated after a new event enters input queue.
        case WINDOW_BUFFER_SIZE_EVENT:
            if (terminalOnResizeEvent)
                terminalOnResizeEvent();
            goto Lread;
        default:
        }
        goto Lread;
    }
    else version (Posix)
    {
        // Readahead buffer for splitting concatenated escape sequences
        // (e.g. scroll wheel: \033[B\033[B\033[B arrives as one read)
        __gshared char[64] _pending;
        __gshared size_t _pending_len;
        
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
        // Fill pending buffer from stdin if empty
        if (_pending_len == 0)
        {
            ssize_t n = read(STDIN_FILENO, _pending.ptr, _pending.sizeof);
            // NOTE: EINTR (errno=4)
            //       Emitted when resizing or on ^C.
            if (n <= 0)
                goto Lread;
            _pending_len = n;
        }

        // Extract exactly one sequence from the pending buffer
        size_t r = _seqlen(_pending[0.._pending_len]);
        
        // Copy data into local buffer, then consume
        event.kbuffer[0..r] = _pending[0..r];
        event.ksize = cast(int)r;
        event.type  = InputType.keyDown; // Assuming for now
        event.key   = 0; // clear as safety measure
        _pending_len -= r;
        if (_pending_len > 0)
            memmove(_pending.ptr, &_pending[r], _pending_len);
        event.pending = _pending_len > 0;

        version (unittest)
        {
            import std.stdio : write, writef, writeln, writefln;
            write("stdin: ");
            for (size_t i; i < r; ++i)
            {
                if (i) write(", ");
                char c = event.kbuffer[i];
                if (c < 32 || c > 126) // non-printable ascii
                    writef("\\0%o", c);
                else
                    writef("'%c'", event.kbuffer[i]);
            }
            writefln(" (pending=%d)", cast(int)_pending_len);
        }
        
        if (event.kbuffer[0] == vintr)
        {
            event.type = InputType.signal;
            event.signal = TerminalSignal.interrupted;
            return event;
        }
        if (event.kbuffer[0] == vquit)
        {
            event.type = InputType.signal;
            event.signal = TerminalSignal.quit;
            return event;
        }
        
        // TODO: xterm modifyOtherKeys mode 1/2 ("\e[>4;1m" and "\e[>4;2m")
        //       These two codes were introduced in VTE 0.78 (Ubuntu 24.04 is on 0.76)
        //       Would allow to capture some odd keys like Ctrl+d9
        //       Needs "\e[>0c" (query device attributes: DA1), example "61;7600;1"
        //       (61: VT420-level conformance, 7600: VTE 0.76, 1: 132-col support)
        enum ESC = 0x1b;
        enum RETURN = '\r';
        
        // https://espterm.github.io/docs/espterm-xterm.html
        switch (event.kbuffer[0]) {
        case 0: // Ctrl+Space
            event.key = Key.Spacebar | Mod.ctrl;
            return event;
        case RETURN: // ^M
            event.key = Key.Enter;
            return event;
        case 8: // ^H (ctrl+backspace)
            // HACK: FreeBSD (15) framebuffer sends \010 on just Backspace
            //       Worse, it's \0177 with Ctrl+Backspace
            version (FreeBSD)
                event.key = Key.Backspace;
            else
                event.key = Key.Backspace | Mod.ctrl;
            return event;
        case 9: // Hardware tab (no control key)
            // Shift+tab -> "\033[Z" (xterm)
            event.key = Key.Tab;
            return event;
        case 127: // \0177
            // See HACK for case 8.
            // OpenBSD (TERM=vt220) seems to only emit \0177 (127) and it's covered here
            version (FreeBSD)
                event.key = Key.Backspace | Mod.ctrl;
            else
                event.key = Key.Backspace;
            event.key = Key.Backspace;
            return event;
        case ESC: // \x1b, \033
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
            // \033, 'O', ...
            case 'O': // SS3/G3 character set (application mode)
                // WARNING: Shift+Alt+O will lead here
                input = input[1..$];
                break;
            case RETURN:
                event.key = Mod.alt | Key.Enter;
                return event;
            default: // Alt+KEY
                event.key = Mod.alt | (input[0] - 32);
                return event;
            }
            
            struct KeyInfo { string text; int value; } // Map sequence to translated key
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
        // Only when single byte, multi-byte UTF-8 lead bytes overlap this range
        else if (r == 1 && c >= 225 && c <= 250)
            event.key = (c - 160) | Mod.alt;
        else if (r > 1) // valid multi-byte UTF-8 grapheme (e.g. accented key)
        {
            int cp = _keyCodepoint(event.kbuffer[0..r]);
            event.key = cp >= 0 ? cp : c; // fall back to lead byte if undecodable
        }
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
            memmove(&buffer[i + chr.length], &buffer[i], length - i);
        }
        
        // Copy new characters into position
        buffer[i .. i + chr.length] = chr[];
        length += chr.length;
        
        cells += w;
        
        return chr.length;
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
            memmove(&buffer[i], &buffer[i + delsize], length - i - delsize);
        }
        
        length -= delsize;
        
        cells = graphs(buffer[0..length]);
        
        return a - cells;
    }
    
    // private but this module ddhx.can see this function anyway
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

    // Multi-byte: insert returns byte count, not cell count
    LineBuffer buf2;
    assert(buf2.insert(0, cast(char[])"\xC3\xA9") == 2); // é: 2 bytes, 1 cell
    assert(buf2.length == 2);
    assert(buf2.cells  == 1);
    assert(buf2.insert(2, cast(char[])"\xC3\xA8") == 2); // è: 2 bytes, 1 cell
    assert(buf2.length == 4);
    assert(buf2.cells  == 2);
    assert(buf2[] == "\xC3\xA9\xC3\xA8");                 // éè
}

// Count number of visible printed characters (for a terminal) from a narrow
// mutlibyte string.
private
size_t graphs(inout(char)[] s)
{
    import std.uni : graphemeStride;

    if (s is null || s.length == 0)
        return 0;

    size_t width;
    size_t i;
    while (i < s.length)
    {
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

private
size_t graphwalk(inout(char)[] s, size_t i, int backward = 0)
{
    import std.uni : graphemeStride;

    if (backward)
    {
        if (i == 0 || s.length == 0)
            return 0;
        // Walk forward from start, tracking grapheme boundaries
        size_t prev;
        size_t pos;
        while (pos < i && pos < s.length)
        {
            prev = pos;
            pos += graphemeStride(s, pos);
        }
        return prev;
    }
    else
    {
        if (i >= s.length)
            return s.length;
        return i + graphemeStride(s, i);
    }
}
unittest
{
    // ASCII
    assert(graphwalk("hello", 0) == 1);
    assert(graphwalk("hello", 4) == 5);
    assert(graphwalk("hello", 5) == 5); // at end
    assert(graphwalk("hello", 5, true) == 4);
    assert(graphwalk("hello", 1, true) == 0);
    assert(graphwalk("hello", 0, true) == 0); // at start

    // Multi-byte: ä is 2 bytes (U+00E4)
    assert(graphwalk("ä", 0) == 2);
    assert(graphwalk("ä", 2, true) == 0);

    // Mixed: "aä" is 3 bytes
    assert(graphwalk("aä", 0) == 1);  // past 'a'
    assert(graphwalk("aä", 1) == 3);  // past 'ä'
    assert(graphwalk("aä", 3, true) == 1);     // back to 'ä'
    assert(graphwalk("aä", 1, true) == 0);     // back to 'a'

    // Emoji: 🥴 is 4 bytes (U+1F974)
    assert(graphwalk("🥴", 0) == 4);
    assert(graphwalk("🥴", 4, true) == 0);

    // Null/empty
    assert(graphwalk("", 0) == 0);
    assert(graphwalk("", 0, true) == 0);
    assert(graphwalk(null, 0) == 0);
    assert(graphwalk(null, 0, true) == 0);
}

// Returns true if narrow byte character is space
// Somehow, the C function was crashing this, so here's a simple extendable replacement
private
bool isuspace(char ch)
{
    // Only considering fewer characters because terminal handles some special
    // keys that we don't need to handle here
    switch (ch) {
    case ' ', '\t':
        return true;
    default:
        // Will need locale-specific white-space character
        return false;
    }
}
unittest
{
    assert(isuspace(' '));
    assert(isuspace('\t'));
    assert(isuspace('e') == false);
}

/// In-memory command history for readline.
private
struct ReadlineHistory
{
    enum MAXSIZE = 64;

    /// Stored history entries (oldest first).
    string[MAXSIZE] entries;
    /// Number of entries currently stored.
    size_t count;
    /// Write position (ring index).
    size_t pos;

    /// Add a line to history.
    void push(string line)
    {
        if (line.length == 0)
            return;
        // Don't add duplicates of the most recent entry
        if (count > 0 && entries[(pos + MAXSIZE - 1) % MAXSIZE] == line)
            return;
        entries[pos] = line;
        pos = (pos + 1) % MAXSIZE;
        if (count < MAXSIZE)
            ++count;
    }

    /// Get entry by index (0 = most recent, count-1 = oldest).
    string get(size_t idx) const
    {
        if (idx >= count)
            return null;
        return entries[(pos + MAXSIZE - 1 - idx) % MAXSIZE];
    }
}
unittest
{
    ReadlineHistory h;
    assert(h.count == 0);

    // Empty strings are not added
    h.push("");
    assert(h.count == 0);

    // Basic push and get
    h.push("first");
    assert(h.count == 1);
    assert(h.get(0) == "first");

    h.push("second");
    assert(h.count == 2);
    assert(h.get(0) == "second"); // most recent
    assert(h.get(1) == "first");

    // Duplicate of most recent is skipped
    h.push("second");
    assert(h.count == 2);

    // Out of bounds returns null
    assert(h.get(100) is null);

    // Ring buffer wraps
    foreach (i; 0 .. ReadlineHistory.MAXSIZE)
        h.push(cast(string)['a' + (i % 26)]);
    assert(h.count == ReadlineHistory.MAXSIZE);
}

/// Readline history
private __gshared ReadlineHistory rl_history;

private
struct ReadlineState
{
    // conhost (pre-Windows Terminal) does not handle '\r' to clear line
    /// Original column position.
    int orig_col;
    /// Original row position.
    int orig_row;
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
    
    // Could also be an imposed max size (like for a text field)
    TerminalSize tsize = terminalSize();
    
    terminalMove(state.orig_col, state.orig_row);
    
    int width = tsize.columns;
    int avail = width - state.orig_col;
    
    // Cell width of text before caret (for screen positioning)
    size_t caret_cells = graphs(buffer[0 .. min(state.caret, buffer.length)]);
    
    // Adjust view (in cell units)
    if (caret_cells < state.base)
        state.base = caret_cells;
    else if (caret_cells >= avail)
        state.base = caret_cells - avail;
    
    // Write buffer: find byte range for visible cells
    // Skip `state.base` cells to find the start byte
    size_t start_byte;
    size_t skipped_cells;
    while (start_byte < buffer.length && skipped_cells < state.base)
    {
        size_t stride = graphwalk(buffer, start_byte) - start_byte;
        skipped_cells += graphs(buffer[start_byte .. start_byte + stride]);
        start_byte += stride;
    }
    
    int w = cast(int)terminalWrite(buffer[start_byte .. buffer.length]);
    if (w < avail) // fill
        terminalWriteChar(' ', avail - w);
    
    // Position caret on screen (cell-based)
    int x = state.orig_col + cast(int)(caret_cells - state.base);
    if (x >= width) // outside buffer
        x = width - 1;
    terminalMove(x, state.orig_row);
    
    terminalFlush(); // fbcons on Linux/BSDs need this
}

// Flags to better define behavior versus relying on current_features.
enum {
    /// Uses legacy readln method.
    RL_OLDREADLN = 1,
    /// Use history feature. Enables saving lines and using up/down arrows.
    RL_HISTORY = 2,
}
private enum {
    _RL_BUFCHANGED = 1 << 16, /// Buffer content changed
}
/// Read a line.
/// Params:
///     column = Original column position.
///     row    = Original row position.
///     flags  = Read flags.
///     completions = Optional list of completion candidates for Tab.
/// Returns: String without newline.
string readline(int column, int row, int flags = 0, const(string)[] completions = null)
{
    // Cheap line-oriented if we're not using alternate screen buffer,
    // because there isn't any rendering worries. Legacy bit.
    // To be removed later.
    if (flags & RL_OLDREADLN)
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
    
    // Prep work
    ReadlineState rl_state;
    rl_state.orig_col = column;
    rl_state.orig_row = row;

    // HACK: Cheap way to clear line + setup cursor
    //       Removes responsability from caller
    terminalWriteChar(' ', terminalSize().columns-column-1);
    terminalMove(column, row);
    terminalFlush(); // Needed on fbcons

    LineBuffer line;    /// Line buffer
    int rl_flags = void;

    // History browsing state
    size_t hist_idx;        // 0 = current input, 1..N = history entries
    string hist_saved;      // saved current input when browsing history
    // Tab completion state
    size_t tab_match_idx;   // current match index (cycles)
    char[] tab_prefix;      // prefix that was matched
    bool tab_active;        // currently cycling through matches
Lread: // Emulate line buffer
    rl_flags = flags;
    
    TermInput input = terminalRead();
    
    // No need to shout (throw exception), it's not some exceptional error
    if (input.type == InputType.signal && input.signal == TerminalSignal.interrupted)
        return null;
    
    // Not interested in mouse or key ups
    if (input.type != InputType.keyDown)
        goto Lread;

    // Reset tab completion state on any non-Tab key
    if (input.key != Key.Tab)
        tab_active = false;

    switch (input.key) {
    case Key.Enter:  goto Lout;
    case Key.Escape: return null; // caller is already aware of length==0 cases
    case Key.LeftArrow:
        if (rl_state.caret == 0)
            goto Lread;
        rl_state.caret = graphwalk(line[], rl_state.caret, true);
        break;
    case Key.RightArrow:
        if (rl_state.caret >= line.length)
            goto Lread;
        rl_state.caret = graphwalk(line[], rl_state.caret);
        break;
    case Mod.ctrl | Key.LeftArrow:
        if (rl_state.caret == 0)
            goto Lread;
        size_t i = rl_state.caret;
        while (i > 0)
        {
            i = graphwalk(line[], i, true);
            if (isuspace(line.buffer[i]))
                break;
        }
        rl_state.caret = i;
        break;
    case Mod.ctrl | Key.RightArrow:
        if (rl_state.caret >= line.length)
            goto Lread;
        size_t i = rl_state.caret;
        while (i < line.length)
        {
            i = graphwalk(line[], i);
            if (i < line.length && isuspace(line.buffer[i]))
                break;
        }
        rl_state.caret = i;
        break;
    case Key.UpArrow:
        if ((flags & RL_HISTORY) == 0)
            goto Lread;
        if (hist_idx >= rl_history.count)
            goto Lread; // no more history
        // Save current input when first entering history
        if (hist_idx == 0)
            hist_saved = line.toString();
        ++hist_idx;
        // Replace line buffer with history entry
        line.length = 0;
        line.cells = 0;
        auto hentry = rl_history.get(hist_idx - 1);
        line.insert(0, cast(char[])hentry);
        rl_state.caret = line.length;
        rl_state.base = 0;
        rl_flags |= _RL_BUFCHANGED;
        break;
    case Key.DownArrow:
        if ((flags & RL_HISTORY) == 0)
            goto Lread;
        if (hist_idx == 0)
            goto Lread; // already at current input
        --hist_idx;
        line.length = 0;
        line.cells = 0;
        if (hist_idx == 0)
        {
            // Restore saved current input
            if (hist_saved !is null && hist_saved.length > 0)
                line.insert(0, cast(char[])hist_saved);
        }
        else
        {
            auto hentry = rl_history.get(hist_idx - 1);
            line.insert(0, cast(char[])hentry);
        }
        rl_state.caret = line.length;
        rl_state.base = 0;
        rl_flags |= _RL_BUFCHANGED;
        break;
    case Key.Home:
        rl_state.caret = 0;
        break;
    case Key.End:
        rl_state.caret = line.length;
        break;
    case Key.Delete: // front delete character
        if (rl_state.caret >= line.length) // nothing to delete
            goto Lread;
        size_t next = graphwalk(line[], rl_state.caret);
        line.deleteAt(rl_state.caret, next - rl_state.caret);
        rl_flags |= _RL_BUFCHANGED;
        break;
    case Mod.ctrl | Key.Delete: // front delete word
        if (rl_state.caret >= line.length) // nothing to delete
            goto Lread;
        size_t i = rl_state.caret;
        while (i < line.length)
        {
            i = graphwalk(line[], i);
            if (i < line.length && isuspace(line.buffer[i]))
                break;
        }
        line.deleteAt(rl_state.caret, i - rl_state.caret);
        rl_flags |= _RL_BUFCHANGED;
        break;
    case Key.Backspace: // back delete character
        if (rl_state.caret == 0) // nothing to delete
            goto Lread;
        size_t prev = graphwalk(line[], rl_state.caret, true);
        line.deleteAt(prev, rl_state.caret - prev);
        rl_state.caret = prev;
        rl_flags |= _RL_BUFCHANGED;
        break;
    case Mod.ctrl | Key.Backspace: // back delete word
        if (rl_state.caret == 0) // nothing to delete
            goto Lread;
        size_t i = rl_state.caret;
        while (i > 0)
        {
            i = graphwalk(line[], i, true);
            if (isuspace(line.buffer[i]))
                break;
        }
        line.deleteAt(i, rl_state.caret - i);
        rl_state.caret = i;
        rl_flags |= _RL_BUFCHANGED;
        break;
    case Key.Tab:
        if (completions is null || completions.length == 0)
            goto Lread;

        if (!tab_active)
        {
            // Start new completion: use current line content as prefix
            tab_prefix = line[].dup;
            tab_match_idx = 0;
            tab_active = true;
        }
        else
        {
            // Cycle to next match
            ++tab_match_idx;
        }
        
        void apply_match(string c)
        {
            line.length = 0;
            line.cells = 0;
            line.insert(0, cast(char[])c);
            rl_state.caret = line.length;
            rl_state.base = 0;
            rl_flags |= _RL_BUFCHANGED;
        }
        
        import std.algorithm : startsWith;
        
        // Find matches
        size_t matches_found;
        foreach (c; completions)
        {
            if (tab_prefix.length == 0 || c.startsWith(tab_prefix))
            {
                if (matches_found == tab_match_idx)
                {
                    apply_match(c);
                }
                ++matches_found;
            }
        }

        if (matches_found == 0)
            goto Lread; // no matches

        // Wrap around if past the end
        if (tab_match_idx >= matches_found)
        {
            tab_match_idx = 0;
            foreach (c; completions)
            {
                if (tab_prefix.length == 0 || c.startsWith(tab_prefix))
                {
                    apply_match(c);
                    break;
                }
            }
        }
        break;
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
        
        // Multi-byte UTF-8 is always insertable; for ASCII, check isprint
        import core.stdc.ctype : isprint;
        if (input.ksize == 1 && !isprint(input.kbuffer[0]))
            goto Lread;
        
        rl_state.caret +=
            line.insert(rl_state.caret, input.kbuffer[0..input.ksize]);
        rl_flags |= _RL_BUFCHANGED;
    }
    readlineRender(rl_state, line[], line.cells, rl_flags);
    goto Lread;
    
Lout:
    string result = line.toString();
    if (flags & RL_HISTORY)
        rl_history.push(result);
    return result;
}

/// Terminal input type.
enum InputType
{
    keyDown,
    keyUp,
    mouseDown,
    mouseUp,
    signal,
}

/// Key modifier
enum Mod // More readable than templates: CTRL!(ALT!(SHIFT!('a')))
{
    ctrl  = 1 << 24,
    shift = 1 << 25,
    alt   = 1 << 26,
}

private
enum SPECIALKEY = 0x01_0000;

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
    Enter = 13, // Acts the same as Return for consistency
    Escape = 27,
    
    // ASCII (32..127)
    Spacebar = 32,
    Exclamation = 33,
    DoubleQuote = 34,
    Hash = 35,
    Dollar = 36,
    Percent = 37,
    Ampersand = 38,
    Apostrophe = 39,
    LeftParen = 40,
    RightParen = 41,
    Asterisk = 42,
    Plus = 43,
    Comma = 44,
    Minus = 45,
    Period = 46,
    Slash = 47,
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
    LessThan = 60,
    Equals = 61,
    GreaterThan = 62,
    Question = 63,
    At = 64,
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
    LeftBracket = 91,
    Backslash = 92,
    RightBracket = 93,
    Caret = 94,
    Underscore = 95,
    Backtick = 96,

    // Special keys
    PageUp      = SPECIALKEY,
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

enum TerminalSignal
{
    /// Emulates SIGINT (typically ^C)
    interrupted,
    /// Emulates SIGQUIT (typically ^\)
    quit,
}

/// Terminal input structure
struct TermInput
{
    union {
    struct
    {
        int key;            /// Keyboard input with possible Mod flags.
        int ksize;          /// Size of the filled input buffer
        // On POSIX, concatenated escape sequences (e.g. scroll wheel)
        // are split by a readahead buffer (_pending); each event
        // here holds exactly one sequence.
        char[8] kbuffer;    /// Input buffer for the character
    }
    struct
    {
        ushort mouseX; /// Mouse column coord
        ushort mouseY; /// Mouse row coord
    }
    TerminalSignal signal; /// Emulated signal value using TerminalSignal
    } // union
    InputType type;    /// Terminal input event type
    bool pending; /// More events queued in readahead buffer (POSIX)
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

/// Decode a single Unicode codepoint from a UTF-8 buffer for use as a key
/// value (bits 15..0 of the translated keycode).
/// Returns: The decoded codepoint, or -1 if the buffer is malformed UTF-8,
/// or the codepoint is astral (>0xFFFF, e.g. emoji) and would collide with
/// the special-key/modifier bits.
private
int _keyCodepoint(const(char)[] buf)
{
    import std.utf : decode, UTFException;
    size_t idx;
    try
    {
        dchar dc = decode(buf, idx);
        return dc < SPECIALKEY ? cast(int)dc : -1;
    }
    catch (UTFException)
        return -1;
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
    
    switch (value) {
    case "insert":      return mod | Key.Insert;
    case "home":        return mod | Key.Home;
    case "end":         return mod | Key.End;
    case "page-up":     return mod | Key.PageUp;
    case "page-down":   return mod | Key.PageDown;
    case "delete":      return mod | Key.Delete;
    case "left-arrow":  return mod | Key.LeftArrow;
    case "right-arrow": return mod | Key.RightArrow;
    case "up-arrow":    return mod | Key.UpArrow;
    case "down-arrow":  return mod | Key.DownArrow;
    case "tab":         return mod | Key.Tab;
    case "backspace":   return mod | Key.Backspace;
    case "enter":       return mod | Key.Enter;
    case "spacebar":    return mod | Key.Spacebar;
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
        int c = value[0]; // had zero check earlier, this is fine
        if (c >= 'a' && c <= 'z') // lower ascii, force to upper to map to Key enum
            return mod | (c - 32);
        else if (c >= 32 && c < 127) // printable
            return mod | c;
        else // possible UTF-8 lead byte (accented/non-ASCII key)
        {
            int cp = _keyCodepoint(value);
            if (cp >= 0)
                return mod | cp;
        }
    }
    
    throw new Exception("Unknown key");
}
unittest
{
    assert(terminalKeybind("a")             == Key.A);
    assert(terminalKeybind("alt+a")         == Mod.alt+Key.A);
    assert(terminalKeybind("ctrl+a")        == Mod.ctrl+Key.A);
    assert(terminalKeybind("ctrl+shift+a")  == Mod.ctrl+Mod.shift+Key.A);
    assert(terminalKeybind("shift+ctrl+a")  == Mod.ctrl+Mod.shift+Key.A);
    assert(terminalKeybind("shift+a")       == Mod.shift+Key.A);
    assert(terminalKeybind("ctrl+0")        == Mod.ctrl+Key.D0);
    assert(terminalKeybind("ctrl+insert")   == Mod.ctrl+Key.Insert);
    assert(terminalKeybind("ctrl+home")     == Mod.ctrl+Key.Home);
    assert(terminalKeybind("page-up")       == Key.PageUp);
    assert(terminalKeybind("shift+page-up") == Mod.shift+Key.PageUp);
    assert(terminalKeybind("delete")        == Key.Delete);
    assert(terminalKeybind("f1")            == Key.F1);
    assert(terminalKeybind(":")             == ':');
    assert(terminalKeybind(":")             == Key.Colon);
    assert(terminalKeybind("]")             == ']');
    assert(terminalKeybind("]")             == Key.RightBracket);

    // Non-ASCII (accented) keys decode to their full codepoint, not just
    // the UTF-8 lead byte
    assert(terminalKeybind("é")         == 0xE9);
    assert(terminalKeybind("ctrl+é")    == (Mod.ctrl | 0xE9));
    assert(terminalKeybind("ñ")         == 0xF1);
    assert(terminalKeybind("ë")         == 0xEB);
    assert(terminalKeybind("€")         == 0x20AC);

    // Astral-plane codepoints (e.g. emoji) don't fit the character bits
    try
    {
        cast(void)terminalKeybind("😀");
        assert(false);
    }
    catch (Exception) {}
}
