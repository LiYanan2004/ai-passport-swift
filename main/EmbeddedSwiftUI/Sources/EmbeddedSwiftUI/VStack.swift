//
//  EmbeddedVStack.swift
//  EmbeddedSwiftUICore

public struct VStack<Content: View>: PrimitiveView, UnaryView {
    let content: Content
    let layout: VStackLayout
    public init(alignment: HorizontalAlignment = .center, spacing: Int32? = nil, @ViewBuilder content: () -> Content) {
        self.content = content(); layout = .init(alignment: alignment, spacing: spacing)
    }

    public static func _makeView(view: Self, inputs: _ViewInputs) -> _ViewOutputs {
        let outputs = Content.makeDebuggableViewList(
            view: view.content,
            inputs: _ViewListInputs(inputs.child(at: 0))
        )
        var displayList = DisplayList()
        displayList.append(.beginContainer(.stack(
            axis: .vertical,
            spacing: view.layout.spacing,
            alignment: Alignment(horizontal: view.layout.alignment, vertical: .top)
        )))
        displayList.append(outputs.displayList)
        displayList.append(.endContainer)
        return _ViewOutputs(
            displayList: displayList,
            viewResponders: outputs.viewResponders
        )
    }
}
public struct VStackLayout: Layout {
    public typealias Cache = _StackLayoutCache
    public var alignment: HorizontalAlignment
    public var spacing: Int32?
    public init(alignment: HorizontalAlignment = .center, spacing: Int32? = nil) {
        precondition((spacing ?? 0) >= 0)
        self.alignment = alignment; self.spacing = spacing
    }
    public static var layoutProperties: LayoutProperties {
        LayoutProperties(stackOrientation: .vertical)
    }
    private func engine(_ subviews: LayoutSubviews) -> EmbeddedStackLayout {
        .init(vertical: true, spacing: spacing, alignment: Alignment(horizontal: alignment, vertical: .top))
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
