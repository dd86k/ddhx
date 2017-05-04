module ddhx;

import std.stdio, std.file : exists;
import std.format : format;
import std.conv : parse, ConvException;
import Menu;
import Poshub;

enum OffsetType {
	Hexadecimal, Decimal, Octal
}

/*
 * User settings
 */

ushort BytesPerRow = 16;
OffsetType CurrentOffset;
bool Base10;

/*
 * Internal
 */

string Filepath;
File CurrentFile;
int LastErrorCode;
private long CurrentPosition;
private ubyte[] Buffer;

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
		KeyInfo k = ReadKey;
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
                UpdateOffsetBar();
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
		default: write("h "); break;
		Decimal: write("d "); break;
		Octal:   write("o "); break;
	}
	for (ushort i; i < BytesPerRow; ++i) writef(" %02X", i);
}

void PrepBuffer()
{
	int h = WindowHeight - 2;
    ulong fs = CurrentFile.size;
    int bufs = h * BytesPerRow;
    Buffer = new ubyte[fs >= bufs ? bufs : cast(uint)fs];
}

void ReadFile()
{
    CurrentFile.seek(CurrentPosition);
    CurrentFile.rawRead(Buffer);
}

void Goto(long pos)
{
    if (Buffer.length < CurrentFile.size)
    {
        if (pos >= 0)
        {
            CurrentPosition = pos;
            RefreshDisplay();
            UpdatePositionBar();
        }
        else Message(format("Out of range : %d", pos));
    }
    else
        Message("Navigation disabled, buffer too small.");
}

void GotoStr(string str)
{
    try
    {
        Goto(parse!long(str));
        UpdateOffsetBar();
    }
    catch (ConvException)
    {
        Message("Failed to parse number.");
    }
}

void UpdateDisplay()
{
    import core.stdc.string : memset;
    int bl = cast(int)Buffer.length;
    char[] data = new char[3 * BytesPerRow], ascii = new char[BytesPerRow];
    memset(&data[0], ' ', data.length);
    SetPos(0, 1);
    for (int o; o < bl; o += BytesPerRow)
    {
        int m = o + BytesPerRow;

        if (m > bl) { // If new maximum is overflowing
            m = bl;
            const int ml = bl - o, dml = ml * 3;
            // Only clear what is necessary
            memset(&data[0] + dml, ' ', dml);
            memset(&ascii[0] + ml, ' ', ml);
        }

        switch (CurrentOffset)
        {
            default: writef("%08X ", o + CurrentPosition); break;
            Decimal: writef("%08d ", o + CurrentPosition); break;
            Octal:   writef("%08o ", o + CurrentPosition); break;
        }

        for (int i = o, di, ai; i < m; ++i, di += 3, ++ai) {
            data[di + 1] = ffupper(Buffer[i] & 0xF0);
            data[di + 2] = fflower(Buffer[i] &  0xF);
            ascii[ai] = FormatChar(Buffer[i]);
        }

        writeln(data, "  ", ascii);
    }
}

/**
 * Fast hex format higher nibble
 * Params: b = Byte
 * Returns: Hex character
 */
char ffupper(ubyte b) pure @safe @nogc
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
char fflower(ubyte b) pure @safe @nogc
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

char FormatChar(ubyte c) pure @safe @nogc
{
    return c < 0x20 || c > 0x7E ? '.' : c;
}

void UpdatePositionBar()
{
    SetPos(0, WindowHeight - 1);
    float f = CurrentPosition;
    f = ((f + Buffer.length) / CurrentFile.size) * 100;
    writef(" HEX:%08X | DEC:%08d | OCT:%08o | %.3f%%",
        CurrentPosition, CurrentPosition, CurrentPosition, f);
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
    writef("%*s", WindowWidth - 1, "");
}

void ClearMsgAlt()
{
    SetPos(0, WindowHeight - 1);
    writef("%*s", WindowWidth - 1, "");
}

void ShowAbout()
{
    MessageAlt("Written by dd86k. Copyright (c) 2017 dd86k");
}

void Exit()
{
    import core.stdc.stdlib : exit;
    Clear();
    exit(0);
}