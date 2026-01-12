/// Backend packages.
///
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module backend;

public import backend.base : IDocumentEditor, selectBackend;
public import backend.piece : PieceDocumentEditor;
public import backend.piecev2 : PieceV2DocumentEditor;