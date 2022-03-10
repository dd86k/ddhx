/// Custom types and conversion routines.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module ddhx.types;

import std.format : FormatSpec, singleSpec, unformatValue;
import std.encoding : transcode;
import ddhx.error;

// NOTE: template to(T) can turn string values into anything.

//TODO: More types ()
//      - FILETIME
//      - GUID (little-endian)/UUID (big-endian)

//TODO: guessType(string)

/// Convert data to a raw pointer dynamically.
/// Params:
/// 	data = Data pointer receiver.
/// 	len = Data length receiver.
/// 	val = Value to parse.
/// 	type = Type name.
/// Returns: Error code.
int convert(ref void *data, ref size_t len, string val, string type) {
	union TypeData {
		ulong  u64;
		long   i64;
		uint   u32;
		int    i32;
		ushort u16;
		short  i16;
		ubyte  u8;
		byte   i8;
		dstring s32;
		wstring s16;
		string  s8;
	}
	__gshared TypeData types;
	
	version (Trace) trace("data=%s val=%s type=%s", data, val, type);
	
	//TODO: utf16le and all.
	//      bswap all wchars?
	
	int e = void;
	with (types) switch (type)
	{
	case "s32", "dstring":
		e = convert(s32, val);
		if (e) return e;
		data = cast(void*)s32.ptr;
		len  = s32.length * dchar.sizeof;
		break;
	case "s16", "wstring":
		e = convert(s16, val);
		if (e) return e;
		data = cast(void*)s16.ptr;
		len  = s16.length * wchar.sizeof;
		break;
	case "s8", "string":
		data = cast(void*)val.ptr;
		len  = val.length;
		break;
	case "u64", "ulong":
		e = convert(u64, val);
		if (e) return e;
		data = &u64;
		len  = u64.sizeof;
		break;
	case "i64", "long":
		e = convert(i64, val);
		if (e) return e;
		data = &i64;
		len  = i64.sizeof;
		break;
	case "u32", "uint":
		e = convert(u32, val);
		if (e) return e;
		data = &u32;
		len  = u32.sizeof;
		break;
	case "i32", "int":
		e = convert(i32, val);
		if (e) return e;
		data = &i32;
		len  = i32.sizeof;
		break;
	case "u16", "ushort":
		e = convert(u16, val);
		if (e) return e;
		data = &u16;
		len  = u16.sizeof;
		break;
	case "i16", "short":
		e = convert(i16, val);
		if (e) return e;
		data = &i16;
		len  = i16.sizeof;
		break;
	case "u8", "ubyte":
		e = convert(u8, val);
		if (e) return e;
		data = &u8;
		len  = u8.sizeof;
		break;
	case "i8", "byte":
		e = convert(i8, val);
		if (e) return e;
		data = &i8;
		len  = i8.sizeof;
		break;
	default:
		return errorSet(ErrorCode.invalidType);
	}
	
	return ErrorCode.success;
}

/// Convert data depending on the type supplied at compile-time.
/// Params:
/// 	v = Data reference.
/// 	val = String value.
/// Returns: Error code.
int convert(T)(ref T v, string val)
{
	import std.conv : ConvException;
	try
	{
		//TODO: ubyte[] input
		static if (is(T == wstring) || is(T == dstring))
		{
			transcode(val, v);
		}
		else // Scalar
		{
			const size_t len = val.length;
			FormatSpec!char fmt = void;
			if (len >= 3 && val[0..2] == "0x")
			{
				fmt = singleSpec("%x");
				val = val[2..$];
			}
			else if (len >= 2 && val[0] == '0')
			{
				fmt = singleSpec("%o");
				val = val[1..$];
			}
			else
			{
				fmt = singleSpec("%d");
			}
			v = unformatValue!T(val, fmt);
		}
	}
	catch (Exception ex)
	{
		return errorSet(ex);
	}
	
	return ErrorCode.success;
}

//TODO: toRaw template
//      int toRaw(T)(ref void *ptr, ref size_t size, ref T v, string val)
//TODO: fromRaw template
//      int fromRaw(T)(ref T ptr, void *ptr, size_t left)

/// 
@system unittest
{
	int i;
	assert(convert(i, "256") == ErrorCode.success);
	assert(i == 256);
	assert(convert(i, "0100") == ErrorCode.success);
	assert(i == 64);
	assert(convert(i, "0x100") == ErrorCode.success);
	assert(i == 0x100);
	ulong l;
	assert(convert(l, "1000000000000000") == ErrorCode.success);
	assert(l == 1000000000000000);
	assert(convert(l, "01000000000000000") == ErrorCode.success);
	assert(l == 35184372088832);
	assert(convert(l, "0x1000000000000000") == ErrorCode.success);
	assert(l == 0x1000000000000000);
	wstring w;
	assert(convert(w, "hello") == ErrorCode.success);
	assert(w == "hello"w);
}
