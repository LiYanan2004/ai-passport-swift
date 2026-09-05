// Embedded adaptation: the upstream lazy/dynamic list infrastructure depends
// on graph-backed ViewList traversal. This profile constructs rows eagerly
// within the adaptor's node budget while retaining the ScrollView API shape
// and keyed ForEach identity across updates.

public struct ScrollView<Content: View>: PrimitiveView, UnaryView {
    private let axes: Axis.Set
    private let showsIndicators: Bool
    private let content: Content
    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true,
                @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content()
    }
    public static func _makeView(view: Self, inputs: _ViewInputs) -> _ViewOutputs {
        let outputs = Content.makeDebuggableViewList(
            view: view.content,
            inputs: _ViewListInputs(inputs.child(at: 0))
        )
        var displayList = DisplayList()
        displayList.append(.beginContainer(
            .scroll(
                axes: view.axes,
                showsIndicators: view.showsIndicators,
                isList: false
            )
        ))
        displayList.append(outputs.displayList)
        displayList.append(.endContainer)
        return _ViewOutputs(
            displayList: displayList,
            viewResponders: outputs.viewResponders
        )
    }
}

/// A small eager list. The same node budget applies to visible and hidden rows.
public struct List<Content: View>: PrimitiveView, UnaryView {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    public init<Row: View>(_ data: Range<Int>, @ViewBuilder rowContent: @escaping (Int) -> Row)
        where Content == ForEach<Range<Int>, Int, Row> {
        content = ForEach(data, content: rowContent)
    }
    public static func _makeView(view: Self, inputs: _ViewInputs) -> _ViewOutputs {
        let outputs = Content.makeDebuggableViewList(
            view: view.content,
            inputs: _ViewListInputs(inputs.child(at: 0))
        )
        var displayList = DisplayList()
        displayList.append(.beginContainer(
            .scroll(axes: .vertical, showsIndicators: true, isList: true)
        ))
        displayList.append(outputs.displayList)
        displayList.append(.endContainer)
        return _ViewOutputs(
            displayList: displayList,
            viewResponders: outputs.viewResponders
        )
    }
}

/// Eager collection construction preserves row identity across updates.
public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: PrimitiveView, MultiView {
    public let data: Data
    public let content: (Data.Element) -> Content
    private let id: (Data.Element) -> ID

    public init(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.content = content
        self.id = { $0[keyPath: id] }
    }

    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content)
        where Data.Element: Identifiable, ID == Data.Element.ID {
        self.data = data
        self.content = content
        id = { $0.id }
    }

    public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content)
        where Data == Range<Int>, ID == Int {
        self.data = data
        self.content = content
        id = { $0 }
    }

    public static func _makeViewList(
        view: Self,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        var outputs = _ViewListOutputs()
        for element in view.data {
            guard inputs.base.constructionBudget?.consume() != false else {
                return _ViewListOutputs(displayList: DisplayList(commands: [.invalid]))
            }
            var childInputs = inputs
            childInputs.base = inputs.base.pushStableID(view.id(element))
            childInputs.implicitID = outputs.nextImplicitID
            outputs.append(Content.makeDebuggableViewList(
                view: view.content(element), inputs: childInputs
            ))
            if inputs.base.constructionBudget?.isExhausted == true {
                return _ViewListOutputs(displayList: DisplayList(commands: [.invalid]))
            }
        }
        return outputs
    }
}
