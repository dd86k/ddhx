/*
 * ddcon.d : In-house console library inspired of the .NET Console class.
 *
 * This library maximize the use of Posix functions to be as portable and
 * compatible for many operating systems.
 *
 * This source is separated by long comments for easier navigation while scrolling.
 */

module ddcon;

private import core.stdc.stdio;
private import core.stdc.stdlib : system;
private alias system sys;

version (Windows)
{
    private import core.sys.windows.windows;
    private enum ALT_PRESSED =  RIGHT_ALT_PRESSED  | LEFT_ALT_PRESSED;
    private enum CTRL_PRESSED = RIGHT_CTRL_PRESSED | LEFT_CTRL_PRESSED;
    private enum DEFAULT_COLOR =
        FOREGROUND_BLUE | FOREGROUND_GREEN | FOREGROUND_RED;
    /// Necessary handles.
    private HANDLE hIn, hOut;
    private USHORT defaultColor = DEFAULT_COLOR;
}
else version (Posix)
{
    private import core.sys.posix.sys.ioctl;
    private import core.sys.posix.unistd;
    private import core.sys.posix.termios;
    private enum TERM_ATTR = ~ICANON & ~ECHO;
    private termios old_tio, new_tio;
}

/*******************************************************************
 * Initiation
 *******************************************************************/

/// Initiate poshub
void InitConsole()
{
    version (Windows)
    {
        hOut = GetStdHandle(STD_OUTPUT_HANDLE);
        hIn  = GetStdHandle(STD_INPUT_HANDLE);
        /*HKEY key;
        if (RegOpenKeyExW(
            HKEY_CURRENT_USER,
            `SOFTWARE\Microsoft\Command Processor`,
            0,
            0,
            &key
        ))*/
        /*wstring e = `SOFTWARE\Microsoft\Command Processor\DefaultColor`w;
        DWORD n = 4;
        DWORD val;
        if (RegQueryValueExW(
                cast(const)HKEY_CURRENT_USER,
                cast(const wchar*)&e[0],
                cast(uint*)0,
                cast(uint*)0,
                cast(void*)&val,
                &n
            ) != 0)
        {
            defaultColor = val & 0xFFFF;
        }*/

        /*if (SetConsoleCP(65001) == 0) {
            sys ("chcp 65001");
        }*/
    }
}

/*******************************************************************
 * Clear
 *******************************************************************/

/// Clear screen
void Clear()
{
    version (Windows)
    {
        CONSOLE_SCREEN_BUFFER_INFO csbi;
        COORD c;
        GetConsoleScreenBufferInfo(hOut, &csbi);
        const int size = csbi.dwSize.X * csbi.dwSize.Y;
        DWORD num = 0;
        if (FillConsoleOutputCharacterA(hOut, ' ', size, c, &num) == 0
            /*|| // .NET uses this but no idea why.
            FillConsoleOutputAttribute(hOut, csbi.wAttributes, size, c, &num) == 0*/)
        {
            SetPos(0, 0);
        }
        else // If that fails, run cls.
            sys ("cls");
    }
    else version (Posix)
    { //TODO: Clear (Posix)
        sys ("clear");
    }
    else static assert(0, "Clear: Not implemented");
}

/*******************************************************************
 * Window dimensions
 *******************************************************************/

// Note: A COORD uses SHORT (short) and Linux uses unsigned shorts.

/// Window width
@property ushort WindowWidth()
{
    version (Windows)
    {
        CONSOLE_SCREEN_BUFFER_INFO c;
        GetConsoleScreenBufferInfo(hOut, &c);
        return cast(ushort)(c.srWindow.Right - c.srWindow.Left + 1);
    }
    else version (Posix)
    {
        winsize ws;
        ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws);
        return ws.ws_col;
    }
    else
    {
        static assert(0, "WindowWidth : Not implemented");
    }
}

/// Window width
@property void WindowWidth(int w)
{
    version (Windows)
    {
        COORD c = { cast(SHORT)w, cast(SHORT)WindowWidth };
        SetConsoleScreenBufferSize(hOut, c);
    }
    else version (Posix)
    {
        winsize ws = { cast(ushort)w, WindowWidth };
        ioctl(STDOUT_FILENO, TIOCSWINSZ, &ws);
    }
    else
    {
        static assert(0, "WindowWidth : Not implemented");
    }
}

/// Window height
@property ushort WindowHeight()
{
    version (Windows)
    {
        CONSOLE_SCREEN_BUFFER_INFO c;
        GetConsoleScreenBufferInfo(hOut, &c);
        return cast(ushort)(c.srWindow.Bottom - c.srWindow.Top + 1);
    }
    else version (Posix)
    {
        winsize ws;
        ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws);
        return ws.ws_row;
    }
    else
    {
        static assert(0, "WindowHeight : Not implemented");
    }
}

