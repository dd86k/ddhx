/// Error handling.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module ddhx.error;

enum ErrorCode {
	success,
	unknown,
	negativeValue,
	exception,
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
}

private __gshared ErrorCode lastCode;
private __gshared string lastMsg;
private __gshared string lastFile;
private __gshared int lastLine;

int errorSet(ErrorCode code, string file = __FILE__, int line = __LINE__) {
	lastFile = file;
	lastLine = line;
	return (lastCode = code);
}

int errorSet(Exception ex) {
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
	return (lastCode = ErrorCode.exception);
}

string errorMsg() {
	switch (lastCode) with (ErrorCode) {
	case exception: return errorMsg;
	case fileEmpty: return "File is empty.";
	case inputEmpty: return "Input is empty.";
	case invalidCommand: return "Command not found.";
	case invalidParameter: return "Parameter is invalid.";
	case invalidType: return "Invalid type.";
	case eof: return "Unexpected end of file (EOF).";
	case notFound: return "Input not found.";
	case overflow: return "Integer overflow.";
	case unparsable: return "Integer could not be parsed.";
	case noLastItem: return "No previous search items saved.";
	case success: return "No errors occured.";
	default: return "Internal error occured.";
	}
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
