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

import std.mmfile;
import std.string : toStringz;
import std.utf : toUTF16z;
import std.file : getSize;
import std.path : baseName;
import std.stdio : File;
import core.stdc.stdio : FILE;

// temp
import ddhx, editor, error, utils.format, settings;

/// Default buffer size.
private enum DEFAULT_BUFFER_SIZE = 4 * 1024;

/// File seek origin.
enum Seek {
	start	= SEEK_SET,	/// Seek since start of file.
	current	= SEEK_CUR,	/// Seek since current position in file.
	end	= SEEK_END	/// Seek since end of file.
}

/// Used in saving and restoring the Io state (position and read buffer).
//TODO: Re-use in Io as-is?
// NOTE: Used in searcher but not being really useful...
deprecated
struct IoState {
	long position;	/// Position.
	uint readSize;	/// Read size.
}

// Mostly-stateless, lazy implementation of a FILE using direct OS
// functions, since File under x86-omf builds seem iffy, broken
// (especially when attempting to get the size of a large file).
deprecated
struct OSFile {
	private OSHANDLE handle;
	bool eof;
	
	//TODO: Share file.
	//      By default, at least on Windows, files aren't shared. Enabling
	//      sharing would allow refreshing view (manually) when a program
	//      writes to file.
	int open(string path) {
		version (Windows) {
			// NOTE: toUTF16z/tempCStringW
			//       Phobos internally uses tempCStringW from std.internal
			//       but I doubt it's meant for us to use so...
			//       Legacy baggage?
			handle = CreateFileW(
				path.toUTF16z,	// lpFileName
				GENERIC_READ/* | GENERIC_WRITE*/,	// dwDesiredAccess
				0,	// dwShareMode
				null,	// lpSecurityAttributes
				OPEN_EXISTING,	// dwCreationDisposition
				0,	// dwFlagsAndAttributes
				null,	// hTemplateFile
			);
			if (handle == INVALID_HANDLE_VALUE)
				return errorSet(ErrorCode.os);
		} else version (Posix) {
			handle = .open(path.toStringz, O_RDWR);
			if (handle == -1)
				return errorSet(ErrorCode.os);
		}
		return 0;
	}
	
	int seek(ref long npos, Seek origin, long pos) {
		version (Trace) trace("origin=%u pos=%u", origin, pos);
		version (Windows) {
			LARGE_INTEGER liIn = void, liOut = void;
			liIn.QuadPart = pos;
			if (SetFilePointerEx(handle, liIn, &liOut, origin) == FALSE)
				return errorSet(ErrorCode.os);
			npos = liOut.QuadPart;
		} else version (OSX) {
			const long r = lseek(handle, pos, origin);
			if (r == -1)
				return errorSet(ErrorCode.os);
			npos = r;
		} else version (Posix) {
			const long r = lseek64(handle, pos, origin);
			if (r == -1)
				return errorSet(ErrorCode.os);
			npos = r;
		}
		return 0;
	}
	
	int read(ref ubyte[] result, ubyte[] buffer) {
		version (Trace) trace("buffer.length=%u", buffer.length);
		version (Windows) {
			const uint len = cast(uint)buffer.length;
			uint r = void; /// size read
			if (ReadFile(handle, buffer.ptr, len, &r, null) == FALSE)
				return errorSet(ErrorCode.os);
			eof = r < len;
			result = buffer[0..r];
		} else version (Posix) {
			ssize_t r = .read(handle, buffer.ptr, buffer.length);
			if (r < 0)
				return errorSet(ErrorCode.os);
			eof = r < buffer.length;
			result = buffer[0..r];
		}
		return 0;
	}
	
