/// File handling.
///
/// This exists because 32-bit runtimes suffer from the 32-bit file size limit.
/// Despite the MS C runtime having _open and _fseeki64, the DM C runtime does
/// not have these functions.
/// 
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module os.file;

version (Windows)
{
    import core.sys.windows.winnt;
    import core.sys.windows.winbase;
    import core.sys.windows.winerror : ERROR_HANDLE_EOF;
    import std.utf : toUTF16z;
    
    private alias OSHANDLE = HANDLE;
    private alias SEEK_SET = FILE_BEGIN;
    private alias SEEK_CUR = FILE_CURRENT;
    private alias SEEK_END = FILE_END;
    
    private enum OFLAG_OPENONLY = OPEN_EXISTING;
    private enum INVALID_OSHANDLE = INVALID_HANDLE_VALUE;
}
else version (Posix)
{
    import core.sys.posix.unistd : read, write, fsync, close;
    import core.sys.posix.fcntl;
    import core.stdc.stdio : SEEK_SET, SEEK_CUR, SEEK_END;
    import std.string : toStringz;
    
    import core.stdc.config : c_long, c_ulong; // do not remove
    
    // NOTE: ioctl(3)
    //       Bionic actually used int at some point.
    //       i64 usage noticed on Android 16 (6.1.148-android14-11).
    version (CRuntime_Bionic)
        private alias IOCTL_TYPE = c_long;
    //       In Musl source, ioctl is really defined as
    //         src/misc/ioctl.c: int ioctl(int fd, int req, ...)
    //       But linker will complain about a redefinition (static compile):
    //         Previous IR: i32 (i32, i64, ...) (libc)
    //         New IR     : i32 (i32, i32, ...) (our definition with int)
    //       Using 'c_long' seems to fix this (under amd64), but I'm not convinced.
    //       I think 'misc' is used when standalone (e.g., not built against Glibc).
    else version (CRuntime_Musl)
        private alias IOCTL_TYPE = c_long;
    else // Glibc, BSDs
        private alias IOCTL_TYPE = c_ulong;
    private extern (C) int ioctl(int, IOCTL_TYPE, ...);
    
    // NOTE: BLKGETSIZE64
    //       BLKGETSIZE64 is missing from dmd 2.098.1 and ldc 1.24.0
    //       ldc 1.24 missing core.sys.linux.fs
    //       source musl 1.2.0 and glibc 2.25 has roughly same settings.
    private enum _IOC_NRBITS = 8;
    private enum _IOC_TYPEBITS = 8;
    private enum _IOC_SIZEBITS = 14;
    private enum _IOC_NRSHIFT = 0;
    private enum _IOC_TYPESHIFT = _IOC_NRSHIFT+_IOC_NRBITS;
    private enum _IOC_SIZESHIFT = _IOC_TYPESHIFT+_IOC_TYPEBITS;
    private enum _IOC_DIRSHIFT = _IOC_SIZESHIFT+_IOC_SIZEBITS;
    private enum _IOC_READ = 2;
    private enum _IOC(int dir,int type,int nr,size_t size) =
        (dir  << _IOC_DIRSHIFT) |
        (type << _IOC_TYPESHIFT) |
        (nr   << _IOC_NRSHIFT) |
        (size << _IOC_SIZESHIFT);
    // NOTE: _IOR!(0x12,114,size_t.sizeof) results in ulong.max
    //       I don't know why, so I'm casting it to used ioctl type to let it compile.
    private enum _IOR(int type,int nr,size_t size) = cast(IOCTL_TYPE)_IOC!(_IOC_READ,type,nr,size);
    private enum BLKGETSIZE64 = cast(IOCTL_TYPE)_IOR!(0x12,114,size_t.sizeof);
    private alias BLOCKSIZE = BLKGETSIZE64;
    
    // NOTE: Every call taking a file offset
    //       Two runtimes hand us a 32-bit off_t on 32-bit targets, which
    //       caps files at 2 GiB (and makes druntime's declarations outright
    //       uncallable with a long), so declare them with the offset the
    //       platform really takes:
    //       - Musl: off_t is 64-bit on every target, but druntime keys it off
    //         __USE_FILE_OFFSET64, which it sets to false. It also declares
    //         no pread/pwrite at all.
    //       - Bionic: Android pins off_t to 32-bit on 32-bit targets by
    //         design (see its 32-bit ABI doc) and offers explicit 64-bit
    //         entry points for exactly this.
    version (CRuntime_Musl)
    {
        private extern (C) long    lseek(int, long, int);
        private extern (C) int     ftruncate(int, long);
        private extern (C) ssize_t pread(int, void*, size_t, long);
        private extern (C) ssize_t pwrite(int, const scope void*, size_t, long);
    }
    else version (CRuntime_Bionic)
    {
        private extern (C) long    lseek64(int, long, int);
        private extern (C) int     ftruncate64(int, long);
        private extern (C) ssize_t pread64(int, void*, size_t, long);
        private extern (C) ssize_t pwrite64(int, const scope void*, size_t, long);
        private alias lseek     = lseek64;
        private alias ftruncate = ftruncate64;
        private alias pread     = pread64;
        private alias pwrite    = pwrite64;
    }
    else
        import core.sys.posix.unistd : lseek, ftruncate, pread, pwrite;

    private alias OSHANDLE = int;
    private enum INVALID_OSHANDLE = -1;
}
else
{
    static assert(0, "Implement file I/O");
}

