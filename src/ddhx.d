module ddhx;

import std.stdio : File, write, writef;
import core.stdc.stdio : printf, puts;
import core.stdc.stdlib;
import core.stdc.string : memset;
import Menu;
import ddcon;

/// App version
enum APP_VERSION = "0.1.0";

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

__gshared ushort BytesPerRow = 16; /// Bytes shown per row
__gshared OffsetType CurrentOffsetType; /// Current offset view type
__gshared DisplayMode CurrentDisplayMode; /// Current display view type

/*
 * Internal
 */

__gshared File CurrentFile; /// Current file handle
__gshared long CurrentPosition; /// Current file position
__gshared ubyte[] Buffer; /// Display buffer
__gshared size_t BufferLength; /// Buffer length
__gshared long fsize; /// File size, cached to avoid spamming system functions
__gshared string tfsize; /// total formatted size

/// Main app entry point
void Start()
{
    import Utils : formatsize;
    tfsize = formatsize(fsize);
	InitConsole;
	PrepBuffer;
    Read;
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
extern (C)
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
    case Key.G:
        EnterMenu("g ");
        UpdateOffsetBar();
        break;
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
extern (C)
void RefreshAll() {
    PrepBuffer;
    Clear;
    CurrentFile.seek(CurrentPosition);
    Read;
    UpdateOffsetBar;
    UpdateDisplayRaw;
    UpdateInfoBarRaw;
}

/**
 * Update the upper offset bar.
 */
extern (C)
void UpdateOffsetBar()
{
	SetPos(0, 0);
	printf("Offset ");
    ushort i;
	final switch (CurrentOffsetType)
	{
		case OffsetType.Hexadecimal: printf("h ");
	        for (; i < BytesPerRow; ++i) printf(" %02X", i);
            break;
		case OffsetType.Decimal: printf("d ");
	        for (; i < BytesPerRow; ++i) printf(" %02d", i);
            break;
		case OffsetType.Octal: printf("o ");
	        for (; i < BytesPerRow; ++i) printf(" %02o", i);
            break;
	}
    printf("\n");
}

/// Update the bottom current information bar.
extern (C)
void UpdateInfoBar()
{
    SetPos(0, WindowHeight - 1);
    UpdateInfoBarRaw;
}

/// Updates information bar without cursor position call.
extern (C)
void UpdateInfoBarRaw()
{
    import Utils : formatsize;
    printf(" %*s | %*s/%*s | %7.3f%%",
        7,  cast(char*)formatsize(BufferLength),    // Buffer size
        10, cast(char*)formatsize(CurrentPosition), // Formatted position
        10, cast(char*)tfsize,                      // Total file size
        ((cast(float)CurrentPosition + BufferLength) / fsize) * 100   // Pos/filesize%
    );
}

/// Prepare buffer and pre-bake some variables
extern (C)
void PrepBuffer()
{
    const int bufs = (WindowHeight - 2) * BytesPerRow; // Proposed buffer size
    Buffer = new ubyte[fsize >= bufs ? bufs : cast(uint)fsize];
    BufferLength = bufs;

    const int ds = (3 * BytesPerRow) + 1; // data size
    const int as = BytesPerRow + 1; // ascii size
    data = cast(char*)realloc(data, ds);
    ascii = cast(char*)realloc(ascii, as);
    memset(data, ' ', ds); // avoids setting space manually everytime later
    data[ds - 1] = ascii[as - 1] = '\0';
}

/**
 * Read file and full buffer.
 */
extern (C)
private void Read()
{
    CurrentFile.rawRead(Buffer);
}

/**
 * Goes to the specified position in the file.
 * Ignores bounds checking for performance reasons.
 * Sets CurrentPosition.
 * Params: pos = New position
 */
extern (C)
void Goto(long pos)
{
    if (BufferLength < fsize)
    {
        CurrentFile.seek(CurrentPosition = pos);
        Read;
        UpdateDisplay;
        UpdateInfoBarRaw;
    }
    else
        MessageAlt("Navigation disabled, buffer too small.");
}

/**
 * Goes to the specified position in the file.
 * Checks bounds and calls Goto.
 * Params: pos = New position
 */
extern (C)
void GotoC(long pos)
{
    if (pos + BufferLength > fsize)
        Goto(fsize - BufferLength);
    else
        Goto(pos);
}

/**
 * Parses the string as a long and navigates to the file location.
 * Includes offset checking (+/- notation).
 * Params: str = String as a number
 */
void GotoStr(string str)
{
    import Utils : unformat;
    byte rel; // Lazy code
    if (str[0] == '+') {
        rel = 1;
        str = str[1..$];
    } else if (str[0] == '-') {
        rel = 2;
        str = str[1..$];
    }
    long l;
    if (unformat(str, l)) {
        switch (rel) {
        case 1:
            if (CurrentPosition + l - BufferLength < fsize)
                Goto(CurrentPosition + l);
            break;
        case 2:
            if (CurrentPosition - l >= 0)
                Goto(CurrentPosition - l);
            break;
        default:
            if (l >= 0 && l < fsize - BufferLength) {
                Goto(l);
            } else {
                import std.format : format;
                MessageAlt(format("Range too far or negative: %d (%XH)", l, l));
            }
        }
    } else {
		MessageAlt("Could not parse number");
    }
}

/// Update display from buffer
extern (C)
void UpdateDisplay()
{
    SetPos(0, 1);
    UpdateDisplayRaw;
}

private __gshared char* data, ascii; /// Temporary buffer

/// Update display from buffer without setting cursor
extern (C)
void UpdateDisplayRaw()
{
    ubyte* bufp = cast(ubyte*)Buffer;
    long p = CurrentPosition;
    long pmax = CurrentPosition + BufferLength;

    for (; p < pmax; p += BytesPerRow) {
        final switch (CurrentOffsetType) {
        case OffsetType.Hexadecimal: printf("%08X ", p); break;
        case OffsetType.Decimal: printf("%08d ", p); break;
        case OffsetType.Octal: printf("%08o ", p); break;
        }

        int i, a; // inits to 0

        if (p > pmax) { // over buffer
            const int max = cast(int)(pmax - (p - BytesPerRow));
            for (; a < max; i += 3, ++a, ++bufp) {
                data[i + 1] = ffupper(*bufp & 0xF0);
                data[i + 2] = fflower(*bufp & 0xF);
                ascii[a] = FormatChar(*bufp);
            }
            data[max * 3] = ascii[max] = '\0';
            printf("%s  %s\n", data, ascii);
            return;
        } else {
            for (; a < BytesPerRow; i += 3, ++a, ++bufp) {
                data[i + 1] = ffupper(*bufp & 0xF0);
                data[i + 2] = fflower(*bufp & 0xF);
                ascii[a] = FormatChar(*bufp);
            }
        }
        printf("%s  %s\n", data, ascii);
    }
}

/// Refresh display
extern (C)
void RefreshDisplay()
{
    Read;
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
extern (C)
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
extern (C)
void ClearMsgAlt()
{
    SetPos(0, WindowHeight - 1);
    writef("%*s", WindowWidth - 1, " ");
}

/// Print some file information at the bottom bar
extern (C)
void PrintFileInfo()
{
    import Utils : formatsize;
    import std.format : format;
    import std.path : baseName;
    MessageAlt(format("%s  %s",
        tfsize,
        baseName(CurrentFile.name))
    );
}

/// Exits ddhx
extern (C)
void Exit()
{
    import core.stdc.stdlib : exit;
    free(ascii); // for good measure
    free(data); // ditto
    Clear();
    exit(0);
}

/**
 * Fast hex format higher nibble
 * Params: b = Byte
 * Returns: Hex character
 */
extern (C)
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
extern (C)
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
extern (C)
char FormatChar(ubyte c) pure @safe @nogc nothrow
{
    //TODO: EIBEC
    return c > 0x7E || c < 0x20 ? DEFAULT_CHAR : c;
}