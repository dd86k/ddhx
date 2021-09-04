module ddhx.input;

import std.stdio : File, stdin;
import std.mmfile;
import std.file : getSize;
import ddhx.error;
import ddhx.utils : formatsize;

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
	}
	union {
		ubyte[] fBuffer;
		ubyte *mmAddress;
	}
	long position;	/// buffer position
	uint bufferSize;	/// buffer size
	
	int openFile(string path) {
		try {
			file.open(path);
			size = file.size();
			if (size == 0)
				return ddhxError(DdhxError.fileEmpty);
			read = &readFile;
			seek = &seekFile;
			mode = InputMode.file;
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
			read = &readMmfile;
			seek = &seekMmfile;
			mode = InputMode.mmfile;
			return 0;
		} catch (Exception ex) {
			return ddhxError(ex);
		}
	}
	int openStdin() {
		read = &readStdin;
		seek = null;
		bufferSize = DEFAULT_BUFFER_SIZE;
		mode = InputMode.stdin;
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
	
	void delegate(long) seek;
	
	private void seekFile(long pos) {
		file.seek(position = pos);
	}
	private void seekMmfile(long pos) {
		position = pos;
	}
	
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
	
	const(char)[] formatSize() {
		__gshared char[32] b;
		return mode == InputMode.stdin ? "--" : formatsize(b, size);
	}
}