import os.error : OSException;

// TODO: FileType GetType(string)
//       Pipe, device, etc.
//       Win32: GetFileType
//       POSIX: fstat(3)

/// File seek origin.
enum Seek
{
    start   = SEEK_SET, /// Seek since start of file.
    current = SEEK_CUR, /// Seek since current position in file.
    end     = SEEK_END, /// Seek since end of file.
}

/// Open file flags
enum OFlags
{
    exists  = 1,        /// File must exist.
    read    = 1 << 1,   /// Read access.
    write   = 1 << 2,   /// Write access.
    readWrite = read | write,   /// Read and write access.
    share   = 1 << 5,   /// Share file with read access to other programs.
}

/// Represents an OS abstracted file instance.
struct OSFile
{
    private OSHANDLE handle = INVALID_OSHANDLE;

    /// Open new or existing file.
    /// Params:
    ///     path = File path.
    ///     flags = OFlags.
    /// Throws: OSException.
    void open(string path, int flags = OFlags.readWrite)
    {
        version (Windows)
        {
            uint dwCreation = flags & OFlags.exists ? OPEN_EXISTING : OPEN_ALWAYS;
            
            uint dwAccess;
            if (flags & OFlags.read)    dwAccess |= GENERIC_READ;
            if (flags & OFlags.write)   dwAccess |= GENERIC_WRITE;
            
            // NOTE: FILE_SHARE_DELETE
            //       A full save's rename(tmp, target) still successd over this open
            //       handle, and the handle keep reading the original (now replaced)
            //       stream. Modern Windows gives POSIX-style rename semantics, so
            //       undo history survives the save.
            //       While adding FILE_SHARE_DELETE is safe, including it would lead
            //       to issues because ddhx uses a live file to fill data into view.
            uint dwShare = flags & OFlags.share ? FILE_SHARE_READ | FILE_SHARE_WRITE : 0;

            // NOTE: FILE_FLAG_OVERLAPPED
            //       Only worth if massive parallelism is done on Windows
            //       Otherwise comes at a great cost to handle ERROR_IO_PENDING everywhere
            handle = CreateFileW(
                path.toUTF16z,  // lpFileName
                dwAccess,       // dwDesiredAccess
                dwShare,        // dwShareMode
                null,           // lpSecurityAttributes
                dwCreation,     // dwCreationDisposition
                0,              // dwFlagsAndAttributes
                null,           // hTemplateFile
            );
            if (handle == INVALID_HANDLE_VALUE)
                throw new OSException("CreateFileW");
        }
        else version (Posix)
        {
            int oflags;
            if ((flags & OFlags.exists) == 0) oflags |= O_CREAT;
            if ((flags & OFlags.readWrite) == OFlags.readWrite)
                oflags |= O_RDWR;
            else if (flags & OFlags.write)
                oflags |= O_WRONLY;
            else if (flags & OFlags.read)
                oflags |= O_RDONLY;
            // NOTE: GVFS does not like being given octal perms on open, even with O_RDONLY
            //       And since it doesn't allow O_RDWR anyway, only give those on file creation
            //       If neither O_CREAT nor O_TMPFILE is specified in flags, then mode is ignored
            //       GVFS is potentially not ignoring it...? Oh well
            import std.conv : octal;
            handle = flags & OFlags.exists ?
                .open(path.toStringz, oflags) :
                .open(path.toStringz, oflags, octal!644); // rw-r--r--
            if (handle < 0)
                throw new OSException("open");
        }
    }
    
