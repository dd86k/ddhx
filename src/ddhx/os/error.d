/// OS error handling.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.os.error;

version (Windows)
{
    import core.sys.windows.winbase;
    import std.format;
}
else
{
    import core.stdc.string;
    import std.string;
}

string messageFromCode(int code)
{
version (Windows)
{
    // TODO: Get console codepage
    enum BUFSZ = 1024;
    __gshared char[BUFSZ] buffer;
    uint len = FormatMessageA(
        FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_MAX_WIDTH_MASK,
        null,
        code,
        0,	// Default
        buffer.ptr,
        BUFSZ,
        null);
    
    if (len == 0)
        return cast(string)sformat(buffer, "FormatMessageA returned code %#x", GetLastError());
    
    return cast(string)buffer[0..len];
}
else
{
    return fromStringz( strerror(code) );
}
}