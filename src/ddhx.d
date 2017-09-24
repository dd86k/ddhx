module ddhx;

import std.stdio : File, write, writef;
import core.stdc.stdio : printf;
import core.stdc.stdlib : malloc, free;
import core.stdc.string : memset;
import Menu;
import ddcon;

//TODO: Bookmarks page? (What shortcut or function key?)

/// App version
enum APP_VERSION = "0.0.0-2";

/// Offset type (hex, dec, etc.)
enum OffsetType : ubyte {
	Hexadecimal, Decimal, Octal
}

/// 
enum DisplayMode : ubyte {
    Default, Text, Data
}

enum DEFAULT_CHAR = '.'; /// Default character for non-displayable characters

/*
 * User settings
 */

ushort BytesPerRow = 16; /// Bytes shown per row
OffsetType CurrentOffsetType; /// Current offset view type
DisplayMode CurrentDisplayMode; /// Current display view type

/*
 * Internal
 */

File CurrentFile; /// Current file handle
long CurrentPosition; /// Current file position
ubyte[] Buffer; /// Display buffer
size_t BufferLength; /// Buffer length
long fsize; /// File size, used to avoid spamming system functions
string tfsize; /// total formatted size

//TODO: When typing g goto menu directly
//      - Tried writing to stdin directly, crashes (2.074.0)

/// Main app entry point
void Start()
{
    import Utils : formatsize;
    tfsize = formatsize(fsize);
	InitConsole;
	PrepBuffer;
    ReadFile;
    Clear;
	UpdateOffsetBar;
	UpdateDisplayRaw;
    UpdateInfoBarRaw;

	while (1)
	{
        const KeyInfo g = ReadKey;
        //TODO: Handle resize event
        HandleKey(&g);
	}
}

/*void HandleMouse(const MouseInfo* mi)
{
    size_t bs = BufferLength;

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
    alias bs = BufferLength;

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
        EnterMenu;
        break;
    /*case Key.G:
        EnterMenu("g");
        UpdateOffsetBar();
        break;*/
    case Key.I:
        PrintFileInfo;
        break;
    case Key.R, Key.F5:
        RefreshAll;
        break;
    case Key.A:
        HandleWidth("a");
        RefreshAll;
        break;
    case Key.Q: Exit; break;
    default:
    }
}

/// Refresh the entire screen
void RefreshAll() {
    PrepBuffer;
    Clear;
    CurrentFile.seek(CurrentPosition);
    ReadFile;
    UpdateOffsetBar;
    UpdateDisplayRaw;
    UpdateInfoBarRaw;
}

/**
 * Update the upper offset bar.
 */
void UpdateOffsetBar()
{
	SetPos(0, 0);
	printf("Offset ");
	final switch (CurrentOffsetType)
	{
		case OffsetType.Hexadecimal: printf("h ");
	        for (ushort i; i < BytesPerRow; ++i) printf(" %02X", i);
            break;
		case OffsetType.Decimal: printf("d ");
	        for (ushort i; i < BytesPerRow; ++i) printf(" %02d", i);
            break;
		case OffsetType.Octal: printf("o ");
	        for (ushort i; i < BytesPerRow; ++i) printf(" %02o", i);
            break;
	}
    printf("\n"); // In case of "raw" function being called afterwards
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
    const float f = CurrentPosition; // Converts to float implicitly
    printf(" %*s | %*s/%*s | %7.3f%%",
        7, &formatsize(BufferLength)[0],     // Buffer size
        10, &formatsize(CurrentPosition)[0], // Formatted position
        10, &tfsize[0],                      // Total file size
        ((f + BufferLength) / fsize) * 100   // Pos/filesize%
    );
}

/// Prepare buffer according to console/term height
void PrepBuffer()
{
    const int bufs = (WindowHeight - 2) * BytesPerRow; // Proposed buffer size
    Buffer = new ubyte[fsize >= bufs ? bufs : cast(uint)fsize];
    BufferLength = bufs;
}

