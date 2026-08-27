/// Utilities.
/// 
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module utils;

/// Template to get binary size in mebibytes (base-1024)
/// Params: base = Base unit.
template MiB(int base)
{
    enum MiB = cast(long)base * 1024 * 1024;
}
/// Template to get binary size in kibibytes (base-1024)
/// Params: base = Base unit.
template KiB(int base)
{
    enum KiB = cast(long)base * 1024;
}

/// One argument out of arguments().
///
/// Because ddhx deals with bytes, arguments are resolved to bytes, allowing
/// weirder escapes and in general, byte arrays.
///
/// No `alias this`, it'd collide with std.conv.text.
struct Argument
{
    /// Argument bytes, quotes removed and escape sequences resolved.
    immutable(ubyte)[] data;

    /// An argument out of raw text, for callers that are not the command line.
    ///
    /// Taken as typed. D source has already resolved its own escapes, so
    /// `Argument("utf8:\t")` holds a real tab and has nothing left to interpret.
    /// Params: text = Argument text.
    this(string text)
    {
        data = cast(immutable(ubyte)[])text;
    }

    /// An argument out of bytes.
    /// Params: newdata = Argument bytes.
    this(immutable(ubyte)[] newdata)
    {
        data = newdata;
    }

    /// Translate argument as text. This validates text.
    ///
    /// Returns: Argument text.
    /// Throws: Exception if the bytes are not valid UTF-8.
    string text() const
    {
        import std.utf : validate, UTFException;
        import std.conv : text;
        import messages : MSG_ARGUMENT_NOT_TEXT;

        string result = cast(string)data;

        try validate(result);
        catch (UTFException ex)
            throw new Exception(text(MSG_ARGUMENT_NOT_TEXT, printable(data)));

        return result;
    }
}
unittest
{
    assert(Argument("utf8:ab").data == cast(immutable(ubyte)[])"utf8:ab");
    assert(Argument("utf8:ab").text == "utf8:ab");
    assert(Argument("héllo").text == "héllo");

    // Bytes that are not text are an argument all the same, they are just not
    // one that a command taking a file name can do anything with
    Argument arg = Argument(cast(immutable(ubyte)[])[ 0x41, 0xff ]);
    assert(arg.data == [ 0x41, 0xff ]);
    try
    {
        cast(void)arg.text;
        assert(false, "text() should have thrown");
    }
    catch (Exception) {}
}

/// Take a list of arguments as text.
///
/// For the callers that only ever wanted text, such as passing a command line
/// on to something that has no idea what quoting is.
/// Params: args = Arguments.
/// Returns: Argument texts.
/// Throws: Exception if an argument is not valid UTF-8.
string[] texts(Argument[] args)
{
    string[] result = new string[args.length];
    foreach (i, Argument arg; args) result[i] = arg.text;
    return result;
}

/// Render bytes for an error message, since the bytes in question are, by
/// definition, the ones that cannot be printed as-is.
/// Params: data = Bytes.
/// Returns: Printable text.
string printable(immutable(ubyte)[] data)
{
    import std.ascii : isPrintable;
    import std.format : format;

    string result;
    foreach (ubyte b; data)
    {
        if (isPrintable(b))
            result ~= cast(char)b;
        else
            result ~= format("\\x%02x", b);
    }
    return result;
}
unittest
{
    assert(printable(cast(immutable(ubyte)[])"ab") == "ab");
    assert(printable(cast(immutable(ubyte)[])[ 0x41, 0xff, 0x0a ]) == `A\xff\x0a`);
}

