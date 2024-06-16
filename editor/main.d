module editor.main;

import std.stdio;
import editor.app;
import ddhx.common;
import ddhx.logger;
import ddhx.document;

private:

int main(string[] args)
{
    args = commonopts(args);
    
    // If file not mentioned, app will assume stdin
    string filename = args.length > 1 ? args[1] : null;
    trace("filename=%s", filename);
    
    // TODO: Support streams (for editor, that's slurping all of stdin)
    if (filename == null)
    {
        stderr.writeln("error: Filename required. No current support for streams.");
        return 0;
    }
    
    Document doc;
    try doc.openFile(filename, _oreadonly);
    catch (Exception ex)
    {
        stderr.writeln("error: ", ex.msg);
        return 1;
    }
    
    startEditor(doc);
    return 0;
}