	int size(ref long nsize) {
		version (Windows) {
			LARGE_INTEGER li = void;
			if (GetFileSizeEx(handle, &li) == 0)
				return errorSet(ErrorCode.os);
			nsize = li.QuadPart;
			return 0;
		} else version (Posix) {
			stat_t stats = void;
			if (fstat(handle, &stats) == -1)
				return errorSet(ErrorCode.os);
			// NOTE: fstat(2) sets st_size to 0 on block devices
			switch (stats.st_mode & S_IFMT) {
			case S_IFREG: // File
			case S_IFLNK: // Link
				nsize = stats.st_size;
				return 0;
			case S_IFBLK: // Block device (like a disk)
				//TODO: BSD variants
				return ioctl(handle, BLOCKSIZE, &nsize) == -1 ?
					errorSet(ErrorCode.os) : 0;
			default:
				return errorSet(ErrorCode.invalidType);
			}
		}
	}
}
//TODO: Set file size (to extend or truncate file, allocate size)
//	useful when writing all changes to file
//	Win32: Seek + SetEndOfFile
//	etc: ftruncate
struct OSFile2 {
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
	bool open(string path) {
		version (Windows) {
			// NOTE: toUTF16z/tempCStringW
			//       Phobos internally uses tempCStringW from std.internal
			//       but I doubt it's meant for us to use so...
			//       Legacy baggage?
			handle = CreateFileW(
				path.toUTF16z,	// lpFileName
				GENERIC_READ | GENERIC_WRITE,	// dwDesiredAccess
				0,	// dwShareMode
				null,	// lpSecurityAttributes
				OPEN_EXISTING,	// dwCreationDisposition
				0,	// dwFlagsAndAttributes
				null,	// hTemplateFile
			);
			return err = handle == INVALID_HANDLE_VALUE;
		} else version (Posix) {
			handle = .open(path.toStringz, O_RDWR);
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
		} else version (Posix) {
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
		version (Windows) {
			uint len = cast(uint)buffer.length;
			err = ReadFile(handle, buffer.ptr, len, &len, null) == FALSE;
			if (err) return null;
			eof = len < buffer.length;
			return buffer[0..len];
		} else version (Posix) {
			ssize_t len = .read(handle, buffer.ptr, buffer.length);
			if ((err = len < 0) == true) return null;
			eof = len < buffer.length;
			return buffer[0..len];
		}
	}
	
	size_t write(ubyte[] data) {
		version (Windows) {
			uint len = cast(uint)data.length;
			err = WriteFile(handle, data.ptr, len, &len, null) == FALSE;
			return len; // 0 on error anyway
		} else version (Posix) {
			ssize_t len = .write(handle, data.ptr, data.length);
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


/// Improved file I/O.
deprecated("Use Editor instead")
struct Io {
	private union {
		OSFile osfile;
		MmFile mmHandle;
		File stream;
	}
	private union {
		ubyte[] readBuffer;	/// Buffer for file/stream inputs
		ubyte *mmAddress;
	}
	
	long position;	/// Current file position.
	
	long size;	/// Last reported file size.
	//TODO: This shouldn't be here
	//      And should not be a property but a function
	const(char)[] sizeString;	/// Binary file size as string
	string fullPath;	/// Original file path.
	string name;	/// Current file name.
	FileMode mode;	/// Current file mode.
	//TODO: Rename to result?
	ubyte[] buffer;	/// Resulting buffer or slice.
	uint readSize;	/// Desired buffer size.
	
	bool eof;	/// End of file marker.
	private bool[3] reserved;
	
	int delegate(Seek, long) seek;
	int delegate() read;
	int delegate(ubyte[], ref ubyte[]) read2;
	
	int openFile(string path) {
		version (Trace) trace("path='%s'", path);
		
		mode = FileMode.file;
		
		if (osfile.open(path))
			return error.ecode;
		if (refreshSize())
			return error.ecode;
		if (size == 0)
			return errorSet(ErrorCode.fileEmpty);
		
		sizeString = getSizeString;
		setProperties(path, baseName(path));
		return 0;
	}
	
	int openMmfile(string path/*, bool create*/) {
		version (Trace) trace("path='%s'", path);
		
		mode = FileMode.mmfile;
		
		try {
			mmHandle = new MmFile(path, MmFile.Mode.read, 0, mmAddress);
		} catch (Exception ex) {
			return errorSet(ex);
		}
		
		if (refreshSize())
			return error.ecode;
		if (mmHandle.length == 0)
			return errorSet(ErrorCode.fileEmpty);
		
		sizeString = getSizeString;
		setProperties(path, baseName(path));
		return 0; 
	}
	
	int openStream(File file) {
		mode = FileMode.stream;
		stream = file;
		setProperties(null, "-");
		return 0;
	}
	
	int openMemory(ubyte[] data) {
		mode = FileMode.memory;
		buffer = data;
		setProperties(null, "-");
		return 0;
	}
	
	// Avoids errors where I forget to set basic property members.
	private void setProperties(string path, string baseName) {
		readSize = DEFAULT_BUFFER_SIZE;
		fullPath = path;
		name = baseName;
		final switch (mode) with (FileMode) {
		case file:
			seek = &seekFile;
			read = &readFile;
			read2 = &readFile2;
			break;
		case mmfile:
			seek = &seekMmfile;
			read = &readMmfile;
			read2 = &readMmfile2;
			break;
		case stream:
			seek = &seekStream;
			read = &readStream;
			read2 = &readStream2;
			break;
		case memory:
			seek = &seekMemory;
			read = &readMemory;
			read2 = &readMemory2;
			break;
		}
	}
	
	private int seekFile(Seek origin, long pos) {
		version (Trace) trace("seek=%s pos=%u", origin, pos);
		
		return osfile.seek(position, origin, pos);
	}
	private int seekMmfile(Seek origin, long pos) {
		version (Trace) trace("seek=%s pos=%u", origin, position);
		
		final switch (origin) with (Seek) {
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
	}
	// Acts as a skip regardless of origin (Seek.current)
	// Read into void
	private int seekStream(Seek origin, long pos) {
		import core.stdc.stdio : fread;
		import core.stdc.stdlib : malloc, free;
		import std.algorithm.comparison : min;
		
		version (Trace) trace("seek=%s pos=%u", origin, position);
		
		FILE *f = stream.getFP;
		size_t bufSize = void;
		
		if (pos) {
		L_PRESKIP:
			bufSize = cast(size_t)min(DEFAULT_BUFFER_SIZE, pos);
			void *buf = malloc(bufSize);
			if (buf == null) throw new Error("Out of memory");
			
		L_SKIP:
			pos -= fread(buf, 1, bufSize, f);
			if (pos <= 0) {
				free(buf);
				return 0;
			}
			if (pos < bufSize) {
				bufSize = cast(size_t)pos;
				free(buf);
				goto L_PRESKIP;
			}
			goto L_SKIP;
		}
		
		return 0;
	}
	// Same operation
	private alias seekMemory = seekMmfile;
	
	private int readFile() {
		version (Trace) trace("pos=%u", position);
		
		return osfile.read(buffer, readBuffer);
	}
	private int readMmfile() {
		version (Trace) trace("pos=%u", position);
		
		long endpos = position + readSize; /// Proposed end marker
		eof = endpos > size; // If end marker overflows
		if (eof)
			endpos = size;
		buffer = cast(ubyte[])mmHandle[position..endpos];
		return 0;
	}
	private int readStream() {
		version (Trace) trace("pos=%u", position);
		
		buffer = stream.rawRead(readBuffer);
		eof = stream.eof;
		return 0;
	}
	private int readMemory() {
		version (Trace) trace("pos=%u", position);
		
		long endpos = position + readSize; /// Proposed end marker
		eof = endpos > size; // If end marker overflows
		if (eof)
			endpos = size;
		buffer = readBuffer[cast(size_t)position..cast(size_t)endpos];
		return 0;
	}
	
	private int readFile2(ubyte[] _buffer, ref ubyte[] _result) {
		version (Trace) trace("buflen=%u", _buffer.length);
		
		int e = osfile.read(_result, _buffer);
		
		eof = osfile.eof;
		
		return e;
	}
	private int readMmfile2(ubyte[] _buffer, ref ubyte[] _result) {
		version (Trace) trace("buflen=%u", _buffer.length);
		
		long endpos = position + readSize; /// Proposed end marker
		eof = endpos > size; // If end marker overflows
		if (eof)
			endpos = size;
		_result = cast(ubyte[])mmHandle[position..endpos];
		return 0;
	}
	private int readStream2(ubyte[] _buffer, ref ubyte[] _result) {
		version (Trace) trace("buflen=%u", _buffer.length);
		
		_result = stream.rawRead(_buffer);
		eof = stream.eof;
		return 0;
	}
	private int readMemory2(ubyte[] _buffer, ref ubyte[] _result) {
		version (Trace) trace("buflen=%u", _buffer.length);
		
		long endpos = position + _buffer.length; /// Proposed end marker
		eof = endpos > size; // If end marker overflows
		if (eof)
			endpos = size;
		_result = readBuffer[cast(size_t)position..cast(size_t)endpos];
		return 0;
	}
	
	void save(ref IoState state) {
		version (Trace) trace("pos=%u read=%u", position, readSize);
		
		state.position = position;
		state.readSize = readSize;
	}
	void restore(ref IoState state) {
		version (Trace) trace("pos=%u->%u read=%u->%u",
			position, state.position, readSize, state.readSize);
		
		position = state.position;
		readSize = state.readSize;
		
		seek(Seek.start, state.position);
		resizeBuffer(readSize);
	}
	
	int refreshSize() {
		version (Trace) trace("mode=%s", mode);
		
		final switch (mode) with (FileMode) {
		case file:
			return osfile.size(size);
		case mmfile:
			size = mmHandle.length;
			return 0;
		case stream:
			return 0;
		case memory:
			return 0;
		}
	}
	
	//TODO: This really shouldn't be here
	const(char)[] getSizeString() {
		__gshared char[32] b = void;
		return formatSize(b, size, setting.si);
	}
	
	void resizeBuffer(uint newSize = DEFAULT_BUFFER_SIZE) {
		readSize = newSize;
		
		switch (mode) with (FileMode) {
		case file, stream:
			readBuffer = new ubyte[newSize];
			break;
		default:
		}
	}
	
	//TODO: from other types
	int toMemory(long skip = 0, long length = 0) {
		import std.array : uninitializedArray;
		import core.stdc.stdio : fread;
		import core.stdc.stdlib : malloc, free;
		import std.algorithm.comparison : min;
		
		ubyte *defbuf = cast(ubyte*)malloc(DEFAULT_BUFFER_SIZE);
		if (defbuf == null)
			return errorSet(ErrorCode.os);
		
		if (skip)
			seek(Seek.start, skip);
		
		// If no length to read is set, just read as much as possible.
		if (length == 0) length = long.max;
		
		FILE *_file = stream.getFP;
		size_t len = void;
		size_t bufSize = void;
		
		// Loop ends when len (read length) is under the buffer's length
		// or requested length.
		readBuffer.length = 0;
		do {
			bufSize = cast(size_t)min(DEFAULT_BUFFER_SIZE, length);
			len = fread(defbuf/*.ptr*/, 1, bufSize, _file);
			// ok to append without init because we got a global instance
			readBuffer ~= defbuf[0..len];
			length -= len;
		} while (len >= DEFAULT_BUFFER_SIZE && length > 0);
		
		free(defbuf);
		
		size = readBuffer.length;
		
		mode = FileMode.memory;
		setProperties(null, "-");
		return 0;
	}
}
