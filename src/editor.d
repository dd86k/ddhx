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
enum EditMode : ushort {
	/// Incoming data will be inserted at cursor position.
	/// Editing: Enabled
	/// Cursor: Enabled
	insert,
	/// Incoming data will be overwritten at cursor position.
	/// Editing: Enabled
	/// Cursor: Enabled
	overwrite,
	/// The file cannot be edited.
	/// Editing: Disabled
	/// Cursor: Enabled
	readOnly,
	/// The file can only be viewed.
	/// Editing: Disabled
	/// Cursor: Disabled
	view,
}

/// Represents a single edit
struct Edit {
	EditMode mode;	/// Which mode was used for edit
	long position;	/// Absolute offset of edit
	ubyte value;	/// Payload
	// or ubyte[]?
}

private union Source {
	OSFile       osfile;
	OSMmFile     mmfile;
	File         stream;
	MemoryStream memory;
}
private __gshared Source source;

__gshared const(char)[] fileName;	/// File base name.
__gshared FileMode fileMode;	/// Current file mode.
__gshared long position;	/// Last known set position.
//TODO: rename to viewSize
__gshared size_t readSize;	/// For input size.
private __gshared ubyte[] readBuffer;	/// For input data.
private __gshared uint vheight;	/// 

// Editing stuff

private __gshared size_t editIndex;	/// Current edit position
private __gshared size_t editCount;	/// Amount of edits in history
private __gshared SList!Edit editHistory;	/// Temporary file edits
__gshared EditMode editMode;	/// Current editing mode

string editModeString(EditMode mode = editMode) {
	final switch (mode) with (EditMode) {
	case insert: return "inse";
	case overwrite: return "over";
	case readOnly: return "read";
	case view: return "view";
	}
}
bool editModeReadOnly(EditMode mode) {
	switch (mode) with (EditMode) {
	case readOnly, view: return true;
	default: return false;
	}
}

private struct cursor_t {
	//TODO: Transform into an 1D position system
	//      2D is just clumsy...
	uint position;	/// Screen cursor byte position
	uint nibble;	/// Data group nibble position
}
__gshared cursor_t cursor;	/// Cursor state

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
	return editIndex == 0;
}

// SECTION: File opening

int openFile(string path) {
	version (Trace) trace("path='%s'", path);
	
	if (source.osfile.open(path, editModeReadOnly(editMode)))
		return errorSet(ErrorCode.os);
	
	fileMode = FileMode.file;
	fileName = baseName(path);
	return 0;
}

int openMmfile(string path) {
	version (Trace) trace("path='%s'", path);
	
	try {
		source.mmfile = new OSMmFile(path, editModeReadOnly(editMode));
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

long seek(long pos) {
	position = pos;
	final switch (fileMode) with (FileMode) {
	case file:   return source.osfile.seek(Seek.start, pos);
	case mmfile: return source.mmfile.seek(pos);
	case memory: return source.memory.seek(pos);
	case stream:
		source.stream.seek(pos);
		return pos;
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
ubyte[] peek() {
	ubyte[] t = read().dup;
	
	
	
	return null;
}

void keydown(Key key) {
	debug assert(editMode != EditMode.readOnly,
		"Editor should not be getting edits in read-only mode");
	
	//TODO: Check by panel (binary or text)
	//TODO: nibble-awareness
	
}

/// Append change at current position
void appendEdit(ubyte data) {
	debug assert(editMode != EditMode.readOnly,
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

private
bool viewStart() {
	bool z = cursor.position > readSize;
	position = 0;
	return z;
}
private
bool viewEnd() {
	//TODO: align to columns
	long old = position;
	position = fileSize - readSize;
	return position != old;
}
private
bool viewUp() {
	long npos = position - setting.width;
	if (npos < 0)
		return false;
	position = npos;
	return true;
}
private
bool viewDown() {
	long fsize = fileSize;
	if (position + readSize > fsize)
		return false;
	position += setting.width;
	return true;
}
private
bool viewPageUp() {
	long npos = position - readSize;
	bool ok = npos >= 0;
	if (ok) position = npos;
	return ok;
}
private
bool viewPageDown() {
	long npos = position + readSize;
	bool ok = npos < fileSize;
	if (ok) position = npos;
	return ok;
}

// !SECTION

//
// SECTION Cursor position management
//

void cursorBound() {
	if (cursor.position < 0)
		cursor.position = 0;
	else if (cursor.position >= readSize) {
		if (cursor.position - setting.width >= readSize)
			cursor.position = cast(uint)(readSize - 1);
		else
			cursor.position -= setting.width;
	}
}

// These return true if view moves.

bool cursorFileStart() {
	viewStart;
	with (cursor) position = nibble = 0;
	return true;
}
bool cursorFileEnd() {
	viewEnd;
	with (cursor) {
		position = cast(uint)readSize - 1;
		nibble = 0;
	}
	return true;
}

bool cursorHome() { // put cursor at the start of row
	cursor.position = cursor.position - (cursor.position % setting.width);
	cursor.nibble = 0;
	return false;
}
bool cursorEnd() { // put cursor at the end of the row
	cursor.position =
		(cursor.position - (cursor.position % setting.width))
		+ setting.width - 1;
	cursor.nibble = 0;
	return false;
}
bool cursorLeft() {
	if (cursor.position == 0) {
		if (position == 0)
			return false;
		cursorEnd;
		return viewUp;
	}
	
	--cursor.position;
	cursor.nibble = 0;
	return false;
}
bool cursorRight() {
	if (cursorTell >= fileSize - 1)
		return false;
	
	if (cursor.position == readSize - 1) {
		cursorHome;
		return viewDown;
	}
	
	++cursor.position;
	cursor.nibble = 0;
	return false;
}
bool cursorUp() {
	if (cursor.position < setting.width) {
		return viewUp;
	}
	
	cursor.position -= setting.width;
	return false;
}
bool cursorDown() {
	/// File size
	long fsize = fileSize;
	/// Normalized file size with last row (remaining) trimmed
	long fsizenorm = fsize - (fsize % setting.width);
	/// Absolute cursor position
	long acpos = cursorTell;
	
	bool bottom = cursor.position + setting.width >= readSize; // cursor bottom
	bool finalr = acpos >= fsizenorm; /// final row
	
	/* /// set if cursor within last row
	bool last = cursor.position > readSize - setting.width;
	/// set if camera wants to be pushed down
	bool move = cpos + setting.width >= fsize;
	/// set if at the end of file
	bool end = cpos > fsize - setting.width;
	bool ok = last && move; */
	
	version (Trace) trace("bottom=%s final=%s", bottom, finalr);
	
	if (finalr)
		return false;
	
	if (bottom) {
		return viewDown;
	}
	
	if (acpos + setting.width > fsize) {
		uint rem = cast(uint)(fsize % setting.width);
		cursor.position = cast(uint)(readSize - setting.width + rem);
		return false;
	}
	
	cursor.position += setting.width;
	return false;
}
bool cursorPageUp() {
	return viewPageUp;
}
bool cursorPageDown() {
	//TODO: Fix cursor position if out of bounds
	//      Should stay on the same column
	return viewPageDown;
}
/// Get cursor absolute position within the file
long cursorTell() {
	return position + cursor.position;
}
void cursorGoto(long m) {
	// Per view chunks, then per y chunks, then x
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