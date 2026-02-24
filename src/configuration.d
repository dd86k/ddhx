/// Configuration management.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module configuration;

// Module is named configuration to avoid confusion with std.getopt.config and
// "rc" local variable names.

import coloring;
import ddhx  : bindkey, setcolor;
import formatting;
import os.terminal : terminal_keybind;
import std.conv : text, to;
import transcoder : CharacterSet, selectCharacterSet;
import utils : arguments;

/// Special value for RC.columns to autoresize.
enum COLUMNS_AUTO = 0;

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
    
    /// If set, hide header.
    bool header = true;
    
    /// If set, hide status bar.
    bool status = true;
    
    /// If set, sets the cursor mirror.
    bool mirror_cursor; // could be paired with "mirror-color" later
    
    /// Gray out zeros.
    bool gray_zeros = true;
    
    /// Enable coalescing
    bool coalescing = true;
    
private:
    // Fixes when RC file has config and CLI already set a field.
    bool address_type_set;
    bool data_type_set;
    bool charset_set;
    bool writemode_set;
    bool columns_set;
    bool address_spacing_set;
    bool header_set;
    bool status_set;
    bool mirror_cursor_set;
    bool gray_zeros_set;
    bool coalescing_set;
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
        case "bind": // bind KEY COMMAND [ARGS...]
            if (args.length < 3)
                throw new Exception("Missing command");
            bindkey(
                terminal_keybind( args[1] ),
                args[2],
                args.length > 3 ? args[3..$] : null);
            continue;
        case "color": // color SCHEME COLOR
            if (args.length < 3)
                throw new Exception("Missing color");
            setcolor(
                getScheme(args[1]),
                ColorMap.parse(args[2])
            );
            continue;
        default:
            configRC(rc, args[0], args[1], true);
        }
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
    assert(binded(key) == null);
    
    // Emulate CLI change, before config
    configure_columns(rc, "6");
    configure_charset(rc, "ascii");
    
    // Load and check
    loadRC(rc,
`columns 20
charset ebcdic
bind j left`);
    assert(rc.columns == 6); // Untouched by config file
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
        "address-spacing", "Address spacing in characters",
        "Number", "11",
        &configure_address_spacing
    },
    {
        "address", "Address representation format",
        `"h[exadecimal]", "o[ctal]", "d[ecimal]"`, `"hexadecimal"`,
        &configure_address
    },
    {
        "data", "Data representation format",
        `"x8", "x16"`, `"x8"`,
        &configure_data
    },
    {
        "charset", "Character set",
        `"ascii", "cp437", "mac", "ebcdic"`, `"ascii"`,
        &configure_charset
    },
    {
        // NOTE: "autoresize" was too ambiguous and moved into columns
        "columns", "Number of elements to show on a row, 'auto' to fit screen",
        "Number", "16",
        &configure_columns
    },
    {
        "header", "If enabled, show the header bar",
        "Boolean", `"on"`,
        &configure_header
    },
    {
        "status", "If enabled, show the status bar",
        "Boolean", `"on"`,
        &configure_status
    },
    {
        "mirror-cursor", "If set, mirrors the cursor for both columns",
        "Boolean", `"off"`,
        &configure_mirror_cursor
    },
    {
        "gray-zeros", "If set, zero values are printed as gray",
        "Boolean", `"off"`,
        &configure_gray_zeros
    },
    {
        "coalesce", "If set, edits are coalescing",
        "Boolean", `"on"`,
        &configure_coalescing
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
    
    configRC(rc, "address", "dec");
    assert(rc.address_type == AddressType.dec);
    
    configRC(rc, "address-spacing", "5");
    assert(rc.address_spacing == 5);
    
    configRC(rc, "charset", "ebcdic");
    assert(rc.charset == CharacterSet.ebcdic);
}

void configure_columns(ref RC rc, string value, bool conf = false)
{
    if (conf && rc.columns_set)
        return;
    
    // Aliases
    switch (value) {
    case "auto", "autoresize":
        rc.columns = COLUMNS_AUTO;
        rc.columns_set = true;
        return;
    default:
    }
    
    int cols = to!int(value);
    if (cols < 0)
        throw new Exception("Cannot have negative columns");
    rc.columns = cols;
    rc.columns_set = true;
}

void configure_address(ref RC rc, string value, bool conf = false)
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

void configure_data(ref RC rc, string value, bool conf = false)
{
    if (conf && rc.data_type_set)
        return;
    
    rc.data_type = selectDataType(value);
    rc.data_type_set = true;
}

void configure_address_spacing(ref RC rc, string value, bool conf = false)
{
    if (conf && rc.address_spacing_set)
        return;
    
    int spacing = to!int(value);
    if (spacing < 3 && spacing > -3) // due to offset indicator ("hex",etc.)
        throw new Exception("Address spacing too low (3 or more needed)");
    rc.address_spacing = spacing;
    rc.address_spacing_set = true;
}

void configure_charset(ref RC rc, string value, bool conf = false)
{
    if (conf && rc.charset_set)
        return;
    
    rc.charset = selectCharacterSet(value);
    rc.charset_set = true;
}

void configure_header(ref RC rc, string value, bool conf = false)
{
    if (conf && rc.header_set)
        return;
    
    rc.header = boolean(value);
    rc.header_set = true;
}

void configure_status(ref RC rc, string value, bool conf = false)
{
    if (conf && rc.status_set)
        return;
    
    rc.status = boolean(value);
    rc.status_set = true;
}

void configure_mirror_cursor(ref RC rc, string value, bool conf = false)
{
    if (conf && rc.mirror_cursor_set)
        return;
    
    rc.mirror_cursor = boolean(value);
    rc.mirror_cursor_set = true;
}

void configure_gray_zeros(ref RC rc, string value, bool conf = false)
{
    if (conf && rc.gray_zeros_set)
        return;
    
    // Eventually could just set the color mapping directly
    rc.gray_zeros = boolean(value);
    rc.gray_zeros_set = true;
}

void configure_coalescing(ref RC rc, string value, bool conf = false)
{
    if (conf && rc.coalescing_set)
        return;
    
    rc.coalescing = boolean(value);
    rc.coalescing_set = true;
}
