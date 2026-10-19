#!/usr/bin/env rdmd
/// Package ddhx for distribution.
///
/// Usage: ./mkpkg.d [options] <step>...   (steps run left to right; see --help)
///
/// The shaderemu steps need a cross toolchain: see packaging/shaderemu/README.
///
/// Honors the PREFIX, ARCH, and MAINTAINER environment variables. The version
/// is read straight from the source so it never drifts from the binary.
import std.stdio;
import std.file;
import std.getopt;
import std.path;
import std.process;
import std.regex;
import std.string;
import std.base64;
import std.algorithm : sort, map;
import std.algorithm.searching : canFind, find;
import std.array : array, replaceFirst;
import std.system : os, OS;
import std.zlib;
import std.conv : octal;

struct PackageInfo
{
    string name = "ddhx";
    string version_;
    string prefix;
    string arch;
    string work;
    string ldc;
    string toolchain;
    string shaderemu;
    string gcc;
    string sysroot;
    string maintainer;
    string homepage = "https://github.com/dd86k/ddhx";
    string summary = "Binary file editor";
    string description =
        "ddhx is a modal hex editor for viewing and editing binary files\n"~
        "in the terminal.";
}

struct Step
{
    string name;
    string help;
    void function(const(PackageInfo) info) fn;
}

// Steps run left to right in the order given; each is "<format>[-<phase>]".
immutable Step[] steps = [
    Step("deb", "Build a .deb from the built ./ddhx", &stepDeb),
    Step("rpm", "Build a .rpm from the built ./ddhx", &stepRpm),
    Step("tar", "Build a portable .tar.gz from the built ./ddhx", &stepTar),
    Step("shaderemu-setup",
        "One-time rv32 toolchain: LDC runtime, zig, druntime (see README)",
        &stepShaderEmuSetup),
    Step("shaderemu-build",
        "Cross-compile ddhx into a bFLT .gz.b64.txt for ShaderEmu",
        &stepShaderEmuBuild),
];

bool dryRun;

// Every side effect goes through a helper that asks this first, so --dry-run
// can show the plan without touching anything.
bool dry(lazy string what)
{
    if (dryRun)
        writeln("   would ", what);
    return dryRun;
}

// A failed check is fatal, except under --dry-run where it is a warning:
// an earlier step in the same run may be what provides the missing piece.
void require(bool ok, string msg)
{
    if (ok)
        return;
    if (dryRun == false)
        throw new Exception(msg);
    stderr.writeln("warning: ", msg);
}

// Capture the whole literal, not just the leading digits, so suffixes like
// "0.10.0-ba" survive (a trailing ~DEBUG concatenation is ignored).
string readVersion(string path)
{
    Captures!string m = matchFirst(readText(path),
        regex(`DDHX_VERSION[^=]*=\s*"([^"]*)"`));
    if (m.empty)
        throw new Exception("could not determine version from "~path);
    return m[1];
}

void run(const(string)[] cmd, const(string[string]) env = null)
{
    if (dryRun)
    {
        enum size_t shown = 16;
        writeln("   + ", cmd.length > shown ? cmd[0..shown].join(" ")~
            format(" ... (%d more)", cmd.length - shown) : cmd.join(" "));
        return;
    }
    int code = spawnProcess(cmd, env).wait();
    if (code != 0)
        throw new Exception(format("%s exited with %d", cmd[0], code));
}

void makeDirs(string path)
{
    if (dry("mkdir "~path))
        return;
    mkdirRecurse(path);
}

void removeTree(string path)
{
    if (exists(path) == false || dry("remove "~path))
        return;
    rmdirRecurse(path);
}

void putFile(string path, const(void)[] data, uint mode = octal!644)
{
    if (dry("write "~path))
        return;
    mkdirRecurse(dirName(path));
    std.file.write(path, data);
    setAttributes(path, mode);
}

