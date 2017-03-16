/*
 * Menu.d : Menu system.
 */

module Menu;

import std.stdio;
import ddhx;
import Poshub;

private static MenuItem[] MenuItems = [
    new MenuItem("File",
        [ new MenuItem("msg hi", { ShowAbout; } ),
          new MenuItem("haha") ]
    )
];
private static bool InMenu;
private static ushort X, Y;

void InitiateMenu()
{
    DrawMenu();
}

private void DrawMenu()
{
    SetPos(0, 0);
    //TODO: Change color
    foreach(item; MenuItems)
        writef(" %s", item.Text);
    //TODO: Fill with (WindowWidth - CursorLeft)
}

private void DrawSubMenu()
{
    import core.stdc.string : memset;
    int x = 0, y = 1;
    for (int i = 0; i < X - 1; --i)
        x += MenuItems[i].Text.length + 1;
    SetPos(x, y);
    char[] line = new char[20]; // tmp
    memset(&line[0], '-', line.length);
    //write("┌", line, "┐");
    write("+", line, "+");
    foreach(item; MenuItems[X].SubItems) {
        SetPos(x, ++y);
        //writef("│ %s │", item.Text);
        writef("| %-*s |", 18, item.Text);
    }
    SetPos(x, ++y);
    //write("└", line, "┘");
    write("+", line, "+");
}

void EnterMenu()
{
    DrawSubMenu();

    InMenu = true;
    while (InMenu)
    {
        KeyInfo ki = ReadKey;

        switch (ki.keyCode)
        {
            case Key.Escape:
                InMenu = false;
                break;
            default:
        }
    }

    UpdateDisplay();
}

void ExecuteMenuItem()
{
    void function() f = MenuItems[X].SubItems[Y].Action;
    if (f !is null) f();
    InMenu = false;
}

void ShowAbout()
{
    Message("Written by dd86k. Copyright (c) 2017 dd86k");
}

class MenuItem
{
    this() {}
    this(string text)
    {
        Text = text;
    }
    this(string text, void function() action)
    {
        Text = text;
        Action = action;
    }
    this(string text, MenuItem[] items)
    {
        Text = text;
        SubItems = items;
    }
    string Text;
    void function() Action;
    MenuItem[] SubItems;
    @property bool IsSeparator()
    {
        return Text == null;
    }
}

