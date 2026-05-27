/// Provides color schemes and line segments.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module colors;

import std.traits : EnumMembers;
import std.conv : text;

import ddhx.list;
import ddhx.platform : assertion;

import os.terminal : TermColor;

/* Remember, we only have 8 usable colors in a 16-color space (fg == bg -> bad).
   And only 6 (excluding "bright" variants) of them can be used for a purpose,
   other than white/black for defaults.
   BUT, a color scheme can always be mapped to something else (by preference).
*/
enum ColorScheme
{
    normal,
    cursor,
    selection,
    mirror,
    zero,
    // The following are just future ideas
    //modified,   // edited data
    //address,    // layout: address/offset
    //constant,   // layout: known constant value
    //bookmark,
    //search,     // search result (could otherwise be "highlighted" or just selection)
    //diff_added,     // 
    //diff_removed,   // 
    //diff_changed,   // 
}
enum SCHEMES = EnumMembers!(ColorScheme).length;

ColorScheme getScheme(string name)
{
    // Maps one or more names to a scheme
    switch (name) {
    case "normal":      return ColorScheme.normal;
    case "cursor":      return ColorScheme.cursor;
    case "selection":   return ColorScheme.selection;
    case "mirror":      return ColorScheme.mirror;
    case "zero":        return ColorScheme.zero;
    default:
        throw new Exception(text("Unknown scheme: ", name));
    }
}
unittest
{
    assert(getScheme("normal")  == ColorScheme.normal);
    assert(getScheme("zero")    == ColorScheme.zero);
}

//
// Color mapping mechanics
//

import std.typecons : Nullable, nullable;
enum
{
    COLORMAP_INVERTED    = 1,    /// 
}
struct ColorMap
{
    int flags;
    Nullable!TermColor foreground;
    Nullable!TermColor background;
    
    static ColorMap parse(string colorstr)
    {
        import std.string : indexOf;
        
        /*
        ┌──────────┬─────────┬─────────┬──────────┐
        │  Input   │   fg    │   bg    │  Flags   │
        ├──────────┼─────────┼─────────┼──────────┤
        │ red:blue │ red     │ blue    │ FG+BG    │
        ├──────────┼─────────┼─────────┼──────────┤
        │ red:     │ red     │ default │ FG       │
        ├──────────┼─────────┼─────────┼──────────┤
        │ red      │ red     │ default │ FG       │
        ├──────────┼─────────┼─────────┼──────────┤
        │ :blue    │ default │ blue    │ BG       │
        ├──────────┼─────────┼─────────┼──────────┤
        │ invert   │ -       │ -       │ INVERTED │
        └──────────┴─────────┴─────────┴──────────┘
        */
        // "default:red" -> bg=red
        // ":red"       -> bg=red
        // "red:"       -> fg=red
        // "red"        -> fg=red
        if (colorstr.length == 0)
            throw new Exception("Color cannot be empty");
        
        ColorMap map;
        
        if (colorstr == "invert")
        {
            map.flags = COLORMAP_INVERTED;
            return map;
        }
        
        ptrdiff_t i = indexOf(colorstr, ':');
        string fg = void;
        string bg = void;
        if (i >= 0) // foreground + background
        {
            fg = colorstr[0..i];
            bg = colorstr[i+1..$];
        }
        else
        {
            fg = colorstr;
            bg = null;
        }
        map.foreground = ColorMap.mapterm(fg);
        map.background = ColorMap.mapterm(bg);
        
        return map;
    }
    private static Nullable!TermColor mapterm(string term)
    {
        switch (term) { // final switch ASSERTS, not a good flow
        // call null and "" are duplicates?!
        case "", "default": return Nullable!TermColor.init;
        case "black":       return Nullable!TermColor(TermColor.black);
        case "blue":        return Nullable!TermColor(TermColor.blue);
        case "green":       return Nullable!TermColor(TermColor.green);
        case "aqua":        return Nullable!TermColor(TermColor.aqua);
        case "red":         return Nullable!TermColor(TermColor.red);
        case "purple":      return Nullable!TermColor(TermColor.purple);
        case "yellow":      return Nullable!TermColor(TermColor.yellow);
        case "gray":        return Nullable!TermColor(TermColor.gray);
        case "lightgray":   return Nullable!TermColor(TermColor.lightgray);
        case "brightblue":  return Nullable!TermColor(TermColor.brightblue);
        case "brightgreen": return Nullable!TermColor(TermColor.brightgreen);
        case "brightaqua":  return Nullable!TermColor(TermColor.brightaqua);
        case "brightred":   return Nullable!TermColor(TermColor.brightred);
        case "brightpurple":return Nullable!TermColor(TermColor.brightpurple);
        case "brightyellow":return Nullable!TermColor(TermColor.brightyellow);
        case "white":       return Nullable!TermColor(TermColor.white);
        default:
            throw new Exception(text("Unknown color: ", term));
        }
    }
}
unittest
{
    assert(ColorMap.parse("default:default")== ColorMap());
    assert(ColorMap.parse("default")        == ColorMap());
    assert(ColorMap.parse("invert")         == ColorMap(COLORMAP_INVERTED));
    
    assert(ColorMap.parse("red:default")    == ColorMap(0, Nullable!TermColor(TermColor.red)));
    assert(ColorMap.parse("red:")           == ColorMap(0, Nullable!TermColor(TermColor.red), Nullable!TermColor.init));
    assert(ColorMap.parse("red")            == ColorMap(0, Nullable!TermColor(TermColor.red)));
    assert(ColorMap.parse("purple")         == ColorMap(0, Nullable!TermColor(TermColor.purple)));
    
    assert(ColorMap.parse("default:red")    == ColorMap(0, Nullable!TermColor.init, Nullable!TermColor(TermColor.red)));
    assert(ColorMap.parse(":red")           == ColorMap(0, Nullable!TermColor.init, Nullable!TermColor(TermColor.red)));
}

