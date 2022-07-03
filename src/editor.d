module editor;

import std.container.slist;
import std.stdio : File;
import std.path : baseName;
import std.file : getSize;
import core.stdc.stdio : FILE;
import settings, error;
import os.file, os.mmfile, os.terminal;
import utils.memory;

// NOTE: Cursor management.
//
//       Viewport ("camera").
//
//       The file position controls the position of the start of the view
//       port and the size of the read buffer determines the screen buffer
//       size.
//
//       Cursor ("pointer").
//
//       The cursor is governed in a 2-dimensional zero-based position relative
//       to the viewport in bytes and is nibble aware. The application calls
//       the cursorXYZ functions and updates the position on-screen manually.

// NOTE: Dependencies
//
//       If the editor doesn't directly invoke screen handlers, the editor
//       code could potentially be re-used in other projects.

//TODO: Error mechanism
//TODO: Consider function hooks for basic events
//      Like when the cursor has changed position, camera moved, etc.
//      Trying to find a purpose for this...
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

//TODO: Make editor hold more states and settings
//      Lower module has internal function pointers set from received option

/*private struct settings_t {
	/// Bytes per row
	//TODO: Rename to columns
	ushort width = 16;
	/// Current offset view type
	NumberType offsetType;
	/// Current data view type
	NumberType dataType;
	/// Default character to use for non-ascii characters
	char defaultChar = '.';
	/// Use ISO base-10 prefixes over IEC base-2
	bool si;
}

/// Current settings.
public __gshared settings_t settings2;*/

// File properties

/// FileMode for Io.
enum FileMode {
	file,	/// Normal file.
	mmfile,	/// Memory-mapped file.
	stream,	/// Standard streaming I/O, often pipes.
	memory,	/// Typically from a stream buffered into memory.
}

/*enum SourceType {
	file,
	pipe,
}*/

/// Editor editing mode.
//TODO: "get string" with "ins","ovr","rdo"
enum EditMode : ushort {
	insert,	/// Data will be inserted.
	overwrite,	/// Data will be overwritten.
	readOnly,	/// Editing data is disallowed by user or permission.
}

/// Represents a single edit
struct Edit {
	EditMode mode;	/// Which mode was used for edit
	long position;	/// Absolute offset of edit
	ubyte value;	/// Payload
	// or ubyte[]?
}

private union Source {
	OSFile2      osfile;
	OSMmFile     mmfile;
	File         stream;
	MemoryStream memory;
}
private __gshared Source source;

__gshared const(char)[] fileName;	/// File base name.
__gshared FileMode fileMode;	/// Current file mode.
__gshared long position;	/// Last known set position.
private __gshared ubyte[] readBuffer;	/// For input input.
__gshared size_t readSize;	/// For input input.

// Editing stuff

private struct Editing {
	EditMode mode;	/// Current editing mode
	const(char[]) modestr = "ins";	/// Current editing mode string
	SList!Edit history;	/// Temporary file edits
	size_t count;	/// Amount of edits in history
	size_t index;	/// Current edit position
}
__gshared Editing edits;

struct cursor_t {
	int x;	/// Data group column position
	int y;	/// Data group row position
	int nibble;	/// Data group nibble position
}
__gshared cursor_t cursor;

// View properties

__gshared size_t viewSize;	/// ?
__gshared ubyte[] viewBuffer;	/// ?

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
	fileName = baseName(path);
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
	fileName = baseName(path);
	return 0; 
}

int openStream(File file) {
	source.stream = file;
	fileMode = FileMode.stream;
	fileName = null;
	return 0;
}

