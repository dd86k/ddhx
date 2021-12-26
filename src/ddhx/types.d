/**
 * Type awareness.
 */
module ddhx.types;

import ddhx.error;

// NOTE: USE CASES
//       - Parse data from menu
//       - Search data in memory
//       - Parse data from file (sdl?)

enum DataMode : ubyte {
	scalar, array
}
enum DataType : ubyte {
	u8, u16, u32, u64,
	i8, i16, i32, i64,
}
enum DATATYPE_LENGTH = DataType.max;

struct DataDefinition {
	DataType type;
	string name;
	size_t length;
}

private
immutable DataDefinition[] definitions = [
	{ DataType.u8,	"u8",	1 },
	{ DataType.u16,	"u16",	2 },
	{ DataType.u32,	"u32",	4 },
	{ DataType.u64,	"u64",	8 },
	{ DataType.i8,	"i8",	1 },
	{ DataType.i16,	"i16",	2 },
	{ DataType.i32,	"i32",	4 },
	{ DataType.i64,	"i64",	8 },
];

struct Data {
	void  *data;
	alias data this;
	size_t len;
	DataType type;
	string name;
	
	string typeName() {
		return "";
	}
	
	void update(void *pos) {
		
		
	}
	
	int parse(string data) {
		
		return 0;
	}
	
	int parse(wstring data) {
		
		return 0;
	}
	
	int parse(dstring data) {
		
		return 0;
	}
	
	int parse(DataType type)(string data) {
		
		return 0;
	}
	
	int parse(string type, string data) {
		DataType t = void;
		
		
		
		return parse(t, data);
	}
	
	int parse(DataType type, string data) {
		if (data == null || data.length == 0) {
			
		}
		
		return 0;
	}
}

/// 
@safe unittest {
	
}
