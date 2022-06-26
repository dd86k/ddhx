# ddhx, Hexadecimal File Viewer

```text
Offset(hex)   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
       1230  e9 c7 97 23 00 e9 e6 78 22 00 e9 b9 e0 20 00 e9  ZGp..ZWÌ..Z¾\..Z
       1240  8c f8 0b 00 e9 a7 4d 09 00 e9 02 99 03 00 e9 35  ð8..Zx(..Z.r..Z.
       1250  b2 26 00 e9 b8 50 23 00 e9 67 99 21 00 e9 5e 16  ¥..Z½&..ZÅr..Z;.
       1260  18 00 e9 69 9e 10 00 e9 f8 74 20 00 e9 d3 8b 21  ..ZÑÆ..Z8È..ZL».
       1270  00 e9 3a b0 19 00 e9 45 b1 14 00 e9 50 d1 1d 00  .Z.^..Zá£..Z&J..
       1280  e9 db 92 06 00 e9 a6 ae 1a 00 e9 ad 82 22 00 e9  Zûk..ZwÞ..ZÝb..Z
       1290  7c e1 15 00 e9 f7 47 1a 00 e9 72 b0 0e 00 e9 8d  @÷..Z7å..ZÊ^..Zý
       12a0  cc 10 00 e9 68 e0 16 00 e9 83 44 13 00 e9 7a cb  ö..ZÇ\..Zcà..Z:ô
       12b0  1f 00 e9 b9 bb 03 00 e9 e0 79 20 00 e9 ff 79 1d  ..Z¾]..Z\`..Z.`.
       12c0  00 e9 ca 2f 17 00 e9 55 90 15 00 e9 80 37 07 00  .Z....Zí°..ZØ...
       12d0  e9 8b 5b 23 00 e9 36 6b 13 00 e9 51 d3 20 00 e9  Z»$..Z.,..ZéL..Z
       12e0  8c 24 1c 00 e9 c7 ff 17 00 e9 a2 55 0e 00 e9 3d  ð...ZG...Zsí..Z.
       12f0  fc 16 00 e9 38 1c 02 00 e9 f3 60 23 00 e9 6e 3a  Ü..Z....Z3-..Z>.
       1300  0f 00 e9 f9 06 02 00 e9 d4 49 1b 00 e9 9f ba 16  ..Z9...ZMñ..Z¤[.
       1310  00 e9 6a 71 15 00 e9 e1 9d 22 00 e9 40 e8 23 00  .Z¦É..Z÷¸..Z Y..
       1320  e9 7b 25 19 00 e9 da e5 27 00 e9 e1 79 1d 00 e9  Z#...Z¹V..Z÷`..Z
       1330  9c 2a 16 00 e9 b7 b2 14 00 e9 a2 08 20 00 e9 fd  æ...Z¼¥..Zs...ZÙ
       1340  72 19 00 e9 18 9d 15 00 e9 03 3b 0e 00 e9 32 f9  Ê..Z.¸..Z....Z.9
       1350  26 00 e9 f5 8f 20 00 e9 48 6f 20 00 e9 43 8b 21  ..Z5±..Zç?..Zä».
       1360  00 e9 6a 0e 17 00 e9 55 c3 14 00 e9 60 b0 0e 00  .Z¦...ZíC..Z-^..
       1370  e9 7b 7a 03 00 e9 8e 96 22 00 e9 e1 ba 18 00 e9  Z#:..Zþo..Z÷[..Z
       1380  9c 48 12 00 e9 c7 08 0b 00 e9 12 e2 1d 00 e9 1d  æç..ZG...Z.S..Z.
 hex | ebcdic | 352 B | 4.9 KB | 0.148291%
```

ddhx is a quick and dirty TUI hexadecimal viewer meant to replace my
[0xdd](https://github.com/dd86k/0xdd) utility, written in a proper system
language, mostly for myself to use.

# Usage

At the moment, there are only two modes:
- Interactive (default)
- Dump (`--dump`)

## Interactive Mode

This is the default mode. It allows you to navigate files and block devices


### Screen

```text
   Base                  Binary data and                           Text
   Offset                  byte offset                         representation
 ____^____    __________________^__________________________    ______^_______
/         \  /                                             \  /              \
Offset(Hex)   0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
       1230  e9 c7 97 23 00 e9 e6 78 22 00 e9 b9 e0 20 00 e9  ZGp..ZWÌ..Z¾\..Z
 hex | ebcdic | 352 B | 4.9 KB | 0.148291%
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