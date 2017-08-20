module ddhx;

import std.stdio;
import core.stdc.stdio : printf;
import Menu;
import ddcon;

//TODO: Bookmarks page (What shortcut or function key?)
//TODO: Tabs? (Probably not)

/// App version
enum APP_VERSION = "0.0.0-*";

/// Offset type (hex, dec, etc.)
enum OffsetType {
	Hexadecimal, Decimal, Octal
}

//TODO: PureText (does not align with offset bar)
//TODO: PureData (does not align with offset bar)
/// 
enum DisplayMode {
    Default, Text, Data
}

enum DEFAULT_CHAR = '.'; /// Default non-ASCII character

/*
 * User settings
 */

ushort BytesPerRow = 16; /// Bytes shown per row
OffsetType CurrentOffsetType; /// Current offset view type
DisplayMode CurrentDisplayMode; /// Current display view type

/*
 * Internal
 */

int LastErrorCode; /// Last error code to report
string Filepath; /// Current file path
File CurrentFile; /// Current file handle
long CurrentPosition; /// Current file position
ubyte[] Buffer; /// Display buffer
long fsize; /// File size, used to avoid spamming system functions
string tfsize; /// total formatted size

//TODO: When typing g goto menu directly
//      - Tried writing to stdin directly, crashes (2.074.0)

/// Main ddhx entry point past CLI.
void Start()
{
    import Utils : formatsize;
    fsize = CurrentFile.size;
    tfsize = formatsize(fsize);
	InitConsole;
	PrepBuffer;
    if (fsize > 0)
	    ReadFile;
    Clear;
	UpdateOffsetBar;
	UpdateDisplayRaw;
    UpdateInfoBarRaw;

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
    import SettingHandler : HandleWidth;
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
        if (CurrentPosition + bs + BytesPerRow <= fsize)
            Goto(CurrentPosition + BytesPerRow);
        else
            Goto(fsize - bs);
        break;
    case Key.LeftArrow:
        if (CurrentPosition - 1 >= 0) // Else already at 0
            Goto(CurrentPosition - 1);
        break;
    case Key.RightArrow:
        if (CurrentPosition + bs + 1 <= fsize)
            Goto(CurrentPosition + 1);
        else
            Goto(fsize - bs);
        break;
    case Key.PageUp:
        if (CurrentPosition - cast(long)bs >= 0)
            Goto(CurrentPosition - bs);
        else
            Goto(0);
        break;
    case Key.PageDown:
        if (CurrentPosition + bs + bs <= fsize)
            Goto(CurrentPosition + bs);
        else
            Goto(fsize - bs);
        break;

    case Key.Home:
        if (k.ctrl)
            Goto(0);
        else
            Goto(CurrentPosition - (CurrentPosition % BytesPerRow));
        break;
    case Key.End:
        if (k.ctrl)
            Goto(fsize - bs);
        else
        {
            const long np = CurrentPosition +
                (BytesPerRow - CurrentPosition % BytesPerRow);

            if (np + bs <= fsize)
                Goto(np);
            else
                Goto(fsize - bs);
        }
        break;

    /*
     * Actions/Shortcuts
     */

    case Key.Escape, Key.Enter:
        EnterMenu();
        break;
    /*case Key.G:
        EnterMenu("g");
        UpdateOffsetBar();
        break;*/
    case Key.I:
        PrintFileInfo;
        break;
    case Key.R, Key.F5:
        Clear;
        UpdateOffsetBar;
        UpdateDisplayRaw;
        UpdateInfoBarRaw;
        break;
    case Key.A:
        HandleWidth("a");
        PrepBuffer;
        ReadFile;
        Clear;
        UpdateOffsetBar;
        UpdateDisplayRaw;
        UpdateInfoBarRaw;
        break;
    case Key.H: ShowHelp; break;
    case Key.Q: Exit; break;
    default:
    }
}

/// Refresh the entire screen
void RefreshAll() {
    Clear;
    ReadFile;
    UpdateOffsetBar;
    UpdateDisplayRaw;
    UpdateInfoBarRaw;
    /*RefreshDisplay;
    ClearMsg;
    UpdateOffsetBar;
    ClearMsgAlt;
    UpdateInfoBar;*/
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
	        for (ushort i; i < BytesPerRow; ++i) printf(" %02X", i);
            break;
		case OffsetType.Decimal: write("d ");
	        for (ushort i; i < BytesPerRow; ++i) printf(" %02d", i);
            break;
		case OffsetType.Octal: write("o ");
	        for (ushort i; i < BytesPerRow; ++i) printf(" %02o", i);
            break;
	}
    writeln; // In case of "raw" function being called
}

/// Update the bottom current information bar.
void UpdateInfoBar()
{
    SetPos(0, WindowHeight - 1);
    UpdateInfoBarRaw;
}

/// Updates information bar without cursor position call.
void UpdateInfoBarRaw()
{
    import Utils : formatsize;
    const size_t bufs = Buffer.length;
    const float f = CurrentPosition; // Converts to float implicitly
    writef(" %*s | %*s/%*s | %7.3f%%",
        7, formatsize(bufs),             // Buffer size
        10, formatsize(CurrentPosition), // Formatted position
        10, tfsize,                      // Total file size
        ((f + bufs) / fsize) * 100       // Pos/filesize%
    );
}

