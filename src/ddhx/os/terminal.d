/// Terminal/console handling.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.os.terminal;

//TODO: readline
//      automatically pause input, stdio.readln, resume input
//TODO: Switch key input depending on $TERM
//      xterm (xterm, xterm-color, xterm-256color), linux, vt100
//TODO: BetterC coverage (using D_BetterC version)

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
    private __gshared HANDLE hIn, hOut;
    private __gshared DWORD oldCP;
    private __gshared ushort oldAttr;
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
    private enum SIGWINCH = 28;
    
    // Bionic depends on the Linux system it's compiled on.
    // But Glibc and Musl have the same settings, so does Bionic.
    // ...And uClibc, at least on Linux.
    // D are missing the following bindings.
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
        private enum TCSANOW    = 0;
        private enum NCCS    = 32;
        private enum ICANON    = 2;
        private enum ECHO    = 10;
        private enum BRKINT    = 2;
        private enum INPCK    = 20;
        private enum ISTRIP    = 40;
        private enum ICRNL    = 400;
        private enum IXON    = 2000;
        private enum IEXTEN    = 100000;
        private enum CS8    = 60;
        private enum TCSAFLUSH    = 2;
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
    
    struct KeyInfo {
        string text;
        int value;
    }
    immutable KeyInfo[] keyInputsVTE = [
        // text         Key value
        { "\033[A",     Key.UpArrow },
        { "\033[1;2A",  Key.UpArrow | Mod.shift },
        { "\033[1;3A",  Key.UpArrow | Mod.alt },
        { "\033[1;5A",  Key.UpArrow | Mod.ctrl },
        { "\033[A:4A",  Key.UpArrow | Mod.shift | Mod.alt },
        { "\033[B",     Key.DownArrow },
        { "\033[1;2B",  Key.DownArrow | Mod.shift },
        { "\033[1;3B",  Key.DownArrow | Mod.alt },
        { "\033[1;5B",  Key.DownArrow | Mod.ctrl },
        { "\033[A:4B",  Key.DownArrow | Mod.shift | Mod.alt },
        { "\033[C",     Key.RightArrow },
        { "\033[1;2C",  Key.RightArrow | Mod.shift },
        { "\033[1;3C",  Key.RightArrow | Mod.alt },
        { "\033[1;5C",  Key.RightArrow | Mod.ctrl },
        { "\033[A:4C",  Key.RightArrow | Mod.shift | Mod.alt },
        { "\033[D",     Key.LeftArrow },
        { "\033[1;2D",  Key.LeftArrow | Mod.shift },
        { "\033[1;3D",  Key.LeftArrow | Mod.alt },
        { "\033[1;5D",  Key.LeftArrow | Mod.ctrl },
        { "\033[A:4D",  Key.LeftArrow | Mod.shift | Mod.alt },
        { "\033[2~",    Key.Insert },
        { "\033[2;3~",  Key.Insert | Mod.alt },
        { "\033[3~",    Key.Delete },
        { "\033[3;5~",  Key.Delete | Mod.ctrl },
        { "\033[H",     Key.Home },
        { "\033[1;3H",  Key.Home | Mod.alt },
        { "\033[1;5H",  Key.Home | Mod.ctrl },
        { "\033[F",     Key.End },
        { "\033[1;3F",  Key.End | Mod.alt },
        { "\033[1;5F",  Key.End | Mod.ctrl },
        { "\033[5~",    Key.PageUp },
        { "\033[5;5~",  Key.PageUp | Mod.ctrl },
        { "\033[6~",    Key.PageDown },
        { "\033[6;5~",  Key.PageDown | Mod.ctrl },
        { "\033OP",     Key.F1 },
        { "\033[1;2P",  Key.F1 | Mod.shift, },
        { "\033[1;3R",  Key.F1 | Mod.alt, },
        { "\033[1;5P",  Key.F1 | Mod.ctrl, },
        { "\033OQ",     Key.F2 },
        { "\033[1;2Q",  Key.F2 | Mod.shift },
        { "\033OR",     Key.F3 },
        { "\033[1;2R",  Key.F3 | Mod.shift },
        { "\033OS",     Key.F4 },
        { "\033[1;2S",  Key.F4 | Mod.shift },
        { "\033[15~",   Key.F5 },
        { "\033[15;2~", Key.F5 | Mod.shift },
        { "\033[17~",   Key.F6 },
        { "\033[17;2~", Key.F6 | Mod.shift },
        { "\033[18~",   Key.F7 },
        { "\033[18;2~", Key.F7 | Mod.shift },
        { "\033[19~",   Key.F8 },
        { "\033[19;2~", Key.F8 | Mod.shift },
        { "\033[20~",   Key.F9 },
        { "\033[20;2~", Key.F9 | Mod.shift },
        { "\033[21~",   Key.F10 },
        { "\033[21;2~", Key.F10 | Mod.shift },
        { "\033[23~",   Key.F11 },
        { "\033[23;2~", Key.F11 | Mod.shift},
        { "\033[24~",   Key.F12 },
        { "\033[24;2~", Key.F12 | Mod.shift },
    ];
    
    private __gshared termios old_ios, new_ios;
}

