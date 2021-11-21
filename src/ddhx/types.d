/**
 * Type awareness.
 */
/+module ddhx.types;

import core.builtins;
import ddhx.error;

enum DataType : ubyte {
	ubyte_,
	byte_,
	ushort_,
	short_,
	uint_,
	int_,
	ulong_,
	long_,
	float_,
	double_,
	real_,	// extended to 80-bit for convenience
	//TODO: Array
}

private immutable string[2][11] typeNames = [
	[ "ubyte",	"u8"  ],
	[ "byte",	"s8"  ],
	[ "ushort",	"u16" ],
	[ "short",	"s16" ],
	[ "uint",	"u32" ],
	[ "int",	"s32" ],
	[ "ulong",	"u64" ],
	[ "long",	"s64" ],
	[ "float",	"f32" ],
	[ "double",	"f64" ],
	[ "real",	"f80" ],
];

struct Data {
	size_t len;
	void  *data;
	DataType type;
	
	string typeString(bool simplified = false) {
		return typeNames[type][simplified];
	}
	
	// auto
	/*int Parse(string data) {
	}*/
	
	int Parse(string type, string data) {
		DataType t = void;
		
		switch (type) with (DataType) {
		case "u8", "ubyte", "byte":
			t = byte_;
			break;
		case "u16", "ushort", "short":
			t = short_;
			break;
		case "u32", "uint", "int":
			t = int_;
			break;
		case "u64", "ulong", "long":
			t = long_;
			break;
		case "f32", "float":
			t = byte_;
			break;
		case "f64", "double":
			t = byte_;
			break;
		case "f80", "real":
			t = byte_;
			break;
		default: return ddhxError(DdhxError.invalidType);
		}
		
		return Parse(t, data);
	}
	
	int Parse(DataType type, string data) {
		if (data == null || data.length == 0) {
			
		}
		
		switch (type) with (DataType) {
		case ubyte_:
		
			break;
		case byte_:
		
			break;
		case ushort_:
		
			break;
		case short_:
		
			break;
		case uint_:
		
			break;
		case int_:
		
			break;
		case ulong_:
		
			break;
		case long_:
		
			break;
		case float_:
		
			break;
		case double_:
		
			break;
		case real_:
		
			break;
		default: return ddhxError(DdhxError.invalidParameter);
		}
		
		return 0;
	}
}

/// 
@safe unittest {
	
}
+/