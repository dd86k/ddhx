/// Backend packages.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module editor;

public import editor.base : IDocumentEditor, selectBackend;
public import editor.piece : PieceDocumentEditor;
public import editor.piecev2 : PieceV2DocumentEditor;