    /// Seek to position.
    /// Params:
    ///     origin = Seek origin.
    ///     pos = Position.
    /// Throws: OSException.
    void seek(Seek origin, long pos)
    {
        version (Windows)
        {
            LARGE_INTEGER i = void;
            i.QuadPart = pos;
            if (SetFilePointerEx(handle, i, &i, origin) == FALSE)
                throw new OSException("SetFilePointerEx");
        }
        else version (Posix)
        {
            if (lseek(handle, pos, origin) < 0)
                throw new OSException("lseek");
        }
        else static assert(0, "Implement OSFile.seek");
    }
    
    /// Tell current position.
    /// Returns: Position.
    long tell()
    {
        version (Windows)
        {
            LARGE_INTEGER i; // .init
            SetFilePointerEx(handle, i, &i, FILE_CURRENT);
            return i.QuadPart;
        }
        else version (Posix)
        {
            return lseek(handle, 0, SEEK_CUR);
        }
        else static assert(0, "Implement OSFile.tell");
    }
    
    /// Get size of file.
    /// Returns: Size in bytes.
    /// Throws: OSException.
    long size()
    {
        version (Windows)
        {
            LARGE_INTEGER li = void;
            if (GetFileSizeEx(handle, &li) == FALSE)
                throw new OSException("GetFileSizeEx");
            return li.QuadPart;
        }
        else version (Posix)
        {
            // NOTE: Why no fstat(2)
            //       druntime has no Musl or Bionic stat_t: both land on
            //       glibc's 32-bit layout, which neither of them matches, so
            //       on 32-bit targets every field is read from the wrong
            //       offset. st_size is the one that bites (an off_t both
            //       runtimes truncate past 2 GiB), but st_mode is in the same
            //       struct, so the file type it reports is no better. The
            //       kernel answers both questions through lseek anyway.
            long current = lseek(handle, 0, SEEK_CUR);
            if (current < 0) // ESPIPE for pipes, sockets and terminals
                throw new OSException("lseek");

            long end = lseek(handle, 0, SEEK_END);
            if (end < 0)
                throw new OSException("lseek");
            if (lseek(handle, current, SEEK_SET) < 0)
                throw new OSException("lseek");

            if (end > 0)
                return end;

            // A zero is either an empty file or a device the kernel only
            // measures through an ioctl, which an empty file refuses
            long blocks = void;
            if (ioctl(handle, BLOCKSIZE, &blocks) < 0)
                return 0;
            return blocks;
        }
        else static assert(0, "Implement OSFile.size");
    }
    
    /// Read file at current position.
    /// Params: buffer = Byte buffer.
    /// Returns: Slice.
    ubyte[] read(ubyte[] buffer)
    {
        return read(buffer.ptr, buffer.length);
    }
    
    /// Read file at current position.
    /// Params:
    ///     buffer = Buffer pointer.
    ///     size = Buffer size.
    /// Returns: Slice.
    /// Throws: OSException.
    ubyte[] read(void *buffer, size_t size)
    {
        version (Windows)
        {
            uint len = cast(uint)size;
            if (ReadFile(handle, buffer, len, &len, null) == FALSE)
                throw new OSException("ReadFile");
            return (cast(ubyte*)buffer)[0..len];
        }
        else version (Posix)
        {
            ssize_t len = .read(handle, buffer, size);
            if (len < 0)
                throw new OSException("read");
            return (cast(ubyte*)buffer)[0..len];
        }
    }
    
    /// Read file at this position.
    ///
    /// Unlike seek+read, this does not depend on the file position, so
    /// several threads may read one file instance at once.
    /// Params:
    ///     position = File position.
    ///     buffer = Byte buffer.
    /// Returns: Slice.
    ubyte[] readAt(long position, ubyte[] buffer)
    {
        return readAt(position, buffer.ptr, buffer.length);
    }

