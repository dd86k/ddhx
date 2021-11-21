module ddhx.input;

import std.stdio : File, stdin, FILE;
import std.mmfile;
import std.file : getSize;
import std.container : Array;
import ddhx.error;
import ddhx.utils : formatSize;

/// Dump default size
enum DEFAULT_BUFFER_SIZE = 4 * 1024;

/// 
enum InputMode {
	file,
	mmfile,
	stdin,
}

/// 
struct Input {
	InputMode mode;
	ulong size;	/// file size
	union {
		File file;
		MmFile mmfile;
		ubyte[] inBuffer; // or //Array!ubyte inBuffer;
	}
	union {
		ubyte[] fBuffer;
		ubyte *mmAddress;
	}
	long position;	/// file/buffer position
	uint bufferSize;	/// buffer size
	
	int openFile(string path) {
		try {
			file.open(path);
			size = file.size();
			if (size == 0)
				return ddhxError(DdhxError.fileEmpty);
			mode = InputMode.file;
			seek = &seekFile;
			read = &readFile;
			readBuffer = &readBufferFile;
			return 0;
		} catch (Exception ex) {
			return ddhxError(ex);
		}
	}
	int openMmfile(string path) {
		try {
			size = getSize(path);
			if (size == 0)
				return ddhxError(DdhxError.fileEmpty);
			mmfile = new MmFile(path, MmFile.Mode.read, 0, mmAddress);
			mode = InputMode.mmfile;
			seek = &seekMmfile;
			read = &readMmfile;
			readBuffer = &readBufferMmfile;
			return 0;
		} catch (Exception ex) {
			return ddhxError(ex);
		}
	}
	int openStdin() {
		mode = InputMode.stdin;
		seek = null;
		read = &readStdin;
		readBuffer = &readBufferStdin;
		bufferSize = DEFAULT_BUFFER_SIZE;
		return 0;
	}
	
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
		return file.rawRead(fBuffer);
	}
	private ubyte[] readMmfile() {
		return cast(ubyte[])mmfile[position..position+bufferSize];
	}
	private ubyte[] readStdin() {
		return stdin.rawRead(fBuffer);
	}
	private ubyte[] readStdin2() {
		version (D_LP64)
			return inBuffer[position..position+bufferSize];
		else
			return inBuffer[cast(uint)position..cast(uint)position+bufferSize];
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
			return inBuffer[position..position+buffer.length];
		else
			return inBuffer[cast(uint)position..cast(uint)position+buffer.length];
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
			//inBuffer ~= stdin.rawRead(buffer);
			l = fread(buffer.ptr, 1, innerBufferSize, _stdin);
			if (l == 0) break;
			inBuffer ~= buffer[0..l];
		//} while (stdin.eof() == false);
		} while (l);
		
		size = inBuffer.length;
	}
	
	const(char)[] binarySize() {
		__gshared char[32] b = void;
		return formatSize(b, size);
	}
}