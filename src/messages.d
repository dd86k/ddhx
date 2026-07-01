/// User-facing status and error messages.
///
/// Centralized here as `static immutable` rather than `enum` so the string
/// data exists once instead of being duplicated at every import site.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module messages;

// General

static immutable string MSG_CANCELED = "Canceled";
static immutable string MSG_OUT_OF_MEMORY = "error: Out of memory";
static immutable string MSG_ALLOCATION_FAILED = "Allocation failed";
static immutable string MSG_UNKNOWN_COMMAND = "Unknown command: ";
static immutable string MSG_COMMAND_NOT_FOUND = "command not found: ";
static immutable string MSG_MISSING_ACTION = "Missing action";

// Ranges and selections

static immutable string MSG_EMPTY_RANGE = "Empty range";
static immutable string MSG_RANGE_LENGTH_ZERO = "Length cannot be zero";
static immutable string MSG_RANGE_MISSING_START = "Missing start in range";
static immutable string MSG_RANGE_MISSING_END = "Missing end in range";
static immutable string MSG_RANGE_MISSING_LENGTH = "Missing length in range";
static immutable string MSG_RANGE_START_CANNOT_BE_EOF = "Range start cannot be EOF";
static immutable string MSG_RANGE_START_OUT_OF_RANGE = "range: Start out of range";
static immutable string MSG_RANGE_END_OUT_OF_RANGE = "range: End out of range";
static immutable string MSG_RANGE_START_AFTER_END = "range: Cannot start after end";
static immutable string MSG_RANGE_LENGTH_MUST_BE_POSITIVE = "Range length must be positive";
static immutable string MSG_SELECTION_TOO_BIG = "Selection too big";
static immutable string MSG_SELECTION_TOO_LARGE = "Selection too large";
static immutable string MSG_NEED_SELECTION = "Need selection";
static immutable string MSG_INSUFFICIENT_SPACE_NEED = "Insufficient space, need ";
static immutable string MSG_NOT_ENOUGH_SPACE_FOR_PROMPT = "Not enough space for prompt";

// Editing / read-only

static immutable string MSG_CANT_EDIT_READONLY = "Can't edit in read-only";
static immutable string MSG_CANNOT_EDIT_READONLY = "Cannot edit, read-only";
static immutable string MSG_CANNOT_SAVE_READONLY = "Cannot save, read-only";
static immutable string MSG_DOCUMENT_READONLY = "Document is read-only";
static immutable string MSG_UNKNOWN_WRITEMODE = "Unknown writemode:";

// Globbing

static immutable string MSG_CANT_REPLACE_GLOBBING = "Can't replace with globbing";
static immutable string MSG_CANT_INSERT_GLOBBING = "Can't insert with globbing";

// Clipboard

static immutable string MSG_CLIPBOARD_CANNOT_CONTAIN_SELECTION = "Clipboard cannot contain selection";
static immutable string MSG_CLIPBOARD_EMPTY = "Clipboard is empty";

// Bookmarks

static immutable string MSG_BOOKMARK_LENGTH_MUST_BE_POSITIVE = "Bookmark length must be positive";
static immutable string MSG_NO_BOOKMARKS = "No bookmarks";
static immutable string MSG_NO_BOOKMARKS_TO_SAVE = "No bookmarks to save";
static immutable string MSG_BOOKMARK_LINE_PREFIX = "Bookmark: line ";

// Find / replace

static immutable string MSG_NEED_SEARCH = "Need search";
static immutable string MSG_NEED_NEEDLE_AND_REPLACEMENT = "Need needle and replacement, separated by --";
static immutable string MSG_MISSING_NEEDLE = "Missing needle";
static immutable string MSG_MISSING_REPLACEMENT = "Missing replacement";
static immutable string MSG_EMPTY_NEEDLE = "Empty needle";
static immutable string MSG_NO_PREVIOUS_FIND_REPLACE = "No previous find-replace to repeat";

// Numeric input

static immutable string MSG_INCOMPLETE_NUMBER = "Incomplete number";
static immutable string MSG_NEED_PERCENTAGE_NUMBER = "Need percentage number";
static immutable string MSG_PERCENTAGE_OVER_100 = "Percentage cannot be over 100";

// Colors / schemes

static immutable string MSG_MISSING_SCHEME = "Missing scheme";
static immutable string MSG_MISSING_COLOR = "Missing color";
static immutable string MSG_COLOR_EMPTY = "Color cannot be empty";
static immutable string MSG_UNKNOWN_SCHEME = "Unknown scheme: ";
static immutable string MSG_UNKNOWN_COLOR = "Unknown color: ";

// Patterns

static immutable string MSG_MISSING_PATTERN_DATA = "Missing data for pattern";
static immutable string MSG_UNKNOWN_PATTERN_PREFIX = "Unknown pattern prefix: ";

// Charsets / transcoding

static immutable string MSG_INVALID_CHARSET = "Invalid charset: ";

// Configuration

static immutable string MSG_ON_OR_OFF_ACCEPTED = `Only "on" or "off" accepted`;
static immutable string MSG_MISSING_VALUE = "Missing value";
static immutable string MSG_MISSING_COMMAND = "Missing command";
static immutable string MSG_UNKNOWN_FIELD = "Unknown field: ";
static immutable string MSG_NEGATIVE_COLUMNS = "Cannot have negative columns";
static immutable string MSG_UNKNOWN_ADDRESS_TYPE = "Unknown address type: ";
static immutable string MSG_ADDRESS_SPACING_TOO_LOW = "Address spacing too low (3 or more needed)";
static immutable string MSG_UNKNOWN_ENDIAN = "Unknown endian: ";

// Editor backends

static immutable string MSG_BACKEND_DOES_NOT_EXIST = "Backend does not exist: ";
