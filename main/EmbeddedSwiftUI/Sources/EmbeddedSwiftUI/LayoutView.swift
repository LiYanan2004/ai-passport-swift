// Embedded adaptation of OpenSwiftUICore/Layout/LayoutView.swift.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

package struct _LayoutView<LayoutType: Layout, Content: View>: PrimitiveView, UnaryView {
    let layout: LayoutType
    let content: Content

    public static func _makeView(
        view: Self,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        let outputs = Content.makeDebuggableViewList(
            view: view.content,
            inputs: _ViewListInputs(inputs.child(at: 0))
        )
        var displayList = DisplayList()
        displayList.append(.beginContainer(.layout(_AnyLayout(view.layout))))
        displayList.append(outputs.displayList)
        displayList.append(.endContainer)
        return _ViewOutputs(
            displayList: displayList,
            viewResponders: outputs.viewResponders
        )
    }
}
