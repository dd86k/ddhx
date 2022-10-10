module reverser;

import std.string : toStringz;
import core.stdc.stdio : FILE, fopen, fwrite, ferror, perror;
import editor;

int start(string outpath) {
	enum BUFSZ = 4096;
	ubyte[BUFSZ] data = void;
	
	outfile = fopen(outpath.toStringz, "wb");
	if (ferror(outfile)) {
		perror("fopen");
		return 2;
	}
	
L_READ:
	ubyte[] r = editor.read(data);
	
	if (editor.err) {
		return 3;
	}
	
	foreach (ubyte b; r) {
		if (b >= '0' && b <= '9') {
			outnibble(b - 0x30);
		} else if (b >= 'a' && b <= 'f') {
			outnibble(b - 0x57);
		} else if (b >= 'A' && b <= 'F') {
			outnibble(b - 0x37);
		}
	}
	
	if (editor.eof) {
		outfinish;
		return 0;
	}
	
	goto L_READ;
}

private:

__gshared FILE *outfile;
__gshared bool  low;
__gshared ubyte data;

void outnibble(int nibble) {
	if (low == false) {
		data = cast(ubyte)(nibble << 4);
		low = true;
		return;
	}
	
	low = false;
	ubyte b = cast(ubyte)(data | nibble);
	fwrite(&b, 1, 1, outfile);
}

void outfinish() {
	if (low == false) return;
	
	fwrite(&data, 1, 1, outfile);
}