/// Basic logger.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.logger;

import std.stdio;
import std.datetime.stopwatch;

private __gshared
{
    StopWatch sw;
    File tracefile;
    bool tracing;
}

// Auto-init logger to stdout for tests
version (unittest)
{
    static this()
    {
        tracing = true;
        tracefile = stdout;
        sw.start();
    }
}

void traceInit()
{
    tracing = true;
    tracefile = File("ddhx.log", "w");
    tracefile.setvbuf(0, _IONBF);
    sw.start();
}

void trace(string func = __FUNCTION__, int line = __LINE__, A...)(string fmt, A args)
{
    if (tracing == false)
        return;
    
    double ms = sw.peek().total!"msecs"() / 1_000.0;
    tracefile.writef("[%08.3f] <%s:%d> ", ms, func, line);
    tracefile.writefln(fmt, args);
}