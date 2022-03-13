# ddhx, Hexadecimal File Viewer

```text
Offset(Hex)   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f                   
     101a30  2e 63 6f 6d 6d 6f 6e 2e 43 68 61 72 54 79 70 65  .common.CharType
     101a40  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
     101a50  90 7d 50 00 00 00 00 00 15 00 00 00 8c 3e 50 00  .}P..........>P.
     101a60  1c 00 00 00 a0 fd 52 00 00 00 00 00 00 00 00 00  ......R.........
     101a70  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
     101a80  00 00 00 00 04 00 00 00 00 00 00 00 53 34 64 64  ............S4dd
     101a90  68 78 36 63 6f 6d 6d 6f 6e 37 47 6c 6f 62 61 6c  hx6common7Global
     101aa0  73 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  s...............
     101ab0  48 65 78 00 00 00 00 00 00 00 00 00 00 00 00 00  Hex.............
     101ac0  44 65 63 00 00 00 00 00 00 00 00 00 00 00 00 00  Dec.............
     101ad0  4f 63 74 00 00 00 00 00 00 00 00 00 00 00 00 00  Oct.............
     101ae0  30 31 32 33 34 35 36 37 38 39 61 62 63 64 65 66  0123456789abcdef
     101af0  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
     101b00  30 31 32 33 34 35 36 37 38 39 00 00 00 00 00 00  0123456789......
     101b10  73 72 63 5c 64 64 68 78 5c 64 69 73 70 6c 61 79  src\ddhx\display
     101b20  2e 64 00 00 00 00 00 00 00 00 00 00 00 00 00 00  .d..............
     101b30  72 3d 00 00 00 00 00 00 00 00 00 00 00 00 00 00  r=..............
     101b40  e2 98 ba 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
     101b50  e2 98 bb 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
     101b60  e2 99 a5 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
     101b70  e2 99 a6 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
     101b80  e2 99 a3 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
 Hex | ascii | 352 B | 1.0 MB | 34.436692%
```

ddhx is a quick and dirty TUI hexadecimal viewer meant to replace my
[0xdd](https://github.com/dd86k/0xdd) utility, written in a proper system
language, mostly for myself to use.

Modes supported:
- Interactive (default).
- Dump (`--dump`).

# Screen

```text
  Offset           Binary data and byte offset               Text representation
 ____^____    __________________^__________________________    ______^_______
/         \  /                                             \  /              \
Offset(Hex)   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
         70  6d 6f 64 65 2e 0d 0d 0a 24 00 00 00 00 00 00 00  mode....$.......
 Hex | ascii | 352 B | 1.0 MB | 34.436692%
  ^     ^       ^        ^          ^
  |     |       |        |          +- End of view position in percentage
  |     |       |        +- End of view buffer position
  |     |       +- View buffer size
  |     +- Character translation mode
  +- Current data mode
```

# Supported Platforms

Confirmed to work on:
- Windows XP (x86-omf builds)
- Windows Vista+ (x86-mscoff and x86-64)
- Linux (glibc and musl)