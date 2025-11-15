module benchmark.src.main;

import core.memory : GC;
import std.getopt;
import std.stdio;
import std.datetime.stopwatch;
import backend.base;

@nogc nothrow
const(char)[] fmtbin(ulong b, ref char[16] buf) {
    static immutable u = ["B","KiB","MiB","GiB","TiB"];
    
    if (b == 0) {
        buf[0] = '0';
        buf[1] = ' ';
        buf[2] = 'B';
        return buf[0..3];
    }
    
    double val = cast(double)b;
    size_t i = 0;
    while (val >= 1024.0 && i < 4) { val /= 1024.0; i++; }
    
    size_t pos = 0;
    
    if (i == 0) {
        // Bytes - no decimal
        ulong whole = b;
        if (whole == 0) buf[pos++] = '0';
        else {
            ulong temp = whole;
            size_t digits = 0;
            while (temp > 0) { temp /= 10; digits++; }
            size_t start = pos;
            pos += digits;
            size_t end = pos;
            while (whole > 0) { buf[--pos] = cast(char)('0' + (whole % 10)); whole /= 10; }
            pos = end;
        }
    } else {
        // With decimals
        long whole = cast(long)val;
        long frac = cast(long)((val - whole) * 100);
        
        // Format whole part
        if (whole == 0) buf[pos++] = '0';
        else {
            long temp = whole;
            size_t digits = 0;
            while (temp > 0) { temp /= 10; digits++; }
            pos += digits;
            size_t end = pos;
            while (whole > 0) { buf[--pos] = cast(char)('0' + (whole % 10)); whole /= 10; }
            pos = end;
        }
        
        // Add decimal point and fractional part
        buf[pos++] = '.';
        buf[pos++] = cast(char)('0' + (frac / 10));
        buf[pos++] = cast(char)('0' + (frac % 10));
    }
    
    buf[pos++] = ' ';
    foreach (c; u[i]) buf[pos++] = c;
    
    return buf[0..pos];
}

@nogc nothrow
const(char)[] fmtdur(Duration dur, ref char[32] buf) {
    double val;
    string unit;
    
    if (dur.total!"weeks" > 0)        { val = dur.total!"weeks" / 1.0; unit = "weeks"; }
    else if (dur.total!"days" > 0)    { val = dur.total!"days" / 1.0; unit = "days"; }
    else if (dur.total!"hours" > 0)   { val = dur.total!"hours" / 1.0; unit = "hours"; }
    else if (dur.total!"minutes" > 0) { val = dur.total!"minutes" / 1.0; unit = "mins"; }
    else if (dur.total!"seconds" > 0) { val = dur.total!"msecs" / 1000.0; unit = "secs"; }
    else if (dur.total!"msecs" > 0)   { val = dur.total!"usecs" / 1000.0; unit = "ms"; }
    else if (dur.total!"usecs" > 0)   { val = dur.total!"hnsecs" / 10.0; unit = "μs"; }
    else { val = dur.total!"hnsecs" / 1.0; unit = "hnsecs"; }
    
    size_t pos = 0;
    long whole = cast(long)val;
    long frac = cast(long)((val - whole) * 1000) % 1000; // 3 decimals
    
    // Format whole
    if (whole == 0) buf[pos++] = '0';
    else {
        long temp = whole;
        size_t digits = 0;
        while (temp > 0) { temp /= 10; digits++; }
        pos += digits;
        size_t end = pos;
        while (whole > 0) { buf[--pos] = cast(char)('0' + (whole % 10)); whole /= 10; }
        pos = end;
    }
    
    // Add decimals if non-zero
    if (frac > 0) {
        buf[pos++] = '.';
        buf[pos++] = cast(char)('0' + (frac / 100));
        buf[pos++] = cast(char)('0' + ((frac / 10) % 10));
        buf[pos++] = cast(char)('0' + (frac % 10));
    }
    
    buf[pos++] = ' ';
    foreach (c; unit) buf[pos++] = c;
    return buf[0..pos];
}

void printDelimiter()
{
    stderr.writeln("--------------------------------");
}
void printTime(string prefix, Duration time)
{
    char[32] tbuf;
    stderr.write(prefix, ": ", fmtdur( time, tbuf ));
    stderr.writeln(" (", fmtdur( time / 1_000, tbuf ), " each)");
}
void printTime(int runs, string what, Duration time)
{
    char[32] tbuf;
    stderr.writef("%*d %s: %s", 6, runs, what, fmtdur( time, tbuf ));
    stderr.writeln(" (", fmtdur( time / 1_000, tbuf ), " each)");
}
void printGCstats(GC.Stats stats)
{
    char[16] tbuf;
    stderr.writeln("GC.free        : ", fmtbin( stats.freeSize, tbuf ));
    stderr.writeln("GC.used        : ", fmtbin( stats.usedSize, tbuf ));
    stderr.writeln("GC.alloc       : ", fmtbin( stats.allocatedInCurrentThread, tbuf ));
}

void test(string name, int rounds = 30, int runs = 100)
{
    writeln("BACKEND: ", name);
    writeln("ROUNDS : ", rounds);
    writeln("RUNS   : ", runs);
    
    // Buffer to avoid influencing GC stats
    // Eventually to include chunk backend
    import core.stdc.stdlib : malloc, free;
    size_t buffer_size = 1_000_000;
    ubyte[] buffer = (cast(ubyte*)malloc(buffer_size))[0..buffer_size];
    if (buffer is null)
        throw new Exception("error: Out of memory");
    scope(exit) free(buffer.ptr);
    
    scope IDocumentEditor e = selectBackend(name);
    
    StopWatch sw;
    
    e.replace(0, buffer.ptr, buffer.length);
    
    printDelimiter();
    printGCstats(GC.stats());
    
    ubyte n = 0xff;
    long pos = 10;
    
    printDelimiter();
    int totalruns;
    for (int r; r < rounds; r++)
    {
        sw.start();
        for (int i; i < runs; i++)
        {
            e.replace(pos, &n, ubyte.sizeof);
            pos += 2; // avoid coalescing
        }
        sw.stop();
        printTime(totalruns += runs, "replaces", sw.peek());
        sw.reset();
    }
    
    ubyte[] viewbuf;
    viewbuf.length = 400;
    printDelimiter();
    
    sw.start();
    ubyte[] res = e.view(0, viewbuf);
    sw.stop();
    stderr.writeln("view(pos=0,size=400): ", sw.peek());
    sw.reset();
    
    sw.start();
    res = e.view(10_000, viewbuf);
    sw.stop();
    stderr.writeln("view(pos=10_000,size=400): ", sw.peek());
    sw.reset();
    
    printGCstats(GC.stats());
}

void main(string[] args)
{
    foreach (string backend; args[1..$])
    {
        test(backend);
    }
}