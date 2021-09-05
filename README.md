# ddhx, Interactive Hexadecimal File Viewer

```
Offset h  00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F
00000000  4D 5A 78 00 01 00 00 00 04 00 00 00 00 00 00 00  MZx.............
00000010  00 00 00 00 00 00 00 00 40 00 00 00 00 00 00 00  ........@.......
00000020  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
00000030  00 00 00 00 00 00 00 00 00 00 00 00 78 00 00 00  ............x...
00000040  0E 1F BA 0E 00 B4 09 CD 21 B8 01 4C CD 21 54 68  ........!..L.!Th
00000050  69 73 20 70 72 6F 67 72 61 6D 20 63 61 6E 6E 6F  is program canno
00000060  74 20 62 65 20 72 75 6E 20 69 6E 20 44 4F 53 20  t be run in DOS
00000070  6D 6F 64 65 2E 24 00 00 50 45 00 00 4C 01 06 00  mode.$..PE..L...
00000080  4A 85 0E 5D 00 00 00 00 00 00 00 00 E0 00 22 01  J..]..........".
00000090  0B 01 0E 00 00 94 05 00 00 78 05 00 00 00 00 00  .........x......
000000A0  20 9E 05 00 00 10 00 00 00 00 00 00 00 00 40 00   .............@.
000000B0  00 10 00 00 00 02 00 00 06 00 00 00 00 00 00 00  ................
000000C0  06 00 00 00 00 00 00 00 00 60 0B 00 00 04 00 00  .........`......
000000D0  00 00 00 00 03 00 40 81 00 00 10 00 00 10 00 00  ......@.........
000000E0  00 00 10 00 00 10 00 00 00 00 00 00 10 00 00 00  ................
000000F0  00 00 00 00 00 00 00 00 70 2F 07 00 8C 00 00 00  ........p/......
00000100  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
00000110  00 00 00 00 00 00 00 00 00 00 0A 00 44 5B 01 00  ............D[..
00000120  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
00000130  00 00 00 00 00 00 00 00 AC 2A 07 00 18 00 00 00  .........*......
00000140  68 62 06 00 A0 00 00 00 00 00 00 00 00 00 00 00  hb..............
00000150  C8 32 07 00 CC 02 00 00 00 00 00 00 00 00 00 00  .2..............
   352 B |        0 B/ 708.00 KB |   0.049%
```

ddhx is a quick and dirty TUI hexadecimal viewer meant to replace my
[0xdd](https://github.com/dd86k/0xdd) utility, written in a proper system
language, mostly for myself to use.

A lot of the code is pretty crappy, but this was mostly written on in a whim,
so I don't entirely care.

# View

```
1 - Offset h  00    
2 - 00000000  4D 5A 78 00 01 00 00 00 04 00 00 00 00 00 00 00  MZx.............
3 -    352 B |        0 B/ 708.00 KB |   0.049%
```

1. Offset type (h: hex, d: decimal, o: octal) and offsets
2. Offset, binary data, and ASCII representation
3. Screen buffer size, file position, file size, and file position in pourcentage

# Commands

Searching for an UTF-8 string? Press the return key, or escape, type in `ss IEND`
and ddhx will search for "IEND"!

Notes:
- Some commands take command parameters, e.g. `search u8 0xdd`.
- Some commands have _aliases_, e.g. `sb 0xdd` is the same as `search u8 0xdd`.
- Some commands have a shortcut, e.g. pressing `r` while outside of command mode
executes `refresh`.

Here is a brief list of commands:

| Command | Sub-command | Alias | Description |
|---|---|---|---|
| search | u8 | sb | Search one byte |
| | u16 | | Search a 2-byte value (LSB) |
| | u32 | | Search a 4-byte value (LSB) |
| | u64 | | Search a 8-byte value (LSB) |
| | utf8 | ss | Search an UTF-8 string |
| | utf16 | sw | Search an UTF-16LE string |
| | utf32 | | Search an UTF-32LE string |
| goto | | g | Goto to a specific file location or jump to a relative offset (shortcut: g) |
| info | | i | Print file information on screen (shortcut: i) |
| offset | | o | Change display mode (hex, dec, oct), same as `set offset` |
| clear | | | Clear screen and redraw every panels |
| set | width | | Set bytes per row |
| | offset | o | See `offset` command |
| refresh | | | Remake buffer, clear screen, re-read file, redraw screen (shortcut: r) |
| quit | | | Quit ddhx (key shortcut: q) |
| about | | | Print About text |
| version | | | Print Version text |

## Supported Platforms

Confirmed to work on:
- Windows XP (x86-omf builds)
- Windows Vista+ (x86-mscoff and x86-64)
- Linux

## Planned features

- UTF-32 string searching
- Scrollwheel support