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
import ddhx.logger;

__gshared:

/// Copyright string
immutable string DDHX_COPYRIGHT = "Copyright (c) 2017-2024 dd86k <dd@dax.moe>";
/// App version
immutable string DDHX_VERSION = "0.5.0";
/// Version line
//immutable string DDHX_ABOUT = "ddhx "~DDHX_VERSION~" (built: "~__TIMESTAMP__~")";
enum POSTFIX_ABOUT = DDHX_VERSION~" (built: "~__TIMESTAMP__~")";

immutable string COMPILER_VERSION =
    format("%d.%03d", version_major, version_minor);
enum POSTFIX_PAGE_VERSION =
    "\n"~
    DDHX_COPYRIGHT~"\n"~
    "License: MIT <https://mit-license.org/>\n"~
    "Homepage: <https://git.dd86k.space/dd86k/ddhx>\n"~
    "Compiler: "~__VENDOR__~" "~COMPILER_VERSION;

/// 
bool _otrace;
/// Group size of one element in bytes
int _ogrpsize = 1;
/// Data formatting
int _odatafmt = Format.hex;
/// Address formatting
int _oaddrfmt = Format.hex;
/// Address space padding in digits
int _oaddrpad = 11;
/// Size of column (one row) in bytes
int _ocolumns;
/// Character set
int _ocharset = CharacterSet.ascii;
/// 
char _ofillchar = '.';
/// Skip/seek position
long _opos;
/// Total length to read
long _olength;

bool cliTestStdin(string path)
{
    return path == "-";
}
long cliParsePos(string v)
{
    if (v[0] != '+')
        throw new Exception(text("Missing '+' prefix to argument: ", v));
    
    return cparse(v[1..$]);
}

void cliOptColumn(string v)
{
    
}