    /// Read file at this position.
    /// Params:
    ///     position = File position.
    ///     buffer = Buffer pointer.
    ///     size = Buffer size.
    /// Returns: Slice.
    /// Throws: OSException.
    ubyte[] readAt(long position, void *buffer, size_t size)
    {
        version (Windows)
        {
            // NOTE: OVERLAPPED on a synchronous handle
            //       Without FILE_FLAG_OVERLAPPED, ReadFile still completes
            //       before returning, and reads from the given offset instead
            //       of the file position. It does move the file position
            //       afterwards, so this must not be mixed with read(), and
            //       maintaining that position makes the I/O manager take the
            //       file object lock: correct under concurrent readers, but
            //       they convoy rather than overlap (see FileDocument.caps).
            OVERLAPPED overlap; // .init
            overlap.Offset     = cast(uint)position;
            overlap.OffsetHigh = cast(uint)(position >>> 32);

            uint len = cast(uint)size;
            if (ReadFile(handle, buffer, len, &len, &overlap) == FALSE)
            {
                // Reading past EOF fills nothing, like a short read
                if (GetLastError() == ERROR_HANDLE_EOF)
                    return (cast(ubyte*)buffer)[0..0];
                throw new OSException("ReadFile");
            }
            return (cast(ubyte*)buffer)[0..len];
        }
        else version (Posix)
        {
            ssize_t len = pread(handle, buffer, size, position);
            if (len < 0)
                throw new OSException("pread");
            return (cast(ubyte*)buffer)[0..len];
        }
        else static assert(0, "Implement OSFile.readAt");
    }

    /// Write file at this position.
    ///
    /// Ditto readAt: independent of the file position.
    /// Params:
    ///     position = File position.
    ///     data = Byte buffer.
    /// Returns: Amount written.
    size_t writeAt(long position, inout(ubyte)[] data)
    {
        return writeAt(position, data.ptr, data.length);
    }

    /// Write file at this position.
    /// Params:
    ///     position = File position.
    ///     data = Buffer pointer.
    ///     size = Buffer size.
    /// Returns: Amount written.
    /// Throws: OSException.
    size_t writeAt(long position, inout(ubyte) *data, size_t size)
    {
        version (Windows)
        {
            OVERLAPPED overlap; // .init
            overlap.Offset     = cast(uint)position;
            overlap.OffsetHigh = cast(uint)(position >>> 32);

            uint len = cast(uint)size;
            if (WriteFile(handle, data, len, &len, &overlap) == FALSE)
                throw new OSException("WriteFile");
            return len; // 0 on error anyway
        }
        else version (Posix)
        {
            ssize_t len = pwrite(handle, data, size, position);
            if (len < 0)
                throw new OSException("pwrite");
            return len;
        }
        else static assert(0, "Implement OSFile.writeAt");
    }

    /// Write file at current position.
    /// Params: data = Byte buffer.
    /// Returns: Amount written.
    size_t write(inout(ubyte)[] data)
    {
        return write(data.ptr, data.length);
    }
    
    /// Write file at current position.
    /// Params:
    ///     data = Buffer pointer.
    ///     size = Buffer size.
    /// Returns: Amount written.
    /// Throws: OSException.
    size_t write(inout(ubyte) *data, size_t size)
    {
        version (Windows)
        {
            uint len = cast(uint)size;
            if (WriteFile(handle, data, len, &len, null) == FALSE)
                throw new OSException("WriteFile");
            return len; // 0 on error anyway
        }
        else version (Posix)
        {
            ssize_t len = .write(handle, data, size);
            if (len < 0)
                throw new OSException("write");
            return len;
        }
    }
    
    /// Set file size (truncate or extend).
    void resize(long size)
    {
        version (Windows)
        {
            LARGE_INTEGER i = void;
            i.QuadPart = size;
            if (SetFilePointerEx(handle, i, null, FILE_BEGIN) == FALSE)
                throw new OSException("SetFilePointerEx");
            // NOTE: Vista+ is SetFileInformationByHandle/FileEndOfFileInfo
            //       Worth if doing concurrent/OVERLAP stuff
            if (SetEndOfFile(handle) == FALSE)
                throw new OSException("SetEndOfFile");
        }
        else version (Posix)
        {
            if (ftruncate(handle, size) < 0)
                throw new OSException("ftruncate");
        }
    }

