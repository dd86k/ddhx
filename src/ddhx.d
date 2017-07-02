module ddhx;

import std.stdio;
import Menu;
import ddcon;

//TODO: Bookmarks page (What shortcut or function key?)
//TODO: Statistics page or functions
//TODO: MD5? SHA1?
//TODO: Tabs? (Probably not)

/// App version
enum APP_VERSION = "0.0.0-0-notoutyet-1";

/// Offset type (hex, dec, etc.)
enum OffsetType {
	Hexadecimal, Decimal, Octal
}
/// 
enum DisplayType {
    Default, Text, Hex
}

/*
 * User settings
 */

ushort BytesPerRow = 16; /// Bytes shown per row
OffsetType CurrentOffsetType; /// Current offset view type
DisplayType CurrentDisplayType; /// Current display view type

/*
 * Internal
 */

int LastErrorCode; /// Last error code to report
string Filepath; /// Current file path
File CurrentFile; /// Current file handle
long CurrentPosition; /// Current file position
ubyte[] Buffer; /// Display buffer

//TODO: When typing g goto menu directly
//      - Tried writing to stdin

/// Main ddhx entry point past CLI.
void Start()
{
	InitConsole();
	PrepBuffer();
    if (CurrentFile.size > 0)
	    ReadFile();
    Clear();
	UpdateOffsetBar();
	UpdateDisplay();
    UpdatePositionBar();

	while (1)
	{
        const KeyInfo g = ReadKey;
        //TODO: Handle resize event (Windows)
        //TODO: Handle resize event (Posix)
        HandleKey(&g);
	}
}

/*void HandleMouse(const MouseInfo* mi)
{
    ulong fs = CurrentFile.size;
    size_t bs = Buffer.length;

    switch (mi.Type) {
        case MouseEventType.Wheel:
            if (mi.ButtonState > 0) { // Up
                if (CurrentPosition - BytesPerRow >= 0)
                    Goto(CurrentPosition - BytesPerRow);
                else
                    Goto(0);
            } else { // Down
                if (CurrentPosition + bs + BytesPerRow <= fs)
                    Goto(CurrentPosition + BytesPerRow);
                else
                    Goto(fs - bs);
            }
            break;
        default:
    }
}*/

/**
 * Handles a user key-stroke
 * Params: k = KeyInfo (ddcon)
 */
void HandleKey(const KeyInfo* k)
{
    ulong fs = CurrentFile.size;
    size_t bs = Buffer.length;

    switch (k.keyCode)
    {
    /*
     * Navigation
     */

    case Key.UpArrow:
        if (CurrentPosition - BytesPerRow >= 0)
            Goto(CurrentPosition - BytesPerRow);
        else
            Goto(0);
        break;
    case Key.DownArrow:
        if (CurrentPosition + bs + BytesPerRow <= fs)
            Goto(CurrentPosition + BytesPerRow);
        else
            Goto(fs - bs);
        break;
    case Key.LeftArrow:
        if (CurrentPosition - 1 >= 0) // Else already at 0
            Goto(CurrentPosition - 1);
        break;
    case Key.RightArrow:
        if (CurrentPosition + bs + 1 <= fs)
            Goto(CurrentPosition + 1);
        else
            Goto(fs - bs);
        break;
    case Key.PageUp:
        if (CurrentPosition - cast(long)bs >= 0)
            Goto(CurrentPosition - bs);
        else
            Goto(0);
        break;
    case Key.PageDown:
        if (CurrentPosition + bs + bs <= fs)
            Goto(CurrentPosition + bs);
        else
            Goto(fs - bs);
        break;

    case Key.Home:
        if (k.ctrl)
            Goto(0);
        else
            Goto(CurrentPosition - (CurrentPosition % BytesPerRow));
        break;
    case Key.End:
        if (k.ctrl)
            Goto(fs - bs);
        else
        {
            const long np = CurrentPosition +
                (BytesPerRow - CurrentPosition % BytesPerRow);

            if (np + bs <= fs)
                Goto(np);
            else
                Goto(fs - bs);
        }
        break;

    /*
     * Actions/Shortcuts
     */

    case Key.Escape, Key.Enter:
        EnterMenu();
        break;
    case Key.G:
        //EnterMenu("g");
        //UpdateOffsetBar();
        break;
    case Key.I:
        PrintFileInfo;
        break;
    case Key.R, Key.F5:
        PrepBuffer;
        RefreshAll;
        break;
    case Key.H: ShowHelp; break;
    case Key.Q: Exit; break;
    default:
    }
}

/// Refresh display and both bars
void RefreshAll() {
    RefreshDisplay;
    ClearMsg;
    UpdateOffsetBar;
    ClearMsgAlt;
    UpdatePositionBar;
}

