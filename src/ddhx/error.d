module ddhx.error;

enum DdhxError {
	none,
	unknown,
	exception,
	fileEmpty,
	inputEmpty,
	invalidParameter,
	invalidNumber,
	invalidType,
	notFound,
	overflow,
	unparsable,
	noLastItem,
	eof,
}

private __gshared DdhxError errorCode;
private __gshared string errorMsg;
private __gshared string errorFile;
private __gshared int errorLine;

int ddhxError(DdhxError code, string file = __FILE__, int line = __LINE__) {
	errorFile = file;
	errorLine = line;
	return (errorCode = code);
}

int ddhxError(Exception ex) {
	errorFile = ex.file;
	errorLine = cast(int)ex.line;
	errorMsg  = ex.msg;
	return (errorCode = DdhxError.exception);
}

string ddhxErrorMsg() {
	switch (errorCode) with (DdhxError) {
	case exception: return errorMsg;
	case fileEmpty: return "File is empty.";
	case inputEmpty: return "Input is empty.";
	case invalidParameter: return "Parameter is invalid.";
	case invalidType: return "Invalid type.";
	case eof: return "Unexpected end of file (EOF).";
	case notFound: return "Input not found.";
	case overflow: return "Integer overflow.";
	case unparsable: return "Integer could not be parsed.";
	case noLastItem: return "No previous search items saved.";
	case none: return "No errors occured.";
	default: return "Unknown error occured.";
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