/// Prepare buffer according to console/term height
void PrepBuffer()
{
	const int h = WindowHeight - 2;
    const int bufs = h * BytesPerRow; // Proposed buffer size
    Buffer = new ubyte[fsize >= bufs ? bufs : cast(uint)fsize];
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
    if (Buffer.length < fsize)
    {
        CurrentPosition = pos;
        RefreshDisplay;
        UpdateInfoBarRaw;
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
    if (pos + Buffer.length > fsize)
        Goto(fsize - Buffer.length);
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
        if (l >= 0 && l < fsize - Buffer.length) {
            Goto(l);
            UpdateOffsetBar;
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
    SetPos(0, 1);
    UpdateDisplayRaw;
}

/// Update display from buffer without setting cursor
void UpdateDisplayRaw()
{
    import core.stdc.string : memset;
    const size_t bl = Buffer.length;
    char[] data, ascii;
    switch (CurrentDisplayMode) {
    default:
        data = new char[3 * BytesPerRow];
        ascii = new char[BytesPerRow];
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
                default: printf("%08X ", o + CurrentPosition); break;
                case OffsetType.Decimal: printf("%08d ", o + CurrentPosition); break;
                case OffsetType.Octal:   printf("%08o ", o + CurrentPosition); break;
            }

            for (int i = o, di, ai; i < m; ++i, di += 3, ++ai) {
                data[di + 1] = ffupper(Buffer[i] & 0xF0);
                data[di + 2] = fflower(Buffer[i] &  0xF);
                ascii[ai] = FormatChar(Buffer[i]);
            }

            printf("%s  %s\n", &data[0], &ascii[0]);
        }
        break; // Default
    case DisplayMode.Text:
        ascii = new char[BytesPerRow * 3];
        for (int o; o < bl; o += BytesPerRow) {
            size_t m = o + BytesPerRow;
            
            if (m > bl) { // If new maximum is overflowing buffer length
                m = bl;
                const size_t ml = bl - o;
                // Only clear what is necessary
                memset(&ascii[0] + ml, ' ', ml);
            }

            switch (CurrentOffsetType) {
                default: printf("%08X  ", o + CurrentPosition); break;
                case OffsetType.Decimal: printf("%08d  ", o + CurrentPosition); break;
                case OffsetType.Octal:   printf("%08o  ", o + CurrentPosition); break;
            }

            for (int i = o, di = 1; i < m; ++i, di += 3)
                ascii[di] = FormatChar(Buffer[i]);
            
            printf("%s\n", &ascii[0]);
        }
        break; // Text
    case DisplayMode.Data:
        data = new char[3 * BytesPerRow];

        for (int o; o < bl; o += BytesPerRow) {
            size_t m = o + BytesPerRow;

            if (m > bl) { // If new maximum is overflowing buffer length
                m = bl;
                const size_t ml = bl - o, dml = ml * 3;
                // Only clear what is necessary
                memset(&data[0] + dml, ' ', dml);
            }

            switch (CurrentOffsetType) {
                default: printf("%08X ", o + CurrentPosition); break;
                case OffsetType.Decimal: printf("%08d ", o + CurrentPosition); break;
                case OffsetType.Octal:   printf("%08o ", o + CurrentPosition); break;
            }

            for (int i = o, di, ai; i < m; ++i, di += 3, ++ai) {
                data[di + 1] = ffupper(Buffer[i] & 0xF0);
                data[di + 2] = fflower(Buffer[i] &  0xF);
            }

            printf("%s\n", &data[0]);
        }
        break; // Hex
    }
}

/// Refresh display
void RefreshDisplay()
{
    ReadFile;
    UpdateDisplay;
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
    writef("%*s", WindowWidth - 1, " ");
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
    writef("%*s", WindowWidth - 1, " ");
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
    { import core.sys.windows.winnt : // FILE_ATTRIBUTE_*
            FILE_ATTRIBUTE_READONLY, FILE_ATTRIBUTE_HIDDEN, FILE_ATTRIBUTE_SYSTEM,
            FILE_ATTRIBUTE_ARCHIVE, FILE_ATTRIBUTE_TEMPORARY, FILE_ATTRIBUTE_TEMPORARY,
            FILE_ATTRIBUTE_SPARSE_FILE, FILE_ATTRIBUTE_COMPRESSED, FILE_ATTRIBUTE_ENCRYPTED;
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
    { import core.sys.posix.sys.stat : S_ISVTX,
            S_IRUSR, S_IWUSR, S_IXUSR,
            S_IRGRP, S_IWGRP, S_IXGRP,
            S_IROTH, S_IWOTH, S_IXOTH;
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
        formatsize(fsize), // File formatted size
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

/**
 * Converts an unsigned byte to an ASCII character. If the byte is outside of
 * the ASCII range, DEFAULT_CHAR will be returned.
 * Params: c = Unsigned byte
 * Returns: ASCII character
 */
pragma(inline, true):
private char FormatChar(ubyte c) pure @safe @nogc
{
    return c > 0x7E || c < 0x20 ? DEFAULT_CHAR : c;
}