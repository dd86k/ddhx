# ddhx, Hexadecimal File Viewer

```text
Offset h   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
       0  4d 5a 90 00 03 00 00 00 04 00 00 00 ff ff 00 00  MZ..............
      10  b8 00 00 00 00 00 00 00 40 00 00 00 00 00 00 00  ........@.......
      20  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
      30  00 00 00 00 00 00 00 00 00 00 00 00 80 00 00 00  ................
      40  0e 1f ba 0e 00 b4 09 cd 21 b8 01 4c cd 21 54 68  ........!..L.!Th
      50  69 73 20 70 72 6f 67 72 61 6d 20 63 61 6e 6e 6f  is program canno
      60  74 20 62 65 20 72 75 6e 20 69 6e 20 44 4f 53 20  t be run in DOS
      70  6d 6f 64 65 2e 0d 0d 0a 24 00 00 00 00 00 00 00  mode....$.......
      80  50 45 00 00 4c 01 03 00 79 3e 06 59 00 00 00 00  PE..L...y>.Y....
      90  00 00 00 00 e0 00 22 00 0b 01 30 00 00 0e 20 00  ......"...0... .
      a0  00 4a 00 00 00 00 00 00 2e 2c 20 00 00 20 00 00  .J......., .. ..
      b0  00 40 20 00 00 00 40 00 00 20 00 00 00 02 00 00  .@ ...@.. ......
      c0  04 00 00 00 00 00 00 00 06 00 00 00 00 00 00 00  ................
      d0  00 c0 20 00 00 02 00 00 00 00 00 00 02 00 60 85  .. ...........`.
      e0  00 00 10 00 00 10 00 00 00 00 10 00 00 10 00 00  ................
      f0  00 00 00 00 10 00 00 00 00 00 00 00 00 00 00 00  ................
     100  dc 2b 20 00 4f 00 00 00 00 40 20 00 e4 46 00 00  .+ .O....@ ..F..
     110  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
     120  00 a0 20 00 0c 00 00 00 a4 2a 20 00 1c 00 00 00  .. ......* .....
     130  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
     140  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
     150  00 00 00 00 00 00 00 00 00 20 00 00 08 00 00 00  ......... ......
 448 B |        0 B/    2.0 MB |  0.0211%
```

ddhx is a quick and dirty TUI hexadecimal viewer meant to replace my
[0xdd](https://github.com/dd86k/0xdd) utility, written in a proper system
language, mostly for myself to use.

Modes supported:
- Interactive (default).
- Dump (`--dump`).

## Screen

```text
 Offset                  Binary data                      Text representation
 __^___    __________________^__________________________    ______^_______
/      \  /                                             \  /              \
Offset h   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
00000000  4d 5a 78 00 01 00 00 00 04 00 00 00 00 00 00 00  MZx.............
   352 B |        0 B/ 708.00 KB |   0.0-0.049%
    ^          ^         ^            ^    ^
    |          |         |            |    +- File position (end of view buffer)
    |          |         |            +- File position (start of view buffer)
    |          |         +- File size
    |          +- File position (start of view buffer)
    +- View buffer size
```

## Supported Platforms

Confirmed to work on:
- Windows XP (x86-omf builds)
- Windows Vista+ (x86-mscoff and x86-64)
- Linux (glibc and musl)