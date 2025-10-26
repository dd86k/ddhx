/// Basic logger.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module logger;

import std.stdio;
import std.datetime.stopwatch;

private __gshared
{
    StopWatch sw;
    File tracefile;
    bool tracing;
}

// When Trace version is specified (e.g., dub test --d-version=Trace),
// turn on logs and send them to stderr.
version (Trace)
{
    static this()
    {
        tracing = true;
        tracefile = stderr;
        sw.start();
    }
}
// TODO: Consider autostart when DDHX_LOG is set (file or stderr)

/// Start logging to this file.
/// Params: file = File path.
void logStart(string file = "ddhx.log")
{
    logOpen(file); // old behavior
    sw.start();
    tracing = true;
    
    import std.datetime.systime : Clock;
    log("Trace started at %s", Clock.currTime());
}

/// Set the file path to log to.
/// Params: file = File path.
void logOpen(string file)
{
    tracefile = File(file, "w");
    tracefile.setvbuf(0, _IONBF);
}

/// Stop logging.
void logStop()
{
    tracing = false;
}

/// Logging status.
/// Returns: true if currently logging.
bool logEnabled()
{
    return tracing;
}

/// Log an entry.
/// Params:
///     fmt = Format.
///     args = Arguments.
void log
    (string file = __FILE__, string func = __FUNCTION__, int line = __LINE__, A...)
    (string fmt, A args)
{
    if (tracing == false)
        return;
    
    // %08.3f gives 4 digits before decimal point
    // meaning 9999 seconds (~166.65 mins) for text alignment
    double ms = sw.peek().total!"msecs"() / 1_000.0;
    tracefile.writef("[%08.3f] %s@L%d|%s: ", ms, file, line, func);
    tracefile.writefln(fmt, args);
}