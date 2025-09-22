/// OS error handling.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module os.error;

version (Windows)
{
    import core.sys.windows.winbase;
    import std.format;
    private alias systemerr = GetLastError;
}
else
{
    import core.stdc.string;
    import std.string;
    import core.stdc.errno : errno;
    private alias systemerr = errno;
}

/// OS error exception.
class OSException : Exception
{
    /// New exception with optional message prefix 
    this(string prefix = null,
        int code = systemerr(),
        string _file = __FILE__, size_t _line = __LINE__)
    {
        oscode = code;
        if (prefix)
            super(prefix~": "~messageFromCode(code), _file, _line);
        else
            super(messageFromCode(code), _file, _line);
    }
    
    /// Original OS code.
    int oscode;
}

private
string messageFromCode(int code)
{
    version (Windows)
    {
        enum BUFSZ = 256;
        __gshared char[BUFSZ] buffer;
        uint len = FormatMessageA(
            FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_MAX_WIDTH_MASK,
            null,
            code,
            0,	// Default
            buffer.ptr,
            BUFSZ,
            null);
        
        import std.conv : text;
        if (len == 0)
            throw new Exception(text("FormatMessageA Error=", GetLastError(), " Original=", code));
        
        return cast(string)buffer[0..len];
    }
    else
    {
        return cast(string)fromStringz( strerror(code) );
    }
}