/// Error handling.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module error;
 
import std.stdio;
import ddhx;

/// Error codes
enum ErrorCode {
	success,
	generic,
	
	negativeValue = 5,
	fileEmpty,
	inputEmpty,
	invalidCommand,
	invalidParameter,
	invalidNumber,
	invalidType,
	invalidCharset,
	notFound,
	overflow,
	unparsable,
	noLastItem,
	eof,
	unimplemented,
	insufficientSpace,
	
	missingArgumentPosition = 40,
	missingArgumentType,
	missingArgumentNeedle,
	missingArgumentWidth,
	missingArgumentCharacter,
	missingArgumentCharset,
	
	unknown,
	exception,
	os,
}

__gshared ErrorCode ecode; /// Last error code.

private struct last_t {
	const(char)[] message;
	const(char)[] file;
	int line;
}
private __gshared last_t last;

int errorSet(ErrorCode code, string file = __FILE__, int line = __LINE__) {
	version (Trace) {
		trace("code=%s line=%s:%u", code, file, line);
		if (code == ErrorCode.os) {
			ecode = code;
			trace("oserror=%s", errorMessage);
		}
	}
	last.file = file;
	last.line = line;
	return (ecode = code);
}

int errorSet(Exception ex) {
	version (unittest) {
		import std.stdio : writeln;
		writeln(ex);
	}
	version (Trace) {
		debug trace("%s", ex);
		else  trace("%s", ex.msg);
	}
	last.file = ex.file;
	last.line = cast(int)ex.line;
	last.message = ex.msg;
	return (ecode = ErrorCode.exception);
}

const(char)[] errorMessage() {
	switch (ecode) with (ErrorCode) {
	case exception: return last.message;
	case os:
		import std.string : fromStringz;
		
		version (Windows) {
			import core.sys.windows.winbase : GetLastError, LocalFree,
				FormatMessageA,
				FORMAT_MESSAGE_ALLOCATE_BUFFER, FORMAT_MESSAGE_FROM_SYSTEM,
				FORMAT_MESSAGE_IGNORE_INSERTS;
			import core.sys.windows.winnt :
				MAKELANGID, LANG_NEUTRAL, SUBLANG_DEFAULT;
			
			enum LANG = MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT);
			
			uint errcode = GetLastError();
			char *strerror;
			
			version (Trace) trace("code=%x", errcode);
			
			uint r = FormatMessageA(
				FORMAT_MESSAGE_ALLOCATE_BUFFER |
				FORMAT_MESSAGE_FROM_SYSTEM |
				FORMAT_MESSAGE_IGNORE_INSERTS,
				null,
				errcode,
				LANG,
				cast(char*)&strerror,
				0,
				null);
			
			version (Trace) trace("FormatMessageA=%u errcode=%x", r, errcode);
			
			if (strerror)
			{
				if (strerror[r - 1] == '\n') --r;
				if (strerror[r - 1] == '\r') --r;
				string msg = strerror[0..r].idup;
				LocalFree(strerror);
				return msg;
			}
			
			goto default;
		} else {
			import core.stdc.errno : errno;
			import core.stdc.string : strerror;
			
			int errcode = errno;
			
			version (Trace) trace("code=%d", errcode);
			
			return strerror(errcode).fromStringz;
		}
	case fileEmpty: return "File is empty.";
	case inputEmpty: return "Input is empty.";
	case invalidCommand: return "Command not found.";
	case invalidParameter: return "Parameter is invalid.";
	case invalidType: return "Invalid type.";
	case eof: return "Unexpected end of file (EOF).";
	case notFound: return "Data not found.";
	case overflow: return "Integer overflow.";
	case unparsable: return "Integer could not be parsed.";
	case noLastItem: return "No previous search items saved.";
	case insufficientSpace: return "Too little space left to search.";
	
	case missingArgumentPosition: return "Missing argument (position).";
	case missingArgumentType: return "Missing argument (type).";
	case missingArgumentNeedle: return "Missing argument (needle).";
	case missingArgumentWidth: return "Missing argument (width).";
	case missingArgumentCharacter: return "Missing argument (character).";
	case missingArgumentCharset: return "Missing argument (charset).";
	
	case success: return "No errors occured.";
	default: return "Internal error occured.";
	}
}

int errorWrite() {
	return errorWrite(ecode, last.message);
}
int errorWrite(A...)(int code, const(char)[] fmt, A args) {
	stderr.write("error: ");
	stderr.writefln(fmt, args);
	return code;
}

version (Trace) {
	private __gshared File log;
	
	void traceInit() {
		log.open("ddhx.log", "w");
	}
	void trace(string func = __FUNCTION__, int line = __LINE__, A...)(string fmt, A args) {
		log.writef("TRACE:%s:%u: ", func, line);
		log.writefln(fmt, args);
		log.flush;
	}
}
