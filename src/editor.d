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
//        +-> File position is at 0x10, at the start of the read buffer
//        |
//        |   hex 01 02 03 04
//       00000010 ab cd 11 22 -+
//       00000014 33 44<55>66  +- Read buffer
//       00000018 77 88 99 ff -+
//                      ^^
//                      ++------ Cursor is at position 6 of read buffer

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
	/// Incoming data will be overwritten at cursor position.
	/// This is the default.
	/// Editing: Enabled
	/// Cursor: Enabled
	overwrite,
	/// Incoming data will be inserted at cursor position.
	/// Editing: Enabled
	/// Cursor: Enabled
	insert,
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
__gshared long fileSize;	/// Last size of file

// Editing stuff

private __gshared size_t editIndex;	/// Current edit position
private __gshared size_t editCount;	/// Amount of edits in history
private __gshared SList!Edit editHistory;	/// Temporary file edits
__gshared EditMode editMode;	/// Current editing mode

string editModeString(EditMode mode = editMode) {
	final switch (mode) with (EditMode) {
	case overwrite:	return "ov";
	case insert:	return "in";
	case readOnly:	return "rd";
	case view:	return "vw";
	}
}
bool editModeReadOnly(EditMode mode) {
	return mode >= EditMode.readOnly;
}

private struct cursor_t {
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
	return editIndex > 0;
}

// SECTION: File opening

int openFile(string path) {
	version (Trace) trace("path='%s'", path);
	
	if (source.osfile.open(path, editModeReadOnly(editMode)))
		return errorSetOs;
	
	fileMode = FileMode.file;
	fileName = baseName(path);
	refreshFileSize;
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
	refreshFileSize;
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
	refreshFileSize;
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
	case file:	return source.osfile.seek(Seek.start, pos);
	case mmfile:	return source.mmfile.seek(pos);
	case memory:	return source.memory.seek(pos);
	case stream:
		source.stream.seek(pos);
		return source.stream.tell;
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

// NOTE: These return true if the position of the view changed.
//       This is to determine if it's really necessary to update the
//       view on screen, because pointlessly rendering content on-screen
//       is not something I want to waste.

private
bool viewStart() {
	bool z = position != 0;
	position = 0;
	return z;
}
private
bool viewEnd() {
	long old = position;
	long npos = (fileSize - readSize) + setting.columns;
	npos -= npos % setting.columns; // re-align to columns
	position = npos;
	return position != old;
}
private
bool viewUp() {
	long npos = position - setting.columns;
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
	position += setting.columns;
	return true;
}
private
bool viewPageUp() {
	long npos = position - readSize;
	bool ok = npos >= 0;
	position = ok ? npos : 0;
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
	// NOTE: It is impossible for the cursor to be at a negative position
	//       Because it is unsigned and the cursor is 0-based
	
	long fsize = fileSize;
	bool nok = cursorTell > fsize;
	
	if (nok) {
		int l = cast(int)(cursorTell - fsize);
		cursor.position -= l;
		return;
	}
}

// NOTE: These return true if view has moved.

/// Move cursor at the absolute start of the file.
/// Returns: True if the view moved.
bool cursorAbsStart() {
	with (cursor) position = nibble = 0;
	return viewStart;
}
/// Move cursor at the absolute end of the file.
/// Returns: True if the view moved.
bool cursorAbsEnd() {
	
	
	
	
	
	uint base = cast(uint)(readSize < fileSize ? fileSize : readSize);
	uint rem = cast(uint)(fileSize % setting.columns);
	uint h = cast(uint)(base / setting.columns);
	cursor.position = h + rem;
	return viewEnd;
}
/// Move cursor at the start of the row.
/// Returns: True if the view moved.
bool cursorHome() { // put cursor at the start of row
	cursor.position = cursor.position - (cursor.position % setting.columns);
	cursor.nibble = 0;
	return false;
}
/// Move cursor at the end of the row.
/// Returns: True if the view moved.
bool cursorEnd() { // put cursor at the end of the row
	cursor.position =
		(cursor.position - (cursor.position % setting.columns))
		+ setting.columns - 1;
	if (cursorTell > fileSize) {
		uint rem = cast(uint)(fileSize % setting.columns);
		cursor.position = (cursor.position + setting.columns - rem);
	}
	cursor.nibble = 0;
	return false;
}
/// Move cursor up the file by a data group.
/// Returns: True if the view moved.
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
/// Move cursor down the file by a data group.
/// Returns: True if the view moved.
bool cursorRight() {
	if (cursorTell >= fileSize)
		return false;
	
	if (cursor.position == readSize - 1) {
		cursorHome;
		return viewDown;
	}
	
	++cursor.position;
	cursor.nibble = 0;
	return false;
}
/// Move cursor up the file by the number of columns.
/// Returns: True if the view moved.
bool cursorUp() {
	if (cursor.position < setting.columns) {
		return viewUp;
	}
	
	cursor.position -= setting.columns;
	return false;
}
/// Move cursor down the file by the bymber of columns.
/// Returns: True if the view moved.
bool cursorDown() {
	/// File size
	long fsize = fileSize;
	/// Normalized file size with last row (remaining) trimmed
	long fsizenorm = fsize - (fsize % setting.columns);
	/// Absolute cursor position
	long acpos = cursorTell;
	
	bool bottom = cursor.position + setting.columns >= readSize; // cursor bottom
	bool finalr = acpos >= fsizenorm; /// final row
	
	version (Trace) trace("bottom=%s final=%s", bottom, finalr);
	
	if (finalr)
		return false;
	
	if (bottom)
		return viewDown;
	
	if (acpos + setting.columns > fsize) {
		uint rem = cast(uint)(fsize % setting.columns);
		cursor.position = cast(uint)(readSize - setting.columns + rem);
		//cursor.position = cast(uint)((fsize + cursor.position) - fsize);
		return false;
	}
	
	cursor.position += setting.columns;
	return false;
}
/// Move cursor by a page up the file.
/// Returns: True if the view moved.
bool cursorPageUp() {
//	int v = readSize / setting.columns;
	return viewPageUp;
}
/// Move cursor by a page down the file.
/// Returns: True if the view moved.
bool cursorPageDown() {
	bool ok = viewPageDown;
	cursorBound;
	return ok;
}
/// Get cursor absolute position within the file.
/// Returns: Cursor absolute position in file.
long cursorTell() {
	return position + cursor.position;
}
/// Make the cursor jump to an absolute position within the file.
/// This is used for search results.
/// Returns: True if the view moved.
void cursorGoto(long m) {
	// Per view chunks, then per y chunks, then x
	//long npos = 
	
}

// !SECTION

long refreshFileSize() {
	final switch (fileMode) with (FileMode) {
	case file:	fileSize = source.osfile.size;	break;
	case mmfile:	fileSize = source.mmfile.length;	break;
	case memory:	fileSize = source.memory.size;	break;
	case stream:	fileSize = source.stream.size;	break;
	}
	
	version (Trace) trace("sz=%u", fileSize);
	
	return fileSize;
}

//TODO: from other types?
//      or implement this via MemoryStream?
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
		return errorSetOs;
	
	FILE *_file = source.stream.getFP;
	
	if (skip) {
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