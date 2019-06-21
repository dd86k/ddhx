# ddhx, Interactive Hexadecimal File Viewer

**NOTE:** Please note that ddhx is an inactive project.

![Screenshot of ddhx](https://dd86k.github.io/imgs/ddhx3.png)

ddhx is a replacement for [0xdd](https://github.com/dd86k/0xdd) as a native tool.

### Commands

Searching for an ASCII string? Press the return key, or escape, type in `ss IEND` and ddhx will search for "IEND"!

Notes:
- Some commands take in sub-command parameters, e.g. `search byte 0xdd`.
- Some commands have _aliases_, e.g. `sb 0xdd` is the same as `search byte 0xdd`.
- Some commands have _multiple definitions_, e.g. `ushort` is the same type as `word` and `w`.
- Some commands have a key binded as a command, e.g. pressing `r` while not in command-mode executes the equivelent of `refresh`.

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

| Platform | Progress |
|---|---|
| Windows XP | Doesn't work |
| Windows | Works! |
| macOS | Unknown |
| Linux | Works! |
| *BSD | Unknown |

## Planned features

- UTF-32 string searching
- Dump to file
- Scrollwheel support

## Screenshots

![ddhx with an ISO file showing information](https://dd86k.github.io/imgs/ddhx3-2.png)