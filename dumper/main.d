module dumper.main;

import dumper.app;
import ddhx.common;
import ddhx.logger;

private:

int main(string[] args)
{
    commonopts(args);
    
    // If file not mentioned, app will assume stdin
    string filename = args.length > 1 ? args[1] : null;
    trace("filename=%s", filename);
    
    return dump(filename);
}