void installFile(string src, string dst, uint mode)
{
    if (dry("install "~dst))
        return;
    mkdirRecurse(dirName(dst));
    copy(src, dst);
    setAttributes(dst, mode);
}

// gzip -9 -n equivalent; Phobos writes no timestamp in the gzip header.
const(void)[] gzip(const(void)[] data)
{
    Compress c = new Compress(9, HeaderFormat.gzip);
    const(void)[] body_ = c.compress(data);
    body_ ~= c.flush();
    return body_;
}

void installGzip(string src, string dst)
{
    if (dry("gzip "~src~" to "~dst))
        return;
    putFile(dst, gzip(read(src)));
}

// Same rounding as du -k: each file counted in whole KiB.
ulong installedSizeKiB(string root)
{
    ulong total;
    if (exists(root) == false)
        return total;
    foreach (DirEntry e; dirEntries(root, SpanMode.depth))
    {
        if (e.isFile)
            total += (e.size + 1023) / 1024;
    }
    return total;
}

// Ubuntu 26.04's ld stamps binaries with an x86-64-v3 ISA note, which makes
// them refuse to run on older CPUs. The same section carries the CET marks,
// so those go too. Other architectures' property notes (BTI, PAC) stay.
bool hasX86IsaNote(string bin)
{
    return execute([ "readelf", "-n", bin ], [ "LC_ALL": "C" ])
        .output.canFind("x86 ISA needed");
}

void stripX86IsaNote(string src, string installed)
{
    if (hasX86IsaNote(src) == false)
        return;
    writeln(">> stripping x86 ISA note");
    run([ "objcopy", "--remove-section=.note.gnu.property", installed ]);
}

// The payload shared by every Linux package format, minus the license, whose
// location differs per distro family.
void stageCommon(string root)
{
    installFile("ddhx", root~"/bin/ddhx", octal!755);
    stripX86IsaNote("ddhx", root~"/bin/ddhx");
    installGzip("ddhx.1", root~"/share/man/man1/ddhx.1.gz");
}

void stepDeb(const(PackageInfo) info)
{
    require(exists("ddhx"), "./ddhx not found, build it first (make release)");
    foreach (string tool; [ "fakeroot", "dpkg-deb", "readelf", "objcopy" ])
        requireTool(tool);

    string arch = info.arch;
    if (arch is null && searchPath("dpkg") !is null)
        arch = execute(["dpkg", "--print-architecture"]).output.strip();
    require(arch !is null, "dpkg not found, pass --arch");
    if (arch is null)
        arch = "unknown";

    string pkg   = format("%s_%s_%s", info.name, info.version_, arch);
    string stage = absolutePath(pkg);
    string root  = stage ~ info.prefix;

    writeln(">> staging into ", stage);
    removeTree(stage);

    stageCommon(root);
    installFile("LICENSE", root~"/share/doc/ddhx/copyright", octal!644);

    // Continuation lines of Description must start with a space.
    string desc = info.description.splitLines().join("\n ");
    putFile(stage~"/DEBIAN/control", format(
        "Package: %s\n"~
        "Version: %s\n"~
        "Section: utils\n"~
        "Priority: optional\n"~
        "Architecture: %s\n"~
        "Maintainer: %s\n"~
        "Installed-Size: %d\n"~
        "Homepage: %s\n"~
        "Description: %s\n %s\n",
        info.name, info.version_, arch, info.maintainer,
        installedSizeKiB(stage), info.homepage, info.summary, desc));

    writeln(">> packaging");
    string output = pkg~".deb";
    run(["fakeroot", "dpkg-deb", "--build", stage, output]);
    removeTree(stage);
    writeln(">> done: ", output);
}

// ARCH may be given in dpkg terms; rpm spells them differently.
string rpmArch(string arch)
{
    switch (arch)
    {
    case "amd64": return "x86_64";
    case "arm64": return "aarch64";
    case "i386":  return "i686";
    case "armhf": return "armv7hl";
    default:      return arch;
    }
}

