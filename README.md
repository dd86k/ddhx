# ddhx, Hexadecimal File Viewer

```text
Offset h  00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f
00000000  4d 5a 78 00 01 00 00 00 04 00 00 00 00 00 00 00  MZx.............
00000010  00 00 00 00 00 00 00 00 40 00 00 00 00 00 00 00  ........@.......
00000020  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
00000030  00 00 00 00 00 00 00 00 00 00 00 00 78 00 00 00  ............x...
00000040  0e 1f ba 0e 00 b4 09 cd 21 b8 01 4c cd 21 54 68  ........!..L.!Th
00000050  69 73 20 70 72 6f 67 72 61 6d 20 63 61 6e 6e 6f  is program canno
00000060  74 20 62 65 20 72 75 6e 20 69 6e 20 44 4f 53 20  t be run in DOS
00000070  6d 6f 64 65 2e 24 00 00 50 45 00 00 4c 01 06 00  mode.$..PE..L...
00000080  4a 85 0e 5d 00 00 00 00 00 00 00 00 e0 00 22 01  J..]..........".
00000090  0b 01 0e 00 00 94 05 00 00 78 05 00 00 00 00 00  .........x......
000000a0  20 9e 05 00 00 10 00 00 00 00 00 00 00 00 40 00   .............@.
000000b0  00 10 00 00 00 02 00 00 06 00 00 00 00 00 00 00  ................
000000c0  06 00 00 00 00 00 00 00 00 60 0b 00 00 04 00 00  .........`......
000000d0  00 00 00 00 03 00 40 81 00 00 10 00 00 10 00 00  ......@.........
000000e0  00 00 10 00 00 10 00 00 00 00 00 00 10 00 00 00  ................
000000f0  00 00 00 00 00 00 00 00 70 2f 07 00 8c 00 00 00  ........p/......
00000100  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
00000110  00 00 00 00 00 00 00 00 00 00 0a 00 44 5b 01 00  ............D[..
00000120  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
00000130  00 00 00 00 00 00 00 00 ac 2a 07 00 18 00 00 00  .........*......
00000140  68 62 06 00 a0 00 00 00 00 00 00 00 00 00 00 00  hb..............
00000150  c8 32 07 00 cc 02 00 00 00 00 00 00 00 00 00 00  .2..............
   352 B |        0 B/ 708.00 KB |   0.049%
```

ddhx is a quick and dirty TUI hexadecimal viewer meant to replace my
[0xdd](https://github.com/dd86k/0xdd) utility, written in a proper system
language, mostly for myself to use.

It also supports dumping.

A lot of the code is pretty crappy, but this was mostly written on in a whim,
so I don't entirely care.

# View

```text
1 - Offset h  00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f
2 - 00000000  4d 5a 78 00 01 00 00 00 04 00 00 00 00 00 00 00  MZx.............
3 -    352 B |        0 B/ 708.00 KB |   0.049%
```

1. Offset type (h: hex, d: decimal, o: octal) and offset marks
2. Position, binary data, and ASCII representation
3. Screen buffer size, binary position, file binary size, and position pourcentage

## Supported Platforms

Confirmed to work on:
- Windows XP (x86-omf builds)
- Windows Vista+ (x86-mscoff and x86-64)
- Linux

## Planned features

- UTF-32 string searching
- Scrollwheel support