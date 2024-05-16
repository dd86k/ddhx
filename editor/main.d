module editor.main;

import editor.app;
import ddhx.common;
import ddhx.logger;

private:

int main(string[] args)
{
    commonopts(args);
    
    // If file not mentioned, app will assume stdin
    string filename = args.length > 1 ? args[1] : null;
    trace("filename=%s", filename);
    
    return start(filename);
}