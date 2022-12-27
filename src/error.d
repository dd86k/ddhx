/// Error handling.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module error;
 
import std.stdio;

/// Error codes
enum ErrorCode {
    success,
    fileEmpty = 2,
    negativeValue,
    inputEmpty,
    invalidCommand,
    invalidSetting,
    invalidParameter,
    invalidNumber,
    invalidType,
    invalidCharset,
    notFound, // ??
    overflow,
    unparsable,
    noLastItem,
    eof, // ??
    unimplemented,
    insufficientSpace,
    missingOption,
    missingValue,
    missingType,
    missingNeedle,
    screenMinimumRows,
    screenMinimumColumns,
    
    // Settings
    
    settingFileMissing = 100,
    settingColumnsInvalid,
    
    // Special
    
    unknown = 0xf000,
    exception,
}
/// Error source
enum ErrorSource {
    code,
    exception,
    os,
}

private struct last_t {
    const(char)[] message;
    const(char)[] file;
    int line;
    ErrorSource source;
}
private __gshared last_t last;
__gshared int errorcode; /// Last error code.

/// Get system error message from an error code.
/// Params: code = System error code.
/// Returns: Error message.
const(char)[] systemMessage(int code)
{
    import std.string : fromStringz;
    
    version (Windows)
    {
        import core.sys.windows.winbase :
            LocalFree, FormatMessageA,
            FORMAT_MESSAGE_ALLOCATE_BUFFER, FORMAT_MESSAGE_FROM_SYSTEM,
            FORMAT_MESSAGE_IGNORE_INSERTS;
        import core.sys.windows.winnt :
            MAKELANGID, LANG_NEUTRAL, SUBLANG_DEFAULT;
        
        enum LANG = MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT);
        
        char *strerror;
        
        uint r = FormatMessageA(
            FORMAT_MESSAGE_ALLOCATE_BUFFER |
            FORMAT_MESSAGE_FROM_SYSTEM |
            FORMAT_MESSAGE_IGNORE_INSERTS,
            null,
            code,
            LANG,
            cast(char*)&strerror,
            0,
            null);
        
        assert(strerror, "FormatMessageA failed");
        
        if (strerror[r - 1] == '\n') --r;
        if (strerror[r - 1] == '\r') --r;
        string msg = strerror[0..r].idup;
        LocalFree(strerror);
        return msg;
    } else {
        import core.stdc.string : strerror;
        
        return strerror(code).fromStringz;
    }
}

int errorSet(ErrorCode code, string file = __FILE__, int line = __LINE__)
{
    version (unittest)
    {
        import std.stdio : writefln;
        writefln("%s:%u: %s", file, line, code);
    }
    version (Trace) trace("%s:%u: %s", file, line, code);
    last.file = file;
    last.line = line;
    last.source = ErrorSource.code;
    return (errorcode = code);
}

int errorSet(Exception ex)
{
    version (unittest)
    {
        import std.stdio : writeln;
        writeln(ex);
    }
    version (Trace)
    {
        debug trace("%s", ex);
        else  trace("%s", ex.msg);
    }
    last.file = ex.file;
    last.line = cast(int)ex.line;
    last.message = ex.msg;
    last.source = ErrorSource.exception;
    return (errorcode = ErrorCode.exception);
}

int errorSetOs(string file = __FILE__, int line = __LINE__)
{
    version (Windows)
    {
        import core.sys.windows.winbase : GetLastError;
        errorcode = GetLastError();
    }
    else version (Posix)
    {
        import core.stdc.errno : errno;
        errorcode = errno;
    }
    version (Trace) trace("errorcode=%u line=%s:%u", errorcode, file, line);
    last.file = file;
    last.line = line;
    last.source = ErrorSource.os;
    return errorcode;
}

const(char)[] errorMessage(int code = errorcode)
{
    final switch (last.source) with (ErrorSource) {
    case os: return systemMessage(errorcode);
    case exception: return last.message;
    case code:
    }
    
    switch (code) with (ErrorCode) {
    case fileEmpty: return "File is empty.";
    case inputEmpty: return "Input is empty.";
    case invalidCommand: return "Command not found.";
    case invalidSetting: return "Invalid setting property.";
    case invalidParameter: return "Parameter is invalid.";
    case invalidType: return "Invalid type.";
    case eof: return "Unexpected end of file (EOF).";
    case notFound: return "Data not found.";
    case overflow: return "Integer overflow.";
    case unparsable: return "Integer could not be parsed.";
    case noLastItem: return "No previous search items saved.";
    case insufficientSpace: return "Too little space left to search.";
    
    // Settings
    
    case settingFileMissing: return "Settings file does not exist at given path.";
    case settingColumnsInvalid: return "Columns cannot be zero.";
    
    case success: return "No errors occured.";
    default: return "Internal error occured.";
    }
}

int errorPrint()
{
    return errorPrint(errorcode, errorMessage());
}
int errorPrint(A...)(int code, const(char)[] fmt, A args)
{
    stderr.write("error: ");
    stderr.writefln(fmt, args);
    return code;
}

version (Trace)
{
    public import std.datetime.stopwatch;
    
    private __gshared File log;
    
    void traceInit(string n)
    {
        log.open("ddhx.log", "w");
        trace(n);
    }
    void trace(string func = __FUNCTION__, int line = __LINE__, A...)()
    {
        log.writefln("TRACE:%s:%u", func, line);
        log.flush;
    }
    void trace(string func = __FUNCTION__, int line = __LINE__, A...)(string fmt, A args)
    {
        log.writef("TRACE:%s:%u: ", func, line);
        log.writefln(fmt, args);
        log.flush;
    }
}
