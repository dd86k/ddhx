/// Utilities to handle arguments.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.utils.args;

import ddhx.utils.strings : cparse;
//import core.stdc.ctype : isprint

/// Separate buffer into arguments (akin to argv).
/// Params: buffer = String buffer.
/// Returns: Argv-like array.
string[] arguments(const(char)[] buffer)
{
    import std.string : strip;
    import std.ascii : isControl, isWhite;
    // NOTE: Using split/splitter would destroy quoted arguments
    
    //TODO: Escape characters (with '\\')
    
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
    //TODO: Test embedded string quotes
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

struct Position
{
    ulong position;
    char op;
}

Position parsePosition(string text)
{
    switch (text[0]) {
    case '-':   return Position(-cparse(text[1..$]), '-');
    case '+':   return Position(cparse(text[1..$]), '+');
    default:    return Position(cparse(text), 0);
    }
}
unittest
{
    Position abs = parsePosition("0x1234");
    assert(abs.op == 0);
    assert(abs.position == 0x1234);
    
    Position revm = parsePosition("-1234");
    assert(revm.op == '-');
    assert(revm.position == -1234);
    
    import std.conv : octal;
    
    Position reva = parsePosition("+0123");
    assert(reva.op == '+');
    assert(reva.position == octal!"123");
}