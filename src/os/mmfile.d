/// A re-imagination and updated version of std.mmfile that features
/// some minor enhancements, such as APIs similar to File.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module os.mmfile;

import std.stdio : File;
import std.mmfile : MmFile;

// temp
public class OSMmFile : MmFile {
    private void *address;
    this(string path, bool readOnly)
    {
        super(path,
            readOnly ?
                MmFile.Mode.read :
                MmFile.Mode.readWriteNew,
            0,
            address);
    }
    bool eof, err;
    private long position;
    long seek(long pos) // only do seek_set for now
    {
        return position = pos;
    }
    long tell()
    {
        return position;
    }
    ubyte[] read(size_t size)
    {
        long sz = cast(long)this.length;
        long p2 = position+size;
        eof = p2 > sz;
        if (eof) p2 = sz;
        return cast(ubyte[])this[position..p2];
    }
    /*void seek(long pos)
    {
        final switch (origin) with (Seek)
        {
        case start:
            position = pos;
            return 0;
        case current:
            position += pos;
            return 0;
        case end:
            position = size - pos;
            return 0;
        }
    }*/
}

/// The mode the memory mapped file is opened with.
/+enum MmFileMode {
    read,            /// Read existing file
    readWriteNew,    /// Delete existing file, write new file (overwrite)
    readWrite,       /// Read/Write existing file, create if not existing
    readCopyOnWrite, /// Read/Write existing file, copy on write
}

/// Memory-mapped file.
struct OSMmFile2 {
    /// Open a memory-mapped file.
    /// Params:
    ///   filename = File path.
    ///   mode = mmfile operating mode.
    ///   size = 
    this(string filename, MmFileMode mode = Mode.read, ulong size = 0,
        void* address = null, size_t window = 0)
{
        
        version (Windows)
{
        } else version (linux)
{
            int oflag;
            int fmode;

            final switch (mode) with (MmFileMode)
{
            case read:
                flags = MAP_SHARED;
                prot = PROT_READ;
                oflag = O_RDONLY;
                fmode = 0;
                break;
            case Mode.readWriteNew:
                assert(size != 0);
                flags = MAP_SHARED;
                prot = PROT_READ | PROT_WRITE;
                oflag = O_CREAT | O_RDWR | O_TRUNC;
                fmode = octal!660;
                break;
            case Mode.readWrite:
                flags = MAP_SHARED;
                prot = PROT_READ | PROT_WRITE;
                oflag = O_CREAT | O_RDWR;
                fmode = octal!660;
                break;
            case Mode.readCopyOnWrite:
                flags = MAP_PRIVATE;
                prot = PROT_READ | PROT_WRITE;
                oflag = O_RDWR;
                fmode = 0;
                break;
            }

            fd = fildes;

            // Adjust size
            stat_t statbuf = void;
            errnoEnforce(fstat(fd, &statbuf) == 0);
            if (prot & PROT_WRITE && size > statbuf.st_size)
            {
            // Need to make the file size bytes big
            lseek(fd, cast(off_t)(size - 1), SEEK_SET);
            char c = 0;
            core.sys.posix.unistd.write(fd, &c, 1);
            }
            else if (prot & PROT_READ && size == 0)
            size = statbuf.st_size;
            this.size = size;

            // Map the file into memory!
            size_t initial_map = (window && 2*window<size)
            ? 2*window : cast(size_t) size;
            auto p = mmap(address, initial_map, prot, flags, fd, 0);
            if (p == MAP_FAILED)
            {
            errnoEnforce(false, "Could not map file into memory");
            }
            data = p[0 .. initial_map];
        }
    }

    version (linux) this(File file, Mode mode = Mode.read, ulong size = 0,
        void* address = null, size_t window = 0)
    {
    // Save a copy of the File to make sure the fd stays open.
    this.file = file;
    this(file.fileno, mode, size, address, window);
    }

