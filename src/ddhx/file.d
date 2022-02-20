/// File handling.
///
/// This exists because 32-bit runtimes suffer from the 32-bit file size limit.
/// Despite the MS C runtime having _open and _fseeki64, the DM C runtime does
/// not have these functions.
/// 
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module ddhx.file;

version (Windows) {
	import core.sys.windows.winnt :
		DWORD, HANDLE, LARGE_INTEGER, FALSE, TRUE,
		GENERIC_ALL, GENERIC_READ, GENERIC_WRITE;
	import core.sys.windows.winbase :
		CreateFileA, CreateFileW, SetFilePointerEx, ReadFile, ReadFileEx, GetFileSizeEx,
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
	import core.sys.posix.sys.ioctl;
	import core.sys.posix.fcntl;
	import core.stdc.errno;
	import core.stdc.stdio : SEEK_SET, SEEK_CUR, SEEK_END;
	
	version (linux) {
		import core.sys.linux.fs : BLKGETSIZE64;
		private alias BLOCKSIZE = BLKGETSIZE64;
	}
	
	private alias OSHANDLE = int;
} else {
	static assert(0, "Implement file I/O");
}

import std.mmfile;
import std.string : toStringz;
import std.utf : toUTF16z;
import std.file : getSize;
import std.path : baseName;
import std.container.array : Array;
import std.stdio : File;
import core.stdc.stdio : FILE;
import ddhx;

/// Default buffer size.
private enum DEFAULT_BUFFER_SIZE = 4 * 1024;

/// FileMode for OSFile.
enum FileMode {
	file,	/// Normal file.
	mmfile,	/// Memory-mapped file.
	stream,	/// Standard streaming I/O.
	memory,	/// Typically from a stream buffered into memory.
}

/// File seek origin.
enum Seek {
	start	= SEEK_SET,	/// Seek since start of file.
	current	= SEEK_CUR,	/// Seek since current position in file.
	end	= SEEK_END	/// Seek since end of file.
}

/// Improved file I/O.
//TODO: Share file.
//      By default file isn't shared (at least on Windows) which would allow
//      refreshing view (manually) when a program writes to file.
//TODO: Virtual change system.
//      For editing/rendering/saving.
//      Array!(Edit) or sorted dictionary?
struct OSFile {
	private union {
		OSHANDLE fileHandle;
		MmFile mmHandle;
		File stream;
	}
	private union {
		ubyte[] readBuffer;	/// Buffer for file/stream inputs
		ubyte *mmAddress;
	}
	
	long position;	/// Current file position.
	private long position2;	/// Saved file position.
	
	long size;	/// Last reported file size.
	const(char)[] sizeString;	/// Binary file size as string
	string fullPath;	/// Original file path.
	string name;	/// Current file name.
	FileMode mode;	/// Current file mode.
	
	ubyte[] buffer;	/// Resulting buffer or slice.
	uint readSize;	/// Desired buffer size.
	
	int delegate(Seek, long) seek;
	int delegate() read;
	
	int openFile(string path/*, bool create*/) {
		version (Windows) {
			// NOTE: toUTF16z/tempCStringW
			//       Phobos internally uses tempCStringW from std.internal
			//       but I doubt it's meant for us to use so...
			///      Legacy baggage?
			fileHandle = CreateFileW(
				path.toUTF16z,	// lpFileName
				GENERIC_READ/* | GENERIC_WRITE*/,	// dwDesiredAccess
				0,	// dwShareMode
				null,	// lpSecurityAttributes
				OPEN_EXISTING,	// dwCreationDisposition
				0,	// dwFlagsAndAttributes
				null,	// hTemplateFile
			);
			if (fileHandle == INVALID_HANDLE_VALUE)
				return errorSet(ErrorCode.os);
		} else version (Posix) {
			fileHandle = open(path.toStringz, O_RDWR);
			if (fileHandle == -1)
				return errorSet(ErrorCode.os);
		}
		
		if (refreshSize())
			return lastError;
		if (size == 0)
			return errorSet(ErrorCode.fileEmpty);
		
		sizeString = getSizeString;
		setProperties(FileMode.file, path, baseName(path));
		return 0;
	}
	
	int openMmfile(string path/*, bool create*/) {
		try {
			/*file.size = getSize(path);
			if (file.size == 0)
				return errorSet(ErrorCode.fileEmpty);*/
			mmHandle = new MmFile(path, MmFile.Mode.read, 0, mmAddress);
		} catch (Exception ex) {
			return errorSet(ex);
		}
		
		if (refreshSize())
			return lastError;
		if (size == 0)
			return errorSet(ErrorCode.fileEmpty);
		
		sizeString = getSizeString;
		setProperties(FileMode.mmfile, path, baseName(path));
		return 0; 
	}
	
	int openStream(File file) {
		setProperties(FileMode.stream, null, "-");
		return 0;
	}
	
	int openMemory(ubyte[] data) {
		buffer = data;
		setProperties(FileMode.memory, null, "-");
		return 0;
	}
	
