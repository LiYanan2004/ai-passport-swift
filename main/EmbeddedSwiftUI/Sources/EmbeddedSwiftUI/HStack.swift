//
//  EmbeddedHStack.swift
//  EmbeddedSwiftUICore

public struct HStack<Content: View>: PrimitiveView, UnaryView {
    let content: Content
    let layout: HStackLayout
    public init(alignment: VerticalAlignment = .center, spacing: Int32? = nil, @ViewBuilder content: () -> Content) {
        self.content = content(); layout = .init(alignment: alignment, spacing: spacing)
    }

    public static func _makeView(view: Self, inputs: _ViewInputs) -> _ViewOutputs {
        let outputs = Content.makeDebuggableViewList(
            view: view.content,
            inputs: _ViewListInputs(inputs.child(at: 0))
        )
        var displayList = DisplayList()
        displayList.append(.beginContainer(.stack(
            axis: .horizontal,
            spacing: view.layout.spacing,
            alignment: Alignment(horizontal: .leading, vertical: view.layout.alignment)
        )))
        displayList.append(outputs.displayList)
        displayList.append(.endContainer)
        return _ViewOutputs(
            displayList: displayList,
            viewResponders: outputs.viewResponders
        )
    }
}
public struct HStackLayout: Layout {
    public typealias Cache = _StackLayoutCache
    public var alignment: VerticalAlignment
    public var spacing: Int32?
    public init(alignment: VerticalAlignment = .center, spacing: Int32? = nil) {
        precondition((spacing ?? 0) >= 0)
        self.alignment = alignment; self.spacing = spacing
    }
    public static var layoutProperties: LayoutProperties {
        LayoutProperties(stackOrientation: .horizontal)
    }
    private func engine(_ subviews: LayoutSubviews) -> EmbeddedStackLayout {
        .init(vertical: false, spacing: spacing, alignment: Alignment(horizontal: .leading, vertical: alignment))
    }
    public func makeCache(subviews: LayoutSubviews) -> Cache {
        .init()
    }
    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout Cache
    ) -> EmbeddedSize {
        engine(subviews).measure(proposal, subviews: subviews, cache: &cache)
    }
    public func placeSubviews(
        in bounds: EmbeddedRect,
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout Cache
    ) {
        engine(subviews).place(bounds, subviews: subviews, cache: cache)
    }
}