// Interpret C string escapes ("\0", "\t", "\x1b", "\101", etc.) into raw bytes.
//
// Unknown sequences throw instead of silently dropping the backslash: a
// backslash that quietly means itself is a gray area, and a needle that
// matches the wrong bytes is worse than one that refuses to compile. A literal
// backslash is "\\", and raw text is what single quotes are for.
//
// Used for double-quoted runs only, see arguments().
private
ubyte[] unescape(const(char)[] input)
{
    import std.ascii : isHexDigit, isOctalDigit;
    import std.conv : text;
    import messages;

    ubyte[] result;

    for (size_t i; i < input.length; ++i)
    {
        char c = input[i];

        if (c != '\\')
        {
            result ~= cast(ubyte)c;
            continue;
        }

        if (++i >= input.length)
            throw new Exception(MSG_INCOMPLETE_ESCAPE);

        char e = input[i];
        switch (e) {
        case 'a':  result ~= '\a'; continue;
        case 'b':  result ~= '\b'; continue;
        case 'e':  result ~= 0x1b; continue; // GNU extension, handy for terminal dumps
        case 'f':  result ~= '\f'; continue;
        case 'n':  result ~= '\n'; continue;
        case 'r':  result ~= '\r'; continue;
        case 't':  result ~= '\t'; continue;
        case 'v':  result ~= '\v'; continue;
        case '\\': result ~= '\\'; continue;
        case '\'': result ~= '\''; continue;
        case '"':  result ~= '"';  continue;
        case '?':  result ~= '?';  continue;
        // Octal, one to three digits ("\0", "\12", "\377")
        case '0': .. case '7':
            uint v = e - '0';
            for (int d = 1; d < 3 && i + 1 < input.length && isOctalDigit(input[i + 1]); ++d)
                v = (v * 8) + (input[++i] - '0');
            if (v > 0xff)
                throw new Exception(text(MSG_ESCAPE_OUT_OF_RANGE, `\`, e));
            result ~= cast(ubyte)v;
            continue;
        // Hexadecimal, one or two digits ("\x0", "\x1b"). C would keep eating
        // digits and overflow; a trailing hex digit here is ambiguous with
        // literal text ("\x1bfoo"), so it is rejected rather than guessed at.
        case 'x':
            if (i + 1 >= input.length || isHexDigit(input[i + 1]) == false)
                throw new Exception(text(MSG_UNKNOWN_ESCAPE, `\x`));
            size_t esc = i - 1; // on '\\', for error reporting
            uint h;
            for (int d; d < 2 && i + 1 < input.length && isHexDigit(input[i + 1]); ++d)
            {
                char x = input[++i];
                h = (h * 16) + (x <= '9' ? x - '0' : (x | 0x20) - 'a' + 10);
            }
            if (i + 1 < input.length && isHexDigit(input[i + 1]))
                throw new Exception(text(MSG_ESCAPE_TOO_MANY_DIGITS, input[esc..i + 2]));
            result ~= cast(ubyte)h;
            continue;
        default:
            throw new Exception(text(MSG_UNKNOWN_ESCAPE, `\`, e, MSG_ESCAPE_RAW_HINT));
        }
    }

    return result;
}
unittest
{
    assert(unescape("")     == []);
    assert(unescape("test") == cast(ubyte[])"test");

    // Single-character escapes
    assert(unescape(`\a`)  == [ 0x07 ]);
    assert(unescape(`\b`)  == [ 0x08 ]);
    assert(unescape(`\e`)  == [ 0x1b ]);
    assert(unescape(`\f`)  == [ 0x0c ]);
    assert(unescape(`\n`)  == [ 0x0a ]);
    assert(unescape(`\r`)  == [ 0x0d ]);
    assert(unescape(`\t`)  == [ 0x09 ]);
    assert(unescape(`\v`)  == [ 0x0b ]);
    assert(unescape(`\\`)  == [ '\\' ]);
    assert(unescape(`\'`)  == [ '\'' ]);
    assert(unescape(`\"`)  == [ '"' ]);
    assert(unescape(`\?`)  == [ '?' ]);

    // Octal
    assert(unescape(`\0`)    == [ 0 ]);
    assert(unescape(`\00`)   == [ 0 ]);
    assert(unescape(`\000`)  == [ 0 ]);
    assert(unescape(`\7`)    == [ 7 ]);
    assert(unescape(`\12`)   == [ 0x0a ]);
    assert(unescape(`\101`)  == [ 'A' ]);
    assert(unescape(`\377`)  == [ 0xff ]);
    assert(unescape(`\0008`) == [ 0, '8' ]);  // stops after three digits
    assert(unescape(`\08`)   == [ 0, '8' ]);  // '8' is not octal

    // Hexadecimal
    assert(unescape(`\x0`)      == [ 0 ]);
    assert(unescape(`\x00`)     == [ 0 ]);
    assert(unescape(`\x1b`)     == [ 0x1b ]);
    assert(unescape(`\xFF`)     == [ 0xff ]);
    assert(unescape(`\x41z`)    == [ 'A', 'z' ]);
    assert(unescape(`\x0z`)     == [ 0, 'z' ]);

    // Mixed
    assert(unescape(`a\tb`)      == [ 'a', 0x09, 'b' ]);
    assert(unescape(`\r\n`)      == [ 0x0d, 0x0a ]);
    assert(unescape(`C:\\Users`) == cast(ubyte[])`C:\Users`);

    void test_throw(string input)
    {
        try { cast(void)unescape(input); } catch (Exception) { return; }

        import std.stdio : stderr, writeln;
        stderr.writeln("Failed to throw with: ", input);
        assert(false, "test_throw test failed");
    }
    test_throw(`\`);        // dangling backslash
    test_throw(`a\`);
    test_throw(`\z`);       // unknown escape
    test_throw(`\U0001`);   // universal character names unsupported
    test_throw(`\x`);       // missing hex digits
    test_throw(`\xzz`);
    test_throw(`\xdead`);   // ambiguous with literal text, use "\xde ad" or x:dead
    test_throw(`\x1bfoo`);
    test_throw(`\400`);     // over 0xff
    test_throw(`\777`);
}

/// Split arguments while accounting for quotes.
///
/// Word splitting, quoting, and escapes, in one pass, out the other end as
/// bytes. Quoting style selects how a run of text is read, the same way it does
/// in a programming language, and the two quotes buy two independent things:
///
/// ---
///              protects whitespace    escape sequences
///  utf8:text          no                   no
///  utf8:'text'        yes                  no
///  utf8:"text"        yes                  yes
/// ---
///
/// So `utf8:C:\Users` and `utf8:'C:\Program Files'` are paths as typed, while
/// `utf8:"\x1b[0m"` is an escape sequence:
///
/// $(UL
/// $(LI Unquoted and `'single quoted'` text is raw. Every byte up to the end of
///      the run is taken verbatim, backslashes included, and there are no
///      escapes at all. A `'` therefore cannot appear inside single quotes.)
/// $(LI `"double quoted"` text is a C string literal and is resolved here, see
///      unescape. An unknown escape is an error rather than a backslash that
///      means itself, so `"C:\dir"` is `'C:\dir'` or `"C:\\dir"`.)
/// )
///
/// Adjacent runs concatenate into one argument, each read its own way, so
/// `utf8:'C:\Users'"\0"` is a raw path followed by a NUL. That is a plain
/// concatenation of literals, as in any language that has more than one kind.
///
/// A quote is written by using the other kind (`"'"`, `'"'`), which is the only
/// way, there being no escapes outside of double quotes.
///
/// The result is bytes because an escape can produce one that is not text: it
/// is up to the command to say whether it wanted text, see Argument.text.
///
/// Uses the GC to append to the new array.
/// Params: buffer = Shell-like input.
/// Returns: Arguments.
/// Throws: Exception on an unterminated quote or an invalid escape sequence.
Argument[] arguments(const(char)[] buffer)
{
    import std.string : strip;
    import std.ascii : isControl, isWhite;
    import std.conv : text;
    import messages : MSG_UNTERMINATED_QUOTE;
    
    buffer = strip(buffer);
    
    if (buffer.length == 0) return [];
    
    Argument[] results;
    immutable(ubyte)[] data; // Bytes of the argument being read
    
    // Empty quotes are not an empty argument, they are no argument
    void flush()
    {
        if (data.length == 0) return;

        results ~= Argument(data);
        data = null;
    }

    for (size_t i; i < buffer.length; ++i)
    {
        char c = buffer[i];

        // Whitespace outside of a quote ends the argument
        if (isControl(c) || isWhite(c))
        {
            flush();
            continue;
        }

        // Single quotes are literal to the byte. They end at the next quote and
        // nothing in between is syntax, not even a backslash, which is what
        // makes them the form for data carrying its own
        if (c == '\'')
        {
            size_t start = ++i;
            while (i < buffer.length && buffer[i] != '\'') ++i;
            if (i >= buffer.length)
                throw new Exception(text(MSG_UNTERMINATED_QUOTE, c));
            data ~= cast(const(ubyte)[])buffer[start..i];
            continue;
        }

        // Double quotes are a C string. The end of the run is found first, with
        // a backslash only recognized as covering the next character, so a pair
        // cannot swallow the closing quote and `"C:\\"` terminates
        if (c == '"')
        {
            size_t start = ++i;
            for (; i < buffer.length; ++i)
            {
                if (buffer[i] == '\\') { ++i; continue; }
                if (buffer[i] == '"') break;
            }
            if (i >= buffer.length)
                throw new Exception(text(MSG_UNTERMINATED_QUOTE, c));
            data ~= unescape(buffer[start..i]);
            continue;
        }

        // Unquoted text is raw and runs until whitespace or a quote
        size_t start = i;
        while (i < buffer.length)
        {
            char u = buffer[i];
            if (isControl(u) || isWhite(u) || u == '\'' || u == '"') break;
            ++i;
        }
        data ~= cast(const(ubyte)[])buffer[start..i];
        --i; // Whatever stopped the run has not been read yet
    }

    flush();

    return results;
}
@system unittest
{
    void test_throw(string input)
    {
        Argument[] r;
        try { r = arguments(input); } catch (Exception) { return; }

        import std.stdio : stderr, writeln;
        stderr.writeln("Failed to throw with: ", input, " it produced: ", r);
        assert(false, "test_throw test failed");
    }

    assert(texts(arguments("")) == []);
    assert(texts(arguments("\n")) == []);
    assert(texts(arguments("a")) == [ "a" ]);
    assert(texts(arguments("simple")) == [ "simple" ]);
    assert(texts(arguments("simple a b c")) == [ "simple", "a", "b", "c" ]);
    assert(texts(arguments("simple test\n")) == [ "simple", "test" ]);
    assert(texts(arguments("simple test\r\n")) == [ "simple", "test" ]);
    assert(texts(arguments("/simple/ /test/")) == [ "/simple/", "/test/" ]);
    assert(texts(arguments(`simple 'test extreme'`)) == [ "simple", "test extreme" ]);
    assert(texts(arguments(`simple "test extreme"`)) == [ "simple", "test extreme" ]);
    assert(texts(arguments(`simple '  hehe  '`)) == [ "simple", "  hehe  " ]);
    assert(texts(arguments(`simple "  hehe  "`)) == [ "simple", "  hehe  " ]);
    assert(texts(arguments(`a 'b c' d`)) == [ "a", "b c", "d" ]);
    assert(texts(arguments(`a "b c" d`)) == [ "a", "b c", "d" ]);
    assert(texts(arguments(`/type 'yes string'`)) == [ "/type", "yes string" ]);
    assert(texts(arguments(`/type "yes string"`)) == [ "/type", "yes string" ]);
    assert(texts(arguments(`A           B`)) == [ "A", "B" ]);

    // Double quotes are the C string literal, so that is the one place a
    // backslash is syntax. Everywhere else it is data and costs nothing
    assert(texts(arguments(`find utf8:a\tb`)) == [ "find", `utf8:a\tb` ]);
    assert(texts(arguments(`find "a\tb"`)) == [ "find", "a\tb" ]);
    assert(texts(arguments(`find utf8:C:\\Users`)) == [ "find", `utf8:C:\\Users` ]);
    assert(texts(arguments(`find "utf8:C:\\Users"`)) == [ "find", `utf8:C:\Users` ]);
    assert(texts(arguments(`test\\ value`)) == [ `test\\`, "value" ]);
    assert(texts(arguments(`test\\value`)) == [ `test\\value` ]);
    assert(texts(arguments(`"a\\ b"`)) == [ `a\ b` ]);
    assert(texts(arguments(`a "b \"c\" d"`)) == [ "a", `b "c" d` ]);
    assert(texts(arguments(`open C:\dir`)) == [ "open", `C:\dir` ]);

    // An unknown escape is an error, not a backslash that means itself, so a
    // Windows path in double quotes has to say which it is. Bash would take
    // `"C:\dir"` as written and `"C:\take"` as a path with a tab in it
    test_throw(`open "C:\dir"`);
    assert(texts(arguments(`open 'C:\dir'`)) == [ "open", `C:\dir` ]);
    assert(texts(arguments(`open "C:\\dir"`)) == [ "open", `C:\dir` ]);

    // Single quotes are literal: not even a backslash is syntax inside
    assert(texts(arguments(`find 'a\tb'`)) == [ "find", `a\tb` ]);
    assert(texts(arguments(`find 'utf8:C:\\Users'`)) == [ "find", `utf8:C:\\Users` ]);
    assert(texts(arguments(`open 'C:\dir'`)) == [ "open", `C:\dir` ]);
    assert(texts(arguments(`open 'C:\'`)) == [ "open", `C:\` ]);
    assert(texts(arguments(`open C:\`)) == [ "open", `C:\` ]);
    assert(texts(arguments(`'a "b" c'`)) == [ `a "b" c` ]);
    assert(texts(arguments(`'a \"b\" c'`)) == [ `a \"b\" c` ]);

    // A quote is written with the other kind of quote, there being nothing else
    // to write it with. The POSIX `'\''` idiom does not apply here: outside of
    // double quotes a backslash is data, so it leaves a dangling quote
    assert(texts(arguments(`'it'"'"'s'`)) == [ `it's` ]);
    assert(texts(arguments(`"it"'"'"s"`)) == [ `it"s` ]);
    assert(texts(arguments(`say'"'hi'"'`)) == [ `say"hi"` ]);
    test_throw(`'it'\''s'`);
    test_throw(`\"a\"`);

    // Adjacent spans concatenate into one argument, so a quote can cover part
    // of an argument and the prefix can sit inside or outside it
    assert(texts(arguments(`utf8:'a''b'`)) == [ `utf8:ab` ]);
    assert(texts(arguments(`utf8:'a'"b"`)) == [ `utf8:ab` ]);
    assert(texts(arguments(`'utf8:'abc`)) == [ `utf8:abc` ]);
    assert(texts(arguments(`a'b'c`)) == [ `abc` ]);

    // Nested/mixed quotes
    assert(texts(arguments(`a "b 'c' d" e`)) == [ "a", `b 'c' d`, "e" ]);
    assert(texts(arguments(`a 'b "c" d' e`)) == [ "a", `b "c" d`, "e" ]);

    // Empty quotes are not an empty argument, they are no argument: there is
    // no command here that distinguishes "" from absent, and dropping keeps
    // 'find ""' an obvious "Need search" rather than an obscure empty needle
    assert(texts(arguments(`find ''`)) == [ "find" ]);
    assert(texts(arguments(`find ""`)) == [ "find" ]);
    assert(texts(arguments(`find '' x:00`)) == [ "find", "x:00" ]);

    // Unterminated quotes are an error, not a line that ends where it stopped
    test_throw(`find 'abc`);
    test_throw(`find "abc`);
    test_throw(`'`);
    test_throw(`"`);
    // A backslash covers the next character, so it cannot swallow the closing
    // quote and a C string can end on one
    assert(texts(arguments(`"test\\"`)) == [ `test\` ]);
    assert(texts(arguments(`a "b\\" c`)) == [ "a", `b\`, "c" ]);
    assert(texts(arguments(`"C:\\"`)) == [ `C:\` ]);
    assert(texts(arguments(`"a\\\"b"`)) == [ `a\"b` ]);
    test_throw(`"abc\"`);

    // Quoting is what selects how a run is read, and unquoted and single quoted
    // are the same raw thing: single quotes only hold an argument together
    assert(arguments(`a`)        == [ Argument(`a`) ]);
    assert(arguments(`'a'`)      == [ Argument(`a`) ]);
    assert(arguments(`"a"`)      == [ Argument(`a`) ]);
    assert(arguments(`utf8:"a"`) == [ Argument(`utf8:a`) ]);
    assert(arguments(`"utf8:a"`) == [ Argument(`utf8:a`) ]);
    assert(arguments(`a "b" c`) == [ Argument(`a`), Argument(`b`), Argument(`c`) ]);

    // Mixing the two forms is a concatenation of literals, as in any language
    // that has more than one kind, so each part keeps its own meaning: a raw
    // path with a NUL stuck on the end
    assert(arguments(`utf8:'C:\dir'"\0"`) == [ Argument(cast(immutable(ubyte)[])"utf8:C:\\dir\0") ]);
    assert(arguments(`utf8:"a"b`)         == [ Argument(`utf8:ab`) ]);
    assert(arguments(`utf8:C:\dir"a b"`)  == [ Argument(`utf8:C:\dir` ~ `a b`) ]);
    assert(arguments(`utf8:'a'b"c""d"`)   == [ Argument(`utf8:abcd`) ]);

    // Bytes that no encoding claims are still an argument. That is the whole
    // point of resolving escapes here: `"\xff"` used to be untypable outside
    // of a pattern, and text was the wrong type for it everywhere
    assert(arguments(`"\xff"`)  == [ Argument(cast(immutable(ubyte)[])[ 0xff ]) ]);
    assert(arguments(`"a\0b"`)  == [ Argument(cast(immutable(ubyte)[])"a\0b") ]);
    assert(arguments(`"\xff"a`) == [ Argument(cast(immutable(ubyte)[])[ 0xff, 'a' ]) ]);
    // ...and only a command that wanted text says so
    try
    {
        cast(void)texts(arguments(`open "\xff"`));
        assert(false, "text() should have thrown");
    }
    catch (Exception) {}

    assert(texts(arguments(`find utf8:WARNING: %s`)) == [ "find", `utf8:WARNING:`, `%s` ]);
    assert(texts(arguments(`find utf8:"WARNING: %s"`)) == [ "find", `utf8:WARNING: %s` ]);
    assert(texts(arguments(`find "WARNING: %s"`)) == [ "find", `WARNING: %s` ]);
}

/// Parse string as hexadecimal, decimal, or octal.
/// Params: input = String input.
/// Returns: Parsed value.
/// Throws: Exception when errno != 0.
long scan(scope string input)
{
    import std.conv : parse;
    import std.string : indexOf, strip, startsWith;
    
    // Imitate stroll a little by ignoring whitespace
    input = strip(input);
    if (input.length == 0)
        throw new Exception("Empty scan");
    
    // Hex: stroll supports "0X" but don't see the appeal yet
    if (startsWith(input, "0x"))
    {
        input = input[2..$]; // parse(ref Source source, uint radix)
        return parse!long(input, 16);
    }
    // Binary: C23 supports "0b" and "0B" for binary numbers
    else if (startsWith(input, "0b"))
    {
        input = input[2..$];
        return parse!long(input, 2);
    }
    // Octal
    else if (input.length > 2 && input[0] == '0')
    {
        input = input[1..$];
        return parse!long(input, 8);
    }
    // NOTE: Decimal is the only base where negative sign is allowed
    else
    {
        return parse!long(input, 10);
    }
}
@system unittest
{
    import std.conv : octal;
    
    // decimal
    assert(scan("0")   == 0);
    assert(scan("1")   == 1);
    assert(scan("2")   == 2);
    assert(scan("10")  == 10);
    assert(scan("-10") == -10);
    // hex
    assert(scan("0x0")  == 0);
    assert(scan("0x1")  == 0x1);
    assert(scan("0x2")  == 0x2);
    assert(scan("0x10") == 0x10);
    // binary
    assert(scan("0b0")  == 0);
    assert(scan("0b1")  == 0b1);
    assert(scan("0b10") == 0b10);
    assert(scan("0b11") == 0b11);
    // octal
    assert(scan("00")  == 0);
    assert(scan("01")  == octal!"1");
    assert(scan("02")  == octal!"2");
    assert(scan("010") == octal!"10");
}

/// Parse as a binary number with optional suffix up to gigabytes.
///
/// For example, "32K" translates to 32768 (Bytes, 32 * 1024).
/// Params: input = String input.
/// Returns: Byte count.
/// Throws: Exception or ConvException on error.
ulong parsebin(scope string input)
{
    import ddhx.platform : assertion;
    import std.conv : parse;
    
    assertion(input, "input is NULL");
    assertion(input.length, "input is EMPTY");
    
    ulong mult = 1;
    if (input.length > 1)
    {
        switch (input[$-1]) {
        case 'k', 'K':
            input = input[0..$-1];
            mult = 1024;
            break;
        case 'm', 'M':
            input = input[0..$-1];
            mult = 1024 * 1024;
            break;
        case 'g', 'G':
            input = input[0..$-1];
            mult = 1024 * 1024 * 1024;
            break;
        default:
        }
    }
    
    return parse!ulong(input) * mult;
}
@system unittest
{
    assert(parsebin("0") == 0);
    assert(parsebin("1") == 1);
    assert(parsebin("10") == 10);
    assert(parsebin("8086") == 8086);
    
    assert(parsebin("1k") ==     1024);
    assert(parsebin("1K") ==     1024);
    assert(parsebin("2K") == 2 * 1024);
    assert(parsebin("1024K") == 1024 * 1024);
    
    assert(parsebin("1m") ==     1024 * 1024);
    assert(parsebin("1M") ==     1024 * 1024);
    assert(parsebin("2M") == 2 * 1024 * 1024);
    
    assert(parsebin("1g") ==      1024 * 1024 * 1024);
    assert(parsebin("1G") ==      1024 * 1024 * 1024);
    assert(parsebin("2G") == 2L * 1024 * 1024 * 1024);
    
    try
    {
        parsebin(null); // @suppress(dscanner.unused_result)
        assert(false); // Needs to throw
    }
    catch (Exception) {}
    
    try
    {
        parsebin(""); // @suppress(dscanner.unused_result)
        assert(false); // Needs to throw
    }
    catch (Exception) {}
    
    try
    {
        parsebin("-"); // @suppress(dscanner.unused_result)
        assert(false); // Needs to throw
    }
    catch (Exception) {}
    
    try
    {
        parsebin("-1"); // @suppress(dscanner.unused_result)
        assert(false); // Needs to throw
    }
    catch (Exception) {}
}

/// Align a value downwards.
/// Params:
///     v = Value.
///     alignment = Alignment value.
/// Returns: Aligned value.
long align64down(long v, size_t alignment)
{
	long mask = alignment - 1;
	return v & ~mask;
}
unittest
{
    assert(align64down( 0, 16) == 0);
    assert(align64down( 1, 16) == 0);
    assert(align64down( 2, 16) == 0);
    assert(align64down(15, 16) == 0);
    assert(align64down(16, 16) == 16);
    assert(align64down(17, 16) == 16);
    assert(align64down(31, 16) == 16);
    assert(align64down(32, 16) == 32);
    assert(align64down(33, 16) == 32);
}

/// Align a value upwards.
/// Params:
///     v = Value.
///     alignment = Alignment value.
/// Returns: Aligned value.
long align64up(long v, size_t alignment)
{
	long mask = alignment - 1;
	return (v+mask) & ~mask;
}
unittest
{
    assert(align64up( 0, 16) == 0);
    assert(align64up( 1, 16) == 16);
    assert(align64up( 2, 16) == 16);
    assert(align64up(15, 16) == 16);
    assert(align64up(16, 16) == 16);
    assert(align64up(17, 16) == 32);
    assert(align64up(31, 16) == 32);
    assert(align64up(32, 16) == 32);
    assert(align64up(33, 16) == 48);
}

/// Divides an integer by a whole percentage.
/// Params:
///     a = Number
///     per = Percent (0-100)
/// Returns: Number. Value of 1000 with per=50(%) will give 500.
long llpercentdiv(long a, int per)
{
    return (a * per) / 100;
}
unittest
{
    assert(llpercentdiv(1000,   0) == 0);
    assert(llpercentdiv(1000,  50) == 500);
    assert(llpercentdiv(1000, 100) == 1000);
    assert(llpercentdiv(  64,  50) == 32);
}

/// Divides an integer by a percentage.
/// Params:
///     a = Number
///     per = Percent (0-100)
/// Returns: Number. Value of 1000 with per=50.0(%) will give 500.
long llpercentdivf(long a, double per)
{
    import std.math : round;
    return cast(long)round((cast(double)a * per) / 100.0);
}
unittest
{
    assert(llpercentdivf(1000,   0.0) == 0);
    assert(llpercentdivf(1000,  50.0) == 500);
    assert(llpercentdivf(1000,  55.5) == 555);
    assert(llpercentdivf(1000, 100.0) == 1000);
    assert(llpercentdivf(  64,  50.0) == 32);
}

/// Simple buffered writer structure with custom flush function
/// Params:
///     FLUSHER = Flush function.
///     SIZE = Size of the buffer.
struct BufferedWriter(void function(void*,size_t) FLUSHER, size_t SIZE = 2048)
{
    private ubyte[SIZE] buffer;
    private size_t index;
    private void function(void*,size_t) flusher = FLUSHER;
    
    /// Append data to the buffer
    /// Automatically flushes if buffer would overflow
    void put(scope const(ubyte)[] data)
    {
        if (data.length > SIZE)
        {
            flush();
            flusher(cast(void*)data.ptr, data.length);
            return;
        }
        
        if (data.length + index > SIZE)
        {
            size_t avail = available();
            buffer[index .. index + avail] = data[0 .. avail];
            index += avail;
            flush();
            data = data[avail .. $];
        }
        
        buffer[index .. index + data.length] = data[];
        index += data.length;
    }
    
    /// Append a string to the buffer
    void put(scope const(char)[] str)
    {
        put(cast(const(ubyte)[])str);
    }
    
    /// Put a single character
    void put(char c)
    {
        if (1 + index > SIZE)
            flush();
        buffer[index] = cast(ubyte)c;
        index++;
    }
    
    void repeat(char c, size_t count)
    {
        if (count == 0) return;
        
        // Handle large counts that exceed buffer
        if (count > SIZE)
        {
            flush();
            
            buffer[] = c;
            
            while (count > SIZE)
            {
                flusher(buffer.ptr, SIZE);
                count -= SIZE;
            }
            
            if (count > 0)
            {
                flusher(buffer.ptr, count);
            }
            return;
        }
        
        // Normal case - fits in buffer (possibly after flush)
        if (count + index > SIZE)
        {
            flush();
        }
        
        buffer[index .. index + count] = c;
        index += count;
    }
    
    /// Write buffered data to stdout
    void flush()
    {
        if (index > 0)
        {
            size_t len = index;
            index = 0;
            flusher(buffer.ptr, len);
        }
    }
    
    /// Clear buffer without flushing
    void reset()
    {
        index = 0;
    }
    
    /// Returns number of bytes currently in buffer.
    /// Returns: Size in bytes.
    size_t length() const
    {
        return index;
    }
    
    /// Returns remaining space in buffer.
    /// Returns: Size in bytes.
    size_t available() const
    {
        return SIZE - index;
    }
    
    /// Returns true if buffer is empty
    /// Returns: True if empty.
    bool empty() const
    {
        return index == 0;
    }
}
unittest
{
    BufferedWriter!((void *data, size_t size) {
        assert(data);
        assert(size == 3);
    }, 16) bufwriter;
    bufwriter.put("gay");
    assert(bufwriter.index == 3);
    assert(bufwriter.buffer[0..3] == "gay");
    bufwriter.flush();
}
unittest
{
    // Incoming data too large to hold into buffer
    string str2 = "very long string that flushes once"; // 34
    BufferedWriter!((void *data, size_t size) {
        assert(data);
        assert(size == 34);
    }, 16) bufwriter;
    bufwriter.put(str2);
    assert(bufwriter.index == 0); // flushed
}
unittest
{
    // 
    BufferedWriter!((void *data, size_t size) {
        assert(data);
        assert(size == 16);
    }, 16) bufwriter;
    bufwriter.put("1234567890");
    bufwriter.put("1234567890");
    assert(bufwriter.index == 4);
}