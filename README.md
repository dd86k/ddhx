# ddhx - Hex file viewer

![Screenshot of ddhx](https://dd86k.github.io/imgs/ddhx0.png)

I wanted a tool that is simple, light, and does what I want to do quickly, and so I created ddhx.

ddhx is meant as a replacement for my [0xdd](https://github.com/dd86k/0xdd) tool.

## Supported Platforms

| Platform | Progress |
|---|---|
| Windows (Vista+) | Mid-way there! |
| macOS | Unknown |
| Linux | Unusable |
| *BSD | Unknown |

## Planned features
Basically a TODO list:

- Byte, Word (short), Doubleword (int), and Quadword (long) searching (both endians)
- UTF-8, UTF-16, and UTF-32 string searching (both endians)
- Hex dump
- More file info

## Screenshots

![ddhx with an ISO file showing information](https://dd86k.github.io/imgs/ddhx1.png)

# FAQ

## Why port it to D?
Back in 2015, 0xdd was my first tool I ever published to Github. I was still relatively new to programming so not only my skills were lacking, but 0xdd was getting a little messy here and there. So I'm starting from scratch!

C# is a great language. However, it requires .NET or the Mono runtime, and thus taking an extra step installing a framework.

As a native tool, it'll be ready out of the box, faster, and less memory hungry:
- 0xdd, 32-bit release build: 10'632 KB (Working set)
- ddhx, 64-bit debug build  :  6'996 KB (Working set)

## Where did the EDIT-like menu go?
After fiddling around for a while, I couldn't get a good looking menu system. .NET and Mono does procedures automatically to set the console output to UTF-16 since .NET's String type is UTF-16.

Best I _could_ of done is pure ASCII (with the `-|+` set) but didn't look as good.

So for now, a command prompt system (a bit like vim's) is a lot faster to implement and use. I still try to remain a little user friendly.

## Why are you making your own console library?
Naming schemes, mostly.