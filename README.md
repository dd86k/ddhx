# ddhx, Hexadecimal File Viewer

```text
Offset(Hex)   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
          0  4d 5a 90 00 03 00 00 00 04 00 00 00 ff ff 00 00  MZ..............
         10  b8 00 00 00 00 00 00 00 40 00 00 00 00 00 00 00  ........@.......
         20  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
         30  00 00 00 00 00 00 00 00 00 00 00 00 f0 00 00 00  ................
         40  0e 1f ba 0e 00 b4 09 cd 21 b8 01 4c cd 21 54 68  ........!..L.!Th
         50  69 73 20 70 72 6f 67 72 61 6d 20 63 61 6e 6e 6f  is program canno
         60  74 20 62 65 20 72 75 6e 20 69 6e 20 44 4f 53 20  t be run in DOS 
         70  6d 6f 64 65 2e 0d 0d 0a 24 00 00 00 00 00 00 00  mode....$.......
         80  70 f0 71 46 34 91 1f 15 34 91 1f 15 34 91 1f 15  p.qF4...4...4...
         90  20 fa 1b 14 3f 91 1f 15 20 fa 1c 14 32 91 1f 15   ...?... ...2...
         a0  20 fa 1a 14 8f 91 1f 15 20 fa 1e 14 33 91 1f 15   ....... ...3...
         b0  34 91 1e 15 aa 91 1f 15 52 fe e2 15 37 91 1f 15  4.......R...7...
         c0  66 e4 1b 14 25 91 1f 15 66 e4 1c 14 3e 91 1f 15  f...%...f...>...
         d0  66 e4 1a 14 1c 91 1f 15 34 91 1f 15 80 96 1f 15  f.......4.......
         e0  8f e4 1d 14 35 91 1f 15 52 69 63 68 34 91 1f 15  ....5...Rich4...
         f0  50 45 00 00 64 86 0d 00 f2 9e fd 61 00 00 00 00  PE..d......a....
        100  00 00 00 00 f0 00 22 00 0b 02 0e 1d 00 d8 24 00  ......".......$.
        110  00 84 0a 00 00 00 00 00 fa 83 00 00 00 10 00 00  ................
        120  00 00 00 40 01 00 00 00 00 10 00 00 00 02 00 00  ...@............
        130  06 00 00 00 00 00 00 00 06 00 00 00 00 00 00 00  ................
        140  00 c0 2f 00 00 04 00 00 00 00 00 00 03 00 60 81  ../...........`.
        150  00 00 10 00 00 00 00 00 00 10 00 00 00 00 00 00  ................
 Hex | 352 B | 0 B - 352 B | 0.000000% - 0.011337%
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
 Hex | 352 B | 0 B - 352 B | 0.000000% - 0.011337%
  ^     ^      \____ ____/   \_________ _________/
  |     |           v                  v
  |     |           |                  +- Start-end view position in pourcentage
  |     |           +- Start-end view buffer position
  |     +- View buffer size
  +- Current data mode
```

# Supported Platforms

Confirmed to work on:
- Windows XP (x86-omf builds)
- Windows Vista+ (x86-mscoff and x86-64)
- Linux (glibc and musl)