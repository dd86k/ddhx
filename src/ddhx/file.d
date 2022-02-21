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

/// Used in saving and restoring the OSFile state (position and read buffer).
struct OSFileState {
	long position;	/// Position.
	uint readSize;	/// Read size.
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
	
	long size;	/// Last reported file size.
	const(char)[] sizeString;	/// Binary file size as string
	string fullPath;	/// Original file path.
	string name;	/// Current file name.
	FileMode mode;	/// Current file mode.
	
	ubyte[] buffer;	/// Resulting buffer or slice.
	uint readSize;	/// Desired buffer size.
	
	bool eof;	/// End of file marker.
	private bool[3] reserved;
	
	int delegate(Seek, long) seek;
	int delegate() read;
	int delegate(ubyte[]) read2;
	
	int openFile(string path/*, bool create*/) {
		version (Windows) {
			// NOTE: toUTF16z/tempCStringW
			//       Phobos internally uses tempCStringW from std.internal
			//       but I doubt it's meant for us to use so...
			//       Legacy baggage?
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
		stream = file;
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
		version (Windows) {
			LARGE_INTEGER p = void;
			p.QuadPart = pos;
			if (SetFilePointerEx(fileHandle, p, null, 0) == FALSE)
				return errorSet(ErrorCode.os);
		} else version (Posix) {
			if (lseek64(fileHandle, pos, origin) == -1)
				return errorSet(ErrorCode.os);
		}
		return seekMmfile(origin, pos);
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
	// Read into void
	private int seekStream(Seek origin, long pos) {
		
		//TODO: seekStream
		
		return 0;
	}
	// Same operation
	private alias seekMemory = seekMmfile;
	
	private int readFile() {
		version (Windows) {
			DWORD r = void;
			if (ReadFile(fileHandle, readBuffer.ptr, readSize, &r, null) == FALSE)
				return errorSet(ErrorCode.os);
			buffer = readBuffer[0..r];
			eof = r < readSize;
		} else version (Posix) {
			alias mygod = core.sys.posix.unistd.read;
			ssize_t r = mygod(fileHandle, readBuffer.ptr, readSize);
			if (r < 0)
				return errorSet(ErrorCode.os);
			buffer = readBuffer[0..r];
			eof = r < readSize;
		}
		return 0;
	}
	private int readMmfile() {
		long endpos = position + readSize; /// Proposed end marker
		eof = endpos > size; // If end marker overflows
		if (eof)
			endpos = size;
		buffer = cast(ubyte[])mmHandle[position..endpos];
		return 0;
	}
	private int readStream() {
		buffer = stream.rawRead(readBuffer);
		eof = stream.eof;
		return 0;
	}
	private int readMemory() {
		long endpos = position + readSize; /// Proposed end marker
		eof = endpos > size; // If end marker overflows
		if (eof)
			endpos = size;
		buffer = readBuffer[cast(size_t)position..cast(size_t)endpos];
		return 0;
	}
	
	private int readFile2(ubyte[] _buffer) {
		version (Windows) {
			const uint _bs = cast(uint)_buffer.length;
			DWORD r = void;
			if (ReadFile(fileHandle, _buffer.ptr, _bs, &r, null) == FALSE)
				return errorSet(ErrorCode.os);
			eof = r < _bs;
			if (eof)
				buffer.length = r;
		} else version (Posix) {
			alias mygod = core.sys.posix.unistd.read;
			ssize_t r = mygod(fileHandle, _buffer.ptr, _buffer.length);
			if (r < 0)
				return errorSet(ErrorCode.os);
			eof = r < readSize;
			if (eof)
				buffer.length = r;
		}
		return 0;
	}
	private int readMmfile2(ubyte[] _buffer) {
		long endpos = position + readSize; /// Proposed end marker
		eof = endpos > size; // If end marker overflows
		if (eof)
			endpos = size;
		buffer = cast(ubyte[])mmHandle[position..endpos];
		return 0;
	}
	private int readStream2(ubyte[] _buffer) {
		buffer = stream.rawRead(_buffer);
		eof = stream.eof;
		return 0;
	}
	private int readMemory2(ubyte[] _buffer) {
		long endpos = position + _buffer.length; /// Proposed end marker
		eof = endpos > size; // If end marker overflows
		if (eof)
			endpos = size;
		buffer = readBuffer[cast(size_t)position..cast(size_t)endpos];
		return 0;
	}
	
	void save(ref OSFileState state) {
		state.position = position;
		state.readSize = readSize;
	}
	void restore(ref OSFileState state) {
		position = state.position;
		readSize = state.readSize;
		
		seek(Seek.start, state.position);
		resizeBuffer(readSize);
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
		import core.stdc.stdio : fread;
		import core.stdc.stdlib : malloc, free;
		import std.algorithm.comparison : min;
		
		ubyte[DEFAULT_BUFFER_SIZE] defbuf = void;
		FILE *f = stream.getFP;
		size_t len = void;
		size_t bufSize = void;
		
		if (skip) {
		L_PRESKIP:
			bufSize = cast(size_t)min(DEFAULT_BUFFER_SIZE, skip);
			void *buf = malloc(bufSize);
			if (buf == null) throw new Error("Out of memory");
			
		L_SKIP:
			skip -= fread(buf, 1, bufSize, f);
			if (skip <= 0) {
				free(buf);
				goto L_READ;
			}
			if (skip < bufSize) {
				bufSize = cast(size_t)skip;
				free(buf);
				goto L_PRESKIP;
			}
			goto L_SKIP;
		}
		
		// If no length to read is set, just read as much as possible.
		if (length == 0) length = long.max;
		
		// Loop ends when len (read length) is under the buffer's length
		// or requested length.
		readBuffer.length = 0;
	L_READ:
		do {
			bufSize = cast(size_t)min(DEFAULT_BUFFER_SIZE, length);
			len = fread(defbuf.ptr, 1, bufSize, f);
			// ok to append without init because we got a global instance
			readBuffer ~= defbuf[0..len];
			length -= len;
		} while (len >= DEFAULT_BUFFER_SIZE && length > 0);
		
		size = readBuffer.length;
		
		setProperties(FileMode.memory, null, "-");
		return 0;
	}
}