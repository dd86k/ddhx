module error;

enum DdhxError {
	none,
	unknown,
	exception,
	fileEmpty,
	invalidParameter,
	invalidNumber,
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
	case invalidParameter: return "Parameter is invalid.";
	case none: return "No errors occured.";
	default: return "Unknown error occured.";
	}
}

int ddhxPrintError(string func = __FUNCTION__) {
	import std.stdio : stderr, writefln;
	
	return 0;
}