    /// Flush data to disk.
    void flush()
    {
        version (Windows)
        {
            FlushFileBuffers(handle);
        }
        else version (Posix)
        {
            .fsync(handle);
        }
    }
    
    /// Close file.
    void close()
    {
        version (Windows)
        {
            if (handle != INVALID_HANDLE_VALUE)
            {
                CloseHandle(handle);
                handle = INVALID_HANDLE_VALUE;
            }
        }
        else version (Posix)
        {
            // 0 is stdin, we better be careful!
            if (handle >= 0)
            {
                .close(handle);
                handle = -1;
            }
        }
    }
}

/// Size measures without disturbing the file position
unittest
{
    import std.file : remove, tempDir, write;
    import std.path : buildPath;

    string path = buildPath(tempDir(), "osfile_size.tmp");
    write(path, new ubyte[300]);

    OSFile file;
    file.open(path, OFlags.read | OFlags.exists);
    scope(exit) { file.close(); remove(path); }

    assert(file.size() == 300);

    file.seek(Seek.start, 100);
    assert(file.size() == 300);
    assert(file.tell() == 100);

    // Growing and shrinking are seen right away
    file.close();
    file.open(path, OFlags.readWrite | OFlags.exists);
    file.resize(5000);
    assert(file.size() == 5000);
    file.resize(0);
    assert(file.size() == 0); // empty, not a device: the ioctl must not throw
}

/// Offsets at 2 GiB, where a 32-bit off_t turns negative.
///
/// Opt-in with `dub test --d-version=TestLargeFile` or `make test-large`:
/// the file is a hole on ext4, FFS, and tmpfs, but not on FAT, and nobody
/// running the suite on an embedded target wants two silent gigabytes written
/// to their card. NTFS gives no hole either, so there the space check below
/// always earns its keep, even though a Windows offset is 64-bit long before
/// it gets here.
version (TestLargeFile)
unittest
{
    import std.file : exists, remove, tempDir;
    import std.path : buildPath;
    import std.stdio : stderr;

    enum long BOUNDARY = 2L * 1024 * 1024 * 1024;

    // Opting in still does not mean the room is there for a non-sparse copy
    string dir = tempDir();
    ulong avail;
    try
        avail = availableDiskSpace(dir);
    catch (Exception ex)
    {
        stderr.writeln("os.file: skipping the 2 GiB test, ", dir, ": ", ex.msg);
        return;
    }

    if (avail < BOUNDARY * 2)
    {
        stderr.writeln("os.file: skipping the 2 GiB test, ", dir, " is short on space");
        return;
    }

    string path = buildPath(dir, "osfile_large.tmp");
    if (exists(path)) remove(path);

    OSFile file;
    file.open(path, OFlags.readWrite);
    scope(exit) { file.close(); remove(path); }

    // Sparse where supported: only the page written below is ever allocated
    file.resize(BOUNDARY + 16);
    assert(file.size() == BOUNDARY + 16);

    // 0x8000_0000 is where an int32 offset reads as negative
    ubyte[4] patch = [ 0xde, 0xad, 0xbe, 0xef ];
    assert(file.writeAt(BOUNDARY, patch) == patch.length);

    ubyte[8] buffer;
    assert(file.readAt(BOUNDARY - 2, buffer[0..6]) ==
        [ 0, 0, 0xde, 0xad, 0xbe, 0xef ]);

    // The hole before it reads as zeroes, not as a wrapped-around offset
    assert(file.readAt(BOUNDARY - 8, buffer) == [ 0, 0, 0, 0, 0, 0, 0, 0 ]);

    file.seek(Seek.start, BOUNDARY);
    assert(file.tell() == BOUNDARY);
}

