//
//  EmbeddedPadding.swift
//  EmbeddedSwiftUICore

public struct _PaddingLayout: PrimitiveViewModifier, UnaryViewModifier {
    public var edges: Edge.Set
    public var insets: EdgeInsets?

    public init(edges: Edge.Set = .all, insets: EdgeInsets?) {
        self.edges = edges
        self.insets = insets
    }

    package var resolvedInsets: EdgeInsets {
        let insets = insets ?? EdgeInsets()
        return EdgeInsets(
            top: edges.contains(.top) ? insets.top : 0,
            leading: edges.contains(.leading) ? insets.leading : 0,
            bottom: edges.contains(.bottom) ? insets.bottom : 0,
            trailing: edges.contains(.trailing) ? insets.trailing : 0
        )
    }

    public static func _makeView(
        modifier: Self,
        inputs: _ViewInputs,
        body: @escaping (_ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var outputs = body(inputs)
        var displayList = DisplayList()
        displayList.append(.beginContainer(
            modifier.insets == nil
                ? .defaultPadding(modifier.edges)
                : .padding(modifier.resolvedInsets)
        ))
        displayList.append(outputs.displayList)
        displayList.append(.endContainer)
        outputs.displayList = displayList
        return outputs
    }
}

extension View {
    public func padding(_ length: Int32? = nil) -> some View {
        modifier(_PaddingLayout(
            edges: .all,
            insets: length.map { .init(top: $0, leading: $0, bottom: $0, trailing: $0) }
        ))
    }

    public func padding(_ insets: EdgeInsets) -> some View {
        modifier(_PaddingLayout(edges: .all, insets: insets))
    }
}