void stepRpm(const(PackageInfo) info)
{
    require(exists("ddhx"), "./ddhx not found, build it first (make release)");
    foreach (string tool; [ "rpmbuild", "readelf", "objcopy" ])
        requireTool(tool);

    string arch = info.arch;
    if (arch is null && dryRun == false)
        arch = execute([ "uname", "-m" ]).output.strip();
    arch = arch is null ? "unknown" : rpmArch(arch);

    // rpm versions cannot contain '-'; '~' sorts a pre-release before the
    // final version.
    string ver  = info.version_.replace("-", "~");
    string top  = absolutePath(format("%s_%s_%s-rpm", info.name, ver, arch));
    string root  = top~"/BUILDROOT";
    string spec = top~"/SPECS/"~info.name~".spec";

    writeln(">> staging into ", top);
    removeTree(top);
    foreach (string dir; [ "BUILD", "RPMS", "SPECS" ])
        makeDirs(top~"/"~dir);

    stageCommon(root~info.prefix);
    installFile("LICENSE", root~info.prefix~"/share/licenses/ddhx/LICENSE",
        octal!644);

    // The binary is prebuilt, so debuginfo extraction has nothing to work on.
    putFile(spec, format(
        "%%global debug_package %%{nil}\n"~
        "Name: %s\n"~
        "Version: %s\n"~
        "Release: 1\n"~
        "Summary: %s\n"~
        "License: MIT\n"~
        "URL: %s\n"~
        "Packager: %s\n"~
        "\n"~
        "%%description\n%s\n"~
        "\n"~
        "%%files\n"~
        "%s/bin/ddhx\n"~
        "%s/share/man/man1/ddhx.1.gz\n"~
        "%%license %s/share/licenses/ddhx/LICENSE\n",
        info.name, ver, info.summary, info.homepage, info.maintainer,
        info.description, info.prefix, info.prefix, info.prefix));

    writeln(">> packaging");
    run([ "rpmbuild", "-bb", "--define", "_topdir "~top,
        "--buildroot", root, "--target", arch, spec ]);

    string output = format("%s-%s-1.%s.rpm", info.name, ver, arch);
    if (dry("copy "~output) == false)
        copy(format("%s/RPMS/%s/%s", top, arch, output), output);
    removeTree(top);
    writeln(">> done: ", output);
}

// A static executable has no program interpreter.
bool isStaticElf(string bin)
{
    return execute([ "readelf", "-l", bin ], [ "LC_ALL": "C" ])
        .output.canFind("INTERP") == false;
}

// Flat, relocatable layout (no prefix) so it unpacks and runs anywhere.
void stepTar(const(PackageInfo) info)
{
    require(exists("ddhx"), "./ddhx not found, build it first (make release)");
    foreach (string tool; [ "tar", "readelf", "objcopy" ])
        requireTool(tool);

    string arch = info.arch;
    if (arch is null && dryRun == false)
        arch = execute([ "uname", "-m" ]).output.strip();
    arch = arch is null ? "unknown" : rpmArch(arch);

    bool portable = exists("ddhx") && isStaticElf("ddhx");
    if (portable == false)
        stderr.writeln("warning: ./ddhx is dynamically linked, "~
            "not tagging the archive as static");

    string name   = format("%s-%s-linux-%s%s", info.name, info.version_, arch,
        portable ? "-static" : "");
    string stage  = absolutePath(name);
    string output = name~".tar.gz";

    writeln(">> staging into ", stage);
    removeTree(stage);
    installFile("ddhx", stage~"/ddhx", octal!755);
    stripX86IsaNote("ddhx", stage~"/ddhx");
    installGzip("ddhx.1", stage~"/ddhx.1.gz");
    installFile("LICENSE", stage~"/LICENSE", octal!644);

    writeln(">> packaging");
    run([ "tar", "--owner=0", "--group=0", "--numeric-owner", "-czf", output,
        "-C", dirName(stage), name ]);
    removeTree(stage);
    writeln(">> done: ", output);
}

