/// Terminal/console handling.
///
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
private import core.stdc.stdlib : system, atexit;
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
    import std.windows.syserror : WindowsException;
    private enum CP_UTF8 = 65_001;
    // CONSOLE_MODE_INPUT: Used for raw input (so setup and resuming)
    // ENABLE_PROCESSED_INPUT:
    //   If set, allows the weird shift+arrow shit.
    //   If unset, captures Ctrl+C as a keystroke.
    private enum CONSOLE_MODE_INPUT = ENABLE_WINDOW_INPUT | ENABLE_MOUSE_INPUT;
    private __gshared HANDLE hIn, hOut;
    private __gshared DWORD oldCP; // Old CodePage
    private __gshared WORD oldAttr; // Old console attributes
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

private import os.error : OSException;

/// Flags for terminalInit.
enum TermFeat {
    /// Initiate only the basic.
    none        = 0,
    /// Initiate the input system.
    inputSys    = 1,
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
            
            // We need processed ouput to have basic shit like backspace
            // for readln.
            DWORD attr = void;
            if (GetConsoleMode(hOut, &attr) == FALSE)
                throw new OSException("GetConsoleMode");
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
        
        // NOTE: While Windows supports UTF-16LE (1200) and UTF-32LE,
        //       it's only for "managed applications" (.NET).
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
            // Should it re-open tty by default?
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
            // remove ISTRIP (strips the 8th bit)
            new_ios.c_iflag &= ~(IXON | ICRNL | BRKINT | INPCK | ISTRIP);
            // output modes
            // remove OPOST (turns on output post-processing)
            //new_ios.c_oflag &= ~(OPOST);
            // local modes
            // remove ICANON (turns on canonical mode (per-line instead of per-byte))
            // remove ECHO (turns on character echo)
            // remove ISIG (enables ^C and ^Z signals)
            // remove IEXTEN (enables ^V)
            new_ios.c_lflag &= ~(ICANON | ECHO | IEXTEN);
            // control modes
            // add CS8 sets Character Size to 8-bit
            new_ios.c_cflag |= CS8;
            // minimum amount of bytes to read,
            // 0 being return as soon as there is data
            //new_ios.c_cc[VMIN] = 0;
            // maximum amount of time to wait for input,
            // 1 being 1/10 of a second (100 milliseconds)
            //new_ios.c_cc[VTIME] = 0;
            //if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &new_ios) < 0)
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

private __gshared void function() terminalOnResizeEvent;

/// Set handler for resize events.
///
/// On Windows, (at least for conhost) this is only called when the buffer is
/// resized, not the window.
/// Params: func = Function to call.
void terminalOnResize(void function() func)
{
    version (Posix)
    {
        sigaction_t sa = void;
        sigemptyset(&sa.sa_mask);
        sa.sa_flags = SA_SIGINFO;
        sa.sa_sigaction = &terminalResized;
        assert(sigaction(SIGWINCH, &sa, NULL_SIGACTION) != -1);
    }
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

/// Pause terminal input. (On POSIX, this restores the old IOS)
private
void terminalPauseInput()
{
    version (Windows)
        SetConsoleMode(hIn, oldMode); // nothrow, called fine in setup
    version (Posix)
        cast(void)tcsetattr(STDIN_FILENO, TCSAFLUSH, &old_ios);
}
/// Resume terminal input. (On POSIX, this restores the old IOS)
private
void terminalResumeInput()
{
    version (Windows)
        SetConsoleMode(hIn, CONSOLE_MODE_INPUT);
    version (Posix)
        cast(void)tcsetattr(STDIN_FILENO, TCSAFLUSH, &new_ios);
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
void terminalCursor(int x, int y)
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
                "KeyEvent: AsciiChar=%d wVirtualKeyCode=%d dwControlKeyState=0x%x\n",
                ir.KeyEvent.AsciiChar,
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
            
            const char ascii = ir.KeyEvent.AsciiChar;
            if (ascii >= 'a' && ascii <= 'z')
            {
                event.key |= ascii - 32;
                return event;
            }
            else if (ascii >= 0x20 && ascii < 0x7f)
            {
                event.key |= ascii;
                return event;
            }
            
            event.key |= keycode;
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
        //       - 0,0 click: ESC [ M   ! !
        //         ! is 0x21, so '!' - 0x21 = 0
        //       - end,end click: ESC [ M   q ;
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
        
        enum BLEN = 8;
        char[BLEN] b = void;
    Lread:
        ssize_t r = read(STDIN_FILENO, b.ptr, BLEN);
        if (r < 0) // happens on term resize, for example (errno=4,EINTR)
        {
            version (unittest) printf("errno: %d\n", errno);
            goto Lread;
        }
        
        version (unittest)
        {
            printf("stdin: ");
            for (size_t i; i < r; ++i)
            {
                if (i) printf(", ");
                char c = b[i];
                if (c < 32 || c > 126) // non-printable ascii
                    printf("\\0%o", c);
                else
                    printf("'%c'", b[i]);
            }
            cast(void)putchar('\n');
        }
        
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
        switch (b[0]) {
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
            
            char[] input = b[1..r];
            
            // Next, detect sequence
            switch (input[0]) {
            case '[': // CSI, Control Sequence Introducer
                // Detect special modifier keys if there are any
                if (r >= 5 && b[2] == '1' && b[3] == ';')
                {
                    // 1;2 -> Shift
                    // 1;3 -> Alt
                    // 1;4 -> Shift+Alt
                    // 1;5 -> Ctrl
                    // 1;6 -> Ctrl+Shift
                    // 1;7 -> Alt+Ctrl
                    // 1;8 -> Shift+Alt+Ctrl
                    switch (b[4]) {
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
                { "2~",     Key.Insert },
                { "3~",     Key.Delete },
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
        int c = b[0];
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

/// Read a line.
/// Params: flags = Read flags.
/// Returns: String without newline.
string terminalReadline(int flags = 0)
{
    import std.stdio : readln;
    import std.string : chomp;
    
    if (current_features & TermFeat.inputSys)
    {
        terminalPauseInput();
        terminalShowCursor();
    }
    
    string line = chomp( readln() );
    
    if (current_features & TermFeat.inputSys)
    {
        terminalHideCursor();
        terminalResumeInput();
    }
    
    return line;
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
enum Mod // A little more readable than e.g., CTRL!(ALT!(SHIFT!('a')))
{
    ctrl  = 1 << 24,
    shift = 1 << 25,
    alt   = 1 << 26,
}

/// Key codes map.
enum Key // These are fine for now
{
    Undefined = 0,
    Backspace = 8,
    Tab = 9,
    Clear = 12,
    Enter = 13,
    Pause = 19,
    Escape = 27,
    Spacebar = 32,
    PageUp = 33,
    PageDown = 34,
    End = 35,
    Home = 36,
    LeftArrow = 37,
    UpArrow = 38,
    RightArrow = 39,
    DownArrow = 40,
    Select = 41,
    Print = 42,
    Execute = 43,
    PrintScreen = 44,
    Insert = 45,
    Delete = 46,
    Help = 47,
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
    LeftMeta = 91,
    RightMeta = 92,
    Applications = 93,
    Sleep = 95,
    NumPad0 = 96,
    NumPad1 = 97,
    NumPad2 = 98,
    NumPad3 = 99,
    NumPad4 = 100,
    NumPad5 = 101,
    NumPad6 = 102,
    NumPad7 = 103,
    NumPad8 = 104,
    NumPad9 = 105,
    Multiply = 106,
    Add = 107,
    Separator = 108,
    Subtract = 109,
    Decimal = 110,
    Divide = 111,
    F1 = 112,
    F2 = 113,
    F3 = 114,
    F4 = 115,
    F5 = 116,
    F6 = 117,
    F7 = 118,
    F8 = 119,
    F9 = 120,
    F10 = 121,
    F11 = 122,
    F12 = 123,
    F13 = 124,
    F14 = 125,
    F15 = 126,
    F16 = 127,
    F17 = 128,
    F18 = 129,
    F19 = 130,
    F20 = 131,
    F21 = 132,
    F22 = 133,
    F23 = 134,
    F24 = 135,
    BrowserBack = 166,
    BrowserForward = 167,
    BrowserRefresh = 168,
    BrowserStop = 169,
    BrowserSearch = 170,
    BrowserFavorites = 171,
    BrowserHome = 172,
    VolumeMute = 173,
    VolumeDown = 174,
    VolumeUp = 175,
    MediaNext = 176,
    MediaPrevious = 177,
    MediaStop = 178,
    MediaPlay = 179,
    LaunchMail = 180,
    LaunchMediaSelect = 181,
    LaunchApp1 = 182,
    LaunchApp2 = 183,
    Oem1 = 186,
    OemPlus = 187,
    OemComma = 188,
    OemMinus = 189,
    OemPeriod = 190,
    Oem2 = 191,
    Oem3 = 192,
    Oem4 = 219,
    Oem5 = 220,
    Oem6 = 221,
    Oem7 = 222,
    Oem8 = 223,
    Oem102 = 226,
    Process = 229,
    Packet = 231,
    Attention = 246,
    CrSel = 247,
    ExSel = 248,
    EraseEndOfFile = 249,
    Play = 250,
    Zoom = 251,
    NoName = 252,
    Pa1 = 253,
    OemClear = 254
}

/// Terminal input structure
struct TermInput
{
    union
    {
        int key; /// Keyboard input with possible Mod flags.
        struct
        {
            ushort mouseX; /// Mouse column coord
            ushort mouseY; /// Mouse row coord
        }
    }
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

/// Return key value from string interpretation.
/// Throws: Exception.
/// Params:
///     value = String value.
/// Returns: Keys.
int terminal_keybind(string value)
{
    import std.string : startsWith;
    
    int mod; /// modificators
    
    static immutable string ctrlpfx = "ctrl+";
    if (startsWith(value, ctrlpfx))
    {
        mod |= Mod.ctrl;
        value = value[ctrlpfx.length..$];
    }
    
    static immutable string altpfx = "alt+";
    if (startsWith(value, altpfx))
    {
        mod |= Mod.alt;
        value = value[altpfx.length..$];
    }
    
    static immutable string shiftpfx = "shift+";
    if (startsWith(value, shiftpfx))
    {
        mod |= Mod.shift;
        value = value[shiftpfx.length..$];
    }
    
    if (value.length == 0)
        throw new Exception("Expected key, got empty");
    
    int c = value[0];
    if (value.length == 1 && c >= 'a' && c <= 'z')
        return mod | (c - 32);
    else if (value.length == 1 && c >= '0' && c <= '9') // NOTE: '0'==Key.D0
        return mod | c;
    
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
        throw new Exception("Unknown key");
    }
}
unittest
{
    assert(terminal_keybind("a")             == Key.A);
    assert(terminal_keybind("alt+a")         == Mod.alt+Key.A);
    assert(terminal_keybind("ctrl+a")        == Mod.ctrl+Key.A);
    assert(terminal_keybind("shift+a")       == Mod.shift+Key.A);
    assert(terminal_keybind("ctrl+0")        == Mod.ctrl+Key.D0);
    assert(terminal_keybind("ctrl+insert")   == Mod.ctrl+Key.Insert);
    assert(terminal_keybind("ctrl+home")     == Mod.ctrl+Key.Home);
    assert(terminal_keybind("page-up")       == Key.PageUp);
    assert(terminal_keybind("shift+page-up") == Mod.shift+Key.PageUp);
    assert(terminal_keybind("delete")        == Key.Delete);
    assert(terminal_keybind("f1")            == Key.F1);
}
