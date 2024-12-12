module tests.color;

import std.stdio;
import terminal;

void termColor(TermColor c, string text)
{
    terminalBackground(c);
    terminalWrite(text);
    terminalResetColor();
    
    terminalWrite(": ");
    
    terminalForeground(c);
    terminalWrite(text);
    terminalResetColor();
    
    terminalWrite("\n");
}

@system unittest {
    terminalInit();
    
    terminalWrite("inverted: ");
    terminalInvertColor();
    terminalWrite("inverted");
    terminalResetColor();
    terminalWrite("\n");
    
    termColor(TermColor.black,    "black");
    termColor(TermColor.blue,     "blue");
    termColor(TermColor.green,    "green");
    termColor(TermColor.aqua,     "aqua");
    termColor(TermColor.red,      "red");
    termColor(TermColor.purple,   "purple");
    termColor(TermColor.yellow,   "yellow");
    termColor(TermColor.gray,     "gray");
    termColor(TermColor.lightgray,    "lightgray");
    termColor(TermColor.brightblue,       "brightblue");
    termColor(TermColor.brightgreen,      "brightgreen");
    termColor(TermColor.brightaqua,       "brightaqua");
    termColor(TermColor.brightred,        "brightred");
    termColor(TermColor.brightpurple,     "brightpurple");
    termColor(TermColor.brightyellow,     "brightyellow");
    termColor(TermColor.white,    "white");
}