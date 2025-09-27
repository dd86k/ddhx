/// OS path utilities.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module os.path;

version (Windows)
{
    import core.sys.windows.windef : S_OK;
    import core.sys.windows.shlobj :
        CSIDL_PROFILE, CSIDL_LOCAL_APPDATA, CSIDL_APPDATA,
        SHGetFolderPathA, SHGetFolderPathW;
    import core.stdc.stdlib : malloc, free;
    import core.stdc.wchar_ : wcslen;
    import std.encoding : transcode;
}
else version (Posix)
{
    import core.sys.posix.unistd : getuid, uid_t;
    import core.sys.posix.pwd : getpwuid, passwd;
    import core.stdc.string : strlen;
}

import std.process : environment;
import std.path : buildPath;

// NOTE: As of Windows Vista, the SHGetSpecialFolderPathW function is a wrapper
//       for SHGetKnownFolderPath. The latter not defined in the shlobj module.

/// Get the path to the current user's home folder.
/// This does not verify if the path exists.
/// Windows: Typically C:\\Users\\%USERNAME%
/// Posix: Typically /home/$USERNAME
/// Returns: Path or null on failure.
string getHomeFolder()
{
    version (Windows)
    {
        // 1. %USERPROFILE%
        if (string userprofile = environment.get("USERPROFILE"))
            return userprofile;
        // 2. %HOMEDRIVE% and %HOMEPATH%
        string homedrive = environment.get("HOMEDRIVE");
        string homepath  = environment.get("HOMEPATH");
        if (homedrive && homepath)
            return homedrive ~ homepath;
        // 3. SHGetFolderPath
        wchar *buffer = cast(wchar*)malloc(1024);
        assert(buffer, "malloc failed");
        scope(exit) free(buffer); // transcode allocates, so it's safe to free
        if (SHGetFolderPathW(null, CSIDL_PROFILE, null, 0, buffer) == S_OK)
        {
            string path;
            transcode(buffer[0..wcslen(buffer)], path);
            return path;
        }
    }
    else version (Posix)
    {
        // 1. $HOME
        if (string home = environment.get("HOME"))
            return home;
        // 2. getpwuid+getuid
        passwd *wd = getpwuid(getuid());
        if (wd && wd.pw_dir)
        {
            return cast(string)wd.pw_dir[0..strlen(wd.pw_dir)];
        }
    }
    
    return null;
}

/// Get the path to the current user data folder.
/// This does not verify if the path exists.
/// Windows: Typically C:\\Users\\%USERNAME%\\AppData\\Local
/// Posix: Typically /home/$USERNAME/.config
/// Returns: Path or null on failure.
string getUserConfigFolder()
{
    version (Windows)
    {
        // 1. %LOCALAPPDATA%
        if (string localappdata = environment.get("LOCALAPPDATA"))
            return localappdata;
        // 2. SHGetFolderPath
        wchar *buffer = cast(wchar*)malloc(1024);
        assert(buffer, "malloc failed");
        scope(exit) free(buffer); // transcode allocates
        if (SHGetFolderPathW(null, CSIDL_LOCAL_APPDATA, null, 0, buffer) == S_OK)
        {
            string path;
            transcode(buffer[0..wcslen(buffer)], path);
            return path;
        }
    }
    else version (Posix)
    {
        if (string xdg_config_home = environment.get("XDG_CONFIG_HOME"))
            return xdg_config_home;
    }
    
    // Fallback
    string base = getHomeFolder;
    if (base is null)
        return null;
    
    version (Windows)
    {
        return buildPath(base, "AppData", "Local");
    }
    else version (Posix)
    {
        return buildPath(base, ".config");
    }
}

/// Attempt to find existing config file on the system.
/// Params:
///     appname = Application name, used for user config folder.
///     filename = File to get.
/// Returns: Path to config file, or null.
string findConfig(string appname, string filename)
{
    import std.file : exists;
    
    // 1. Check in app config directory
    string appdir = getUserConfigFolder;
    if (appdir)
    {
        string path = buildPath(appdir, appname, filename);
        if (exists(path))
            return path;
    }
    
    // 2. Check in user home folder
    string homedir = getHomeFolder();
    if (homedir)
    {
        string path = buildPath(homedir, filename);
        if (exists(path))
            return path;
    }
    
    // 3. Check in system folder (TODO)
    
    return null;
}
