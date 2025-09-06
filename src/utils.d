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

long scan(scope string input)
{
    // std.format.read, std.conv.to, and std.conv.parse makes this harder
    // than it should be...
    
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