    version (linux) private this(int fildes, Mode mode, ulong size,
        void* address, size_t window)
    {
    int oflag;
    int fmode;

    final switch (mode)
    {
    case Mode.read:
        flags = MAP_SHARED;
        prot = PROT_READ;
        oflag = O_RDONLY;
        fmode = 0;
        break;

    case Mode.readWriteNew:
        assert(size != 0);
        flags = MAP_SHARED;
        prot = PROT_READ | PROT_WRITE;
        oflag = O_CREAT | O_RDWR | O_TRUNC;
        fmode = octal!660;
        break;

    case Mode.readWrite:
        flags = MAP_SHARED;
        prot = PROT_READ | PROT_WRITE;
        oflag = O_CREAT | O_RDWR;
        fmode = octal!660;
        break;

    case Mode.readCopyOnWrite:
        flags = MAP_PRIVATE;
        prot = PROT_READ | PROT_WRITE;
        oflag = O_RDWR;
        fmode = 0;
        break;
    }

    fd = fildes;

    // Adjust size
    stat_t statbuf = void;
    errnoEnforce(fstat(fd, &statbuf) == 0);
    if (prot & PROT_WRITE && size > statbuf.st_size)
    {
        // Need to make the file size bytes big
        lseek(fd, cast(off_t)(size - 1), SEEK_SET);
        char c = 0;
        core.sys.posix.unistd.write(fd, &c, 1);
    }
    else if (prot & PROT_READ && size == 0)
        size = statbuf.st_size;
    this.size = size;

    // Map the file into memory!
    size_t initial_map = (window && 2*window<size)
        ? 2*window : cast(size_t) size;
    auto p = mmap(address, initial_map, prot, flags, fd, 0);
    if (p == MAP_FAILED)
    {
        errnoEnforce(false, "Could not map file into memory");
    }
    data = p[0 .. initial_map];
    }

    /**
     * Open memory mapped file filename in mode.
     * File is closed when the object instance is deleted.
     * Params:
     *  filename = name of the file.
     *      If null, an anonymous file mapping is created.
     *  mode = access mode defined above.
     *  size =  the size of the file. If 0, it is taken to be the
     *      size of the existing file.
     *  address = the preferred address to map the file to,
     *      although the system is not required to honor it.
     *      If null, the system selects the most convenient address.
     *  window = preferred block size of the amount of data to map at one time
     *      with 0 meaning map the entire file. The window size must be a
     *      multiple of the memory allocation page size.
     * Throws:
     *  - On POSIX, $(REF ErrnoException, std, exception).
     *  - On Windows, $(REF WindowsException, std, windows, syserror).
     */
    this(string filename, Mode mode, ulong size, void* address,
        size_t window = 0)
    {
    this.filename = filename;
    this.mMode = mode;
    this.window = window;
    this.address = address;

    version (Windows)
    {
        void* p;
        uint dwDesiredAccess2;
        uint dwShareMode;
        uint dwCreationDisposition;
        uint flProtect;

        final switch (mode)
        {
        case Mode.read:
        dwDesiredAccess2 = GENERIC_READ;
        dwShareMode = FILE_SHARE_READ;
        dwCreationDisposition = OPEN_EXISTING;
        flProtect = PAGE_READONLY;
        dwDesiredAccess = FILE_MAP_READ;
        break;

        case Mode.readWriteNew:
        assert(size != 0);
        dwDesiredAccess2 = GENERIC_READ | GENERIC_WRITE;
        dwShareMode = FILE_SHARE_READ | FILE_SHARE_WRITE;
        dwCreationDisposition = CREATE_ALWAYS;
        flProtect = PAGE_READWRITE;
        dwDesiredAccess = FILE_MAP_WRITE;
        break;

        case Mode.readWrite:
        dwDesiredAccess2 = GENERIC_READ | GENERIC_WRITE;
        dwShareMode = FILE_SHARE_READ | FILE_SHARE_WRITE;
        dwCreationDisposition = OPEN_ALWAYS;
        flProtect = PAGE_READWRITE;
        dwDesiredAccess = FILE_MAP_WRITE;
        break;

        case Mode.readCopyOnWrite:
        dwDesiredAccess2 = GENERIC_READ | GENERIC_WRITE;
        dwShareMode = FILE_SHARE_READ | FILE_SHARE_WRITE;
        dwCreationDisposition = OPEN_EXISTING;
        flProtect = PAGE_WRITECOPY;
        dwDesiredAccess = FILE_MAP_COPY;
        break;
        }

        if (filename != null)
        {
        hFile = CreateFileW(filename.tempCStringW(),
            dwDesiredAccess2,
            dwShareMode,
            null,
            dwCreationDisposition,
            FILE_ATTRIBUTE_NORMAL,
            cast(HANDLE) null);
        wenforce(hFile != INVALID_HANDLE_VALUE, "CreateFileW");
        }
        else
        hFile = INVALID_HANDLE_VALUE;

        scope(failure)
        {
        if (hFile != INVALID_HANDLE_VALUE)
        {
            CloseHandle(hFile);
            hFile = INVALID_HANDLE_VALUE;
        }
        }

        int hi = cast(int)(size >> 32);
        hFileMap = CreateFileMappingW(hFile, null, flProtect,
            hi, cast(uint) size, null);
        wenforce(hFileMap, "CreateFileMapping");
        scope(failure)
        {
        CloseHandle(hFileMap);
        hFileMap = null;
        }

        if (size == 0 && filename != null)
        {
        uint sizehi;
        uint sizelow = GetFileSize(hFile, &sizehi);
        wenforce(sizelow != INVALID_FILE_SIZE || GetLastError() != ERROR_SUCCESS,
            "GetFileSize");
        size = (cast(ulong) sizehi << 32) + sizelow;
        }
        this.size = size;

        size_t initial_map = (window && 2*window<size)
        ? 2*window : cast(size_t) size;
        p = MapViewOfFileEx(hFileMap, dwDesiredAccess, 0, 0,
            initial_map, address);
        wenforce(p, "MapViewOfFileEx");
        data = p[0 .. initial_map];

        debug (MMFILE) printf("MmFile.this(): p = %p, size = %d\n", p, size);
    }
    else version (Posix)
    {
        void* p;
        int oflag;
        int fmode;

        final switch (mode)
        {
        case Mode.read:
        flags = MAP_SHARED;
        prot = PROT_READ;
        oflag = O_RDONLY;
        fmode = 0;
        break;

        case Mode.readWriteNew:
        assert(size != 0);
        flags = MAP_SHARED;
        prot = PROT_READ | PROT_WRITE;
        oflag = O_CREAT | O_RDWR | O_TRUNC;
        fmode = octal!660;
        break;

        case Mode.readWrite:
        flags = MAP_SHARED;
        prot = PROT_READ | PROT_WRITE;
        oflag = O_CREAT | O_RDWR;
        fmode = octal!660;
        break;

        case Mode.readCopyOnWrite:
        flags = MAP_PRIVATE;
        prot = PROT_READ | PROT_WRITE;
        oflag = O_RDWR;
        fmode = 0;
        break;
        }

        if (filename.length)
        {
        fd = .open(filename.tempCString(), oflag, fmode);
        errnoEnforce(fd != -1, "Could not open file "~filename);

        stat_t statbuf;
        if (fstat(fd, &statbuf))
        {
            //printf("\tfstat error, errno = %d\n", errno);
            .close(fd);
            fd = -1;
            errnoEnforce(false, "Could not stat file "~filename);
        }

        if (prot & PROT_WRITE && size > statbuf.st_size)
        {
            // Need to make the file size bytes big
            .lseek(fd, cast(off_t)(size - 1), SEEK_SET);
            char c = 0;
            core.sys.posix.unistd.write(fd, &c, 1);
        }
        else if (prot & PROT_READ && size == 0)
            size = statbuf.st_size;
        }
        else
        {
        fd = -1;
        flags |= MAP_ANON;
        }
        this.size = size;
        size_t initial_map = (window && 2*window<size)
        ? 2*window : cast(size_t) size;
        p = mmap(address, initial_map, prot, flags, fd, 0);
        if (p == MAP_FAILED)
        {
        if (fd != -1)
        {
            .close(fd);
            fd = -1;
        }
        errnoEnforce(false, "Could not map file "~filename);
        }

        data = p[0 .. initial_map];
    }
    else
    {
        static assert(0);
    }
    }