private void ReadFile()
{
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
    if (BufferLength < fsize)
    {
        CurrentFile.seek(CurrentPosition = pos);
        ReadFile;
        UpdateDisplay;
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
    if (pos + BufferLength > fsize)
        Goto(fsize - BufferLength);
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
        if (l >= 0 && l < fsize - BufferLength) {
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
    const int ds = (3 * BytesPerRow) + 1;
    const int as = BytesPerRow + 1;
    ubyte* bufp = &Buffer[0];
    char* data, ascii; // Buffers
    long p = CurrentPosition;

    final switch (CurrentDisplayMode) {
    case DisplayMode.Default:
        data = cast(char*)malloc(ds);
        ascii = cast(char*)malloc(as);
        memset(data, ' ', ds);
        memset(ascii, ' ', as);
        *(data + ds - 1) = '\0';
        *(ascii + as - 1) = '\0';
        for (int bi; bi < BufferLength; p += BytesPerRow) {
            final switch (CurrentOffsetType) {
                case OffsetType.Hexadecimal: printf("%08X ", p); break;
                case OffsetType.Decimal: printf("%08d ", p); break;
                case OffsetType.Octal:   printf("%08o ", p); break;
            }

            if ((bi += BytesPerRow) > BufferLength) {
                const ulong max = BufferLength - (bi - BytesPerRow);
                for (int i, a; a < max; i += 3, ++a) {
                    *(data + i + 1) = ffupper(*bufp & 0xF0);
                    *(data + i + 2) = fflower(*bufp   &  0xF);
                    *(ascii + a) = FormatChar(*bufp);
                    ++bufp;
                }
                *(data + (max * 3)) = '\0';
                *(ascii + max) = '\0';
                printf("%s  %s\n", data, ascii);
                free(ascii);
                free(data);
                return;
            } else {
                for (int i, a; a < BytesPerRow; i += 3, ++a) {
                    *(data + i + 1) = ffupper(*bufp & 0xF0);
                    *(data + i + 2) = fflower(*bufp   &  0xF);
                    *(ascii + a) = FormatChar(*bufp);
                    ++bufp;
                } 
            }
            printf("%s  %s\n", data, ascii);
        }
        free(ascii);
        free(data);
        break; // Default
    case DisplayMode.Text:
        ascii = cast(char*)malloc(BytesPerRow * 3);
        ascii[as - 1] = '\0';
        for (int o; o < BufferLength; o += BytesPerRow, p += CurrentPosition) {
            size_t m = o + BytesPerRow;

            if (m > BufferLength) { // If new maximum is overflowing buffer length
                m = BufferLength;
                const size_t ml = BufferLength - o;
                // Only clear what is necessary
                memset(&ascii[0] + ml, ' ', ml);
            }

            final switch (CurrentOffsetType) {
                case OffsetType.Hexadecimal: printf("%08X  ", p); break;
                case OffsetType.Decimal: printf("%08d  ", p); break;
                case OffsetType.Octal:   printf("%08o  ", p); break;
            }

            for (int i = o, di = 1; i < m; ++i, di += 3) {
                ascii[di] = FormatChar(*bufp);
                ++bufp;
            }

            printf("%s\n", ascii);
        }
        free(ascii);
        break; // Text
    case DisplayMode.Data:
        data = cast(char*)malloc(3 * BytesPerRow);
        data[ds] = '\0';
        for (int o; o < BufferLength; o += BytesPerRow, p += CurrentPosition) {
            size_t m = o + BytesPerRow;

            if (m > BufferLength) { // If new maximum is overflowing buffer length
                m = BufferLength;
                const size_t ml = BufferLength - o, dml = ml * 3;
                // Only clear what is necessary
                memset(&data[0] + dml, ' ', dml);
            }

            final switch (CurrentOffsetType) {
                case OffsetType.Hexadecimal: printf("%08X ", p); break;
                case OffsetType.Decimal: printf("%08d ", p); break;
                case OffsetType.Octal:   printf("%08o ", p); break;
            }

            for (int i = o, di, ai; i < m; ++i, di += 3, ++ai) {
                data[di] = ' ';
                data[di + 1] = ffupper(Buffer[i] & 0xF0);
                data[di + 2] = fflower(Buffer[i] &  0xF);
            }

            printf("%s\n", data);
        }
        free(data);
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
    import std.path : baseName;
    MessageAlt(format("%s  %s",
        formatsize(fsize), // File formatted size
        baseName(CurrentFile.name))
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
    final switch (b) {
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
    final switch (b) {
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
 * the ASCII range, $(D DEFAULT_CHAR) will be returned.
 * Params: c = Unsigned byte
 * Returns: ASCII character
 */
char FormatChar(ubyte c) pure @safe @nogc nothrow
{
    //TODO: EIBEC
    return c > 0x7E || c < 0x20 ? DEFAULT_CHAR : c;
}