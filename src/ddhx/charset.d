/// Single-byte character sets, both ways: bytes to UTF-8 for display, and
/// Unicode to bytes for text needles.
///
/// A set is a code point map, which is the source of truth, and a UTF-8
/// glyph table derived from it at compile time. The map is the code page
/// proper, so decoded text survives a copy (LF stays LF); pictures are what
/// the display shows in its place, like CP437's ◙, and encode back to the
/// same byte, which is unambiguous since they are different code points.
///
/// The view renders from the glyph table, costing one indexed load per byte.
/// Encoding scans linearly because it only runs on typed input, and a
/// reverse table would add a kilobyte per set for no noticeable gain.
/// std.encoding supplies tables for the sets it defines, but its
/// EncodingScheme is not used at runtime: a virtual call and a dchar round
/// trip per byte would cost every redraw.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.charset;

import std.encoding : Latin1Char, Windows1252Char, safeDecode, INVALID_SEQUENCE;
import std.format : format;
static import std.utf;

// NOTE: std.encoding is not used at runtime
//       Its registration API was changed after 2.076 and this potentially affects gdc-11 coverage
//       Plus, hand-written functions are faster (might write proper benchmark later) and
//       the design allows user tables to be loaded laters
struct Charset
{
    string id;
    string name;
    /// Code point per byte, U+FFFF (wchar.init) where the set defines none.
    wchar[256] map;
    /// Display overrides for the first bytes, U+FFFF where the map shows.
    wstring pictures;
    /// UTF-8 per byte in [0..3] and its length in [3], which is free because
    /// every entry is in the BMP.
    char[4][256] glyphs;

    this(string id, string name, wchar[256] map, wstring pictures = null)
    {
        this.id       = id;
        this.name     = name;
        this.map      = map;
        this.pictures = pictures;
        foreach (i, wchar c; map)
        {
            if (i < pictures.length && pictures[i] != wchar.init)
                c = pictures[i];
            // Explicit zero: char.init is 0xFF, which would read as a length
            glyphs[i][3] = visible(c) ? cast(char)std.utf.encode(glyphs[i], c) : 0;
        }
    }

    /// Returns: UTF-8 for display, one column wide, or empty (though not
    ///          null, so test the length) if nothing prints.
    string glyph(ubyte b) immutable
    {
        return glyphs[b][0 .. glyphs[b][3]];
    }

    /// Like C's isprint: whether glyph() has something to show.
    bool printable(ubyte b) immutable
    {
        return glyphs[b][3] != 0;
    }

    /// Returns: Code point, U+FFFF if undefined.
    dchar decode(ubyte b) immutable
    {
        return map[b];
    }

    /// Returns: Byte for this code point, or -1 if the set lacks it.
    int encode(dchar c) immutable
    {
        if (c >= wchar.init) // also keeps the sentinel from matching
            return -1;
        foreach (i, wchar m; map)
        {
            if (m == c)
                return cast(int)i;
        }
        foreach (i, wchar p; pictures)
        {
            if (p == c)
                return cast(int)i;
        }
        return -1;
    }

    /// Encode UTF-8 text.
    /// Throws: UTFException on malformed input, Exception on a character the
    ///         set lacks, rather than substituting one.
    ubyte[] encode(const(char)[] text) immutable
    {
        // No code point is shorter than its byte, so this is the most needed
        ubyte[] buffer = new ubyte[text.length];
        size_t o;
        for (size_t i; i < text.length;)
        {
            dchar c = std.utf.decode(text, i);
            int b = encode(c);
            if (b < 0)
                throw new Exception(format("U+%04X is not in %s", cast(uint)c, id));
            buffer[o++] = cast(ubyte)b;
        }
        return buffer[0 .. o];
    }
}

/// Returns: Character set, or null if unknown.
immutable(Charset)* findCharset(const(char)[] id)
{
    foreach (immutable(Charset)* set; charsets)
    {
        if (set.id == id)
            return set;
    }
    return null;
}