struct ColorMapper
{
    enum ColorMap DEFAULT_NORMAL    = ColorMap(0);
    enum ColorMap DEFAULT_CURSOR    = ColorMap(COLORMAP_INVERTED);
    enum ColorMap DEFAULT_SELECTION = ColorMap(COLORMAP_INVERTED);
    enum ColorMap DEFAULT_MIRROR    = ColorMap(0, Nullable!TermColor.init, Nullable!TermColor(TermColor.red));
    enum ColorMap DEFAULT_ZERO      = ColorMap(0, Nullable!TermColor(TermColor.gray));
    
    // Initial color specifications
    private
    ColorMap[SCHEMES] maps = [
        DEFAULT_NORMAL,
        DEFAULT_CURSOR,
        DEFAULT_SELECTION,
        DEFAULT_MIRROR,
        DEFAULT_ZERO,
    ];
    static assert(maps.length == SCHEMES);
    // Defaults
    private
    static immutable ColorMap[SCHEMES] defaults = [
        DEFAULT_NORMAL,
        DEFAULT_CURSOR,
        DEFAULT_SELECTION,
        DEFAULT_MIRROR,
        DEFAULT_ZERO,
    ];
    static assert(defaults.length == SCHEMES);
    
    ColorMap get(ColorScheme scheme)
    {
        size_t i = cast(size_t)scheme;
        version (D_NoBoundsChecks)
            assertion(i < SCHEMES, "i < SCHEMES");
        return maps[i];
    }
    void set(ColorScheme scheme, ColorMap map)
    {
        size_t i = cast(size_t)scheme;
        version (D_NoBoundsChecks)
            assertion(i < SCHEMES, "i < SCHEMES");
        maps[i] = map;
    }
    
    static ColorMap default_(ColorScheme scheme)
    {
        size_t i = cast(size_t)scheme;
        version (D_NoBoundsChecks)
            assertion(i < SCHEMES, "i < SCHEMES");
        return defaults[i];
    }
}

