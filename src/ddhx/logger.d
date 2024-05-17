/// Basic logger.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.logger;

import std.stdio;
import std.datetime.stopwatch;

private __gshared File tracefile;
private __gshared StopWatch sw;
private __gshared bool tracing;

void traceInit()
{
    tracing = true;
    tracefile = File("ddhx.log", "w");
    tracefile.setvbuf(0, _IONBF);
    sw.start();
}

void trace(string func = __FUNCTION__, A...)(string fmt, A args)
{
    if (tracing == false)
        return;
    
    double ms = sw.peek().total!"msecs"() / 1_000.0;
    tracefile.writef("[%08.3f] %s: ", ms, func);
    tracefile.writefln(fmt, args);
}