module ddhx.benchmark.src.main;

import core.memory : GC;
import core.sync.mutex : Mutex;
import core.sync.rwmutex : ReadWriteMutex;
import core.thread : Thread;
import core.time : Duration;
import std.stdio;
import std.datetime.stopwatch;
import ddhx.editor;

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

// NOTE: stderr because DUB prints to stdout, so capturing this is easier
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

//
// Positional read scaling (os.file)
//
// Same total number of reads, spread over more threads. Reads that truly run
// in parallel keep the wall time flat; reads serialized behind one file
// object grow it linearly. Comparing one shared handle against one handle per
// thread tells the two apart from plain cache or disk limits.
//

void testReads(int reads = 200_000)
{
    import core.atomic : atomicOp;
    import std.file : remove, tempDir, write;
    import std.path : buildPath;
    import os.file : OFlags, OSFile;

    enum SIZE   = 4 * 1024 * 1024;
    enum WINDOW = 512;

    stderr.writeln("READS  : ", reads, " x ", WINDOW, " B over ", SIZE / 1024, " KiB");

    string path = buildPath(tempDir(), "ddhx_bench_reads.tmp");
    write(path, new ubyte[SIZE]);
    scope(exit) remove(path);

    OSFile shared_handle;
    shared_handle.open(path, OFlags.read | OFlags.exists | OFlags.share);
    scope(exit) shared_handle.close();

    // Warm the page cache: this measures the read path, not the disk
    ubyte[4096] warm;
    for (long pos; pos < SIZE; pos += warm.length)
        shared_handle.readAt(pos, warm);

    Duration run(int threads, bool own)
    {
        int each = reads / threads;
        shared long total;

        // Each worker needs its own closure frame, hence the maker function
        Thread worker()
        {
            return new Thread({
                OSFile file = shared_handle; // same OS handle, unless...
                if (own)
                    file.open(path, OFlags.read | OFlags.exists | OFlags.share);
                scope(exit) if (own) file.close();

                ubyte[WINDOW] buffer;
                size_t got;
                foreach (i; 0 .. each)
                    got += file.readAt((cast(long)i * 9973) % (SIZE - WINDOW), buffer).length;
                atomicOp!"+="(total, got);
            });
        }

        Thread[] workers;
        foreach (int tid; 0 .. threads)
            workers ~= worker();

        StopWatch sw;
        sw.start();
        foreach (Thread t; workers) t.start();
        foreach (Thread t; workers) t.join();
        sw.stop();

        if (total != cast(long)each * threads * WINDOW)
            throw new Exception("short read during scaling benchmark");
        return sw.peek();
    }

    static immutable int[] counts = [ 1, 2, 4, 8 ];

    void row(string name, bool own)
    {
        Duration[] times;
        foreach (int threads; counts)
            times ~= run(threads, own);

        char[32] tbuf;
        stderr.writef("%-20s", name);
        foreach (Duration time; times)
            stderr.writef("%11s", fmtdur(time, tbuf));
        stderr.writeln();

        stderr.writef("%-20s", "  speedup");
        foreach (Duration time; times)
            stderr.writef("%10.2fx", cast(double)times[0].total!"usecs" / time.total!"usecs");
        stderr.writeln();
    }

    printDelimiter();
    stderr.writef("%-20s", "threads");
    foreach (int threads; counts)
        stderr.writef("%11d", threads);
    stderr.writeln();
    row("shared handle", false);
    row("handle per thread", true);
}

//
// Lock policy comparison (piecev4)
//
// Guards an editor that has its own locking turned off, so the only thing
// changing between runs is the lock policy around the very same critical
// sections.
//

interface Guard
{
    void lockRead();
    void unlockRead();
    void lockWrite();
    void unlockWrite();
}

/// No locking: the "internal" run measures piecev4's own lock instead.
class NoGuard : Guard
{
    void lockRead() {}
    void unlockRead() {}
    void lockWrite() {}
    void unlockWrite() {}
}

class MutexGuard : Guard
{
    private Mutex mutex;
    this() { mutex = new Mutex(); }
    void lockRead()    { mutex.lock(); }
    void unlockRead()  { mutex.unlock(); }
    void lockWrite()   { mutex.lock(); }
    void unlockWrite() { mutex.unlock(); }
}