// Named rather than only listed, because the address of an array element is
// not a constant and a field default like `= &ASCII` needs one
immutable Charset ASCII     = Charset("ascii",     "ASCII",                        ascii());
immutable Charset CP437     = Charset("cp437",     "IBM PC Code Page 437 (DOS)",   ascii(CP437_HIGH), cp437pictures());
immutable Charset EBCDIC037 = Charset("ebcdic037", "IBM EBCDIC Code Page 37",      table(CP037));
immutable Charset MACROMAN  = Charset("macroman",  "Mac OS Roman (Windows 10000)", ascii(MAC_HIGH));
immutable Charset LATIN1    = Charset("latin1",    "ISO/IEC 8859-1",               phobos!Latin1Char());
immutable Charset WIN1252   = Charset("win1252",   "Windows-1252",                 phobos!Windows1252Char());

immutable(Charset*)[] charsets = [ &ASCII, &CP437, &EBCDIC037, &MACROMAN, &LATIN1, &WIN1252 ];

private:

// Controls, soft hyphen, and private use would print as nothing, as a
// zero-width mark that shifts every column after it, or as a font's own glyph
bool visible(wchar c)
{
    return c >= 0x20 && (c < 0x7f || c >= 0xa0) &&
        c != 0xad && (c < 0xe000 || c > 0xf8ff) && c != wchar.init;
}

wchar[256] table(wstring s)
{
    assert(s.length == 256);
    wchar[256] map = s;
    return map;
}

wchar[256] ascii(wstring high = null)
{
    assert(high.length == 0 || high.length == 128);
    wchar[256] map;
    foreach (i; 0 .. 0x80)
        map[i] = cast(wchar)i;
    map[0x80 .. 0x80 + high.length] = high;
    return map;
}

wchar[256] phobos(E)()
{
    wchar[256] map;
    foreach (i; 0 .. 256)
    {
        immutable(E)[] s = [ cast(E)i ];
        dchar c = safeDecode(s);
        if (c != INVALID_SEQUENCE)
            map[i] = cast(wchar)c;
    }
    return map;
}

// What a PC displays for the controls, and what DOS-era data is expected to
// look like
wstring cp437pictures()
{
    wchar[] pictures = new wchar[0x80];
    pictures[0x01 .. 0x20] = "☺☻♥♦♣♠•◘○◙♂♀♪♫☼►◄↕‼¶§▬↨↑↓→←∟↔▲▼"w;
    pictures[0x7f] = '⌂';
    return pictures.idup;
}

immutable wstring CP437_HIGH =
/*80*/  "ÇüéâäàåçêëèïîìÄÅ"~
/*90*/  "ÉæÆôöòûùÿÖÜ¢£¥₧ƒ"~
/*a0*/  "áíóúñÑªº¿⌐¬½¼¡«»"~
/*b0*/  "░▒▓│┤╡╢╖╕╣║╗╝╜╛┐"~
/*c0*/  "└┴┬├─┼╞╟╚╔╩╦╠═╬╧"~
/*d0*/  "╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀"~
/*e0*/  "αßΓπΣσµτΦΘΩδ∞φε∩"~
/*f0*/  "≡±≥≤⌠⌡÷≈°∙·√ⁿ²■\u00a0";

immutable wstring CP037 =
/*00*/  "\u0000\u0001\u0002\u0003\u009c\u0009\u0086\u007f\u0097\u008d\u008e\u000b\u000c\u000d\u000e\u000f"~
/*10*/  "\u0010\u0011\u0012\u0013\u009d\u0085\u0008\u0087\u0018\u0019\u0092\u008f\u001c\u001d\u001e\u001f"~
/*20*/  "\u0080\u0081\u0082\u0083\u0084\u000a\u0017\u001b\u0088\u0089\u008a\u008b\u008c\u0005\u0006\u0007"~
/*30*/  "\u0090\u0091\u0016\u0093\u0094\u0095\u0096\u0004\u0098\u0099\u009a\u009b\u0014\u0015\u009e\u001a"~
/*40*/  " \u00a0âäàáãåçñ¢.<(+|"~
/*50*/  "&éêëèíîïìß!$*);¬"~
/*60*/  "-/ÂÄÀÁÃÅÇÑ¦,%_>?"~
/*70*/  "øÉÊËÈÍÎÏÌ`:#@'=\""~
/*80*/  "Øabcdefghi«»ðýþ±"~
/*90*/  "°jklmnopqrªºæ¸Æ¤"~
/*a0*/  "µ~stuvwxyz¡¿ÐÝÞ®"~
/*b0*/  "^£¥·©§¶¼½¾[]¯¨´×"~
/*c0*/  "{ABCDEFGHI\u00adôöòóõ"~
/*d0*/  "}JKLMNOPQR¹ûüùúÿ"~
/*e0*/  "\\÷STUVWXYZ²ÔÖÒÓÕ"~
/*f0*/  "0123456789³ÛÜÙÚ\u009f";

