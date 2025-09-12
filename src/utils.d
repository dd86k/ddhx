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
    // NOTE: Using split/splitter would destroy quoted arguments
    
    // TODO: Escape characters (with '\\')
    
    buffer = strip(buffer);
    
    if (buffer.length == 0) return [];
    
    string[] results;
    const size_t buflen = buffer.length;
    char delim = void;
    
    for (size_t index, start; index < buflen; ++index)
    {
        char c = buffer[index];
        
        if (isControl(c) || isWhite(c))
            continue;
        
        switch (c) {
        case '"', '\'':
            delim = c;
            
            for (start = ++index, ++index; index < buflen; ++index)
            {
                c = buffer[index];
                if (c == delim)
                    break;
            }
            
            results ~= cast(string)buffer[start..(index++)];
            break;
        default:
            for (start = index, ++index; index < buflen; ++index)
            {
                c = buffer[index]; 
                if (isControl(c) || isWhite(c))
                    break;
            }
            
            results ~= cast(string)buffer[start..index];
        }
    }
    
    return results;
}
@system unittest
{
    // TODO: Test nested string quotes
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
    //assert(arguments(`tab\tmoment`) == [ "tab", "moment" ]);
}

// Parse string as long supporting dec/hex/oct bases.
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

// Parse as a binary number with optional suffix up to gigabytes.
//
// For example, "32K" translates to 32768 (Bytes, 32 * 1024).
ulong parsebin(scope string input)
{
    import std.exception : enforce;
    import std.conv : to;
    
    enforce(input, "input is NULL");
    enforce(input.length, "input is EMPTY");
    
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
        parsebin(null);
        assert(false); // Needs to throw
    }
    catch (Exception) {}
    
    try
    {
        parsebin("");
        assert(false); // Needs to throw
    }
    catch (Exception) {}
}

// Utility to help with address alignment
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

// Utility to help with address alignment
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

/// Divides an integer by a whole percentage
/// Params:
///     a = Number
///     per = Percent (0-100)
/// Returns: Number. Value of 1000 with per=50(%) will give 500.
long llpercentdiv(long a, int per)
{
    // TODO: Check for overflow using std.numeric (if available) or manually
    return (a * per) / 100;
}
unittest
{
    assert(llpercentdiv(1000,   0) == 0);
    assert(llpercentdiv(1000,  50) == 500);
    assert(llpercentdiv(1000, 100) == 1000);
}
