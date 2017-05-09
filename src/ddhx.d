module ddhx;

import std.stdio, std.file : exists;
import std.format : format;
import Menu;
import Poshub;

debug enum APP_VERSION = "0.0.0-debug";
else  enum APP_VERSION = "0.0.0";

enum OffsetType {
	Hexadecimal, Decimal, Octal
}

/*
 * User settings
 */

ushort BytesPerRow = 16;
OffsetType CurrentOffset;

/*
 * Internal
 */

bool Echo;
string Filepath;
File CurrentFile;
int LastErrorCode;
long CurrentPosition;
ubyte[] Buffer;

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
		const KeyInfo k = ReadKey;
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

            case Key.End:
                if (k.ctrl)
                    Goto(fs - bs);
                else
                {
                    long np = CurrentPosition +
                        (BytesPerRow - CurrentPosition % BytesPerRow);

                    if (np + bs <= fs)
                        Goto(np);
                    else
                        Goto(fs - bs);
                }
                break;
            case Key.Home:
                if (k.ctrl)
                    Goto(0);
                else
                    Goto(CurrentPosition - (CurrentPosition % BytesPerRow));
                break;

            /*
             * Actions/Shortcuts
             */

            case Key.F5:
                RefreshDisplay();
                break;
            case Key.Escape, Key.Enter:
                EnterMenu();
                break;
            case Key.G:
                /*EnterMenu("g");
                UpdateOffsetBar();*/
                break;
            case Key.H:
                ShowHelp;
                break;
            case Key.Q: Exit(); break;
			default:
		}
	}
}

void UpdateOffsetBar()
{
	SetPos(0, 0);
	write("Offset ");
	switch (CurrentOffset)
	{
		default:
            write("h ");
	        for (ushort i; i < BytesPerRow; ++i)
                writef(" %02X", i);
            break;
		case OffsetType.Decimal:
            write("d ");
	        for (ushort i; i < BytesPerRow; ++i)    
                writef(" %02d", i);
            break;
		case OffsetType.Octal:
            write("o ");
	        for (ushort i; i < BytesPerRow; ++i)
                writef(" %02o", i);
            break;
	}
}

void UpdatePositionBar()
{
    SetPos(0, WindowHeight - 1);
    float f = CurrentPosition;
    f = ((f + Buffer.length) / CurrentFile.size) * 100;
    writef(" HEX:%08X | DEC:%08d | OCT:%08o | %7.3f%%",
        CurrentPosition, CurrentPosition, CurrentPosition, f);
}

private void PrepBuffer()
{
	int h = WindowHeight - 2;
    ulong fs = CurrentFile.size;
    int bufs = h * BytesPerRow;
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
 * Param: pos = New position.
 */
void Goto(long pos)
{
    if (Buffer.length < CurrentFile.size)
    {
        CurrentPosition = pos;
        RefreshDisplay();
        UpdatePositionBar();
    }
    else
        Message("Navigation disabled, buffer too small.");
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
    }
}

void UpdateDisplay()
{
    import core.stdc.string : memset;
    const size_t bl = Buffer.length;
    char[] data = new char[3 * BytesPerRow], ascii = new char[BytesPerRow];
    memset(&data[0], ' ', data.length);
    SetPos(0, 1);
    for (int o; o < bl; o += BytesPerRow)
    {
        size_t m = o + BytesPerRow;

        if (m > bl) { // If new maximum is overflowing
            m = bl;
            const size_t ml = bl - o, dml = ml * 3;
            // Only clear what is necessary
            memset(&data[0] + dml, ' ', dml);
            memset(&ascii[0] + ml, ' ', ml);
        }

        switch (CurrentOffset)
        {
            default: writef("%08X ", o + CurrentPosition); break;
            case OffsetType.Decimal: writef("%08d ", o + CurrentPosition); break;
            case OffsetType.Octal:   writef("%08o ", o + CurrentPosition); break;
        }

        for (int i = o, di, ai; i < m; ++i, di += 3, ++ai) {
            data[di + 1] = ffupper(Buffer[i] & 0xF0);
            data[di + 2] = fflower(Buffer[i] &  0xF);
            ascii[ai] = FormatChar(Buffer[i]);
        }

        writeln(data, "  ", ascii);
    }
}

void ClearDisplay()
{
    import core.stdc.string : memset;
    SetPos(0, 0);
    int h = WindowHeight;
    char[] s = new char[WindowWidth];
    memset(&s[0], ' ', s.length);
    for(int i; i < h; ++i)
        writeln(s);
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

private char FormatChar(ubyte c) pure @safe @nogc
{
    return c > 0x7E || c < 0x20 ? '.' : c;
}

void RefreshDisplay()
{
    ReadFile();
    UpdateDisplay();
}

void Message(string msg)
{
    ClearMsg();
    SetPos(0, 0);
    write(msg);
}

void MessageAlt(string msg)
{
    ClearMsgAlt();
    SetPos(0, WindowHeight - 1);
    write(msg);
}

void ClearMsg()
{
    SetPos(0, 0);
    writef("%*s", WindowWidth, "");
}

void ClearMsgAlt()
{
    SetPos(0, WindowHeight - 1);
    writef("%*s", WindowWidth, "");
}

void Exit()
{
    import core.stdc.stdlib : exit;
    Clear();
    exit(0);
}