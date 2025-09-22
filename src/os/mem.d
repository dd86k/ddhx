/// Memory utilities.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module os.mem;

/// Get system's configured page size.
///
/// This function exists because core.memory.pageSize does not exist on
/// older GDC versions, like 11 (Ubuntu 22.04).
/// Returns: Page size in bytes.
size_t syspagesize()
{
    version (Windows)
    {
        import core.sys.windows.winbase : GetSystemInfo, SYSTEM_INFO;
        SYSTEM_INFO sysinfo = void;
        GetSystemInfo(&sysinfo);
        return sysinfo.dwPageSize;
    }
    else version (Posix)
    {
        import core.sys.posix.unistd : sysconf, _SC_PAGESIZE;
        return cast(size_t) sysconf(_SC_PAGESIZE);
    }
    else
        return 4096;
}