/// Flags for terminalInit.
//TODO: captureCtrlC: Block CTRL+C
enum TermFeat : ushort {
    /// Initiate only the basic.
    none        = 0,
    /// Initiate the input system.
    inputSys    = 1,
    /// Initiate the alternative screen buffer.
    altScreen   = 1 << 1,
    /// Initiate everything.
    all         = 0xffff,
}

private __gshared int current_features;

/// Initiate terminal.
/// Params: features = Feature bits to initiate.
/// Throws: (Windows) WindowsException on OS exception
void terminalInit(int features)
{
    current_features = features;
    
    version (Windows)
    {
        CONSOLE_SCREEN_BUFFER_INFO csbi = void;
        
        if (features & TermFeat.inputSys)
        {
            //NOTE: Re-opening stdin before new screen fixes quite a few things
            //      - usage with CreateConsoleScreenBuffer
            //      - readln (for menu)
            //      - receiving key input when stdin was used for reading a buffer
            hIn = CreateFileA("CONIN$", GENERIC_READ, 0, null, OPEN_EXISTING, 0, null);
            if (hIn == INVALID_HANDLE_VALUE)
                throw new WindowsException(GetLastError);
            SetConsoleMode(hIn, ENABLE_EXTENDED_FLAGS | ENABLE_WINDOW_INPUT | ENABLE_MOUSE_INPUT);
            stdin.windowsHandleOpen(hIn, "r");
            SetStdHandle(STD_INPUT_HANDLE, hIn);
        }
        else
        {
            hIn = GetStdHandle(STD_INPUT_HANDLE);
        }
        
        if (features & TermFeat.altScreen)
        {
            //
            // Setting up stdout
            //
            
            hOut = GetStdHandle(STD_OUTPUT_HANDLE);
            if (hIn == INVALID_HANDLE_VALUE)
                throw new WindowsException(GetLastError);
            
            if (GetConsoleScreenBufferInfo(hOut, &csbi) == FALSE)
                throw new WindowsException(GetLastError);
            
            DWORD attr = void;
            if (GetConsoleMode(hOut, &attr) == FALSE)
                throw new WindowsException(GetLastError);
            
            hOut = CreateConsoleScreenBuffer(
                GENERIC_READ | GENERIC_WRITE,    // dwDesiredAccess
                FILE_SHARE_READ | FILE_SHARE_WRITE,    // dwShareMode
                null,    // lpSecurityAttributes
                CONSOLE_TEXTMODE_BUFFER,    // dwFlags
                null,    // lpScreenBufferData
            );
            if (hOut == INVALID_HANDLE_VALUE)
                throw new WindowsException(GetLastError);
            
            stdout.flush;
            stdout.windowsHandleOpen(hOut, "wb"); // fixes using write functions
            
            SetStdHandle(STD_OUTPUT_HANDLE, hOut);
            SetConsoleScreenBufferSize(hOut, csbi.dwSize);
            SetConsoleMode(hOut, attr | ENABLE_PROCESSED_OUTPUT);
            
            if (SetConsoleActiveScreenBuffer(hOut) == FALSE)
                throw new WindowsException(GetLastError);
        }
        else
        {
            hOut = GetStdHandle(STD_OUTPUT_HANDLE);
        }
        
        stdout.setvbuf(0, _IONBF); // fixes weird cursor positions with alt buffer
        
        // NOTE: While Windows supports UTF-16LE (1200) and UTF-32LE,
        //       it's only for "managed applications" (.NET).
        // LINK: https://docs.microsoft.com/en-us/windows/win32/intl/code-page-identifiers
        oldCP = GetConsoleOutputCP();
        if (SetConsoleOutputCP(CP_UTF8) == FALSE)
            throw new WindowsException(GetLastError);
        
        //TODO: Get active (or default) colors
        GetConsoleScreenBufferInfo(hOut, &csbi);
        oldAttr = csbi.wAttributes;
    }
    else version (Posix)
    {
        stdout.setvbuf(0, _IONBF);
        if (features & TermFeat.inputSys)
        {
            // Should it re-open tty by default?
            stat_t s = void;
            fstat(STDIN_FILENO, &s);
            if (S_ISFIFO(s.st_mode))
                stdin.reopen("/dev/tty", "r");
            tcgetattr(STDIN_FILENO, &old_ios);
            new_ios = old_ios;
            // NOTE: input modes
            // - IXON enables ^S and ^Q
            // - ICRNL enables ^M
            // - BRKINT causes SIGINT (^C) on break conditions
            // - INPCK enables parity checking
            // - ISTRIP strips the 8th bit
            new_ios.c_iflag &= ~(IXON | ICRNL | BRKINT | INPCK | ISTRIP);
            // NOTE: output modes
            // - OPOST turns on output post-processing
            //new_ios.c_oflag &= ~(OPOST);
            // NOTE: local modes
            // - ICANON turns on canonical mode (per-line instead of per-byte)
            // - ECHO turns on character echo
            // - ISIG enables ^C and ^Z signals
            // - IEXTEN enables ^V
            new_ios.c_lflag &= ~(ICANON | ECHO | IEXTEN);
            // NOTE: control modes
            // - CS8 sets Character Size to 8-bit
            new_ios.c_cflag |= CS8;
            // minimum amount of bytes to read,
            // 0 being return as soon as there is data
            //new_ios.c_cc[VMIN] = 0;
            // maximum amount of time to wait for input,
            // 1 being 1/10 of a second (100 milliseconds)
            //new_ios.c_cc[VTIME] = 0;
            terminalResumeInput;
        }
        
        if (features & TermFeat.altScreen)
        {
            // change to alternative screen buffer
            stdout.write("\033[?1049h");
        }
    }
    
    atexit(&terminalQuit);
}

