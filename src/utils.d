/// Utilities.
/// 
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module utils;

/// Split arguments while accounting for quotes.
///
/// Uses the GC to append to the new array.
/// Params: buffer = Shell-like input.
/// Returns: Arguments.
/// Throws: Does not explicitly throw any exceptions.
string[] arguments(const(char)[] buffer)
{
    import std.string : strip;
    import std.ascii : isControl, isWhite;
    import std.array : appender;
    
    buffer = strip(buffer);
    
    if (buffer.length == 0) return [];
    
    string[] results;
    scope auto argBuf = appender!string();
    bool inQuote = false;
    char quoteChar;
    
    for (size_t i; i < buffer.length; ++i)
    {
        char c = buffer[i];
        
        // Skip leading whitespace when not in a quote
        if (!inQuote && (isControl(c) || isWhite(c)))
        {
            // If we have accumulated text, save it
            if (argBuf.data.length > 0)
            {
                results ~= argBuf.data;
                argBuf = appender!string(); // Create new appender
            }
            continue;
        }
        
        // Handle escape character
        if (c == '\\' && i + 1 < buffer.length)
        {
            char next = buffer[i + 1];
            // Escape next character if it's a quote, backslash, or we're in a quote
            if (next == '"' || next == '\'' || next == '\\' || inQuote)
            {
                argBuf.put(next);
                ++i; // Skip the escaped character
                continue;
            }
        }
        
        // Handle quotes
        if ((c == '"' || c == '\'') && !inQuote)
        {
            inQuote = true;
            quoteChar = c;
            continue;
        }
        else if (inQuote && c == quoteChar)
        {
            inQuote = false;
            continue;
        }
        
        // Regular character - add to buffer
        argBuf.put(c);
    }
    
    // Add any remaining argument
    if (argBuf.data.length > 0)
        results ~= argBuf.data;
    
    return results;
}

@system unittest
{
    assert(arguments("") == []);
    assert(arguments("\n") == []);
    assert(arguments("a") == [ "a" ]);
    assert(arguments("simple") == [ "simple" ]);
    assert(arguments("simple a b c") == [ "simple", "a", "b", "c" ]);
    assert(arguments("simple test\n") == [ "simple", "test" ]);
    assert(arguments("simple test\r\n") == [ "simple", "test" ]);
    assert(arguments("/simple/ /test/") == [ "/simple/", "/test/" ]);
    assert(arguments(`simple 'test extreme'`) == [ "simple", "test extreme" ]);
    assert(arguments(`simple "test extreme"`) == [ "simple", "test extreme" ]);
    assert(arguments(`simple '  hehe  '`) == [ "simple", "  hehe  " ]);
    assert(arguments(`simple "  hehe  "`) == [ "simple", "  hehe  " ]);
    assert(arguments(`a 'b c' d`) == [ "a", "b c", "d" ]);
    assert(arguments(`a "b c" d`) == [ "a", "b c", "d" ]);
    assert(arguments(`/type 'yes string'`) == [ "/type", "yes string" ]);
    assert(arguments(`/type "yes string"`) == [ "/type", "yes string" ]);
    assert(arguments(`A           B`) == [ "A", "B" ]);
    
    // Escape tests
    assert(arguments(`a \"b c\" d`) == [ "a", `"b`, `c"`, "d" ]);
    assert(arguments(`a "b \"c\" d"`) == [ "a", `b "c" d` ]);
    assert(arguments(`a 'b \'c\' d'`) == [ "a", `b 'c' d` ]);
    assert(arguments(`test\\ value`) == [ `test\`, "value" ]);
    assert(arguments(`test\\value`) == [ `test\value` ]);
    assert(arguments(`"test\\"`) == [ `test\` ]);
    assert(arguments(`'test\\'`) == [ `test\` ]);
    assert(arguments(`a\\ b`) == [ `a\`, "b" ]);
    assert(arguments(`"a\\ b"`) == [ `a\ b` ]);
    assert(arguments(`\"a\"`) == [ `"a"` ]);
    
    // Nested/mixed quotes
    assert(arguments(`a "b 'c' d" e`) == [ "a", `b 'c' d`, "e" ]);
    assert(arguments(`a 'b "c" d' e`) == [ "a", `b "c" d`, "e" ]);
}

/// Parse string as hexadecimal, decimal, or octal.
/// Params: input = String input.
/// Returns: Parsed value.
/// Throws: Exception when errno != 0.
long scan(scope string input)
{
    // std.format.read, std.conv.to, and std.conv.parse makes this harder
    // than it should be...
    // If we need ulong, use strtoull
    
    import core.stdc.stdlib : strtoll;
    import core.stdc.errno : errno;
    import core.stdc.string : strerror;
    import std.string : toStringz, fromStringz;
    
    errno = 0;
    long i = strtoll(toStringz(input), null, 0);
    if (errno)
        throw new Exception(cast(string)fromStringz(strerror(errno)));
    
    return i;
}
@system unittest
{
    import std.conv : octal;
    
    assert(scan("0") == 0);
    // decimal
    assert(scan("1") == 1);
    assert(scan("2") == 2);
    assert(scan("10") == 10);
    // hex
    assert(scan("0x1")  == 0x1);
    assert(scan("0x2")  == 0x2);
    assert(scan("0x10") == 0x10);
    // octal
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
    import platform : assertion;
    import std.conv : to;
    
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
    
    return to!ulong(input) * mult;
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