    /**
     * Flushes pending output and closes the memory mapped file.
     */
    ~this()
    {
    debug (MMFILE) printf("MmFile.~this()\n");
    unmap();
    data = null;
    version (Windows)
    {
        wenforce(hFileMap == null || CloseHandle(hFileMap) == TRUE,
            "Could not close file handle");
        hFileMap = null;

        wenforce(!hFile || hFile == INVALID_HANDLE_VALUE
            || CloseHandle(hFile) == TRUE,
            "Could not close handle");
        hFile = INVALID_HANDLE_VALUE;
    }
    else version (Posix)
    {
        version (linux)
        {
        if (file !is File.init)
        {
            // The File destructor will close the file,
            // if it is the only remaining reference.
            return;
        }
        }
        errnoEnforce(fd == -1 || fd <= 2
            || .close(fd) != -1,
            "Could not close handle");
        fd = -1;
    }
    else
    {
        static assert(0);
    }
    }

    /* Flush any pending output.
     */
    void flush()
    {
    debug (MMFILE) printf("MmFile.flush()\n");
    version (Windows)
    {
        FlushViewOfFile(data.ptr, data.length);
    }
    else version (Posix)
    {
        int i;
        i = msync(cast(void*) data, data.length, MS_SYNC);   // sys/mman.h
        errnoEnforce(i == 0, "msync failed");
    }
    else
    {
        static assert(0);
    }
    }

