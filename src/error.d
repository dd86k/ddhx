/// Error handling.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module error;

import types;

__gshared ErrorCode lastError; /// Last error code.
private __gshared string lastMsg;
private __gshared string lastFile;
private __gshared int lastLine;

int set(ErrorCode code, string file = __FILE__, int line = __LINE__) {
	version (Trace)
	{
		trace("code=%s line=%s:%u", code, file, line);
		if (code == ErrorCode.os)
		{
			lastError = code;
			trace("oserror=%s", error.message);
		}
	}
	lastFile = file;
	lastLine = line;
	return (lastError = code);
}

int set(Exception ex) {
	version (unittest)
	{
		import std.stdio : writeln;
		writeln(ex);
	}
	version (Trace)
	{
		debug trace("%s", ex);
		else  trace("%s", ex.msg);
	}
	lastFile = ex.file;
	lastLine = cast(int)ex.line;
	lastMsg  = ex.msg;
	return (lastError = ErrorCode.exception);
}

const(char)[] message() {
	switch (lastError) with (ErrorCode) {
	case exception: return lastMsg;
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
				string errMsg = strerror[0..r].idup;
				LocalFree(strerror);
				return errMsg;
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

int print() {
	return print(lastError, message);
}
int print(A...)(int code, const(char)[] fmt, A args) {
	import std.stdio : stderr;
	stderr.write("error: ");
	stderr.writefln(fmt, args);
	return code;
}

version (Trace) {
	import std.stdio;
	
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
