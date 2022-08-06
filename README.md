# ddhx

```text
Offset(hex)   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f                    
        230  10 00 00 00 00 00 00 00 50 e5 74 64 04 00 00 00  ........P.td....
        240  90 e3 1c 00 00 00 00 00 90 e3 1c 00 00 00 00 00  ................
        250  90 e3 1c 00 00 00 00 00 54 a7 00 00 00 00 00 00  ........T.......
        260  54 a7 00 00 00 00 00 00 04 00 00 00 00 00 00 00  T...............
        270  51 e5 74 64 06 00 00 00 00 00 00 00 00 00 00 00  Q.td............
        280  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
        290  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
        2a0  10 00 00 00 00 00 00 00 52 e5 74 64 04 00 00 00  ........R.td....
        2b0  d0 f4 1f 00 00 00 00 00 d0 04 20 00 00 00 00 00  .......... .....
        2c0  d0 04 20 00 00 00 00 00 30 2b 00 00 00 00 00 00  .. .....0+......
        2d0  30 2b 00 00 00 00 00 00 01 00 00 00 00 00 00 00  0+..............
        2e0  2f 6c 69 62 36 34 2f 6c 64 2d 6c 69 6e 75 78 2d  /lib64/ld-linux-
        2f0  78 38 36 2d 36 34 2e 73 6f 2e 32 00 04 00 00 00  x86-64.so.2.....
        300  14 00 00 00 03 00 00 00 47 4e 55 00 f7 2b 19 df  ........GNU..+..
        310  d9 b5 50 88 1c 64 57 4d 8a 43 0e 44 61 95 ec f5  ..P..dWM.C.Da...
        320  04 00 00 00 10 00 00 00 01 00 00 00 47 4e 55 00  ............GNU.
        330  00 00 00 00 03 00 00 00 02 00 00 00 00 00 00 00  ................
        340  03 10 00 00 9f 00 00 00 00 04 00 00 10 00 00 00  ................
        350  81 a0 24 10 40 84 a1 00 98 68 02 00 44 81 06 0c  ..$.@....h..D...
        360  10 80 00 18 85 22 4a 40 08 b8 00 00 44 84 00 20  ....."J@....D.. 
        370  10 42 90 00 00 10 00 90 29 00 00 40 00 01 00 01  .B......)..@....
        380  02 09 01 4b 12 25 01 41 50 13 04 50 75 14 02 01  ...K.%.AP..Pu...
        390  00 08 41 13 14 00 4c 14 0d 01 08 00 08 10 00 00  ..A...L.........
 in | hex | ascii | 368 B |         357 | 0.020338%
```

ddhx is a (soon to be) TUI hex editor that replaces my old
[0xdd](https://github.com/dd86k/0xdd) viewer.

I made this because:
- I no longer want to dump xxd or hexdump output to a pager, like less;
- I was worried about portability;

# Usage

For additional help, use the `--help` command-line option.

## Interactive Mode (default mode)

This mode allows you to navigate the view freely for files and block devices.

It replaces the need to pipe the output for xxd(1) or hexdump(1) into a pager, like less(1).

There are four sub-modes for the interactive session:
- Insert (`--insert`);
  - In insert mode, new data is inserted at the positon of the caret, pushing old data forward.
  - This is the default editing mode.
- Overwrite (`--overwrite`);
  - In overwrite mode, new data overwrites old data at the positon of the caret.
- Read-only (`-R|--readonly`);
  - Editing data is disallowed in this mode, but cursor nagivation remains.
- And view (`view`).
  - This emulates the old viewing navigation mechanic by disabling the cursor.
  - This is closest to using less(1).

### Screen

The interactive session screen consists of three parts:
- Offset bar at the top;
  - The single element offset is shown here.
  - The menu prompt will appear here.
- Data and text representation;
  - The base offset, binary data, and text representation is shown here.
- And a status bar.
  - By default, these are:
    - Editing mode (insert);
    - Data mode (hex)
    - Text mode (ascii);
    - Binary size of view;
    - Absolute cursor position;
    - And position percentage within file or device.

### Menu

The menu system can be invoked using `:` (ala vim). `Enter` is the old way to invoke it.

Some commands require `/` (forward search) or `?` (backward search) to be invoked.

To set a setting, like a character set (`charset`) or offset type (`offset`), use `set <option> <value>`. For example: `set columns auto`

## Dump

The dump mode replaces the need for xxd(1) and hexdump(1).

Most formatting settings can be used for this mode.

# Platforms

- Windows XP (x86-omf builds)
- Windows Vista+ (x86-mscoff and x86-64)
- Linux (glibc and musl)
