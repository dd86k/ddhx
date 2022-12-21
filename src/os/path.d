/// OS path utilities.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module os.path;

version (Windows) {
    import core.sys.windows.windef : S_OK;
    import core.sys.windows.shlobj :
        CSIDL_PROFILE, CSIDL_LOCAL_APPDATA, CSIDL_APPDATA,
        SHGetFolderPathA, SHGetFolderPathW;
    import core.stdc.stdlib : malloc, free;
    import core.stdc.wchar_ : wcslen;
    import std.encoding : transcode;
} else version (Posix) {
    import core.sys.posix.unistd : getuid, uid_t;
    import core.sys.posix.pwd : getpwuid, passwd;
    import core.stdc.string : strlen;
}

import std.process : environment;
import std.path : dirSeparator, buildPath;
import std.file : exists;

// NOTE: As of Windows Vista, the SHGetSpecialFolderPathW function is a wrapper
//       for SHGetKnownFolderPath. The latter not defined in the shlobj module.

/// Get the path to the current user's home folder.
/// This does not verify if the path exists.
/// Windows: Typically C:\\Users\\%USERNAME%
/// Posix: Typically /home/$USERNAME
/// Returns: Path or null on failure.
string getHomeFolder() {
    version (Windows) {
        // 1. SHGetFolderPath
        wchar *buffer = cast(wchar*)malloc(1024);
        if (SHGetFolderPathW(null, CSIDL_PROFILE, null, 0, buffer) == S_OK) {
            string path;
            transcode(buffer[0..wcslen(buffer)], path);
            free(buffer); // since transcode allocated
            return path;
        }
        free(buffer);
        // 2. %USERPROFILE%
        if ("USERPROFILE" in environment)
            return environment["USERPROFILE"];
        // 3. %HOMEDRIVE% and %HOMEPATH%
        if ("HOMEDRIVE" in environment && "HOMEPATH" in environment)
            return environment["HOMEDRIVE"] ~ environment["HOMEPATH"];
    } else version (Posix) {
        // 1. $HOME
        if ("HOME" in environment)
            return environment["HOME"];
        // 2. getpwuid+getuid
        uid_t uid = getuid();
        if (uid >= 0) {
            passwd *wd = getpwuid(uid);
            if (wd) {
                return cast(immutable(char)[])
                    wd.pw_dir[0..strlen(wd.pw_dir)];
            }
        }
    }
    
    return null;
}

/// Get the path to the current user data folder.
/// This does not verify if the path exists.
/// Windows: Typically C:\\Users\\%USERNAME%\\AppData\\Roaming
/// Posix: Typically /home/$USERNAME/.config
/// Returns: Path or null on failure.
string getUserDataFolder() {
    version (Windows) {
        // 1. SHGetFolderPath
        wchar *buffer = cast(wchar*)malloc(1024);
        if (SHGetFolderPathW(null, CSIDL_APPDATA, null, 0, buffer) == S_OK) {
            string path;
            transcode(buffer[0..wcslen(buffer)], path);
            free(buffer); // transcode allocates
            return path;
        }
        free(buffer);
        // 2. %APPDATA%
        //    Is is the exact same with CSIDL_APPDATA but anything can go wrong.
        if ("APPDATA" in environment)
            return environment["APPDATA"];
    } else version (Posix) {
        if ("XDG_CONFIG_HOME" in environment)
            return environment["XDG_CONFIG_HOME"];
    }
    
    // Fallback
    
    string base = getHomeFolder;
    
    if (base is null)
        return null;
    
    version (Windows) {
        return buildPath(base, "AppData", "Local");
    } else version (Posix) {
        return buildPath(base, ".config");
    }
}

/// Build the path for a given file name with the user home folder.
/// This does not verify if the path exists.
/// Windows: Typically C:\\Users\\%USERNAME%\\{filename}
/// Posix: Typically /home/$USERNAME/{filename}
/// Params: filename = Name of a file.
/// Returns: Path or null on failure.
string buildUserFile(string filename) {
    string base = getHomeFolder;
    
    if (base is null)
        return null;
    
    return buildPath(base, filename);
}

/// Build the path for a given file name and parent folder with the user data folder.
/// This does not verify if the path exists.
/// Windows: Typically C:\\Users\\%USERNAME%\\AppData\\Roaming\\{appname}\\{filename}
/// Posix: Typically /home/$USERNAME/.config/{appname}/{filename}
/// Params:
///     appname = Name of the app. This acts as the parent folder.
///     filename = Name of a file.
/// Returns: Path or null on failure.
string buildUserAppFile(string appname, string filename) {
    string base = getUserDataFolder;
    
    if (base is null)
        return null;
    
    return buildPath(base, appname, filename);
}