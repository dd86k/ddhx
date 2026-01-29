/// Target platform information.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module platform;

/// Soft assertion exception class.
///
/// Utilities:
/// - An assert quits program without a chance to do anything.
/// - Debug-only asserts can still be invoked as "debug assertion(...)".
public class Assertion : Exception
{
    this(string msg, // @suppress(dscanner.style.undocumented_declaration)
        string _file = __FILE__, size_t _line = __LINE__)
    {
        super("assert: "~msg, _file, _line);
    }
}
static if (__VERSION__ >= 2079) // eponymous std.exception.enforce
{
    import std.exception : enforce;
    public alias assertion = enforce!Assertion;
}
else
{
    import std.exception : enforceEx;
    public alias assertion = enforceEx!Assertion;
}

/// Represents a feature not implemented, yet or never.
public class NotImplementedException : Exception
{
    this( // @suppress(dscanner.style.undocumented_declaration)
        string _file = __FILE__, size_t _line = __LINE__)
    {
        super("Not implemented", _file, _line);
    }
}

// Target architecture
version (X86)
    enum TARGET_PLATFORM = "x86";	/// Platform string
else version (X86_64)
    enum TARGET_PLATFORM = "x86_64";	/// Ditto
else version (ARM_Thumb) // NOTE: "In any Thumb mode", so could be T16 too...
    enum TARGET_PLATFORM = "arm_t32";	/// Ditto
else version (AArch64)
    enum TARGET_PLATFORM = "arm_a64";	/// Ditto
else version (ARM)
    enum TARGET_PLATFORM = "arm_a32";	/// Ditto
else version (PPC)
    enum TARGET_PLATFORM = "powerpc";	/// Ditto
else version (PPC64)
    enum TARGET_PLATFORM = "powerpc64";	/// Ditto
else version (SPARC)
    enum TARGET_PLATFORM = "sparc";	/// Ditto
else version (SPARC64)
    enum TARGET_PLATFORM = "sparc64";	/// Ditto
else version (S390)
    enum TARGET_PLATFORM = "s390";	/// Ditto
else version (SystemZ)
    enum TARGET_PLATFORM = "systemz";	/// Ditto
else version (RISCV32)
    enum TARGET_PLATFORM = "riscv32";	/// Ditto
else version (RISCV64)
    enum TARGET_PLATFORM = "riscv64";	/// Ditto
else version (Xtensa)
    enum TARGET_PLATFORM = "xtensa";	/// Ditto
else
    enum TARGET_PLATFORM = "unknown";	/// Ditto

// Target OS
version (Win64)
    enum TARGET_OS = "win64";	/// Platform OS string
else version (Win32)
    enum TARGET_OS = "win32";	/// Ditto
else version (Android)
    enum TARGET_OS = "android";	/// Ditto
else version (linux)
    enum TARGET_OS = "linux";	/// Ditto
else version (OSX)
    enum TARGET_OS = "osx";	/// Ditto
else version (FreeBSD)
    enum TARGET_OS = "freebsd";	/// Ditto
else version (OpenBSD)
    enum TARGET_OS = "openbsd";	/// Ditto
else version (NetBSD)
    enum TARGET_OS = "netbsd";	/// Ditto
else version (DragonflyBSD)
    enum TARGET_OS = "dragonflybsd";	/// Ditto
else version (Solaris)
    enum TARGET_OS = "solaris";	/// Ditto
else version (AIX)
    enum TARGET_OS = "aix";	/// Ditto
else version (Hurd)
    enum TARGET_OS = "hurd";	/// Ditto
else
    enum TARGET_OS = "unknown";	/// Ditto

// Target runtime environment
version (MinGW)
    enum TARGET_ENV = "mingw";	/// Platform environment string
else version (Cygwin)
    enum TARGET_ENV = "cygwin";	/// Ditto
else version (CRuntime_DigitalMars)
    enum TARGET_ENV = "digitalmars";	/// Ditto
else version (CRuntime_Microsoft)
    enum TARGET_ENV = "mscvrt";	/// Ditto
else version (CRuntime_Bionic)
    enum TARGET_ENV = "bionic";	/// Ditto
else version (CRuntime_Musl)
    enum TARGET_ENV = "musl";	/// Ditto
else version (CRuntime_Glibc)
    enum TARGET_ENV = "glibc";	/// Ditto
else version (CRuntime_Newlib)
    enum TARGET_ENV = "newlib";	/// Ditto
else version (CRuntime_UClibc)
    enum TARGET_ENV = "uclibc";	/// Ditto
else version (CRuntime_WASI)	// WebAssembly
    enum TARGET_ENV = "wasi";	/// Ditto
else version (FreeStanding)
    enum TARGET_ENV = "freestanding";	/// Ditto
else
    enum TARGET_ENV = "unknown";	/// Ditto

/// Full target triple.
enum TARGET_TRIPLE = TARGET_PLATFORM ~ "-" ~ TARGET_OS ~ "-" ~ TARGET_ENV;

/// Maximum address value for this target.
enum MAXSIZE = size_t.max;

/// Pointer size in bits
enum BITNESS = cast(int)size_t.sizeof * 8;

version (verbose)
{
    pragma(msg, "TARGET\t",  TARGET_TRIPLE);
    pragma(msg, "MAXSIZE\t", MAXSIZE);
    pragma(msg, "BITNESS\t", BITNESS);
}