// 0xF0 is the Apple logo, which Apple maps to private use
immutable wstring MAC_HIGH =
/*80*/  "ÄÅÇÉÑÖÜáàâäãåçéè"~
/*90*/  "êëíìîïñóòôöõúùûü"~
/*a0*/  "†°¢£§•¶ß®©™´¨≠ÆØ"~
/*b0*/  "∞±≤≥¥µ∂∑∏π∫ªºΩæø"~
/*c0*/  "¿¡¬√ƒ≈∆«»…\u00a0ÀÃÕŒœ"~
/*d0*/  "–—“”‘’÷◊ÿŸ⁄€‹›ﬁﬂ"~
/*e0*/  "‡·‚„‰ÂÊÁËÈÍÎÏÌÓÔ"~
/*f0*/  "\uf8ffÒÚÛÙıˆ˜¯˘˙˚¸˝˛ˇ";

unittest
{
    immutable(Charset)* ebcdic = findCharset("ebcdic037");
    assert(ebcdic);
    assert(ebcdic.glyph(0x00) == "");
    assert(ebcdic.glyph(0x25) == "");   // LF, not printable...
    assert(ebcdic.decode(0x25) == '\n'); // ...but still decodes
    assert(ebcdic.printable(0x25) == false);
    assert(ebcdic.printable(0x7c));
    assert(findCharset("cp437").printable(0x0a)); // as ◙
    assert(ebcdic.glyph(0x42) == "â");
    assert(ebcdic.glyph(0x7c) == "@");
    assert(ebcdic.glyph(0xca) == "");   // soft hyphen
    assert(ebcdic.encode("Hello\n") == [ 0xc8, 0x85, 0x93, 0x93, 0x96, 0x25 ]);
    assert(ebcdic.encode("") == []);

    immutable(Charset)* cp437 = findCharset("cp437");
    assert(cp437.glyph(0x00) == "");
    assert(cp437.glyph(0x01) == "☺");
    assert(cp437.glyph(0x3d) == "=");
    assert(cp437.glyph(0x4c) == "L");
    assert(cp437.glyph(0x0a) == "◙");
    assert(cp437.glyph(0x7f) == "⌂");
    assert(cp437.decode(0x0a) == '\n');
    assert(cp437.encode("☺ß") == [ 0x01, 0xe1 ]);
    assert(cp437.encode("\r\n♪◙") == [ 0x0d, 0x0a, 0x0d, 0x0a ]);

    immutable(Charset)* ascii = findCharset("ascii");
    assert(ascii.glyph('a') == "a");
    assert(ascii.glyph(0x7f) == "");
    assert(ascii.glyph(0x80) == "");
    assert(ascii.decode(0x80) == wchar.init);
    assert(ascii.encode(wchar.init) == -1);

    immutable(Charset)* mac = findCharset("macroman");
    assert(mac.glyph(0xaa) == "™");
    assert(mac.glyph(0xf0) == "");
    assert(mac.encode('\uf8ff') == 0xf0);

    immutable(Charset)* win1252 = findCharset("win1252");
    assert(win1252.glyph(0x80) == "€");
    assert(win1252.decode(0x81) == wchar.init);

    assert(findCharset("utf8") == null);
}

// Every defined byte comes back as itself
unittest
{
    foreach (immutable(Charset)* set; charsets)
    {
        foreach (i; 0 .. 256)
        {
            if (set.map[i] == wchar.init)
                continue;
            assert(set.encode(set.map[i]) == i, set.id);
        }
        foreach (i, wchar p; set.pictures)
        {
            if (p != wchar.init)
                assert(set.encode(p) == i, set.id);
        }
    }
}

unittest
{
    import std.exception : assertThrown;
    import std.utf : UTFException;
    immutable(Charset)* ebcdic = findCharset("ebcdic037");
    assertThrown!UTFException(ebcdic.encode("\xff"));
    assertThrown(ebcdic.encode("€"));
    assertThrown(findCharset("ascii").encode("é"));
}