private extern (C)
void terminalQuit()
{
    terminalRestore();
}

/// Restore CP and other settings
void terminalRestore()
{
    version (Windows)
    {
        SetConsoleOutputCP(oldCP); // unconditionally
    }
    else version (Posix)
    {
        // restore main screen buffer
        if (current_features & TermFeat.altScreen)
            terminalOut("\033[?1049l");
        terminalShowCursor;
    }
    if (current_features & TermFeat.inputSys)
        terminalPauseInput;
}

private __gshared void function() terminalOnResizeEvent;

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
private extern (C)
void terminalResized(int signo, siginfo_t *info, void *content)
{
    if (terminalOnResizeEvent)
        terminalOnResizeEvent();
}

void terminalPauseInput()
{
    version (Posix)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &old_ios);
}

void terminalResumeInput()
{
    version (Posix)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &new_ios);
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
        if (FillConsoleOutputCharacterA(hOut, ' ', size, c, &num) == 0
            /*||
            FillConsoleOutputAttribute(hOut, csbi.wAttributes, size, c, &num) == 0*/)
        {
            terminalCursor(0, 0);
        }
        else // If that fails, run cls.
            system("cls");
    }
    else version (Posix)
    {
        // \033c is a Reset
        // \033[2J is "Erase whole display"
        terminalOut("\033[2J");
    } else static assert(0, "Clear: Not implemented");
}

