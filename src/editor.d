module editor;

import ddhx;
import std.container.slist;
import std.stdio : File;
import std.path : baseName;
import std.file : getSize;
import core.stdc.stdio : FILE;
import os.file, os.mmfile;
import os.terminal;

/// FileMode for Io.
enum FileMode {
	file,	/// Normal file.
	mmfile,	/// Memory-mapped file.
	stream,	/// Standard streaming I/O.
	memory,	/// Typically from a stream buffered into memory.
}

enum SourceInput {
	File,
	Stream,
}

/// Editor editing mode.
enum EditMode : ushort {
	readOnly,	/// Editing data will be disallowed.
	insert,	/// Data will be inserted.
	overwrite,	/// Data will be overwritten.
}

/// Represents a single edit
struct Edit {
	EditMode mode;	/// Which mode was used for edit
	long position;	/// Absolute offset of edit
	ubyte value;	/// Payload
	// or ubyte[]?
}

/// Editor.
//TODO: [0.5] Virtual change system.
//      For editing/rendering/saving.
//      Array!(Edit) or sorted dictionary?
//      Obviously CTRL+Z for undo, CTRL+Y for redo.
//TODO: [0.5] ubyte[] view
//      Copy screen buffer, modify depending on changes, send
//      foreach edit
//        if edit.position within current position + screen length
//          modify screen result buffer
//TODO: File watcher
//TODO: File lock mechanic

private union Source {
	OSFile2      osfile;
	OSMmFile     mmfile;
	File         stream;
	MemoryStream memory;
} private __gshared Source source;

// File properties

private __gshared ubyte[] readBuffer;	/// For input input
private __gshared size_t readSize;	/// For input input
private __gshared FileMode fileMode;	/// Current file mode.

// Editing stuff

private struct Editing {
	EditMode mode;	/// Current editing mode
	SList!Edit history;	/// Temporary file edits
	size_t count;	/// Amount of edits in history
	size_t index;	/// Current edit position
} private Editing edits;

// View properties

size_t viewSize;	/// ?
ubyte[] viewBuffer;	/// ?

bool eof() {
	final switch (fileMode) {
	case FileMode.file:	return source.osfile.eof;
	case FileMode.mmfile:	return source.mmfile.eof;
	case FileMode.stream:	return source.stream.eof;
	case fileMode.memory:	return source.memory.eof;
	}
}

bool err() {
	final switch (fileMode) {
	case FileMode.file:	return source.osfile.err;
	case FileMode.mmfile:	return source.mmfile.err;
	case FileMode.stream:	return source.stream.error;
	case fileMode.memory:	return false;
	}
}

bool dirty() {
	return edits.index == 0;
}

// SECTION: File opening

int openFile(string path) {
	version (Trace) trace("path='%s'", path);
	
	if (source.osfile.open(path))
		return errorSet(ErrorCode.os);
	
	fileMode = FileMode.file;
	return 0;
}

int openMmfile(string path/*, bool create*/) {
	version (Trace) trace("path='%s'", path);
	
	try {
		source.mmfile = new OSMmFile(path);
	} catch (Exception ex) {
		return errorSet(ex);
	}
	
	fileMode = FileMode.mmfile;
	return 0; 
}

int openStream(File file) {
	source.stream = file;
	fileMode = FileMode.stream;
	return 0;
}

int openMemory(ubyte[] data) {
	source.memory.open(data);
	fileMode = FileMode.memory;
	return 0;
}

// !SECTION

// SECTION: Buffer management

void setBuffer(size_t size) {
	readSize = size;
	
	switch (fileMode) with (FileMode) {
	case file, stream:
		readBuffer = new ubyte[size];
		return;
	default:
	}
}

// !SECTION

// SECTION: Position management

void seek(long pos) {
	final switch (fileMode) with (FileMode) {
	case file:
		source.osfile.seek(Seek.start, pos);
		return;
	case mmfile:
		source.mmfile.seek(pos);
		return;
	case memory:
		source.memory.seek(pos);
		return;
	case stream:
		source.stream.seek(pos);
		return;
	}
}

long tell() {
	final switch (fileMode) {
	case FileMode.file:	return source.osfile.tell;
	case FileMode.mmfile:	return source.mmfile.tell;
	case FileMode.stream:	return source.stream.tell;
	case fileMode.memory:	return source.memory.tell;
	}
}

// !SECTION

// SECTION: Reading

ubyte[] read() {
	final switch (fileMode) with (FileMode) {
	case file:	return source.osfile.read(readBuffer);
	case mmfile:	return source.mmfile.read(readSize);
	case stream:	return source.stream.rawRead(readBuffer);
	case memory:	return source.memory.read(readSize);
	}
}

// !SECTION

// SECTION: Editing

/// 
ubyte[] view() {
	ubyte[] t = read().dup;
	
	
	
	return null;
}

/// Append change
void change(ubyte data, long pos, EditMode mode) {
	debug assert(mode != EditMode.readOnly,
		"Editor should not be getting edits in read-only mode");
	
	
}

/// Write all changes to file
void writeChanges() {
	
}


// !SECTION

long size() {
	version (Trace) trace("");
	
	final switch (fileMode) with (FileMode) {
	case file:   return source.osfile.size;
	case mmfile: return source.mmfile.length;
	case memory: return source.memory.size;
	case stream: return source.stream.size;
	}
}

// long newSize() ?




//TODO: from other types
/+int toMemory(long skip = 0, long length = 0) {
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
	
	fileMode = FileMode.memory;
	setMeta(null, "-");
	return 0;
}+/