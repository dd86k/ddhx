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
    
    /// On terminal resize, automatically set number of columns to fit screen.
    bool autoresize;
    
    // Fixes when RC file has config and CLI already set a field.
    bool address_type_set;  // @suppress(dscanner.style.undocumented_declaration)
    bool data_type_set;     // @suppress(dscanner.style.undocumented_declaration)
    bool charset_set;       // @suppress(dscanner.style.undocumented_declaration)
    bool writemode_set;     // @suppress(dscanner.style.undocumented_declaration)
    bool columns_set;       // @suppress(dscanner.style.undocumented_declaration)
    bool address_spacing_set; // @suppress(dscanner.style.undocumented_declaration)
    bool autoresize_set;    // @suppress(dscanner.style.undocumented_declaration)
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

/// Load a configuration from text.
/// Params:
///     rc = RC instance reference.
///     text = Configuration text.
void loadRC(ref RC rc, string text) // @suppress(dscanner.style.doc_missing_throw)
{
    import utils : arguments;
    import ddhx  : bindkey;
    import os.terminal : terminal_keybind;
    // NOTE: The strategy is to only update value in RC if they're default.
    //       Otherwise, if the value is different than default, then it was set
    //       at the command-line, and thus should not be changed.
    import std.string : lineSplitter;
    foreach (ref string line; lineSplitter(text))
    {
        if (line.length == 0 || line[0] == '#')
            continue;
        
        string[] args = arguments(line);
        if (args.length < 2)
            throw new Exception("Missing value");
        
        // Special
        switch (args[0]) {
        case "bind":
            if (args.length < 3)
                throw new Exception("Missing command");
            bindkey(
                terminal_keybind( args[1] ),
                args[2],
                args.length > 3 ? args[3..$] : null);
            continue;
        default:
        }
        
        // Config
        configRC(rc, args[0], args[1], true);
    }
}
unittest
{
    import ddhx : initdefaults, binded;
    import os.terminal : terminal_keybind;
    
    initdefaults(); // bindkey depends on g_commands (command names)
    
    // Check defaults
    RC rc;
    int key = terminal_keybind("j");
    assert(rc.columns == 16);
    assert(rc.autoresize == false);
    assert(binded(key) == null);
    
    // Emulate CLI change, before config
    configuration_columns(rc, "6");
    configuration_charset(rc, "ascii");
    
    // Load and check
    loadRC(rc,
`columns 20
autoresize on
charset ebcdic
bind j left`);
    assert(rc.columns == 6); // Untouched by config file
    assert(rc.autoresize); // Touched by config
    assert(rc.charset == CharacterSet.ascii);
    assert(binded(key));
}

/// Describes a configuration.
struct Config
{
    string name;        /// Short name
    string description; /// Configuration description
    string availvalues; /// Available values or expected type
    string defaultval;  /// Default value
    
    void function(ref RC, string val, bool rc) impl; /// Implementation function
}
/// Available configurations.
immutable Config[] configurations = [ // Try keeping this ascending by name!
    {
        "address-spacing", "Left row address spacing in characters",
        "Number", "11",
        &configuration_address_spacing
    },
    {
        "addressing", "Addressing offset format displayed",
        `"hexadecimal", "octal", "decimal"`, `"hex"`,
        &configuration_addressing
    },
    {
        "autoresize", "If set, automatically resize columns to fit screen",
        "Boolean", `"off"`,
        &configuration_autoresize
    },
    {
        "charset", "Character set",
        `"ascii", "cp437", "mac", "ebcdic"`, `"ascii"`,
        &configuration_charset
    },
    {
        "columns", "Number of elements to show on a row",
        "Number", "16",
        &configuration_columns
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
///     conf = Loading from RC. If set, do not change if already set.
/// Throws: Exception when a setting or value is invalid.
void configRC(ref RC rc, string field, string value, bool conf = false)
{
    foreach (config; configurations)
    {
        if (config.name == field)
        {
            config.impl(rc, value, conf);
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

void configuration_autoresize(ref RC rc, string value, bool conf = false)
{
    if (conf && rc.autoresize_set)
        return;
    
    rc.autoresize = boolean(value);
    rc.autoresize_set = true;
}

void configuration_columns(ref RC rc, string value, bool conf = false)
{
    if (conf && rc.columns_set)
        return;
    
    int cols = to!int(value);
    if (cols <= 0)
        throw new Exception("Cannot have negative or zero columns");
    rc.columns = cols;
    rc.columns_set = true;
}

void configuration_addressing(ref RC rc, string value, bool conf = false)
{
    if (conf && rc.address_type_set)
        return;
    
    if (value is null || value.length == 0)
    Lerror:
        throw new Exception(text("Unknown address type: ", value));
    
    switch (value[0]) { // cheap "startsWith"
    case 'h': rc.address_type = AddressType.hex; break;
    case 'd': rc.address_type = AddressType.dec; break;
    case 'o': rc.address_type = AddressType.oct; break;
    default: goto Lerror;
    }
    rc.address_type_set = true;
}

void configuration_address_spacing(ref RC rc, string value, bool conf = false)
{
    if (conf && rc.address_spacing_set)
        return;
    
    int spacing = to!int(value);
    if (spacing < 3) // due to offset indicator ("hex",etc.)
        throw new Exception("Can't have address spacing lower than 3");
    rc.address_spacing = spacing;
    rc.address_spacing_set = true;
}

void configuration_charset(ref RC rc, string value, bool conf = false)
{
    if (conf && rc.charset_set)
        return;
    
    rc.charset = selectCharacterSet(value);
    rc.charset_set = true;
}
