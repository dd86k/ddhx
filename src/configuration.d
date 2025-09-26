/// Configuration management.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module configuration;

// Module is named configuration to avoid confusion with std.getopt.config and
// "rc" local variable names.

import transcoder : CharacterSet, selectCharacterSet;
import doceditor : WritingMode, AddressType, DataType;
import std.conv : text, to;

// TODO: autosize (with --autosize)
//       When set, automatically resize width (columns).
//       Practically, at startup and when terminal is resized.

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
    WritingMode writemode = WritingMode.overwrite;
    
    /// Number of columns
    int columns = 16;
    
    /// Number of characters to fill when printing row address.
    int address_spacing = 11;
}

/// Return true/false given sting input.
///
/// Values like "on"/"off" are accepted.
///
/// More values could be accepted in the future, such as "true"/"false",
/// "yes"/"no", "enabled"/"disabled", but for the sake of consistency
/// and simplicity, it's better to just stick to one pair.
/// Params: input = String value input.
/// Returns: true for "on", false for "off"
/// Throws: Exception if neither.
private
bool boolean(string input)
{
    switch (input) {
    case "on":  return true;
    case "off": return false;
    default:    throw new Exception(`Only "on" or "off" accepted`);
    }
}
unittest
{
    assert(boolean("on")  == true);
    assert(boolean("off") == false);
    try
    {
        cast(void)boolean(null);
        assert(false);
    }
    catch (Exception) {}
}

/// Load a configuration from a target file path.
/// Params:
///     rc = RC instance reference.
///     path = File path.
void loadRC(ref RC rc, string path) // @suppress(dscanner.style.doc_missing_throw)
{
    throw new Exception("TODO");
}

/// Describes a configuration.
struct Config
{
    string name;        /// Short name
    string description; /// Configuration description
    string availvalues; /// Available values or expected type
    string defaultval;  /// Default value
    
    void function(ref RC, string) impl; /// Implementation function
}
/// Available configurations.
immutable Config[] configurations = [
    {
        "columns", "Number of elements to show on a row",
        "Number", "16",
        &configuration_columns
    },
    {
        "addressing", "Addressing offset format displayed",
        `"hexadecimal", "octal", "decimal"`, `"hex"`,
        &configuration_addressing
    },
    {
        "address-spacing", "Left row address spacing in characters",
        "Number", "11",
        &configuration_address_spacing
    },
    {
        "charset", "Character set",
        `"ascii", "cp437", "mac", "ebcdic"`, `"ascii"`,
        &configuration_charset
    },
];
unittest
{
    foreach (config; configurations)
    {
        // Must have name
        assert(config.name, "No name");
        // Must have description
        assert(config.description, "No description: "~config.name);
        // Must have values
        assert(config.availvalues, "No values: "~config.name);
        // Must have default
        assert(config.defaultval, "No default: "~config.name);
        // Must have implementation
        assert(config.impl, "No impl: "~config.name);
    }
}

// Used when configurating runtime config and parsing command values.
/// Set a runtime configuration setting to a value.
/// Params:
///     rc = RC instance reference.
///     field = Setting name.
///     value = New value.
/// Throws: Exception when a setting or value is invalid.
void configRC(ref RC rc, string field, string value)
{
    foreach (config; configurations)
    {
        if (config.name == field)
        {
            config.impl(rc, value);
            return;
        }
    }
    
    throw new Exception(text("Unknown field: ", field));
}
unittest
{
    RC rc;
    
    configRC(rc, "columns", "10");
    assert(rc.columns == 10);
    
    configRC(rc, "addressing", "dec");
    assert(rc.address_type == AddressType.dec);
    
    configRC(rc, "address-spacing", "5");
    assert(rc.address_spacing == 5);
    
    configRC(rc, "charset", "ebcdic");
    assert(rc.charset == CharacterSet.ebcdic);
}

void configuration_columns(ref RC rc, string value)
{
    int cols = to!int(value);
    if (cols <= 0)
        throw new Exception("Cannot have negative or zero columns");
    rc.columns = cols;
}

void configuration_addressing(ref RC rc, string value)
{
    if (value is null || value.length == 0)
        goto Lerror;
    
    switch (value[0]) { // cheap "startsWith"
    case 'h': rc.address_type = AddressType.hex; return;
    case 'd': rc.address_type = AddressType.dec; return;
    case 'o': rc.address_type = AddressType.oct; return;
    default:
    }
    
Lerror:
    throw new Exception(text("Unknown address type: ", value));
}

void configuration_address_spacing(ref RC rc, string value)
{
    int spacing = to!int(value);
    if (spacing < 3) // due to offset indicator ("hex",etc.)
        throw new Exception("Can't have address spacing lower than 3");
    rc.address_spacing = spacing;
}

void configuration_charset(ref RC rc, string value)
{
    rc.charset = selectCharacterSet(value);
}
