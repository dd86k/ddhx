module settings;

import std.stdio;
import ddhx;
import utils : unformat;
import core.stdc.stdlib : exit;
import std.format : format;

//TODO: Delete this module
//      ddhx module should be the one with external functions
//      main (cli) should have getopt handlers

private enum
	ENOPARSE = "Could not parse number",
	ETRANGE = "Number %d out of range (1-%d)";

deprecated:

/**
 * Handles the Width setting from getopt.
 * Params:
 *   opt = Usually "w|width"
 *   val = Value to assign
 */
void ddhx_setting_handle_cli(string opt, string val) {
	ddhx_setting_handle_rowwidth(val, true);
}

/**
 * Handles the Width setting.
 * Params:
 *   val = Value to assign
 *   cli = From CLI (Assumes false by default)
 */
void ddhx_setting_handle_rowwidth(string val, bool cli = false) {
	switch (val[0]) {
	case 'a': // Automatic
		// NOTE: I forgot why this is there
		version (Windows) {
			import ddcon : coninit;
			if (cli) coninit;
		}
		g_rowwidth = getBytesPerRow;
		break;
	case 'd': // Default
		g_rowwidth = 16;
		break;
	default:
		long l;
		if (unformat(val, l)) {
			if (l < 1 || l > ushort.max) {
				if (cli) {
					writefln(ETRANGE, l, ushort.max);
					exit(1);
				} else
					ddhx_msglow("Number out of range");
					return;
			}
			g_rowwidth = cast(ushort)l;
		} else {
			if (cli) {
				writeln(ENOPARSE);
				exit(1);
			} else 
				ddhx_msglow(ENOPARSE);
		}
	}
}

/**
 * Handle offset CLI option.
 * Params:
 *   opt = Option
 *   val = Option value
 */
void HandleOCLI(string opt, string val) {
	HandleOffset(val, true);
}

/**
 * Handle offset setting.
 * Params:
 *   val = Value
 *   cli = From CLI?
 */
void HandleOffset(string val, bool cli = false) {
	switch (val[0]) {
	case 'o','O': g_offsettype = OffsetType.Octal; break;
	case 'd','D': g_offsettype = OffsetType.Decimal; break;
	case 'h','H': g_offsettype = OffsetType.Hex; break;
	default:
		if (cli) {
			writef("Unknown mode parameter: %s", val);
			exit(1);
		} else {
			ddhx_msglow(" Invalid offset type: %s", val);
		}
		break;
	}
}

private ushort getBytesPerRow() {
	import ddcon : conwidth;
	final switch (g_displaymode)
	{
		case DisplayMode.Default:
			return cast(ushort)((conwidth - 11) / 4);
		case DisplayMode.Text, DisplayMode.Data:
			return cast(ushort)((conwidth - 11) / 3);
	}
}