class RWGuard : Guard
{
    private ReadWriteMutex mutex;
    this(ReadWriteMutex.Policy policy) { mutex = new ReadWriteMutex(policy); }
    void lockRead()    { mutex.reader().lock(); }
    void unlockRead()  { mutex.reader().unlock(); }
    void lockWrite()   { mutex.writer().lock(); }
    void unlockWrite() { mutex.writer().unlock(); }
}

Duration runLocks(Guard guard, IDocumentEditor e, int threads, int ops, int writes)
{
    long docsize = e.size();
    long window = docsize - 256;

    // Each worker needs its own closure frame, hence the maker function
    Thread worker(int tid)
    {
        return new Thread({
            ubyte[256] buffer;
            ubyte value = cast(ubyte)(0x40 + tid);
            long seed = (tid + 1) * 7919;
            // Fixed tail position: splitting the last piece keeps the cost
            // of a write from growing with the piece count
            long wpos = docsize - 1 - tid;

            foreach (i; 0 .. ops)
            {
                if (i % 100 < writes)
                {
                    guard.lockWrite();
                    e.replace(wpos, &value, ubyte.sizeof);
                    guard.unlockWrite();
                }
                else
                {
                    guard.lockRead();
                    e.view((seed * (i + 1)) % window, buffer);
                    guard.unlockRead();
                }
            }
        });
    }

    Thread[] workers;
    foreach (int tid; 0 .. threads)
        workers ~= worker(tid);

    StopWatch sw;
    sw.start();
    foreach (Thread t; workers) t.start();
    foreach (Thread t; workers) t.join();
    sw.stop();
    return sw.peek();
}

void testLocks(int threads = 4, int ops = 5_000)
{
    import std.file : remove, tempDir, write;
    import std.path : buildPath;
    import ddhx.document.base : IDocument;
    import ddhx.document.file : FileDocument;
    import ddhx.document.memory : MemoryDocument;
    import ddhx.editor.piecev4 : PieceV4DocumentEditor;

    enum SIZE = 1024 * 1024;

    writeln("BACKEND: piecev4");
    writeln("THREADS: ", threads);
    writeln("OPS    : ", ops, " per thread");

    ubyte[] content = new ubyte[SIZE];
    foreach (i, ref ubyte b; content)
        b = cast(ubyte)i;

    string path = buildPath(tempDir(), "ddhx_bench_locks.tmp");
    write(path, content);
    scope(exit) remove(path);

    static immutable string[] docnames = [ "memory", "file" ];
    static immutable string[] policies =
        [ "none (1 thread)", "mutex", "rwmutex readers", "rwmutex writers", "piecev4 internal" ];
    static immutable int[] ratios = [ 0, 10, 50, 90 ];

    foreach (string docname; docnames)
    {
        printDelimiter();
        writeln("DOCUMENT: ", docname);
        writef("%-18s", "writes");
        foreach (int ratio; ratios)
            writef("%10d%%", ratio);
        writeln();

        foreach (size_t p, string policy; policies)
        {
            writef("%-18s", policy);
            foreach (int ratio; ratios)
            {
                IDocument doc;
                if (docname == "file")
                    doc = new FileDocument(path, true);
                else
                    doc = new MemoryDocument(content);

                // Only the internal run lets the editor lock itself
                PieceV4DocumentEditor e = new PieceV4DocumentEditor(p == 4);
                e.open(doc);
                e.coalescing(false); // keep every write the same amount of work

                Guard guard;
                final switch (p) {
                case 0, 4: guard = new NoGuard(); break;
                case 1: guard = new MutexGuard(); break;
                case 2: guard = new RWGuard(ReadWriteMutex.Policy.PREFER_READERS); break;
                case 3: guard = new RWGuard(ReadWriteMutex.Policy.PREFER_WRITERS); break;
                }

                // Unguarded runs would corrupt the table with real threads
                Duration time = runLocks(guard, e, p == 0 ? 1 : threads, ops, ratio);

                char[32] tbuf;
                writef("%11s", fmtdur(time, tbuf));
                e.close();
                doc.close();
            }
            writeln();
        }
    }
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
    
    scope IDocumentEditor e = spawnEditor(name);
    
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
    if (args.length <= 1)
    {
        test(null);
        return;
    }
    
    foreach (string backend; args[1..$])
    {
        switch (backend) {
        case "locks": // lock policy comparison, piecev4 only
            testLocks();
            break;
        case "reads": // positional read scaling, os.file only
            testReads();
            break;
        default:
            test(backend);
        }
    }
}