string searchPath(string name)
{
    if (name.canFind(dirSeparator))
        return exists(name) ? name : null;
    foreach (string dir; environment.get("PATH", "").split(pathSeparator))
    {
        string path = buildPath(dir, name);
        if (exists(path) && isFile(path))
            return path;
    }
    return null;
}

string requireTool(string name)
{
    string path = searchPath(name);
    require(path !is null, "'"~name~"' not found in PATH");
    return path is null ? name : path;
}

// `ldc2 --version` starts with "LDC - the LLVM D compiler (1.43.0):".
string ldcVersion(string ldc)
{
    string text;
    try text = execute([ ldc, "--version" ]).output;
    catch (ProcessException ex)
    {
        require(false, "cannot run "~ldc);
        return "VERSION";
    }
    Captures!string m = matchFirst(text, regex(`\((\d+\.\d+\.\d+)\)`));
    if (m.empty)
        throw new Exception("could not determine the version of "~ldc);
    return m[1];
}

void download(string url, string dir)
{
    string archive = buildPath(dir, baseName(url));
    run([ "curl", "-fsSL", "-o", archive, url ]);
    run([ "tar", "-xf", archive, "-C", dir ]);
    if (dry("remove "~archive) == false)
        remove(archive);
}

// Idempotent: a patch already applied is skipped, one that no longer matches
// (a different LDC version) is an error rather than a silent no-op.
void patch(string path, string from, string to)
{
    if (dry("patch "~path))
        return;
    string text = readText(path);
    if (text.canFind(to))
        return;
    if (text.canFind(from) == false)
        throw new Exception("patch does not apply to "~path);
    std.file.write(path, text.replaceFirst(from, to));
}

// Fills in the riscv32 gaps of LDC's runtime; see packaging/shaderemu/README.
void patchRuntime(string ldcSrc)
{
    string dr = ldcSrc~"/runtime/druntime/src/";
    patch(dr~"core/sys/posix/signal.d",
        "else version (RISCV64)\n    {\n        enum MINSIGSTKSZ",
        "else version (RISCV_Any)\n    {\n        enum MINSIGSTKSZ");
    patch(dr~"core/stdc/fenv.d",
        "alias fexcept_t = uint;\n    }\n    else version (RISCV64)\n"~
        "    {\n        alias fenv_t",
        "alias fexcept_t = uint;\n    }\n    else version (RISCV_Any)\n"~
        "    {\n        alias fenv_t");
    patch(dr~"core/stdc/config.d",
        "    else version (CRuntime_Musl_Pre_Time64)\n"~
        "        enum muslRedirTime64 = false;\n",
        "    else version (CRuntime_Musl_Pre_Time64)\n"~
        "        enum muslRedirTime64 = false;\n"~
        "    else version (RISCV32)\n        enum muslRedirTime64 = false;\n");
    // Opaque storage for libunwind's context/cursor; the rv64 sizes are an
    // upper bound for rv32 with F registers.
    patch(dr~"core/internal/backtrace/libunwind.d",
        "else version (RISCV64) // 32 is not supported\n{",
        "else version (RISCV32)\n{\n    enum _LIBUNWIND_CONTEXT_SIZE = 64;\n"~
        "    enum _LIBUNWIND_CURSOR_SIZE = 76;\n}\nelse version (RISCV64)\n{");
    patch(ldcSrc~"/runtime/phobos/std/math/hardware.d",
        "else version (RISCV_Any) version = IeeeFlagsSupport;",
        "else version (RISCV64) version = IeeeFlagsSupport;");

    // Without a riscv32 ABI the compiler has no va_list type to check the
    // v*printf/v*scanf pragmas against.
    string stdio = dr~"core/stdc/stdio.d";
    if (dry("patch "~stdio))
        return;
    string text = readText(stdio);
    string fixed = text.replaceAll(
        regex(`pragma\((?:printf|scanf)\)\n(\s+int v\w*(?:printf|scanf)\()`),
        "$1");
    if (fixed != text)
        std.file.write(stdio, fixed);
}

