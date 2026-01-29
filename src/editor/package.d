/// Backend packages.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module editor;

public import editor.base : IDocumentEditor;
import editor.piece : PieceDocumentEditor;
import editor.piecev2 : PieceV2DocumentEditor;

// Convenience function used in main.d and benchmarks.
/// Select and initiate new document editor instance.
///
/// This function also checks environment for further configuration if exists.
/// Params: name = Backend name.
/// Returns: Document editor instance.
/// Throws: When unknown name given.
IDocumentEditor spawnEditor(string name)
{
    import std.conv : text;
    import std.process : environment;
    import logger : log;
    switch (name) { // null=default
    case "piece":
        return new PieceDocumentEditor();
    case "piecev2", null:
        return new PieceV2DocumentEditor();
    default:
        throw new Exception(text("Backend does not exist: ", name));
    }
}