/**
 * Update the upper offset bar.
 */
void UpdateOffsetBar()
{
	SetPos(0, 0);
	write("Offset ");
	switch (CurrentOffsetType)
	{
		default: write("h ");
	        for (ushort i; i < BytesPerRow; ++i) writef(" %02X", i);
            break;
		case OffsetType.Decimal: write("d ");
	        for (ushort i; i < BytesPerRow; ++i) writef(" %02d", i);
            break;
		case OffsetType.Octal: write("o ");
	        for (ushort i; i < BytesPerRow; ++i) writef(" %02o", i);
            break;
	}
}

/// Update the bottom current position bar.
void UpdatePositionBar()
{
    SetPos(0, WindowHeight - 1);
    UpdatePositionBarRaw;
}

/// Used right after UpdateDisplay to not waste a cursor positioning call.
void UpdatePositionBarRaw()
{
    const float f = CurrentPosition;
    writef(" %7.3f%%", ((f + Buffer.length) / CurrentFile.size) * 100);
}

/// Prepare buffer according to console/term height
void PrepBuffer()
{
	const int h = WindowHeight - 2;
    const ulong fs = CurrentFile.size;
    const int bufs = h * BytesPerRow;
    Buffer = new ubyte[fs >= bufs ? bufs : cast(uint)fs];
}

private void ReadFile()
{
    CurrentFile.seek(CurrentPosition);
    CurrentFile.rawRead(Buffer);
}

/**
 * Goes to the specified position in the file.
 * Ignores some verification since this function is mostly used
 * by the program itself. (And we know what we're doing!)
 * Params: pos = New position.
 */
void Goto(long pos)
{
    if (Buffer.length < CurrentFile.size)
    {
        CurrentPosition = pos;
        RefreshDisplay;
        UpdatePositionBarRaw;
    }
    else
        MessageAlt("Navigation disabled, buffer too small.");
}

/**
 * Goto a position while checking bounds
 * Mostly used for user entered numbers.
 * Params: pos = New position
 */
void GotoC(long pos)
{
    if (pos + Buffer.length > CurrentFile.size)
        Goto(CurrentFile.size - Buffer.length);
    else
        Goto(pos);
}

/**
 * Parses the string as a long and navigates to the file location.
 * This function takes a few more steps to ensure the number is properly
 * formatted and isn't going off range.
 * Params: str = String as a number
 */
void GotoStr(string str)
{
    import Utils : unformat;
    long l;
    if (unformat(str, l)) {
        if (l >= 0 && l < CurrentFile.size - Buffer.length) {
            Goto(l);
            UpdateOffsetBar();
        } else {
            import std.format : format;
            MessageAlt(format("Range too far or negative: %d (%XH)", l, l));
        }
    } else {
		MessageAlt("Could not parse number");
    }
}

/// Update display from buffer
void UpdateDisplay()
{
    import core.stdc.string : memset;
    const size_t bl = Buffer.length;
    char[] data, ascii;
    SetPos(0, 1);
    switch (CurrentDisplayType) {
    default:
        data = new char[3 * BytesPerRow]; ascii = new char[BytesPerRow];
        memset(&data[0], ' ', data.length);
        for (int o; o < bl; o += BytesPerRow) {
            size_t m = o + BytesPerRow;

            if (m > bl) { // If new maximum is overflowing buffer length
                m = bl;
                const size_t ml = bl - o, dml = ml * 3;
                // Only clear what is necessary
                memset(&data[0] + dml, ' ', dml);
                memset(&ascii[0] + ml, ' ', ml);
            }

            switch (CurrentOffsetType) {
                default: writef("%08X ", o + CurrentPosition); break;
                case OffsetType.Decimal: writef("%08d ", o + CurrentPosition); break;
                case OffsetType.Octal:   writef("%08o ", o + CurrentPosition); break;
            }

            for (int i = o, di, ai; i < m; ++i, di += 3, ++ai) {
                data[di + 1] = ffupper(Buffer[i] & 0xF0);
                data[di + 2] = fflower(Buffer[i] &  0xF);
                ascii[ai] = FormatChar(Buffer[i]);
            }

            writefln("%s  %s", data, ascii);
        }
        break; // Default
    case DisplayType.Text:
        ascii = new char[BytesPerRow * 4];
        for (int o; o < bl; o += BytesPerRow) {
            size_t m = o + BytesPerRow;

            switch (CurrentOffsetType) {
                default: writef("%08X ", o + CurrentPosition); break;
                case OffsetType.Decimal: writef("%08d ", o + CurrentPosition); break;
                case OffsetType.Octal:   writef("%08o ", o + CurrentPosition); break;
            }

            for (int i = o, di, ai; i < m; ++i, di += 3, ++ai)
                ascii[ai] = FormatChar(Buffer[i]);
        }
        break; // Text
    case DisplayType.Hex:

        break; // Hex
    }
}

