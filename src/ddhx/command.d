/// Command interpreter.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module ddhx.command;

import std.string : strip;
import std.ascii : isControl, isWhite;
import ddhx;

/// Separate buffer into arguments (akin to argv).
/// Params: buffer = String buffer.
/// Returns: Argv-like array.
string[] arguments(string buffer) {
	// NOTE: Using split/splitter would destroy quoted arguments
	
	//TODO: Escape characters (with '\\')
	
	buffer = strip(buffer);
	
	if (buffer.length == 0) return [];
	
	string[] results;
	const size_t buflen = buffer.length;
	char delim = void;
	
	for (size_t index, start; index < buflen; ++index)
	{
		char c = buffer[index];
		
		if (isControl(c) || isWhite(c))
			continue;
		
		switch (c)
		{
		case '"', '\'':
			delim = c;
			
			for (start = ++index, ++index; index < buflen; ++index)
			{
				c = buffer[index];
				
				if (c == delim)
					break;
			}
			
			results ~= buffer[start..(index++)];
			break;
		default:
			for (start = index, ++index; index < buflen; ++index)
			{
				c = buffer[index];
				
				if (isControl(c) || isWhite(c))
					break;
			}
			
			results ~= buffer[start..index];
		}
	}
	
	return results;
}

/// 
@system unittest {
	assert(arguments("") == []);
	assert(arguments("\n") == []);
	assert(arguments("a") == [ "a" ]);
	assert(arguments("simple") == [ "simple" ]);
	assert(arguments("simple a b c") == [ "simple", "a", "b", "c" ]);
	assert(arguments("simple test\n") == [ "simple", "test" ]);
	assert(arguments("simple test\r\n") == [ "simple", "test" ]);
	assert(arguments("/simple/ /test/") == [ "/simple/", "/test/" ]);
	assert(arguments(`simple 'test extreme'`) == [ "simple", "test extreme" ]);
	assert(arguments(`simple "test extreme"`) == [ "simple", "test extreme" ]);
	assert(arguments(`simple '  hehe  '`) == [ "simple", "  hehe  " ]);
	assert(arguments(`simple "  hehe  "`) == [ "simple", "  hehe  " ]);
	assert(arguments(`a 'b c' d`) == [ "a", "b c", "d" ]);
	assert(arguments(`a "b c" d`) == [ "a", "b c", "d" ]);
	assert(arguments(`/type 'yes string'`) == [ "/type", "yes string" ]);
	assert(arguments(`/type "yes string"`) == [ "/type", "yes string" ]);
}

int command(string line) {
	return command(arguments(line));
}

int command(string[] argv) {
	const size_t argc = argv.length;
	if (argc == 0) return 0;
	
	version (Trace) trace("%(%s %)", argv);
	
	string command = argv[0];
	//TODO: Check length of command string?
	
	int error = void;
	
	void *p = void;
	size_t len = void;
	string data = void;
	string type = void;
	
	switch (command[0]) {
	case '/': // Search
		if (command.length <= 1)
			return errorSet(ErrorCode.missingArgumentType);
		if (argc <= 1)
			return errorSet(ErrorCode.missingArgumentNeedle);
		
		argv ~= argv[1].idup;
		argv[1] = command[1..$];
		goto L_SEARCH;
	case '?': // Search backwards
		if (command.length <= 1)
			return errorSet(ErrorCode.missingArgumentType);
		if (argc <= 1)
			return errorSet(ErrorCode.missingArgumentNeedle);
		
		type = command[1..$];
		data = argv[1];
		
		error = convert(p, len, data, type);
		if (error) return error;
		
		return search(p, len, type, true);
	default: // Regular
		switch (argv[0]) {
		case "g", "goto":
			if (argc <= 1)
				return errorSet(ErrorCode.missingArgumentPosition);
			
			switch (argv[1])
			{
			case "e", "end":
				moveEnd;
				break;
			case "h", "home":
				moveStart;
				break;
			default:
				appSeek(argv[1]);
			}
			break;
		case "s", "search": // Search
			if (argc <= 1)
				return errorSet(ErrorCode.missingArgumentType);
			if (argc <= 2)
				return errorSet(ErrorCode.missingArgumentNeedle);
			
		L_SEARCH:
			type = argv[1];
			data = argv[2];
			
			error = convert(p, len, data, type);
			if (error) return error;
			
			return search(p, len, type, false);
		case "skip":
			ubyte byte_ = void;
			if (argc <= 1) {
				byte_ = io.buffer[0];
			} else {
				if (argv[1] == "zero")
					byte_ = 0;
				else if ((error = convert(byte_, argv[1])) != 0)
					break;
			}
			return skipByte(byte_);
		case "i", "info": msgFileInfo; break;
		case "refresh": appRefresh; break;
		case "q", "quit": appExit; break;
		case "about":
			enum C = "Written by dd86k. " ~ COPYRIGHT;
			msgBottom(C);
			break;
		case "version":
			msgBottom(ABOUT);
			break;
		//
		// Settings
		//
		case "w", "width":
			if (argc <= 1)
				return errorSet(ErrorCode.missingArgumentWidth);
			
			error = settingWidth(argv[1]);
			if (error) return error;
			
			appRefresh;
			break;
		case "o", "offset":
			if (argc <= 1)
				return errorSet(ErrorCode.missingArgumentType);
			
			error = settingOffset(argv[1]);
			if (error) return error;
			
			appRender;
			break;
		case "d", "data":
			if (argc <= 1)
				return errorSet(ErrorCode.missingArgumentType);
			
			error = settingData(argv[1]);
			if (error) return error;
			
			appRender;
			break;
		case "C", "defaultchar":
			if (argc <= 1)
				return errorSet(ErrorCode.missingArgumentCharacter);
			
			error = settingDefaultChar(argv[1]);
			if (error) return error;
			
			appRender;
			break;
		case "cp", "charset":
			if (argc <= 1)
				return errorSet(ErrorCode.missingArgumentCharset);
			
			error = settingCharset(argv[1]);
			if (error) return error;
			
			appRender;
			break;
		case "reset":
			settingResetAll();
			appRender;
			break;
		default: return errorSet(ErrorCode.invalidCommand);
		}
	}
	
	return 0;
}