/// Positional I/O ignores the file position, and short reads at EOF
unittest
{
    import std.file : remove, tempDir, write;
    import std.path : buildPath;

    string path = buildPath(tempDir(), "osfile_readat.tmp");
    ubyte[256] content;
    foreach (i, ref ubyte b; content)
        b = cast(ubyte)i;
    write(path, content[]);

    OSFile file;
    file.open(path, OFlags.readWrite | OFlags.exists);
    scope(exit) { file.close(); remove(path); }

    ubyte[16] buffer;
    assert(file.readAt(0, buffer) == content[0..16]);
    assert(file.readAt(200, buffer) == content[200..216]);

    // Seeking must not influence it, nor it the other way around
    file.seek(Seek.start, 100);
    assert(file.readAt(8, buffer) == content[8..24]);

    // Reads clamp at EOF
    assert(file.readAt(250, buffer) == content[250..256]);
    assert(file.readAt(256, buffer).length == 0);

    // Writes land where told
    ubyte[4] patch = [ 0xde, 0xad, 0xbe, 0xef ];
    assert(file.writeAt(64, patch[]) == patch.length);
    assert(file.readAt(62, buffer[0..8]) == [ 62, 63, 0xde, 0xad, 0xbe, 0xef, 68, 69 ]);
}

/// Concurrent readers do not steal each other's position
unittest
{
    import core.thread : Thread;
    import std.file : remove, tempDir, write;
    import std.path : buildPath;

    enum SIZE    = 4096;
    enum READERS = 4;
    enum ROUNDS  = 128;
    enum WINDOW  = 64;

    string path = buildPath(tempDir(), "osfile_concurrent.tmp");
    ubyte[SIZE] content;
    foreach (i, ref ubyte b; content)
        b = cast(ubyte)i;
    write(path, content[]);

    OSFile file;
    file.open(path, OFlags.read | OFlags.exists);
    scope(exit) { file.close(); remove(path); }

    // Each reader needs its own closure frame, hence the maker function
    Thread reader(long seed)
    {
        return new Thread({
            ubyte[WINDOW] buffer;
            foreach (round; 0 .. ROUNDS)
            {
                long pos = (seed * (round + 1)) % (SIZE - WINDOW);
                ubyte[] got = file.readAt(pos, buffer);
                assert(got.length == WINDOW);
                foreach (i, ubyte b; got)
                    assert(b == cast(ubyte)(pos + i));
            }
        });
    }

    Thread[READERS] readers;
    foreach (i, ref Thread t; readers)
        t = reader((cast(long)i + 1) * 37);
    foreach (Thread t; readers) t.start();
    foreach (Thread t; readers) t.join();
}

/// Replacement for std.file.getAvailableDiskSpace since gdc-11 (FE: 2.076),
/// the default for Ubuntu 22.04, does not have have said function.
///
/// Plus does the safer thing on Windows where it forces getting the parent
/// directory if the target isn't a directory.
///
/// Used specifically with a file target in mind.
/// Params: path = Target path.
/// Returns: Available bytes.
/// Throws: OSException
ulong availableDiskSpace(string path)
{
    // NOTE: std.file.cenforce is private... But we have OSException
    
    import std.file : exists, isDir;
    import std.path : dirName;
    
    if (exists(path) == false || isDir(path) == false)
        path = dirName(path); // force getting directory path
    
version (Windows)
{
    import std.internal.cstring : tempCStringW;
    
    ULARGE_INTEGER avail;
    BOOL err = GetDiskFreeSpaceExW(path.tempCStringW(), &avail, null, null);
    if (err == FALSE)
        throw new OSException("GetDiskFreeSpaceExW");
    
    return avail.QuadPart;
}
else version (FreeBSD)
{
    import std.internal.cstring : tempCString;
    import core.sys.freebsd.sys.mount : statfs, statfs_t;

    statfs_t stats;
    int err = statfs(path.tempCString(), &stats);
    if (err < 0)
        throw new OSException("statfs");

    return stats.f_bavail * stats.f_bsize;
}
else version (Posix)
{
    import std.internal.cstring : tempCString;
    import core.sys.posix.sys.statvfs : statvfs, statvfs_t;

    statvfs_t stats;
    int err = statvfs(path.tempCString(), &stats);
    if (err < 0)
        throw new OSException("statvfs");

    return stats.f_bavail * stats.f_frsize;
}
else static assert(0, "Unsupported platform");
}
