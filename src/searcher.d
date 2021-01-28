/**
 * Search module.
 * 
 * As crappy as it may be written, this is actually "sort of" of an extension
 * to the menu module, being an extension of the ddhx module.
 */
module searcher;

import std.stdio;
import std.encoding : transcode;
import core.bitop; // NOTE: byteswap was only in 2.092
import ddhx;
import utils;

private ushort bswap16(ushort v) pure {
	return cast(ushort)((v << 8) | (v >> 8));
}
	
align(1) private struct search_settings_t {
	align(1) struct data_t {
		align(1) union {
			void *p;	/// Data void pointer
			ubyte *pu8;	/// Data 8-bit pointer
			ushort *pu16;	/// Data 16-bit pointer
			uint *pu32;	/// Data 32-bit pointer
			ulong *pu64;	/// Data 64-bit pointer
		}
		void* _ptr;
		size_t len;
	} data_t data;
	align(1) struct sample_t {
		align(1) union {
			ubyte u8;	/// 8-bit sample data
			ushort u16;	/// 16-bit sample data
			uint u32;	/// 32-bit sample data
			ulong u64;	/// 64-bit sample data
		}
		uint size;	/// Sample size
		bool same;	/// Is sample size the same as input data?
	} sample_t sample;
}

/**
 * Search an UTF-8/ASCII string
 * Params: v = utf-8 string
 */
void search_utf8(immutable(char)[] v) {
	search_internal(cast(void*)v.ptr, v.length, "utf-8 string");
}

/**
 * Search an UTF-16 string
 * Params:
 *   v = utf-16 string
 */
void search_utf16(immutable(char)[] v) {
	wstring ws;
	transcode(v, ws);
	search_internal(cast(void*)ws.ptr, ws.length, "utf-16 string");
}

/**
 * Search an UTF-32 string
 * Params:
 *   v = utf-32 string
 */
void search_utf32(const char[] v) {
	dstring ds;
	transcode(v, ds);
	search_internal(cast(void*)ds.ptr, ds.length, "utf-32 string");
}

/**
 * Search a byte
 * Params: v = ubyte
 */
void search_u8(string v) {
	long l = void;
	if (unformat(v, l) == false) {
		ddhx_msglow("Could not parse number");
		return;
	}
	if (l < byte.min || l > ubyte.max) {
		ddhx_msglow("Integer too large for a byte");
		return;
	}
	byte data = cast(byte)l;
	search_internal(&data, 1, "u8");
}

/**
 * Search for a 16-bit value.
 * Params:
 *   input = Input
 *   invert = Invert endianness
 */
void search_u16(string input, bool invert = false) {
	long l = void;
	if (unformat(input, l) == false) {
		ddhx_msglow("Could not parse number");
		return;
	}
	if (l < short.min || l > ushort.max) {
		ddhx_msglow("Integer too large for a u16 value");
		return;
	}
	short data = cast(short)l;
	if (invert)
		data = bswap16(data);
	search_internal(&data, 2, "u16");
}

/**
 * Search for a 32-bit value.
 * Params:
 *   input = Input
 *   invert = Invert endianness
 */
void search_u32(string input, bool invert = false) {
	long l = void;
	if (unformat(input, l) == false) {
		ddhx_msglow("Could not parse number");
		return;
	}
	if (l < int.min || l > uint.max) {
		ddhx_msglow("Integer too large for a u16 value");
		return;
	}
	int data = cast(int)l;
	if (invert)
		data = bswap(data);
	search_internal(&data, 4, "u32");
}

/**
 * Search for a 64-bit value.
 * Params:
 *   input = Input
 *   invert = Invert endianness
 */
void search_u64(string input, bool invert = false) {
	long l = void;
	if (unformat(input, l) == false) {
		ddhx_msglow("Could not parse number");
		return;
	}
	if (invert)
		l = bswap(l);
	search_internal(&l, 8, "u64");
}

/**
 * Search using raw array of byte data.
 * Params: v = Byte array
 */
void search_array(ubyte[] v) {
	search_internal(v.ptr, v.length, "u8 array");
}

private void search_sample(ref search_settings_t s, void *data, ulong len) {
	//TODO: Use D_SIMD
	
	s.data.p = data;
	s.data.len = len;
	
	version (D_LP64)
	if (len >= 8) {	// ulong.sizeof
		s.sample.size = 8;
		s.sample.same = len == 8;
		s.sample.u64  = *s.data.pu64;
		return;
	}
	if (len >= 4) {	// uint.sizeof
		s.sample.size = 4;
		s.sample.same = len == 4;
		s.sample.u32  = *s.data.pu32;
	} else if (len >= 2) {	// ushort.sizeof
		s.sample.size = 2;
		s.sample.same = len == 2;
		s.sample.u16  = *s.data.pu16;
	} else {
		s.sample.size = 1;
		s.sample.same = len == 1;
		s.sample.u8   = *s.data.pu8;
	}
}

private void search_internal(void *data, ulong len, string type) {
	import core.stdc.string : memcmp;
	
	if (len == 0) {
		ddhx_msglow(" Empty input, cancelled");
		return;
	}
	
	search_settings_t s = void;
	search_sample(s, data, len);
	
	ddhx_msglow(" Searching %s...", type);
	
	//TODO: Use D_SIMD
	
	long i = g_fpos + 1;
	ubyte[] a = cast(ubyte[])g_fhandle[g_fpos + 1..$];
	ubyte * b = a.ptr;
	const ulong alen = a.length;
	ulong o;	/// File offset
	
	for (; o < alen; ++o, ++i) {
		if (a[o] == s.sample.u8) {
			if (i + s.data.len >= g_fsize)
				goto L_BOUND;
			if (memcmp(b + o, s.data.p, s.data.len) == 0) {
				ddhx_seek(i);
				return;
			}
		}
	}

L_BOUND:
	ddhx_msglow(" Not found (%s)", type);
}