/// Get terminal window size in characters.
/// Returns: Size
TerminalSize terminalSize()
{
    TerminalSize size = void;
    version (Windows)
    {
        CONSOLE_SCREEN_BUFFER_INFO c = void;
        GetConsoleScreenBufferInfo(hOut, &c);
        size.rows    = c.srWindow.Bottom - c.srWindow.Top + 1;
        size.columns = c.srWindow.Right - c.srWindow.Left + 1;
    }
    else version (Posix)
    {
        //TODO: Consider using LINES and COLUMNS environment variables
        //      as fallback if ioctl returns -1.
        //TODO: Consider ESC [ 18 t for fallback of environment.
        //      Reply: ESC [ 8 ; ROWS ; COLUMNS t
        winsize ws = void;
        ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws);
        size.rows    = ws.ws_row;
        size.columns = ws.ws_col;
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
        SetConsoleCursorPosition(hOut, c);
    }
    else version (Posix) // 1-based, so 0,0 needs to be output as 1,1
    {
        char[16] b = void;
        int r = snprintf(b.ptr, 16, "\033[%d;%dH", ++y, ++x);
        assert(r > 0);
        terminalOut(b.ptr, r);
    }
}

/// Hide the terminal cursor.
void terminalHideCursor()
{
    version (Windows)
    {
        CONSOLE_CURSOR_INFO cci = void;
        GetConsoleCursorInfo(hOut, &cci);
        cci.bVisible = FALSE;
        SetConsoleCursorInfo(hOut, &cci);
    }
    else version (Posix)
    {
        terminalOut("\033[?25l");
    }
}
/// Show the terminal cursor.
void terminalShowCursor()
{
    version (Windows)
    {
        CONSOLE_CURSOR_INFO cci = void;
        GetConsoleCursorInfo(hOut, &cci);
        cci.bVisible = TRUE;
        SetConsoleCursorInfo(hOut, &cci);
    }
    else version (Posix)
    {
        terminalOut("\033[?25h");
    }
}

