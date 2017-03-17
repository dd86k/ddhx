/*
 * poshub.d : In-house console library.
 */

module Poshub;

import std.stdio;
private alias sys = core.stdc.stdlib.system;

version (Windows)
{
    private import core.sys.windows.windows;
    private enum ALT_PRESSED =  RIGHT_ALT_PRESSED  | LEFT_ALT_PRESSED;
    private enum CTRL_PRESSED = RIGHT_CTRL_PRESSED | LEFT_CTRL_PRESSED;
    /// Necessary handles.
    private HANDLE hIn, hOut;
}
else version (Posix)
{
    private import core.sys.posix.sys.ioctl;
    //import core.sys.posix.termios;
}

/// Initiate poshub
void InitConsole()
{
    version (Windows)
    {
        hOut = GetStdHandle(STD_OUTPUT_HANDLE);
        hIn = GetStdHandle(STD_INPUT_HANDLE);
        /*if (SetConsoleCP(65001) == 0) {
            sys ("chcp 65001");
        }*/
    }
}

/*
 * Buffer management.
 */

/// Clear screen
void Clear()
{
    version (Windows)
    {
        CONSOLE_SCREEN_BUFFER_INFO csbi;
        COORD c;
        GetConsoleScreenBufferInfo(hOut, &csbi);
        int size = csbi.dwSize.X * csbi.dwSize.Y;
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

/*
 * Window dimensions.
 */
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
        ioctl(0, TIOCGWINSZ, &ws);
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
        ioctl(0, TIOCSWINSZ, &ws);
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
        ioctl(0, TIOCGWINSZ, &ws);
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
        ioctl(0, TIOCSWINSZ, &ws);
    }
    else
    {
        static assert(0, "WindowHeight : Not implemented");
    }
}

/*
 * Cursor
 */

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
        write("\033[", y + 1, ";", x + 1, "H");
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

/*
 * Titles
 */

/// Set session title
@property void Title(string value)
{
    version (Windows)
    {
        // Sanity check
        if (value[$-1] != '\0') value ~= '\0';
        SetConsoleTitleA(&value[0]);
    }
}

/// Set session title
@property void Title(wstring value)
{
    version (Windows)
    {
        // Sanity check
        if (value[$-1] != '\0') value ~= '\0';
        SetConsoleTitleW(&value[0]);
    }
}

/// Get session title
@property string Title()
{
    version (Windows)
    {
        char[255] buf;
        return buf[0..GetConsoleTitleA(&buf[0], MAX_PATH)].idup;
    }
    else 
    {
        return null;
    }
}

/// Get session title
@property wstring TitleW()
{
    version (Windows)
    {
        wchar[255] buf;
        return buf[0..GetConsoleTitleW(&buf[0], MAX_PATH)].idup;
    }
    else 
    {
        return null;
    }
}

/*
 * Input
 */

/// Read a single character.
KeyInfo ReadKey(bool echo = false)
{
    version (Windows)
    { // Sort of is like .NET's ReadKey
        KeyInfo k;

        INPUT_RECORD ir;
        DWORD num = 0;
        if (ReadConsoleInput(hIn, &ir, 1, &num))
        {
            if (ir.KeyEvent.bKeyDown && ir.EventType == KEY_EVENT)
            {
                DWORD state = ir.KeyEvent.dwControlKeyState;
                k.alt   = (state & ALT_PRESSED)   != 0;
                k.ctrl  = (state & CTRL_PRESSED)  != 0;
                k.shift = (state & SHIFT_PRESSED) != 0;
                k.keyChar  = ir.KeyEvent.AsciiChar;
                k.keyCode  = ir.KeyEvent.wVirtualKeyCode;
                k.scanCode = ir.KeyEvent.wVirtualScanCode;
 
                if (echo) write(k.keyChar);
            }
        }

        return k;
    }
    else version (Posix)
    { //TODO: Readkey (Posix)
        KeyInfo k;



        return k;
    }
}

RawEvent ReadGlobal()
{
    version (Windows)
    {
        RawEvent r;

        INPUT_RECORD ir;
        DWORD num = 0;
        if (ReadConsoleInput(hIn, &ir, 1, &num))
        {
            r.Type = cast(EventType)ir.EventType;

            if (ir.KeyEvent.bKeyDown)
            {
                DWORD state = ir.KeyEvent.dwControlKeyState;
                r.Key.alt   = (state & ALT_PRESSED)   != 0;
                r.Key.ctrl  = (state & CTRL_PRESSED)  != 0;
                r.Key.shift = (state & SHIFT_PRESSED) != 0;
                r.Key.keyChar  = ir.KeyEvent.AsciiChar;
                r.Key.keyCode  = ir.KeyEvent.wVirtualKeyCode;
                r.Key.scanCode = ir.KeyEvent.wVirtualScanCode;
            }

            r.Mouse.Location.X = cast(ushort)ir.MouseEvent.dwMousePosition.X;
            r.Mouse.Location.Y = cast(ushort)ir.MouseEvent.dwMousePosition.Y;
            r.Mouse.Buttons = cast(ushort)ir.MouseEvent.dwButtonState;
            r.Mouse.State = cast(ushort)ir.MouseEvent.dwControlKeyState;
            r.Mouse.Type = cast(ushort)ir.MouseEvent.dwEventFlags;

            r.Size.Width = ir.WindowBufferSizeEvent.dwSize.X;
            r.Size.Height = ir.WindowBufferSizeEvent.dwSize.Y;
        }

        return r;
    }
    else version (Posix)
    { //TODO: RawEvent (Posix)
        RawEvent r;

        return r;
    }
}

enum EventType : ushort {
    Key = 1, Mouse = 2, Resize = 4
}

struct RawEvent
{
    EventType Type;
    KeyInfo Key;
    MouseInfo Mouse;
    WindowSize Size;
}

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

enum MouseButton : ushort { // Windows compilant
    Left = 1, Right = 2, Middle = 4, Mouse4 = 8, Mouse5 = 16
}

enum MouseState : ushort { // Windows compilant
    RightAlt = 1, LeftAlt = 2, RightCtrl = 4,
    LeftCtrl = 8, Shift = 0x10, NumLock = 0x20,
    ScrollLock = 0x40, CapsLock = 0x80, EnhancedKey = 0x100
}

enum MouseEventType { // Windows compilant
    Moved = 1, DoubleClick = 2, Wheel = 4, HorizontalWheel = 8
}

struct MouseInfo
{
    struct ScreenLocation { ushort X, Y; }
    ScreenLocation Location;
    ushort Buttons;
    ushort State;
    ushort Type;
}

struct WindowSize
{
    ushort Width, Height;
}

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

/*
 * Output
 */

//SetFgColor : SetConsoleTextAttribute

/*
 * CTRL Handler
 */

void SetCtrlHandler(void function() f)
{ //TODO: Ctrl handler

}