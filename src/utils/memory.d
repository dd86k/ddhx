module utils.memory;


import std.stdio : File;
import std.container.array;

//TODO: Use OutBuffer or Array!ubyte when writing changes?
struct MemoryStream {
	private ubyte[] buffer;
	private long position;
	
	bool err, eof;
	
	void cleareof() {
		eof = false;
	}
	void clearerr() {
		err = false;
	}
	
	// read file into memory
	/*void open(string path) {
	}*/
	void open(ubyte[] data) {
		buffer = data;
		
		
	}
	void open(File stream) {
		buffer = buffer.init;
		//TODO: use OutBuffer
		foreach (ubyte[] a; stream.byChunk(4096)) {
			buffer ~= a;
		}
		
	}
	
	void seek(long pos) {
		/*final switch (origin) with (Seek) {
		case start:*/
			position = pos;
		/*	return 0;
		case current:
			position += pos;
			return 0;
		case end:
			position = size - pos;
			return 0;
		}*/
	}
	
	ubyte[] read(size_t size) {
		long p2 = position + size;
		
		return null;
	}
	
	// not inout ref, just want to read
	ubyte[] opSlice(size_t n1, size_t n2) {
		return buffer[n1..n2];
	}
	
	long size() { return buffer.length; }
	
	long tell() { return position; }
}