struct LineSegment
{
    string data;
    ColorScheme scheme;

    string toString() const { return data; }
}
struct Line
{
    List!LineSegment segments;
    char[4 * 1024] textbuf;
    size_t textpos;

    // "reserve" is a function in object.d. DO NOT try to collide with it.
    this(size_t segment_count)
    {
        segments = List!LineSegment(segment_count);
    }
    ~this()
    {
        destroy(segments);
    }

    LineSegment opIndex(size_t i)
    {
        return segments[i];
    }

    // Setting index=0 is faster than de- and re-allocating
    void reset() { segments.reset(); textpos = 0; }

    size_t add(string text, ColorScheme scheme)
    {
        import core.stdc.string : memcpy;

        assertion(textpos + text.length <= textbuf.length);

        memcpy(textbuf.ptr + textpos, text.ptr, text.length);

        // Coalesce: extend previous segment if same scheme
        if (segments.count > 0 && segments.buffer[segments.count - 1].scheme == scheme)
        {
            auto prev = &segments.buffer[segments.count - 1];
            prev.data = cast(string) textbuf[textpos - prev.data.length .. textpos + text.length];
        }
        else
        {
            LineSegment segment;
            segment.data = cast(string) textbuf[textpos .. textpos + text.length];
            segment.scheme = scheme;
            segments ~= segment;
        }

        textpos += text.length;
        return text.length;
    }
    
    // No color
    size_t normal(string[] texts...)
    {
        size_t r;
        foreach (text; texts)
            r += add(text, ColorScheme.normal);
        return r;
    }
    
    size_t cursor(string text)
    {
        return add(text, ColorScheme.cursor);
    }
    
    size_t selection(string text)
    {
        return add(text, ColorScheme.selection);
    }
    
    size_t mirror(string text)
    {
        return add(text, ColorScheme.mirror);
    }
}
unittest
{
    Line line;

    assert(line.normal("test", "second") == 10);
    assert(line.cursor("ff") == 2);
    assert(line.selection("ffff") == 4);

    // "test" and "second" coalesce into one normal segment
    assert(line[0].toString()   == "testsecond");
    assert(line[0].scheme       == ColorScheme.normal);

    assert(line[1].toString()   == "ff");
    assert(line[1].scheme       == ColorScheme.cursor);

    assert(line[2].toString()   == "ffff");
    assert(line[2].scheme       == ColorScheme.selection);
}
unittest
{
    Line line; // Emulate a line of 4 x8 columns...

    // address
    assert(line.normal("    1000000") == 11);
    assert(line.normal(" ")     == 1);

    // data
    assert(line.normal(" ")     == 1);
    assert(line.normal("ff")    == 2);
    assert(line.normal(" ")     == 1);
    assert(line.normal("ff")    == 2);
    assert(line.normal(" ")     == 1);
    assert(line.selection("ff") == 2);
    assert(line.selection(" ")  == 1);
    assert(line.selection("ff") == 2);

    // data-text spacers
    assert(line.normal("  ")    == 2);

    // text
    assert(line.normal(".")     == 1);
    assert(line.normal(".")     == 1);
    assert(line.normal(".")     == 1);
    assert(line.normal(".")     == 1);

    // Adjacent same-scheme segments coalesce:
    // [0] normal:    "    1000000  ff ff " (address + data before selection)
    // [1] selection: "ff ff"               (selected data)
    // [2] normal:    "  ...."              (spacer + text)
    assert(line.segments.count == 3);

    assert(line[0].toString()   == "    1000000  ff ff ");
    assert(line[0].scheme       == ColorScheme.normal);

    assert(line[1].toString()   == "ff ff");
    assert(line[1].scheme       == ColorScheme.selection);

    assert(line[2].toString()   == "  ....");
    assert(line[2].scheme       == ColorScheme.normal);
}