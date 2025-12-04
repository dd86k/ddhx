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
    import std.utf : toUTF16z;
    
    private alias OSHANDLE = HANDLE;
    private alias SEEK_SET = FILE_BEGIN;
    private alias SEEK_CUR = FILE_CURRENT;
    private alias SEEK_END = FILE_END;
    
    private enum OFLAG_OPENONLY = OPEN_EXISTING;
}
else version (Posix)
{
    import core.sys.posix.unistd : lseek, read, write, fsync, close;
    import core.sys.posix.fcntl;
    import core.stdc.errno;
    import core.stdc.stdio : SEEK_SET, SEEK_CUR, SEEK_END;
    import std.string : toStringz;
    
    import core.stdc.config : c_long, c_ulong;
    
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
    
    // NOTE: lseek64
    //       Most Linux system modules have been updated since the last time I had
    //       to force myself using lseek64 definitions.
    
    private alias OSHANDLE = int;
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

// TODO: Set file size (to extend or truncate file, allocate size)
//       useful when writing all changes to file
//       Win32: Seek + SetEndOfFile
//       others: ftruncate
/// Represents an OS abstracted file instance.
struct OSFile
{
    private OSHANDLE handle;

    // TODO: Share file.
    //       By default, at least on Windows, files aren't shared. Enabling
    //       sharing would allow refreshing view (manually) when a program
    //       writes to file.
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
            
            // NOTE: toUTF16z/tempCStringW
            //       Phobos internally uses tempCStringW from std.internal
            //       but I doubt it's meant for us to use so...
            //       Legacy baggage?
            handle = CreateFileW(
                path.toUTF16z,  // lpFileName
                dwAccess,       // dwDesiredAccess
                0,              // dwShareMode
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
            handle = .open(path.toStringz, oflags);
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
            stat_t stats = void;
            if (fstat(handle, &stats) < 0)
                throw new OSException("Couldn't get file size");
            
            int typ = stats.st_mode & S_IFMT;
            switch (typ) {
            case S_IFREG: // File
            case S_IFLNK: // Link
                return stats.st_size;
            case S_IFBLK: // Block devices (like a disk)
                // fstat(2) sets st_size to 0 on block devices
                long s = void;
                if (ioctl(handle, BLOCKSIZE, &s) < 0)
                    throw new OSException("ioctl(BLOCKSIZE)");
                return s;
            default:
                import std.conv : text;
                throw new Exception(text("Unsupported file type: ", typ));
            }
        }
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
    
    /// Write file at current position.
    /// Params: data = Byte buffer.
    /// Returns: Amount written.
    size_t write(ubyte[] data)
    {
        return write(data.ptr, data.length);
    }
    
    /// Write file at current position.
    /// Params:
    ///     data = Buffer pointer.
    ///     size = Buffer size.
    /// Returns: Amount written.
    /// Throws: OSException.
    size_t write(ubyte *data, size_t size)
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
            CloseHandle(handle);
            
            handle = INVALID_HANDLE_VALUE;
        }
        else version (Posix)
        {
            .close(handle);
            
            handle = 0;
        }
    }
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
    import core.sys.windows.winbase : GetDiskFreeSpaceExW;
    import core.sys.windows.winnt : ULARGE_INTEGER, BOOL, TRUE, FALSE;
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