string findZig(string work)
{
    string zig = searchPath("zig");
    if (zig !is null)
        return zig;
    if (exists(work))
    {
        foreach (DirEntry e; dirEntries(work, "zig-*", SpanMode.shallow))
        {
            if (exists(e.name~"/zig"))
                return e.name~"/zig";
        }
    }

    version (X86_64) enum bool x64 = true;
    else             enum bool x64 = false;
    if (x64 == false || os != OS.linux)
        throw new Exception("'zig' not found in PATH, and only x86_64 Linux "~
            "hosts can fetch it automatically");
    writeln(">> fetching zig");
    download("https://ziglang.org/download/0.14.1/"~
        "zig-x86_64-linux-0.14.1.tar.xz", work);
    return work~"/zig-x86_64-linux-0.14.1/zig";
}

// One-time toolchain for the zig flavor of the shaderemu format: patched
// runtime sources, zig wrappers, and a druntime/phobos built for rv32.
void stepShaderEmuSetup(const(PackageInfo) info)
{
    if (info.toolchain != "zig")
        throw new Exception("setup only supports --toolchain zig");
    foreach (string tool; [ "curl", "tar", "cmake", "ninja" ])
        requireTool(tool);

    string work = absolutePath(info.work);
    makeDirs(work~"/bin");

    string ldc = requireTool(info.ldc);
    string buildRt = buildPath(dirName(ldc), "ldc-build-runtime");
    if (exists(buildRt) == false)
        buildRt = requireTool("ldc-build-runtime");

    string ver    = ldcVersion(ldc);
    string ldcSrc = format("%s/ldc-%s-src", work, ver);
    if (exists(ldcSrc) == false)
    {
        writeln(">> fetching LDC ", ver, " sources");
        download(format("https://github.com/ldc-developers/ldc/releases/"~
            "download/v%s/ldc-%s-src.tar.gz", ver, ver), work);
    }
    writeln(">> patching runtime");
    patchRuntime(ldcSrc);

    // zig's rv32 musl only builds soft-float (setjmp.S uses fsd), so no +f
    // here; the +f D objects still link, both are ilp32.
    string zig = findZig(work);
    foreach (string[2] w; [ [ "rv32cc", "cc -target riscv32-linux-musl "~
            "-mcpu=generic_rv32+m+a" ], [ "rv32ar", "ar" ],
            [ "rv32ranlib", "ranlib" ] ])
    {
        putFile(work~"/bin/"~w[0],
            format("#!/bin/sh\nexec \"%s\" %s \"$@\"\n", zig, w[1]),
            octal!755);
    }

    if (exists(work~"/rt/lib/libphobos2-ldc.a") == false)
    {
        writeln(">> building druntime/phobos");
        string[string] env = [ "CC": work~"/bin/rv32cc",
                               "AR": work~"/bin/rv32ar" ];
        run([ buildRt, "--ninja", "--buildDir="~work~"/rt",
            "--ldcSrcDir="~ldcSrc, "--targetSystem=Linux;musl;UNIX",
            "--dFlags=-mtriple=riscv32-unknown-linux-musl;"~
            "-mattr=+m,+a,+f,-c,-d;-mabi=ilp32;-wi",
            "--cFlags=-O2", "LDC_EXE_FULL="~ldc, "BUILD_SHARED_LIBS=OFF",
            "CMAKE_AR="~work~"/bin/rv32ar",
            "CMAKE_RANLIB="~work~"/bin/rv32ranlib" ], env);
    }
    writeln(">> done: ", work);
}

