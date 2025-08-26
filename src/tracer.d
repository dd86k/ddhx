/// Basic logger.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module tracer; // TODO: rename to logger (logInit(), log(...), etc.)

import std.stdio;
import std.datetime.stopwatch;

private __gshared
{
    StopWatch sw;
    File tracefile;
    bool tracing;
}

// For unittests, automatically enable traces to stderr.
// TODO: Make it a configuration
version (unittest)
{
    static this()
    {
        tracing = true;
        tracefile = stderr;
        sw.start();
    }
}

void traceInit(string file = "ddhx.log")
{
    tracefile = File(file, "w");
    tracefile.setvbuf(0, _IONBF);
    sw.start();
    tracing = true;
    
    import std.datetime.systime : Clock;
    trace("Trace started at %s", Clock.currTime());
}

bool traceEnabled()
{
    return tracing;
}

void trace(string file = __FILE__, string func = __FUNCTION__, int line = __LINE__, A...)(string fmt, A args)
{
    if (tracing == false)
        return;
    
    // %08.3f gives 4 digits before decimal point
    // meaning 9999 seconds (~166.65 mins) for text alignment
    double ms = sw.peek().total!"msecs"() / 1_000.0;
    tracefile.writef("[%08.3f] %s@L%d|%s: ", ms, file, line, func);
    tracefile.writefln(fmt, args);
}