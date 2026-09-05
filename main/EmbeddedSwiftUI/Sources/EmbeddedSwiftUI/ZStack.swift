//
//  EmbeddedZStack.swift
//  EmbeddedSwiftUICore

/// Measures all children with the same proposal, then aligns their fitted sizes.
public struct ZStack<Content: View>: PrimitiveView, UnaryView {
    public let content: Content
    let alignment: Alignment
    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {
        self.alignment = alignment; self.content = content()
    }

    public static func _makeView(view: Self, inputs: _ViewInputs) -> _ViewOutputs {
        let outputs = Content.makeDebuggableViewList(
            view: view.content,
            inputs: _ViewListInputs(inputs.child(at: 0))
        )
        var displayList = DisplayList()
        displayList.append(.beginContainer(.overlay(alignment: view.alignment)))
        displayList.append(outputs.displayList)
        displayList.append(.endContainer)
        return _ViewOutputs(
            displayList: displayList,
            viewResponders: outputs.viewResponders
        )
    }
}
