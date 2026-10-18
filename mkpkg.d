#!/usr/bin/env rdmd
/// Package ddhx for distribution.
///
/// Usage: ./mkpkg.d [options] <format>   (formats: deb; see --help)
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
import std.zlib;
import std.conv : octal;

struct PackageInfo
{
    string name = "ddhx";
    string version_;
    string prefix;
    string arch;
    string maintainer;
    string homepage = "https://github.com/dd86k/ddhx";
    string summary = "Binary file editor";
    string description =
        "ddhx is a modal hex editor for viewing and editing binary files\n"~
        "in the terminal.";
}

alias PackageFunc = string function(const(PackageInfo) info);

immutable PackageFunc[string] formats;
shared static this()
{
    formats = [ "deb": &packageDeb ];
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

void run(const(string)[] cmd)
{
    int code = spawnProcess(cmd).wait();
    if (code != 0)
        throw new Exception(format("%s exited with %d", cmd[0], code));
}

void installFile(string src, string dst, uint mode)
{
    mkdirRecurse(dirName(dst));
    copy(src, dst);
    setAttributes(dst, mode);
}

// gzip -9 -n equivalent; Phobos writes no timestamp in the gzip header.
void installGzip(string src, string dst)
{
    mkdirRecurse(dirName(dst));
    Compress c = new Compress(9, HeaderFormat.gzip);
    const(void)[] body_ = c.compress(read(src));
    body_ ~= c.flush();
    std.file.write(dst, body_);
    setAttributes(dst, octal!644);
}

// Same rounding as du -k: each file counted in whole KiB.
ulong installedSizeKiB(string root)
{
    ulong total;
    foreach (DirEntry e; dirEntries(root, SpanMode.depth))
    {
        if (e.isFile)
            total += (e.size + 1023) / 1024;
    }
    return total;
}

string packageDeb(const(PackageInfo) info)
{
    string arch = info.arch;
    if (arch is null)
        arch = execute(["dpkg", "--print-architecture"]).output.strip();

    string pkg   = format("%s_%s_%s", info.name, info.version_, arch);
    string stage = absolutePath(pkg);
    string root  = stage ~ info.prefix;

    writeln(">> staging into ", stage);
    if (exists(stage))
        rmdirRecurse(stage);

    installFile("ddhx", root~"/bin/ddhx", octal!755);
    installGzip("ddhx.1", root~"/share/man/man1/ddhx.1.gz");
    installFile("LICENSE", root~"/share/doc/ddhx/copyright", octal!644);

    // Continuation lines of Description must start with a space.
    string desc = info.description.splitLines().join("\n ");
    mkdirRecurse(stage~"/DEBIAN");
    std.file.write(stage~"/DEBIAN/control", format(
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
    rmdirRecurse(stage);
    return output;
}

int main(string[] args)
{
    PackageInfo info;
    info.prefix     = environment.get("PREFIX", "/usr");
    info.arch       = environment.get("ARCH", null);
    info.maintainer = environment.get("MAINTAINER", "dd86k <dd@dax.moe>");

    string usage = "Usage: mkpkg.d [options] <" ~ formats.keys.join("|") ~ ">";
    GetoptResult opts;
    try
    {
        opts = getopt(args,
            "prefix",     "Install prefix (env PREFIX, default /usr)", &info.prefix,
            "arch",       "Target architecture (env ARCH, default native)", &info.arch,
            "maintainer", "Package maintainer (env MAINTAINER)", &info.maintainer);
    }
    catch (GetOptException ex)
    {
        stderr.writeln("error: ", ex.msg);
        return 1;
    }

    if (opts.helpWanted)
    {
        defaultGetoptPrinter(usage, opts.options);
        return 0;
    }
    if (args.length != 2 || args[1] !in formats)
    {
        stderr.writeln(usage);
        return 1;
    }

    try
    {
        info.version_ = readVersion("src/view.d");
        writeln(">> done: ", formats[args[1]](info));
    }
    catch (Exception ex)
    {
        stderr.writeln("error: ", ex.msg);
        return 2;
    }
    return 0;
}