	// Avoids errors where I forget to set basic property members.
	private void setProperties(FileMode newMode, string path, string baseName) {
		readSize = DEFAULT_BUFFER_SIZE;
		mode = newMode;
		fullPath = path;
		name = baseName;
		final switch (newMode) with (FileMode) {
		case file:
			read = &readFile;
			seek = &seekFile;
			break;
		case mmfile:
			read = &readMmfile;
			seek = &seekMmfile;
			break;
		case stream:
			read = &readStream;
			seek = &seekStream;
			break;
		case memory:
			read = &readMemory;
			seek = &seekMemory;
			break;
		}
	}
	
	private int readFile() {
		version (Windows) {
			DWORD r = void;
			if (ReadFile(fileHandle, readBuffer.ptr, readSize, &r, null) == FALSE)
				return errorSet(ErrorCode.os);
			buffer = readBuffer[0..r];
		} else version (Posix) {
			alias mygod = core.sys.posix.unistd.read;
			ssize_t r = void;
			if ((r = mygod(fileHandle, readBuffer.ptr, readBuffer.length)) < 0)
				return errorSet(ErrorCode.os);
			buffer = readBuffer[0..r];
		}
		return 0;
	}
	private int readMmfile() {
		buffer = cast(ubyte[])mmHandle[position..position + readSize];
		return 0;
	}
	private int readStream() {
		buffer = stream.rawRead(readBuffer);
		return 0;
	}
	private int readMemory() {
		buffer = readBuffer[position..position + readSize];
		return 0;
	}
	
	private int seekFile(Seek origin, long pos) {
		version (Windows) {
			LARGE_INTEGER p = void;
			p.QuadPart = pos;
			if (SetFilePointerEx(fileHandle, p, null, 0) == FALSE)
				return errorSet(ErrorCode.os);
		} else version (Posix) {
			if (lseek64(fileHandle, pos, origin) == -1)
				return errorSet(ErrorCode.os);
		}
		return 0;
	}
	private int seekMmfile(Seek origin, long pos) {
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
	private int seekStream(Seek origin, long pos) {
		return 0;
	}
	private alias seekMemory = seekMmfile;
	
	void saveState() {
	}
	void restoreState() {
	}
	
	int refreshSize() {
		final switch (mode) with (FileMode) {
		case file:
			version (Windows) {
				LARGE_INTEGER li = void;
				if (GetFileSizeEx(fileHandle, &li) == 0)
					return errorSet(ErrorCode.os);
				size = li.QuadPart;
				return 0;
			} else version (Posix) {
				stat_t stats = void;
				if (fstat(fileHandle, &stats) == -1)
					return errorSet(ErrorCode.os);
				// NOTE: fstat(2) sets st_size to 0 on block devices
				switch (stats.st_mode & S_IFMT) {
				case S_IFREG: // File
				case S_IFLNK: // Link
					size = stats.st_size;
					return 0;
				case S_IFBLK: // Block device (like a disk)
					//TODO: BSD variants
					return ioctl(fileHandle, BLOCKSIZE, &size) == -1 ?
						errorSet(ErrorCode.os) : 0;
				default: return errorSet(ErrorCode.invalidType);
				}
			}
		case mmfile:
			size = mmHandle.length;
			return 0;
		case stream:
			return 0;
		case memory:
			return 0;
		}
	}
	
	const(char)[] getSizeString() {
		__gshared char[32] b = void;
		return formatSize(b, size);
	}
	
	void resizeBuffer(uint newSize) {
		readSize = newSize;
		
		switch (mode) with (FileMode) {
		case file, stream:
			readBuffer = new ubyte[newSize];
			break;
		default:
		}
	}
	
	//TODO: other types
	int toMemory(uint skip, long length) {
		import core.stdc.stdio : fread;
		import core.stdc.stdlib : malloc, free;
		
		ubyte[DEFAULT_BUFFER_SIZE] defbuf = void;
		
		FILE *f = stream.getFP;
		
		size_t l = void;
		if (skip) {
			import std.algorithm.comparison : min;
		
		L_PRESKIP:
			int bufSize = min(DEFAULT_BUFFER_SIZE, skip);
			void *buf = malloc(bufSize);
			if (buf == null) throw new Error("Out of memory");
			
		L_SKIP:
			skip -= fread(buf, 1, bufSize, f);
			if (skip <= 0) {
				free(buf);
				goto L_READ;
			}
			if (skip < bufSize) {
				bufSize = skip;
				free(buf);
				goto L_PRESKIP;
			}
			goto L_SKIP;
		}
		
	L_READ:
		do {
			l = fread(defbuf.ptr, 1, DEFAULT_BUFFER_SIZE, f);
			buffer ~= defbuf[0..l];
			if (length) {
				length -= l;
				if (length < 0) break;
			}
		} while (l >= DEFAULT_BUFFER_SIZE);
		
		size = buffer.length;
		
		setProperties(FileMode.memory, null, "-");
		return 0;
	}
}