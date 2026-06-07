/// Inspector panel: renders different type interpretations of bytes at cursor.
///
/// The inspector lives below the address/data/text rows, terminal-wide,
/// separated by a horizontal line. It is read-only and does not participate
/// in cursor focus (see PanelType in view.d).
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.inspector;

import core.stdc.string : memcpy;
import std.format : sformat;
import std.math : isNaN, isInfinity;
import std.system : Endian;

/// Inspector row type. Inspector-local: keeps formatting.d clean of float
/// concerns until the data column itself needs them.
enum InspectorType
{
    u8,
    u16,
    u32,
    u64,
    i8,
    i16,
    i32,
    i64,
    f32,
    f64,
}

/// One row in the inspector panel.
struct InspectorRow
{
    string label;       /// Short label shown to the user.
    InspectorType type; /// Underlying interpretation.
    int width;          /// Display width budget in characters.
}

/// Rows shown by the inspector, in display order.
immutable static InspectorRow[] inspector_rows = [
    { "u8 ",  InspectorType.u8,   3 },
    { "i8 ",  InspectorType.i8,   4 },
    { "u16",  InspectorType.u16,  5 },
    { "i16",  InspectorType.i16,  6 },
    { "u32",  InspectorType.u32, 10 },
    { "i32",  InspectorType.i32, 11 },
    { "u64",  InspectorType.u64, 20 },
    { "i64",  InspectorType.i64, 20 },
    { "f32",  InspectorType.f32, 12 },
    { "f64",  InspectorType.f64, 12 },
];

/// Bytes required for a given InspectorType.
int byteSize(InspectorType type)
{
    final switch (type) {
    case InspectorType.u8, InspectorType.i8:   return 1;
    case InspectorType.u16, InspectorType.i16: return 2;
    case InspectorType.u32, InspectorType.i32: return 4;
    case InspectorType.u64, InspectorType.i64: return 8;
    case InspectorType.f32: return 4;
    case InspectorType.f64: return 8;
    }
}

/// Format a value at the cursor for the given inspector type.
///
/// Returns "N/A" when `bytes` is shorter than required, "Invalid" for
/// non-finite floats (NaN/Inf). For multi-byte types, `endian` selects
/// little or big endian; u8/i8 ignore it.
///
/// Params:
///     buf    = Destination buffer (must hold at least row.width chars).
///     type   = Type to interpret.
///     bytes  = Source bytes from cursor onwards (may be shorter than needed).
///     endian = Endian for multi-byte ints/floats.
/// Returns: Slice into `buf` holding the formatted value.
string formatInspector(char[] buf, InspectorType type, const(ubyte)[] bytes, Endian endian)
{
    int need = byteSize(type);
    if (bytes.length < need)
        return "N/A";

    ubyte[8] tmp = void;
    tmp[0..need] = bytes[0..need];
    if (endian == Endian.bigEndian && need > 1)
    {
        // Reverse in place for native interpretation.
        for (int i; i < need / 2; ++i)
        {
            ubyte t = tmp[i];
            tmp[i] = tmp[need - 1 - i];
            tmp[need - 1 - i] = t;
        }
    }

    final switch (type) {
    case InspectorType.u8:
        return cast(string)sformat(buf, "%u", tmp[0]);
    case InspectorType.i8:
        return cast(string)sformat(buf, "%d", cast(byte)tmp[0]);
    case InspectorType.u16:
        ushort u16 = void;
        memcpy(&u16, tmp.ptr, ushort.sizeof);
        return cast(string)sformat(buf, "%u", u16);
    case InspectorType.i16:
        short i16 = void;
        memcpy(&i16, tmp.ptr, short.sizeof);
        return cast(string)sformat(buf, "%d", i16);
    case InspectorType.u32:
        uint u32 = void;
        memcpy(&u32, tmp.ptr, uint.sizeof);
        return cast(string)sformat(buf, "%u", u32);
    case InspectorType.i32:
        int i32 = void;
        memcpy(&i32, tmp.ptr, int.sizeof);
        return cast(string)sformat(buf, "%d", i32);
    case InspectorType.u64:
        ulong u64 = void;
        memcpy(&u64, tmp.ptr, ulong.sizeof);
        return cast(string)sformat(buf, "%u", u64);
    case InspectorType.i64:
        long i64 = void;
        memcpy(&i64, tmp.ptr, long.sizeof);
        return cast(string)sformat(buf, "%d", i64);
    case InspectorType.f32:
        float f32 = void;
        memcpy(&f32, tmp.ptr, float.sizeof);
        if (isNaN(f32)) return "NaN";
        if (isInfinity(f32)) return "Inf";
        return cast(string)sformat(buf, "%.4g", f32);
    case InspectorType.f64:
        double f64 = void;
        memcpy(&f64, tmp.ptr, double.sizeof);
        if (isNaN(f64)) return "NaN";
        if (isInfinity(f64)) return "Inf";
        return cast(string)sformat(buf, "%.6g", f64);
    }
}
unittest
{
    char[32] buf = void;

    // u8 always available with 1 byte
    ubyte[] b1 = [0x2a];
    assert(formatInspector(buf, InspectorType.u8, b1, Endian.littleEndian) == "42");
    assert(formatInspector(buf, InspectorType.i8, [cast(ubyte)0xff], Endian.littleEndian) == "-1");

    // u16 LE vs BE
    ubyte[] b2 = [0x34, 0x12];
    assert(formatInspector(buf, InspectorType.u16, b2, Endian.littleEndian) == "4660");
    assert(formatInspector(buf, InspectorType.u16, b2, Endian.bigEndian)    == "13330");

    // Insufficient bytes -> N/A
    assert(formatInspector(buf, InspectorType.u32, b2, Endian.littleEndian) == "N/A");
    assert(formatInspector(buf, InspectorType.f64, b2, Endian.littleEndian) == "N/A");

    // f32 round-trip: 1.0f little-endian is 00 00 80 3f
    ubyte[] f1 = [0x00, 0x00, 0x80, 0x3f];
    string s = formatInspector(buf, InspectorType.f32, f1, Endian.littleEndian);
    assert(s == "1" || s == "1.000", s);

    // f32 NaN -> NaN
    ubyte[] fnan = [0x00, 0x00, 0xc0, 0x7f];
    assert(formatInspector(buf, InspectorType.f32, fnan, Endian.littleEndian) == "NaN");
}

/// Total rows the inspector consumes (one per type + one separator line).
int inspectorHeight()
{
    return cast(int)inspector_rows.length + 1;
}