int openMemory(ubyte[] data) {
	source.memory.open(data);
	fileMode = FileMode.memory;
	fileName = null;
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

//
// SECTION: View position management
//

void seek(long pos) {
	position = pos;
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
	final switch (fileMode) with (FileMode) {
	case file:	return source.osfile.tell;
	case mmfile:	return source.mmfile.tell;
	case stream:	return source.stream.tell;
	case memory:	return source.memory.tell;
	}
}

// !SECTION

//
// SECTION: Reading
//

ubyte[] read() {
	final switch (fileMode) with (FileMode) {
	case file:	return source.osfile.read(readBuffer);
	case mmfile:	return source.mmfile.read(readSize);
	case stream:	return source.stream.rawRead(readBuffer);
	case memory:	return source.memory.read(readSize);
	}
}
ubyte[] read(ubyte[] buffer) {
	final switch (fileMode) with (FileMode) {
	case file:	return source.osfile.read(buffer);
	case mmfile:	return source.mmfile.read(buffer.length);
	case stream:	return source.stream.rawRead(buffer);
	case memory:	return source.memory.read(buffer.length);
	}
}

// !SECTION

// SECTION: Editing

/// 
ubyte[] view() {
	ubyte[] t = read().dup;
	
	
	
	return null;
}

void keydown(Key key) {
	debug assert(edits.mode != EditMode.readOnly,
		"Editor should not be getting edits in read-only mode");
	
	//TODO: Check by panel (binary or text)
	//TODO: nibble-awareness
	
}

/// Append change at current position
void appendEdit(ubyte data) {
	debug assert(edits.mode != EditMode.readOnly,
		"Editor should not be getting edits in read-only mode");
	
	
}

/// Write all changes to file.
/// Only edits [0..index] will be carried over.
/// When done, [0..index] edits will be cleared.
void writeEdits() {
	
}


// !SECTION

//
// SECTION View position management
//


// Reserve bytes for file allocation
// void reserve(long nsize) ?

void moveStart() {
	position = 0;
}
void moveEnd() {
	position = fileSize - readSize;
}
void moveUp() {
	if (position - setting.width >= 0)
		position -= setting.width;
	else
		position = 0;
}
void moveDown() {
	long fsize = fileSize;
	if (position + readSize + setting.width <= fsize)
		seek(position + setting.width);
	else
		seek(fsize - readSize);
}

// !SECTION

//
// SECTION Cursor position management
//

long tellPosition() {
	return position + (cursor.y * setting.width) + cursor.x;
}

void cursorFileStart() {
	moveStart;
	with (cursor) x = y = nibble = 0;
}
void cursorFileEnd() {
	moveEnd;
	with (cursor) {
		x = setting.width - 1;
		y = (cast(int)readSize / setting.width) - 1;
		nibble = 0;
	}
}


void cursorHome() {
	cursor.x = cursor.nibble = 0;
}
void cursorEnd() {
	cursor.x = setting.width - 1;
	cursor.nibble = 0;
}
void cursorLeft() {
	if (cursor.x == 0) {
		if (cursor.y == 0)
			return;
		
		--cursor.y;
		cursorEnd;
		return;
	}
	
	--cursor.x;
}
void cursorRight() {
	if (cursor.x == setting.width - 1) {
		size_t r = (readSize / setting.width) - 1;
		if (cursor.y == r) {
			moveDown;
			cursorHome;
			return;
		}
		
		++cursor.y;
		cursorHome;
		return;
	}
	
	++cursor.x;
}
void cursorUp() {
	if (cursor.y == 0) {
		moveUp;
		return;
	}
	
	--cursor.y;
}
void cursorDown() {
	size_t r = (readSize / setting.width) - 1;
	
	version (Trace) trace("rsz=%u w=%u r=%u", readSize, setting.width, r);
	
	if (cursor.y == r) {
		moveDown;
		return;
	}
	
	++cursor.y;
}
void cursorPageUp() {
	
}
void cursorPageDown() {
	size_t r = (readSize / setting.width) - 1;
	
	
}
/// Get cursor absolute position
long cursorTell() {
	return position + cursorView;
}
void cursorTo(long m) { // absolute
	// Per view chunks, then per y chunks, then x
	//long npos = 
	
}
/// Get cursor relative position to view
long cursorView() {
	return (cursor.y * setting.width) + cursor.x;
}
void cursorJump(long m) { // relative
	
	//long npos = 
	
}

// !SECTION

long fileSize() {
	long sz = void;
	
	final switch (fileMode) with (FileMode) {
	case file:	sz = source.osfile.size;	break;
	case mmfile:	sz = source.mmfile.length;	break;
	case memory:	sz = source.memory.size;	break;
	case stream:	sz = source.stream.size;	break;
	}
	
	version (Trace) trace("sz=%u", sz);
	
	return sz;
}

//TODO: from other types?
int slurp(long skip = 0, long length = 0) {
	import std.array : uninitializedArray;
	import core.stdc.stdio : fread;
	import core.stdc.stdlib : malloc, free;
	import std.algorithm.comparison : min;
	import std.outbuffer : OutBuffer;
	import std.typecons : scoped;
	
	enum READ_SIZE = 4096;
	
	//
	// Skiping
	//
	
	ubyte *b = cast(ubyte*)malloc(READ_SIZE);
	if (b == null)
		return errorSet(ErrorCode.os);
	
	FILE *_file = source.stream.getFP;
	
	if (skip) {
		/*while (skip > 0) {
			if (skip - READ_SIZE > 0) {
				break;
			}
			
			skip -= fread(b, READ_SIZE, 1, _file);
		}
		if (skip > 0) { // remaining
			fread(b, cast(size_t)skip, 1, _file);
		}*/
		do {
			size_t bsize = cast(size_t)min(READ_SIZE, skip);
			skip -= fread(b, 1, bsize, _file);
		} while (skip > 0);
	}
	
	//
	// Reading
	//
	
	auto outbuf = scoped!OutBuffer;
	
	// If no length set, just read as much as possible.
	if (length == 0) length = long.max;
	
	// Loop ends when len (read length) is under the buffer's length
	// or requested length.
	do {
		size_t bsize = cast(size_t)min(READ_SIZE, length);
		size_t len = fread(b, 1, bsize, _file);
		outbuf.put(b[0..len]);
		length -= len;
	} while (length > 0);
	
	free(b);
	
	source.memory.open(outbuf.toBytes.dup);
	fileMode = FileMode.memory;
	return 0;
}