void terminalHighlight()
{
    version (Windows)
    {
        SetConsoleTextAttribute(hOut, oldAttr | BACKGROUND_RED);
    }
    else version (Posix)
    {
        terminalOut("\033[41m");
    }
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
        terminalOut("\033[7m");
    }
}
/// Underline.
/// Bugs: Does not work on Windows Terminal. See https://github.com/microsoft/terminal/issues/8037
void terminalUnderline()
{
    version (Windows)
    {
        SetConsoleTextAttribute(hOut, oldAttr | COMMON_LVB_UNDERSCORE);
    }
    else version (Posix)
    {
        terminalOut("\033[4m");
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

size_t terminalWrite(const(void)[] data)
{
    return terminalWrite(data.ptr, data.length);
}

/// Directly write to output.
/// Params:
///     data = Character data.
///     size = Amount in bytes.
/// Returns: Number of bytes written.
size_t terminalWrite(const(void) *data, size_t size)
{
    version (Windows)
    {
        uint r = void;
        assert(WriteFile(hOut, data, cast(uint)size, &r, null));
        return r;
    }
    else version (Posix)
    {
        ssize_t r = write(STDOUT_FILENO, data, size);
        assert(r >= 0);
        return r;
    }
}

// Commented until terminalRead() improves
/*template CTRL(int c) { enum CTRL = c & 0x1f; }
unittest
{
    assert(CTRL!('a') == 0xa);
}*/

/// Read an input event. This function is blocking.
/// Throws: (Windows) WindowsException on OS error.
/// Returns: Terminal input.
TermInput terminalRead()
{
    TermInput event;
    
    version (Windows)
    {
        enum ALT_PRESSED =  RIGHT_ALT_PRESSED  | LEFT_ALT_PRESSED;
        enum CTRL_PRESSED = RIGHT_CTRL_PRESSED | LEFT_CTRL_PRESSED;

        INPUT_RECORD ir = void;
        DWORD num = void;
Lread:
        if (ReadConsoleInputA(hIn, &ir, 1, &num) == 0)
            throw new WindowsException(GetLastError);
        
        if (num == 0)
            goto Lread;
        
        switch (ir.EventType) {
        case KEY_EVENT:
            if (ir.KeyEvent.bKeyDown == FALSE)
                goto Lread;
            
            version (unittest)
            {
                printf(
                "KeyEvent: AsciiChar=%d wVirtualKeyCode=%d dwControlKeyState=%x\n",
                ir.KeyEvent.AsciiChar,
                ir.KeyEvent.wVirtualKeyCode,
                ir.KeyEvent.dwControlKeyState,
                );
            }
            
            const ushort keycode = ir.KeyEvent.wVirtualKeyCode;
            
            // Filter out single modifier key events
            switch (keycode) {
            case 16, 17, 18: goto Lread; // shift,ctrl,alt
            default:
            }
            
            event.type = InputType.keyDown;
            
            const char ascii = ir.KeyEvent.AsciiChar;
            
            if (ascii >= 'a' && ascii <= 'z')
            {
                event.key = ascii - 32;
                return event;
            }
            else if (ascii >= 0x20 && ascii < 0x7f)
            {
                event.key = ascii;
                
                // '?' on a fr-ca kb is technically shift+6,
                // breaking app input since expecting no modifiers
                if (ascii >= 'A' && ascii <= 'Z')
                    event.key = Mod.shift;
                
                return event;
            }
            
            event.key = keycode;
            const DWORD state = ir.KeyEvent.dwControlKeyState;
            if (state & ALT_PRESSED) event.key |= Mod.alt;
            if (state & CTRL_PRESSED) event.key |= Mod.ctrl;
            if (state & SHIFT_PRESSED) event.key |= Mod.shift;
            return event;
        /*case MOUSE_EVENT:
            if (ir.MouseEvent.dwEventFlags & MOUSE_WHEELED)
            {
                // Up=0x00780000 Down=0xFF880000
                event.type = ir.MouseEvent.dwButtonState > 0xFF_0000 ?
                    Mouse.ScrollDown : Mouse.ScrollUp;
            }*/
        case WINDOW_BUFFER_SIZE_EVENT:
            if (terminalOnResizeEvent)
                terminalOnResizeEvent();
            goto Lread;
        default: goto Lread;
        }
    }
    else version (Posix)
    {
        //TODO: Mouse reporting in Posix terminals
        //      * X10 compatbility mode (mouse-down only)
        //      Enable: ESC [ ? 9 h
        //      Disable: ESC [ ? 9 l
        //      "sends ESC [ M bxy (6 characters)"
        //      - ESC [ M button column row (1-based)
        //      - 0,0 click: ESC [ M   ! !
        //        ! is 0x21, so '!' - 0x21 = 0
        //      - end,end click: ESC [ M   q ;
        //        q is 0x71, so 'q' - 0x21 = 0x50 (column 80)
        //        ; is 0x3b, so ';' - 0x21 = 0x1a (row 26)
        //      - button left:   ' '
        //      - button right:  '"'
        //      - button middle: '!'
        //      * Normal tracking mode
        //      Enable: ESC [ ? 1000 h
        //      Disable: ESC [ ? 1000 l
        //      b bits[1:0] 0=MB1 pressed, 1=MB2 pressed, 2=MB3 pressed, 3=release
        //      b bits[7:2] 4=Shift (bit 3), 8=Meta (bit 4), 16=Control (bit 5)
        //TODO: Faster scanning
        //      So we have a few choices:
        //      - string table (current, works alright)
        //      - string[string]
        //        - needs active init though
        //      - string decoding (slower?)
        //        [ -> escape
        //        1;2 -> shift (optional)
        //        B -> right arrow
        //      - template char[8] to long
        //        - very cursed
        //        - screwed if there are keys more than 8 bytes
        //        - template should do endianness
        //      - Manually hash it
        //        - Allows static arrays
        //        - std.digest.murmurhash already available
        
        enum BLEN = 8;
        char[BLEN] b = void;
    Lread:
        ssize_t r = read(STDIN_FILENO, b.ptr, BLEN);
        
        event.type = InputType.keyDown; // Assuming for now
        event.key  = 0; // clear as safety measure
        
        switch (r) {
        case -1:
            assert(0, "read(2) failed");
            goto Lread;
        case 0: // How even
            version (unittest) printf("stdin: empty\n");
            goto Lread;
        case 1:
            char c = b[0];
            version (unittest) printf("stdin: \\0%o (%d)\n", c, c);
            // Filtering here adjusts the value only if necessary.
            switch (c) {
            case 0: // Ctrl+Space
                event.key = Key.Spacebar | Mod.ctrl;
                return event;
            case 13:
                event.key = Key.Enter;
                return event;
            case 8, 127: // ^H
                event.key = Key.Backspace;
                return event;
            default:
            }
            if (c >= 'a' && c <= 'z')
                event.key = cast(ushort)(c - 32);
            else if (c >= 'A' && c <= 'Z')
                event.key = c | Mod.shift;
            else if (c < 32)
                event.key = (c + 64) | Mod.ctrl;
            else
                event.key = c;
            return;
        default:
        }
        
        version (unittest)
        {
            printf("stdin:");
            for (size_t i; i < r; ++i)
            {
                char c = b[i];
                if (c < 32 || c > 126)
                    printf(" \\0%o", c);
                else
                    putchar(b[i]);
            }
            putchar('\n');
            stdout.flush();
        }
        
        // Make a slice of misc. input.
        const(char)[] inputString = b[0..r];
        
        //TODO: Checking for mouse inputs
        //      Starts with \033[M
        
        // Checking for other key inputs
        foreach (ki; keyInputsVTE)
        {
            if (r != ki.text.length) continue;
            if (inputString != ki.text) continue;
            event.key  = ki.value;
            return event;
        }
        
        // Matched to nothing
        goto Lread;
    } // version posix
}


/// Terminal input type.
enum InputType
{
    keyDown,
    keyUp,
    mouseDown,
    mouseUp,
}

//TODO: Redo input encoding
//      15: 0 key value (ascii or special key)
//      23:16 flags
//            0000 0000
//            |||| ||+-- Alt
//            |||| |+--- Ctrl
//            |||+------ Special key
//      31:24 input type
//              0 keydown
//              1 mousedown
//            128 keyup
//            129 mouseup

/*private enum specialbit = 1 << 20;
enum Special
{
    rightArrow  = 1 | specialbit,
    leftArrow   = 2 | specialbit,
    upArrow     = 3 | specialbit,
    Arrow       = 4 | specialbit,
    
    
}*/

/// Key modifier
enum Mod
{
    ctrl  = 1 << 24,
    shift = 1 << 25,
    alt   = 1 << 26,
}

/// Key codes map.
//TODO: Consider mapping these to os/ascii-specific
enum Key
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
