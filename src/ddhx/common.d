/// Common variables
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.common;

import std.stdio, std.format, std.compiler;
import std.conv, std.getopt;
import core.stdc.stdlib : exit;
import ddhx.formatter : Format, selectFormat;
import ddhx.transcoder : CharacterSet, selectCharacterSet;
import ddhx.utils.strings : cparse;

__gshared:

/// Copyright string
immutable string DDHX_COPYRIGHT = "Copyright (c) 2017-2024 dd86k <dd@dax.moe>";
/// App version
immutable string DDHX_VERSION = "0.5.0";
/// Version line
//immutable string DDHX_ABOUT = "ddhx "~DDHX_VERSION~" (built: "~__TIMESTAMP__~")";
immutable string POSTFIX_ABOUT = DDHX_VERSION~" (built: "~__TIMESTAMP__~")";

immutable string COMPILER_VERSION =
    format("%d.%03d", version_major, version_minor);
immutable string POSTFIX_PAGE_VERSION =
    "\n"~
    DDHX_COPYRIGHT~"\n"~
    "License: MIT <https://mit-license.org/>\n"~
    "Homepage: <https://git.dd86k.space/dd86k/ddhx>\n"~
    "Compiler: "~__VENDOR__~" "~COMPILER_VERSION;

struct Options
{
    Format data_format = Format.hex;
    int view_columns = 16;
    Format address_format = Format.hex;
    int address_padding = 10;
    CharacterSet character_set = CharacterSet.ascii;
    char character_default = '.';
    
    bool trace;
}
Options options;