    /**
     * Gives size in bytes of the memory mapped file.
     */
    @property ulong length() const
    {
    debug (MMFILE) printf("MmFile.length()\n");
    return size;
    }

    /**
     * Forwards `length`.
     */
    alias opDollar = length;

    /**
     * Read-only property returning the file mode.
     */
    Mode mode()
    {
    debug (MMFILE) printf("MmFile.mode()\n");
    return mMode;
    }

    /**
     * Returns entire file contents as an array.
     */
    void[] opSlice()
    {
    debug (MMFILE) printf("MmFile.opSlice()\n");
    return opSlice(0,size);
    }

    /**
     * Returns slice of file contents as an array.
     */
    void[] opSlice(ulong i1, ulong i2)
    {
    debug (MMFILE) printf("MmFile.opSlice(%lld, %lld)\n", i1, i2);
    ensureMapped(i1,i2);
    size_t off1 = cast(size_t)(i1-start);
    size_t off2 = cast(size_t)(i2-start);
    return data[off1 .. off2];
    }

    /**
     * Returns byte at index i in file.
     */
    ubyte opIndex(ulong i)
    {
    debug (MMFILE) printf("MmFile.opIndex(%lld)\n", i);
    ensureMapped(i);
    size_t off = cast(size_t)(i-start);
    return (cast(ubyte[]) data)[off];
    }

    /**
     * Sets and returns byte at index i in file to value.
     */
    ubyte opIndexAssign(ubyte value, ulong i)
    {
    debug (MMFILE) printf("MmFile.opIndex(%lld, %d)\n", i, value);
    ensureMapped(i);
    size_t off = cast(size_t)(i-start);
    return (cast(ubyte[]) data)[off] = value;
    }


    // return true if the given position is currently mapped
    private int mapped(ulong i)
    {
    debug (MMFILE) printf("MmFile.mapped(%lld, %lld, %d)\n", i,start,
        data.length);
    return i >= start && i < start+data.length;
    }

    // unmap the current range
    private void unmap()
    {
    debug (MMFILE) printf("MmFile.unmap()\n");
    version (Windows)
    {
        wenforce(!data.ptr || UnmapViewOfFile(data.ptr) != FALSE, "UnmapViewOfFile");
    }
    else
    {
        errnoEnforce(!data.ptr || munmap(cast(void*) data, data.length) == 0,
            "munmap failed");
    }
    data = null;
    }

    // map range
    private void map(ulong start, size_t len)
    {
    debug (MMFILE) printf("MmFile.map(%lld, %d)\n", start, len);
    void* p;
    if (start+len > size)
        len = cast(size_t)(size-start);
    version (Windows)
    {
        uint hi = cast(uint)(start >> 32);
        p = MapViewOfFileEx(hFileMap, dwDesiredAccess, hi, cast(uint) start, len, address);
        wenforce(p, "MapViewOfFileEx");
    }
    else
    {
        p = mmap(address, len, prot, flags, fd, cast(off_t) start);
        errnoEnforce(p != MAP_FAILED);
    }
    data = p[0 .. len];
    this.start = start;
    }

    // ensure a given position is mapped
    private void ensureMapped(ulong i)
    {
    debug (MMFILE) printf("MmFile.ensureMapped(%lld)\n", i);
    if (!mapped(i))
    {
        unmap();
        if (window == 0)
        {
        map(0,cast(size_t) size);
        }
        else
        {
        ulong block = i/window;
        if (block == 0)
            map(0,2*window);
        else
            map(window*(block-1),3*window);
        }
    }
    }

    // ensure a given range is mapped
    private void ensureMapped(ulong i, ulong j)
    {
    debug (MMFILE) printf("MmFile.ensureMapped(%lld, %lld)\n", i, j);
    if (!mapped(i) || !mapped(j-1))
    {
        unmap();
        if (window == 0)
        {
        map(0,cast(size_t) size);
        }
        else
        {
        ulong iblock = i/window;
        ulong jblock = (j-1)/window;
        if (iblock == 0)
        {
            map(0,cast(size_t)(window*(jblock+2)));
        }
        else
        {
            map(window*(iblock-1),cast(size_t)(window*(jblock-iblock+3)));
        }
        }
    }
    }

private:
    string filename;
    void[] data;
    ulong  start;
    size_t window;
    ulong  size;
    Mode   mMode;
    void*  address;
    version (linux) File file;

    version (Windows)
    {
        HANDLE hFile = INVALID_HANDLE_VALUE;
        HANDLE hFileMap = null;
        uint dwDesiredAccess;
    }
    else version (Posix)
    {
        int fd;
        int prot;
        int flags;
        int fmode;
    } else {
        static assert(0);
    }
}+/