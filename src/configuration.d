/// Configuration management.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module configuration;

// Module is named configuration to avoid confusion with std.getopt.config and
// "rc" local variable names.

import transcoder : CharacterSet, selectCharacterSet;
import editor : WritingMode, AddressType, DataType;

/// Editor configuration
struct RC
{
    /// Address formatting (hex, dec, oct).
    AddressType address_type = AddressType.hex;
    
    /// Data formatting (x8, etc.)
    DataType data_type  = DataType.x8;
    
    /// Character set used for transcoding.
    CharacterSet charset = CharacterSet.ascii;
    
    /// Writing mode.
    ///
    /// Opening document as read-only automatically sets this as readonly too.
    // TODO: Move to ddhx.Session.
    WritingMode writemode = WritingMode.overwrite;
    
    /// Number of columns
    int columns = 16;
    
    /// Number of characters to fill when printing row address.
    int address_spacing = 11;
    
    /// Maximum allowed size (length).
    /// File: TODO
    /// Stream: (Memory buffer) TODO
    long maxsize;
    
    /// Minimum seek position.
    long seek;
}

void loadRC(ref RC rc, string path)
{
    throw new Exception("TODO");
}

// Used when configurating runtime config and parsing command values.
void configRC(ref RC rc, string field, string value)
{
    import std.conv : text, to;
    
    switch (field) {
    case "columns":
        int cols = to!int(value);
        if (cols <= 0)
            throw new Exception("Cannot have negative or zero columns");
        rc.columns = cols;
        break;
    case "address-type":
        switch (value) {
        case "hex": rc.address_type = AddressType.hex; break;
        case "dec": rc.address_type = AddressType.dec; break;
        case "oct": rc.address_type = AddressType.oct; break;
        default:
            throw new Exception(text("Unknown address type: ", value));
        }
        break;
    case "address-spacing":
        int aspc = to!int(value);
        if (aspc <= 0)
            throw new Exception("Cannot have negative or zero address spacing");
        rc.address_spacing = aspc;
        break;
    case "charset":
        rc.charset = selectCharacterSet(value);
        break;
    default:
        throw new Exception(text("Unknown field: ", field));
    }
}
unittest
{
    RC rc;
    
    configRC(rc, "columns", "10");
    assert(rc.columns == 10);
    
    configRC(rc, "address-type", "dec");
    assert(rc.address_type == AddressType.dec);
    
    configRC(rc, "address-spacing", "5");
    assert(rc.address_spacing == 5);
    
    configRC(rc, "charset", "ebcdic");
    assert(rc.charset == CharacterSet.ebcdic);
}