// Cross-compiles for ShaderEmu (rv32imaf/ilp32, musl, bFLT) with a stock LDC
// and a druntime/phobos built beforehand (see packaging/shaderemu/README).
// "shaderemu" links with ShaderEmu's own gcc and sysroot; "zig" with zig cc.
void stepShaderEmuBuild(const(PackageInfo) info)
{
    string work = absolutePath(info.work);
    string libs = work~"/rt/lib";
    string elf2bflt = absolutePath(info.shaderemu)~"/linux/nommu/elf2bflt.py";
    string crt  = "packaging/shaderemu/flatcrt.c";

    string ldcSrc = format("%s/ldc-%s-src", work, ldcVersion(info.ldc));

    bool zig = info.toolchain == "zig";
    string cc;
    string sysroot;
    if (zig)
        cc = work~"/bin/rv32cc";
    else if (info.toolchain == "shaderemu")
    {
        cc = absolutePath(info.gcc);
        sysroot = absolutePath(info.sysroot);
    }
    else
        throw new Exception("unknown toolchain: "~info.toolchain);

    requireTool("python3");
    require(exists(elf2bflt), "missing "~elf2bflt~
        ": download ShaderEmu into ./ShaderEmu or pass --shaderemu");
    foreach (string p; [ cc, ldcSrc, libs ])
    {
        require(exists(p), "missing "~p~
            " (the shaderemu-setup step builds it for --toolchain zig)");
    }

    string pkg    = format("%s_%s_shaderemu-rv32", info.name, info.version_);
    string output = pkg~".gz.b64.txt";
    string stage  = absolutePath(pkg);
    removeTree(stage);
    makeDirs(stage);
    scope (exit) if (dryRun == false) removeTree(stage);

    string[] sources = dirEntries("src", "*.d", SpanMode.depth)
        .map!(e => e.name).array.sort.release;

    // The machine has an FPU (F only, no D, no compressed); ilp32 still
    // passes floats in integer registers.
    writeln(">> compiling");
    run([ info.ldc, "-conf=", "-mtriple=riscv32-unknown-linux-musl",
        "-mattr=+m,+a,+f,-c,-d", "-mabi=ilp32",
        "-I"~ldcSrc~"/runtime/druntime/src", "-I"~ldcSrc~"/runtime/phobos",
        "-Isrc", "-O2", "-release", "-boundscheck=off", "-c", "-singleobj",
        "-of="~stage~"/ddhx.o" ] ~ sources);

    string objCrt = stage~"/flatcrt.o";
    string elf    = stage~"/ddhx.elf";
    // The no-MMU kernel only runs bFLT: link a static PIE with our own entry
    // point, since the bFLT loader does the relocating.
    writeln(">> linking");
    if (zig)
    {
        run([ cc, "-O2", "-fPIC", "-c", crt, "-o", objCrt ]);
        run([ cc, "-O2", "-fPIE", "-static-pie", "-s", "-Wl,--gc-sections",
            "-Wl,-e,_flat_start", objCrt, stage~"/ddhx.o",
            "-L"~libs, "-lphobos2-ldc", "-ldruntime-ldc", "-lunwind",
            "-o", elf ]);
    }
    else
    {
        string[] arch = [ "-march=rv32imaf", "-mabi=ilp32" ];
        string gccInc = "GCC_INCLUDE";
        if (dryRun == false)
            gccInc = execute([ cc, "-print-file-name=include" ]).output.strip();
        run([ cc ] ~ arch ~ [ "-O2", "-fPIC", "-nostdinc",
            "-isystem", sysroot~"/include", "-isystem", gccInc,
            "-c", crt, "-o", objCrt ]);
        // Same link line as ShaderEmu's rv32-cc driver, minus its flatcrt.o
        // (ours replaces it).
        run([ cc ] ~ arch ~ [ "-fPIE", "-static", "-s", "-nostdlib",
            "-Wl,-pie,--no-dynamic-linker,-z,text", "-Wl,--gc-sections",
            "-Wl,-e,_flat_start", "-L"~sysroot~"/lib", "-L"~libs,
            sysroot~"/lib/crti.o", objCrt, stage~"/ddhx.o",
            "-Wl,--start-group", "-lphobos2-ldc", "-ldruntime-ldc", "-lunwind",
            "-lc", "-lcompiler_rt", "-Wl,--end-group",
            sysroot~"/lib/crtn.o", "-o", elf ]);
    }
    run([ "python3", elf2bflt, elf, stage~"/ddhx", "0x100000" ]);

    if (dry("pack "~output))
        return;
    ubyte[] flat = cast(ubyte[])read(stage~"/ddhx");
    if (flat.length < 4 || flat[0..4] != cast(ubyte[])"bFLT")
        throw new Exception("elf2bflt output is not bFLT");

    // Text form so the browser can "Save page as" it inside ShaderEmu.
    char[] b64 = Base64.encode(cast(ubyte[])gzip(flat));
    File f = File(output, "w");
    for (size_t i = 0; i < b64.length; i += 76)
    {
        size_t end = i + 76 < b64.length ? i + 76 : b64.length;
        f.writeln(b64[i..end]);
    }
    f.close();
    writeln(">> done: ", output);
}

