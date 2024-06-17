/// File handling.
///
/// This exists because 32-bit runtimes suffer from the 32-bit file size limit.
/// Despite the MS C runtime having _open and _fseeki64, the DM C runtime does
/// not have these functions.
/// 
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.os.file;

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
    import core.sys.posix.unistd;
    import core.sys.posix.sys.types;
    import core.sys.posix.sys.stat;
    import core.sys.posix.fcntl;
    import core.stdc.errno;
    import core.stdc.stdio : SEEK_SET, SEEK_CUR, SEEK_END;
    import std.string : toStringz;
    
    // BLKGETSIZE64 missing from dmd 2.098.1 and ldc 1.24.0
    // ldc 1.24 missing core.sys.linux.fs
    // source musl 1.2.0 and glibc 2.25 has roughly same settings.
    
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
    //TODO: _IOR!(0x12,114,size_t.sizeof) results in ulong.max
    //      I don't know why, so I'm casting it to int to let it compile.
    //      Fix later.
    private enum _IOR(int type,int nr,size_t size) =
        cast(int)_IOC!(_IOC_READ,type,nr,size);
    
    private enum BLKGETSIZE64 = cast(int)_IOR!(0x12,114,size_t.sizeof);
    private alias BLOCKSIZE = BLKGETSIZE64;
    
    version (Android)
        alias off_t = int;
    else
        alias off_t = long;
    
    private extern (C) int ioctl(int,off_t,...);
    
    private alias OSHANDLE = int;
}
else
{
    static assert(0, "Implement file I/O");
}

//TODO: FileType GetType(string)
//      Pipe, device, etc.

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
    share   = 1 << 5,   /// [TODO] Share file with read access to other programs.
}

//TODO: Set file size (to extend or truncate file, allocate size)
//    useful when writing all changes to file
//    Win32: Seek + SetEndOfFile
//    others: ftruncate
struct OSFile
{
    private OSHANDLE handle;

    //TODO: Share file.
    //      By default, at least on Windows, files aren't shared. Enabling
    //      sharing would allow refreshing view (manually) when a program
    //      writes to file.
    int open(string path, int flags = OFlags.readWrite)
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
            return handle == INVALID_HANDLE_VALUE ? GetLastError : 0;
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
            return handle < 0 ? errno : 0;
        }
    }
    
    int seek(Seek origin, long pos)
    {
        version (Windows)
        {
            LARGE_INTEGER i = void;
            i.QuadPart = pos;
            return SetFilePointerEx(handle, i, &i, origin) == FALSE ?
                GetLastError() : 0;
        }
        else version (OSX)
        {
            // NOTE: Darwin has set off_t as long
            //       and doesn't have lseek64
            return lseek(handle, pos, origin) < 0 ? errno : 0;
        }
        else version (Posix) // Should cover glibc and musl
        {
            return lseek64(handle, pos, origin) < 0 ? errno : 0;
        }
    }
    
    long tell()
    {
        version (Windows)
        {
            LARGE_INTEGER i; // .init
            SetFilePointerEx(handle, i, &i, FILE_CURRENT);
            return i.QuadPart;
        }
        else version (OSX)
        {
            return lseek(handle, 0, SEEK_CUR);
        }
        else version (Posix)
        {
            return lseek64(handle, 0, SEEK_CUR);
        }
    }
    
    long size()
    {
        version (Windows)
        {
            LARGE_INTEGER li = void;
            return GetFileSizeEx(handle, &li) ? li.QuadPart : -1;
        }
        else version (Posix)
        {
            // TODO: macOS
            stat_t stats = void;
            if (fstat(handle, &stats) == -1)
                return -1;
            // NOTE: fstat(2) sets st_size to 0 on block devices
            switch (stats.st_mode & S_IFMT) {
            case S_IFREG: // File
            case S_IFLNK: // Link
                return stats.st_size;
            case S_IFBLK: // Block devices (like a disk)
                //TODO: BSD variants
                long s = void;
                return ioctl(handle, BLOCKSIZE, &s) == -1 ? -1 : s;
            default:
                return -1;
            }
        }
    }
    
    ubyte[] read(ubyte[] buffer)
    {
        return read(buffer.ptr, buffer.length);
    }
    
    ubyte[] read(ubyte *buffer, size_t size)
    {
        version (Windows)
        {
            uint len = cast(uint)size;
            if (ReadFile(handle, buffer, len, &len, null) == FALSE)
                return null;
            return buffer[0..len];
        }
        else version (Posix)
        {
            ssize_t len = .read(handle, buffer, size);
            if (len < 0)
                return null;
            return buffer[0..len];
        }
    }
    
    size_t write(ubyte[] data)
    {
        return write(data.ptr, data.length);
    }
    
    size_t write(ubyte *data, size_t size)
    {
        version (Windows)
        {
            uint len = cast(uint)size;
            if (WriteFile(handle, data, len, &len, null) == FALSE)
                return 0;
            return len; // 0 on error anyway
        }
        else version (Posix)
        {
            ssize_t len = .write(handle, data, size);
            err = len < 0;
            return len < 0 ? 0 : len;
        }
    }
    
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
    
    void close()
    {
        version (Windows)
        {
            CloseHandle(handle);
        }
        else version (Posix)
        {
            .close(handle);
        }
    }
}
