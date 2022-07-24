/// File handling.
///
/// This exists because 32-bit runtimes suffer from the 32-bit file size limit.
/// Despite the MS C runtime having _open and _fseeki64, the DM C runtime does
/// not have these functions.
/// 
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module os.file;

version (Windows) {
	import core.sys.windows.winnt :
		DWORD, HANDLE, LARGE_INTEGER, FALSE, TRUE,
		GENERIC_ALL, GENERIC_READ, GENERIC_WRITE;
	import core.sys.windows.winbase :
		CreateFileA, CreateFileW,
		SetFilePointerEx, GetFileSizeEx,
		ReadFile, ReadFileEx,
		WriteFile,
		FlushFileBuffers,
		CloseHandle,
		OPEN_ALWAYS, OPEN_EXISTING, INVALID_HANDLE_VALUE,
		FILE_BEGIN, FILE_CURRENT, FILE_END;
	
	private alias OSHANDLE = HANDLE;
	private alias SEEK_SET = FILE_BEGIN;
	private alias SEEK_CUR = FILE_CURRENT;
	private alias SEEK_END = FILE_END;
} else version (Posix) {
	import core.sys.posix.unistd;
	import core.sys.posix.sys.types;
	import core.sys.posix.sys.stat;
	import core.sys.posix.fcntl;
	import core.stdc.errno;
	import core.stdc.stdio : SEEK_SET, SEEK_CUR, SEEK_END;
	
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
	
	private extern (C) int ioctl(int,long,...);
	
	private alias OSHANDLE = int;
} else {
	static assert(0, "Implement file I/O");
}

//TODO: FileType GetType(string)
//      Pipe, device, etc.

import std.string : toStringz;
import std.utf : toUTF16z;

/// File seek origin.
enum Seek {
	start	= SEEK_SET,	/// Seek since start of file.
	current	= SEEK_CUR,	/// Seek since current position in file.
	end	= SEEK_END	/// Seek since end of file.
}

//TODO: Set file size (to extend or truncate file, allocate size)
//	useful when writing all changes to file
//	Win32: Seek + SetEndOfFile
//	others: ftruncate
struct OSFile {
	private OSHANDLE handle;
	bool eof, err;
	
	void cleareof() {
		eof = false;
	}
	void clearerr() {
		err = false;
	}
	
	//TODO: Share file.
	//      By default, at least on Windows, files aren't shared. Enabling
	//      sharing would allow refreshing view (manually) when a program
	//      writes to file.
	bool open(string path, bool readOnly) {
		version (Windows) {
			// NOTE: toUTF16z/tempCStringW
			//       Phobos internally uses tempCStringW from std.internal
			//       but I doubt it's meant for us to use so...
			//       Legacy baggage?
			handle = CreateFileW(
				path.toUTF16z,	// lpFileName
				readOnly ?	// dwDesiredAccess
					GENERIC_READ :
					GENERIC_READ | GENERIC_WRITE,
				0,	// dwShareMode
				null,	// lpSecurityAttributes
				OPEN_EXISTING,	// dwCreationDisposition
				0,	// dwFlagsAndAttributes
				null,	// hTemplateFile
			);
			return err = handle == INVALID_HANDLE_VALUE;
		} else version (Posix) {
			handle = .open(path.toStringz, readOnly ? O_RDONLY : O_RDWR);
			return err = handle == -1;
		}
	}
	
	long seek(Seek origin, long pos) {
		version (Windows) {
			LARGE_INTEGER i = void;
			i.QuadPart = pos;
			err = SetFilePointerEx(handle, i, &i, origin) == FALSE;
			return i.QuadPart;
		} else version (OSX) {
			// NOTE: Darwin has set off_t as long
			//       and doesn't have lseek64
			pos = lseek(handle, pos, origin);
			err = pos == -1;
			return pos;
		} else version (Posix) { // Should cover glibc and musl
			pos = lseek64(handle, pos, origin);
			err = pos == -1;
			return pos;
		}
	}
	
	long tell() {
		version (Windows) {
			LARGE_INTEGER i; // .init
			SetFilePointerEx(handle, i, &i, FILE_CURRENT);
			return i.QuadPart;
		} else version (OSX) {
			return lseek(handle, 0, SEEK_CUR);
		} else version (Posix) {
			return lseek64(handle, 0, SEEK_CUR);
		}
	}
	
	long size() {
		version (Windows) {
			LARGE_INTEGER li = void;
			err = GetFileSizeEx(handle, &li) == 0;
			return err ? -1 : li.QuadPart;
		} else version (Posix) {
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
	
	ubyte[] read(ubyte[] buffer) {
		return read(buffer.ptr, buffer.length);
	}
	
	ubyte[] read(ubyte *buffer, size_t size) {
		version (Windows) {
			uint len = cast(uint)size;
			err = ReadFile(handle, buffer, len, &len, null) == FALSE;
			if (err) return null;
			eof = len < size;
			return buffer[0..len];
		} else version (Posix) {
			ssize_t len = .read(handle, buffer, size);
			if ((err = len < 0) == true) return null;
			eof = len < size;
			return buffer[0..len];
		}
	}
	
	size_t write(ubyte[] data) {
		return write(data.ptr, data.length);
	}
	
	size_t write(ubyte *data, size_t size) {
		version (Windows) {
			uint len = cast(uint)size;
			err = WriteFile(handle, data, len, &len, null) == FALSE;
			return len; // 0 on error anyway
		} else version (Posix) {
			ssize_t len = .write(handle, data, size);
			err = len < 0;
			return err ? 0 : len;
		}
	}
	
	void flush() {
		version (Windows) {
			FlushFileBuffers(handle);
		} else version (Posix) {
			.fsync(handle);
		}
	}
	
	void close() {
		version (Windows) {
			CloseHandle(handle);
		} else version (Posix) {
			.close(handle);
		}
	}
}
