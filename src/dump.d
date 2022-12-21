/// Dumps binary data to stdout.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module dump;

import os.terminal;
import error, editor, screen, settings;

/*TODO: DumpOutput
//      Then add to function as parameter

// With custom "byte" formatter
// Default formatter has " " as prefix/suffix
// HTML formatter will have "<td>" as prefix and "</td>" as suffix

enum DumpOutput {
    text,
    html
}*/

/// Dump to stdout, akin to xxd(1) or hexdump(1).
/// Params:
///     skip = If set, number of bytes to skip.
///     length = If set, maximum length to read.
/// Returns: Error code.
int start(long skip, long length) {
    if (length < 0)
        return errorPrint(1, "Length must be a positive value");
    
    terminalInit(TermFeat.none);
    
    version (Trace) trace("skip=%d length=%d", skip, length);
    
    switch (editor.fileMode) with (FileMode) {
    case file, mmfile: // Seekable
        long fsize = editor.fileSize;
        
        // negative skip value: from end of file
        if (skip < 0)
            skip = fsize + skip;
        
        // adjust length if unset
        if (length == 0)
            length = fsize - skip;
        else if (length < 0)
            return errorPrint(1, "Length value must be positive");
        
        // overflow check
        //TODO: This shouldn't error and should take the size we get from file.
        if (skip + length > fsize)
            return errorPrint(1, "Specified length overflows file size");
        
        break;
    case stream: // Unseekable
        if (skip < 0)
            return errorPrint(1, "Skip value must be positive with stream");
        if (length == 0)
            length = long.max;
        break;
    default: // Memory mode is never initiated from CLI
    }
    
    // start skipping
    if (skip)
        editor.seek(skip);
    
    // top bar to stdout
    screen.renderOffset;
    
    // mitigate unaligned reads/renders
    size_t a = setting.columns * 16;
    if (a > length)
        a = cast(size_t)length;
    editor.setBuffer(a);
    
    // read until EOF or length spec
    long r;
    do {
        ubyte[] data = editor.read;
        screen.renderContent(r, data);
        r += data.length;
        //io.position = r;
    } while (editor.eof == false && r < length);
    
    return 0;
}