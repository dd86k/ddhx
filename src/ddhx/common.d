/// Common global variables.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module ddhx.common;

//TODO: Remove imports
import std.stdio : File, stdin, FILE, fgetpos, fsetpos, fpos_t;
import std.mmfile;
import std.file : getSize;
import std.path : baseName;
import ddhx;

//TODO: If File.size() still causes issue in DMCRT, redo File

/// Copyright string
enum COPYRIGHT = "Copyright (c) 2017-2022 dd86k <dd@dax.moe>";

/// App version
enum VERSION = "0.4.0";

/// Version line
enum VERSION_LINE = "ddhx " ~ VERSION ~ " (built: " ~ __TIMESTAMP__~")";

//
// SECTION Input structure
//

/// Dump default size
enum DEFAULT_BUFFER_SIZE = 4 * 1024;

/// 
enum InputMode {
	file,
	mmfile,
	stdin,
}

/// 
//TODO: Deprecate
struct Input {
	private union { // Input internals or buffer
		File file;	/// File input
		MmFile mmfile;	/// Mmfile input
		ubyte[] stdinBuffer;	/// Stdin read-all buffer
	}
	private union { // Input buffer
		ubyte[] fBuffer;	/// input buffer for file/stdin
		ubyte *mmAddress;	/// address placeholder for MmFile
	}
	union { // Read buffer
		ubyte[] result;
	}
	ulong size;	/// file size
	long position;	/// Absolute position in file/mmfile/buffer
	private long position2;
	uint bufferSize;	/// buffer size
	string fileName;	/// File basename
	const(char)[] sizeString;	/// Binary file size as string
	InputMode mode;	/// Current input mode
	
	int openFile(string path) {
		try {
			// NOTE: File.size() has overflow issues in 32-bit builds
			//       in the DigitalMars C runtime
			size = getSize(path);
			if (size == 0)
				return errorSet(ErrorCode.fileEmpty);
			file.open(path);
			fileName = baseName(path);
			sizeString = binarySize();
			mode = InputMode.file;
			seek = &seekFile;
			read = &readFile;
			readBuffer = &readBufferFile;
			return 0;
		} catch (Exception ex) {
			return errorSet(ex);
		}
	}
	int openMmfile(string path) {
		try {
			size = getSize(path);
			if (size == 0)
				return errorSet(ErrorCode.fileEmpty);
			mmfile = new MmFile(path, MmFile.Mode.read, 0, mmAddress);
			fileName = baseName(path);
			sizeString = binarySize();
			mode = InputMode.mmfile;
			seek = &seekMmfile;
			read = &readMmfile;
			readBuffer = &readBufferMmfile;
			return 0;
		} catch (Exception ex) {
			return errorSet(ex);
		}
	}
	int openStdin() {
		fileName = "-";
		mode = InputMode.stdin;
		seek = null;
		read = &readStdin;
		readBuffer = &readBufferStdin;
		bufferSize = DEFAULT_BUFFER_SIZE;
		return 0;
	}
	
	/// Adjust input read size.
	/// Params: s = New read size.
	void adjust(uint s) {
		bufferSize = s;
		switch (mode) with (InputMode) {
		case file, stdin:
			fBuffer = new ubyte[s];
			break;
		default:
		}
	}
	
	/// Seek into input.
	void delegate(long) seek;
	
	private void seekFile(long pos) {
		file.seek(position = pos);
	}
	private void seekMmfile(long pos) {
		position = pos;
	}
	
	/// Read input.
	ubyte[] delegate() read;
	
	private ubyte[] readFile() {
		return (result = file.rawRead(fBuffer));
	}
	private ubyte[] readMmfile() {
		//TODO: Be smart: Check for overflows
		return (result = cast(ubyte[])mmfile[position..position+bufferSize]);
	}
	private ubyte[] readStdin() {
		return (result = stdin.rawRead(fBuffer));
	}
	private ubyte[] readStdin2() {
		version (D_LP64)
			return stdinBuffer[position..position+bufferSize];
		else
			return stdinBuffer[cast(uint)position..cast(uint)position+bufferSize];
	}
	
	/// Read into a buffer.
	ubyte[] delegate(ubyte[]) readBuffer;
	
	private ubyte[] readBufferFile(ubyte[] buffer) {
		return file.rawRead(buffer);
	}
	private ubyte[] readBufferMmfile(ubyte[] buffer) {
		return cast(ubyte[])mmfile[position..position+buffer.length];
	}
	private ubyte[] readBufferStdin(ubyte[] buffer) {
		return stdin.rawRead(buffer);
	}
	private ubyte[] readBufferStdin2(ubyte[] buffer) {
		version (D_LP64)
			return stdinBuffer[position..position+buffer.length];
		else
			return stdinBuffer[cast(uint)position..cast(uint)position+buffer.length];
	}
	
	void slurpStdin(long skip = 0, long length = 0) {
		enum innerBufferSize = 512;
		
		seek = &seekMmfile;
		read = &readStdin2;
		readBuffer = &readBufferStdin2;
		
		size_t l = void;
		ubyte[] buffer;
		if (skip) {
			if (skip > innerBufferSize) {
				buffer = new ubyte[innerBufferSize];
			} else {
				buffer = new ubyte[cast(uint)skip];
			}
			do {
				l = stdin.rawRead(buffer).length;
			} while (l >= innerBufferSize);
		}
		
		buffer = new ubyte[innerBufferSize];
		
		import core.stdc.stdio : fread;
		FILE *_stdin = stdin.getFP;
		do {
			//stdinBuffer ~= stdin.rawRead(buffer);
			l = fread(buffer.ptr, 1, innerBufferSize, _stdin);
			if (l == 0) break;
			stdinBuffer ~= buffer[0..l];
		//} while (stdin.eof() == false);
		} while (l);
		
		size = stdinBuffer.length;
	}
	
	const(char)[] binarySize() {
		__gshared char[32] b = void;
		return formatSize(b, size);
	}
}

// !SECTION

/// Number type to render either for offset or data
enum NumberType {
	hexadecimal,
	decimal,
	octal
}

/// Character translation
enum CharType {
	ascii,	/// 7-bit US-ASCII
	cp437,	/// IBM PC CP-437
	ebcdic,	/// IBM EBCDIC Code Page 37
//	gsm,	/// GSM 03.38
}

//TODO: --no-header: bool
//TODO: --no-offset: bool
//TODO: --no-status: bool
/// Global definitions and default values
// Aren't all of these engine settings anyway?
struct Globals {
	// Settings
	ushort rowWidth = 16;	/// How many bytes are shown per row
	NumberType offsetType;	/// Current offset view type
	NumberType dataType;	/// Current data view type
	CharType charType;	/// Current charset
	char defaultChar = '.';	/// Default character to use for non-ascii characters
//	int include;	/// Include what panels
	// Internals
	TerminalSize termSize;	/// Last known terminal size
}

__gshared Globals globals; /// Single-instance of globals.
__gshared Input   input;   /// Input file/stream