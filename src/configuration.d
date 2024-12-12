/// Configuration management.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module configuration;

// Module is named configuration to avoid confusion with std.getopt.config.

// Editor configuration
struct RC
{
    //
    string address_format;
    //
    string data_format;
    //
    string charset;
    // Number of columns
    int columns;
    
    // Path to trace log
    string logfile;
    
    string len;
    string seek;
    
    // 
    bool readonly;
}

RC loadRC(string path)
{
    throw new Exception("TODO");
}
