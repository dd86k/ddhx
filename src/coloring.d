/// Provides color schemes and line segments.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module coloring;

import std.traits : EnumMembers;
import list;
import os.terminal : TermColor;
import platform : assertion;

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
        import std.conv : text;
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

enum
{
    COLORMAP_INVERTED    = 1,    /// 
    COLORMAP_FOREGROUND  = 2,    /// 
    COLORMAP_BACKGROUND  = 4,    ///
}
// ColorPair[ColorScheme] mapping;
struct ColorMap
{
    int flags;
    TermColor fg;
    TermColor bg;
    
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
        if (colorstr is null || colorstr.length == 0)
            throw new Exception("Color cannot be empty");
        
        ColorMap map;
        string fg = void;
        string bg = void;
        
        ptrdiff_t i = indexOf(colorstr, ':');
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
        
        ColorMap.mapterm(map, fg, COLORMAP_FOREGROUND);
        ColorMap.mapterm(map, bg, COLORMAP_BACKGROUND);
        
        return map;
    }
    private static void mapterm(ref ColorMap map, string term, int pre)
    {
        // Final switch asserts...
        TermColor color = void;
        switch (term) {
        case "", "default": return; // leave .init default
        case "invert": map.flags |= COLORMAP_INVERTED; return;
        case "black":   color = TermColor.black; break;
        case "blue":    color = TermColor.blue; break;
        case "green":   color = TermColor.green; break;
        case "aqua":    color = TermColor.aqua; break;
        case "red":     color = TermColor.red; break;
        case "purple":  color = TermColor.purple; break;
        case "yellow":  color = TermColor.yellow; break;
        case "gray":    color = TermColor.gray; break;
        case "lightgray":   color = TermColor.lightgray; break;
        case "brightblue":  color = TermColor.brightblue; break;
        case "brightgreen": color = TermColor.brightgreen; break;
        case "brightaqua":  color = TermColor.brightaqua; break;
        case "brightred":   color = TermColor.brightred; break;
        case "brightpurple":color = TermColor.brightpurple; break;
        case "brightyellow":color = TermColor.brightyellow; break;
        case "white":       color = TermColor.white; break;
        default:
            import std.conv : text;
            throw new Exception(text("Unknown color: ", term));
        }
        // No magic here
        map.flags |= pre;
        if (pre & COLORMAP_FOREGROUND)
            map.fg = color;
        else
            map.bg = color;
    }
}
unittest
{
    assert(ColorMap.parse("default:default") == ColorMap(0, TermColor.init, TermColor.init));
    assert(ColorMap.parse("default")        == ColorMap(0, TermColor.init, TermColor.init));
    assert(ColorMap.parse("invert")         == ColorMap(COLORMAP_INVERTED, TermColor.init, TermColor.init));
    
    assert(ColorMap.parse("red:default")    == ColorMap(COLORMAP_FOREGROUND, TermColor.red, TermColor.init));
    assert(ColorMap.parse("red:")           == ColorMap(COLORMAP_FOREGROUND, TermColor.red, TermColor.init));
    assert(ColorMap.parse("red")            == ColorMap(COLORMAP_FOREGROUND, TermColor.red, TermColor.init));
    assert(ColorMap.parse("purple")         == ColorMap(COLORMAP_FOREGROUND, TermColor.purple, TermColor.init));
    
    assert(ColorMap.parse("default:red")    == ColorMap(COLORMAP_BACKGROUND, TermColor.init, TermColor.red));
    assert(ColorMap.parse(":red")           == ColorMap(COLORMAP_BACKGROUND, TermColor.init, TermColor.red));
}

struct ColorMapper
{
    enum ColorMap DEFAULT_NORMAL    = ColorMap(0, TermColor.init, TermColor.init);
    enum ColorMap DEFAULT_CURSOR    = ColorMap(COLORMAP_INVERTED, TermColor.init, TermColor.init);
    enum ColorMap DEFAULT_SELECTION = ColorMap(COLORMAP_INVERTED, TermColor.init, TermColor.init);
    enum ColorMap DEFAULT_MIRROR    = ColorMap(COLORMAP_BACKGROUND, TermColor.init, TermColor.red);
    enum ColorMap DEFAULT_ZERO      = ColorMap(COLORMAP_FOREGROUND, TermColor.gray, TermColor.init);
    
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