int main(string[] args)
{
    PackageInfo info;
    info.prefix     = environment.get("PREFIX", "/usr");
    info.arch       = environment.get("ARCH", null);
    info.maintainer = environment.get("MAINTAINER", "dd86k <dd@dax.moe>");
    string home = environment.get("HOME", ".");
    info.work       = buildPath(home, "ddhx-rv32");
    info.ldc        = "ldc2";
    info.toolchain  = "zig";
    info.shaderemu  = "ShaderEmu";
    info.gcc        = buildPath(home,
        "shaderemu-linux/toolchain/bin/riscv32-linux-gcc");
    info.sysroot    = buildPath(home, "nm/work/sysroot");

    string usage = "Usage: mkpkg.d [options] <step>...";
    GetoptResult opts;
    try
    {
        opts = getopt(args,
            "dry-run|n", "Show what each step would do, change nothing",
                &dryRun,
            "prefix", "Install prefix (env PREFIX, default /usr)",
                &info.prefix,
            "arch", "Target architecture (env ARCH, default native)",
                &info.arch,
            "maintainer", "Package maintainer (env MAINTAINER)",
                &info.maintainer,
            "work", "Toolchain directory for shaderemu (default ~/ddhx-rv32)",
                &info.work,
            "ldc", "Stock LDC for shaderemu (default ldc2)",
                &info.ldc,
            "toolchain", "zig, or shaderemu (ShaderEmu gcc+sysroot, untested)",
                &info.toolchain,
            "shaderemu", "ShaderEmu checkout (default ./ShaderEmu)",
                &info.shaderemu,
            "gcc", "ShaderEmu riscv32-linux-gcc", &info.gcc,
            "sysroot", "ShaderEmu musl sysroot", &info.sysroot);
    }
    catch (GetOptException ex)
    {
        stderr.writeln("error: ", ex.msg);
        return 1;
    }

    File dest = opts.helpWanted ? stdout : stderr;
    bool valid = opts.helpWanted == false && args.length > 1;
    foreach (string name; args[1..$])
    {
        if (steps.canFind!(s => s.name == name) == false)
        {
            stderr.writeln("error: unknown step '", name, "'");
            valid = false;
        }
    }
    if (valid == false)
    {
        if (opts.helpWanted)
            defaultGetoptPrinter(usage, opts.options);
        else
            dest.writeln(usage);
        dest.writeln("\nSteps, run in the order given:");
        foreach (const(Step) s; steps)
            dest.writefln("  %-16s %s", s.name, s.help);
        return opts.helpWanted ? 0 : 1;
    }

    try
    {
        info.version_ = readVersion("src/view.d");
        foreach (string name; args[1..$])
        {
            writeln("== ", name);
            steps.find!(s => s.name == name)[0].fn(info);
        }
    }
    catch (Exception ex)
    {
        stderr.writeln("error: ", ex.msg);
        return 2;
    }
    return 0;
}