/// Refresh display
void RefreshDisplay()
{
    ReadFile();
    UpdateDisplay();
}

/**
 * Message once (upper bar)
 * Params: msg = Message string
 */
void Message(string msg)
{
    ClearMsg;
    SetPos(0, 0);
    write(msg);
}

/// Clear upper bar
void ClearMsg()
{
    SetPos(0, 0);
    writef("%*s", WindowWidth - 1, "");
}

/**
 * Message once (bottom bar)
 * Params: msg = Message string
 */
void MessageAlt(string msg)
{
    ClearMsgAlt;
    SetPos(0, WindowHeight - 1);
    write(msg);
}

/// Clear bottom bar
void ClearMsgAlt()
{
    SetPos(0, WindowHeight - 1);
    writef("%*s", WindowWidth - 1, "");
}

/// Print some file information at the bottom bar
void PrintFileInfo()
{
    import Utils : formatsize;
    import std.format : format;
    import std.file : getAttributes;
    import std.path : baseName;
    const uint a = getAttributes(Filepath);
    version (Windows)
    { import core.sys.windows.winnt; // FILE_ATTRIBUTE_*
        char[8] c;
        c[0] = a & FILE_ATTRIBUTE_READONLY ? 'r' : '-';
        c[1] = a & FILE_ATTRIBUTE_HIDDEN ? 'h' : '-';
        c[2] = a & FILE_ATTRIBUTE_SYSTEM ? 's' : '-';
        c[3] = a & FILE_ATTRIBUTE_ARCHIVE ? 'a' : '-';
        c[4] = a & FILE_ATTRIBUTE_TEMPORARY ? 't' : '-';
        c[6] = a & FILE_ATTRIBUTE_SPARSE_FILE ? 'S' : '-';
        c[5] = a & FILE_ATTRIBUTE_COMPRESSED ? 'c' : '-';
        c[7] = a & FILE_ATTRIBUTE_ENCRYPTED ? 'e' : '-';
    }
    else version (Posix)
    { import core.sys.posix.sys.stat;
        char[10] c;
        c[0] = a & S_IRUSR ? 'r' : '-';
        c[1] = a & S_IWUSR ? 'w' : '-';
        c[2] = a & S_IXUSR ? 'x' : '-';
        c[3] = a & S_IRGRP ? 'r' : '-';
        c[4] = a & S_IWGRP ? 'w' : '-';
        c[5] = a & S_IXGRP ? 'x' : '-';
        c[6] = a & S_IROTH ? 'r' : '-';
        c[7] = a & S_IWOTH ? 'w' : '-';
        c[8] = a & S_IXOTH ? 'x' : '-';
        c[9] = a & S_ISVTX ? 't' : '-';
    }
    MessageAlt(format("%s  %s  %s",
        c, // File attributes symbolic representation
        formatsize(CurrentFile.size), // File formatted size
        baseName(Filepath))
    );
}

/// Exits ddhx
void Exit()
{
    import core.stdc.stdlib : exit;
    Clear();
    exit(0);
}

/**
 * Fast hex format higher nibble
 * Params: b = Byte
 * Returns: Hex character
 */
private char ffupper(ubyte b) pure @safe @nogc
{
    final switch (b)
    {
        case 0:    return '0';
        case 0x10: return '1';
        case 0x20: return '2';
        case 0x30: return '3';
        case 0x40: return '4';
        case 0x50: return '5';
        case 0x60: return '6';
        case 0x70: return '7';
        case 0x80: return '8';
        case 0x90: return '9';
        case 0xA0: return 'A';
        case 0xB0: return 'B';
        case 0xC0: return 'C';
        case 0xD0: return 'D';
        case 0xE0: return 'E';
        case 0xF0: return 'F';
    }
}

/**
 * Fast hex format lower nibble
 * Params: b = Byte
 * Returns: Hex character
 */
private char fflower(ubyte b) pure @safe @nogc
{
    final switch (b)
    {
        case 0:   return '0';
        case 1:   return '1';
        case 2:   return '2';
        case 3:   return '3';
        case 4:   return '4';
        case 5:   return '5';
        case 6:   return '6';
        case 7:   return '7';
        case 8:   return '8';
        case 9:   return '9';
        case 0xA: return 'A';
        case 0xB: return 'B';
        case 0xC: return 'C';
        case 0xD: return 'D';
        case 0xE: return 'E';
        case 0xF: return 'F';
    }
}

pragma(inline, true):
private char FormatChar(ubyte c) pure @safe @nogc
{
    return c > 0x7E || c < 0x20 ? '.' : c;
}