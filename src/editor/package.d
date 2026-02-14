/// Backend packages.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module editor;

public import editor.base : IDocumentEditor;
import editor.piece : PieceDocumentEditor;
import editor.piecev2 : PieceV2DocumentEditor;
import editor.piecev3 : PieceV3DocumentEditor;

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
    switch (name) { // NOTE: null chooses default backend
    case "piece":
        return new PieceDocumentEditor();
    case "piecev2", null:
        return new PieceV2DocumentEditor();
    case "piecev3":
        return new PieceV3DocumentEditor();
    default:
        throw new Exception(text("Backend does not exist: ", name));
    }
}