/// Window height
@property void WindowHeight(int h)
{
    version (Windows)
    {
        COORD c = { cast(SHORT)WindowWidth, cast(SHORT)h };
        SetConsoleScreenBufferSize(hOut, c);
    }
    else version (Posix)
    {
        winsize ws = { WindowWidth, cast(ushort)h, 0, 0 };
        ioctl(STDOUT_FILENO, TIOCSWINSZ, &ws);
    }
    else
    {
        static assert(0, "WindowHeight : Not implemented");
    }
}

/*******************************************************************
 * Cursor management
 *******************************************************************/

/// Set cursor position x and y position respectively from the
/// top left corner, 0-based.
void SetPos(int x, int y)
{
    version (Windows)
    { // 0-based
        COORD c = { cast(SHORT)x, cast(SHORT)y };
        SetConsoleCursorPosition(hOut, c);
    }
    else version (Posix)
    { // 1-based
        printf("\033[%d;%dH", y + 1, x + 1);
    }
}

/*@property ushort CursorLeft()
{
    version (Windows)
    {


        return 0;
    }
    else version (Posix)
    {


        return 0;
    }
}

@property ushort CursorTop()
{
    version (Windows)
    {


        return 0;
    }
    else version (Posix)
    {


        return 0;
    }
}*/

/*******************************************************************
 * Input
 *******************************************************************/

/**
 * Read a single character.
 * Params: echo = Echo character to output.
 * Returns: A KeyInfo structure.
 */
KeyInfo ReadKey(bool echo = false)
{
    KeyInfo k;
    version (Windows)
    { // Sort of is like .NET's ReadKey
        INPUT_RECORD ir;
        DWORD num = 0;
        if (ReadConsoleInput(hIn, &ir, 1, &num))
        {
            if (ir.KeyEvent.bKeyDown && ir.EventType == KEY_EVENT)
            {
                const DWORD state = ir.KeyEvent.dwControlKeyState;
                k.alt   = (state & ALT_PRESSED)   != 0;
                k.ctrl  = (state & CTRL_PRESSED)  != 0;
                k.shift = (state & SHIFT_PRESSED) != 0;
                k.keyChar  = ir.KeyEvent.AsciiChar;
                k.keyCode  = ir.KeyEvent.wVirtualKeyCode;
                k.scanCode = ir.KeyEvent.wVirtualScanCode;
 
                if (echo) printf("%c", k.keyChar);
            }
        }
    }
    else version (Posix)
    {
        //TODO: Get modifier keys states

        // Commenting this section will echo the character
        // And also it won't do anything to getchar
        tcgetattr(STDIN_FILENO, &old_tio);
        new_tio = old_tio;
        new_tio.c_lflag &= TERM_ATTR;
        tcsetattr(STDIN_FILENO,TCSANOW, &new_tio);

        uint c = getchar();

        with (k)
        switch (c)
        {
        case '\n': // \n (ENTER)
            keyCode = Key.Enter;
            break;
        case 27: // ESC
            switch (c = getchar())
            {
            case '[':
                switch (c = getchar())
                {
                case 'A': keyCode = Key.UpArrow; break;
                case 'B': keyCode = Key.DownArrow; break;
                case 'C': keyCode = Key.RightArrow; break;
                case 'D': keyCode = Key.LeftArrow; break;
                case 'F': keyCode = Key.End; break;
                case 'H': keyCode = Key.Home; break;
                // There is an additional getchar due to the pending '~'
                case '2': keyCode = Key.Insert; getchar; break;
                case '3': keyCode = Key.Delete; getchar; break;
                case '5': keyCode = Key.PageUp; getchar; break;
                case '6': keyCode = Key.PageDown; getchar; break;
                default: break;
                }
                break;
            default: // EOF?

                break;
            }
            break;
        case 'a': .. case 'z': // A .. Z
            k.keyCode = cast(Key)(c - 32);
            break;
        //TODO: The rest
        default:
            k.keyCode = c & 0xFFFF;
            break;
        }

        tcsetattr(STDIN_FILENO,TCSANOW, &old_tio);
    }
    return k;
}

/*******************************************************************
 * Handlers
 *******************************************************************/

/*void SetCtrlHandler(void function() f)
{ //TODO: Ctrl handler

}*/

/*******************************************************************
 * Emunerations
 *******************************************************************/

/// Key codes mapping.
enum Key : ushort {
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

/*******************************************************************
 * Structs
 *******************************************************************/

/// Key information structure
// ala C#
struct KeyInfo
{
    /// UTF-8 Character.
    char keyChar;
    /// Key code.
    ushort keyCode;
    /// Scan code.
    ushort scanCode;
    /// If either CTRL was held down.
    bool ctrl;
    /// If either ALT was held down.
    bool alt;
    /// If SHIFT was held down.
    bool shift;
}