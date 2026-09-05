// Embedded adaptation of EmbeddedSwiftUICore/View/View.swift and Never+View.swift.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

public protocol View {
    static func _makeView(
        view: Self,
        inputs: _ViewInputs
    ) -> _ViewOutputs
    static func _makeViewList(
        view: Self,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs
    static func _viewListCount(inputs: _ViewListCountInputs) -> Int?
    static func _makeProperties(
        in buffer: inout _DynamicPropertyBuffer,
        container: inout Self,
        inputs: inout _ViewInputs
    )
    associatedtype Body: View
    @ViewBuilder var body: Body { get }
}

extension View {
    public static func _makeProperties(
        in buffer: inout _DynamicPropertyBuffer,
        container: inout Self,
        inputs: inout _ViewInputs
    ) {}

    package static func makeDebuggableView(view: Self, inputs: _ViewInputs) -> _ViewOutputs {
        guard inputs.constructionBudget?.isExhausted != true else { return _ViewOutputs(.invalid) }
        var inputs = inputs.pushStableType(Self.self)
        var view = view
        var buffer = _DynamicPropertyBuffer()
        Self._makeProperties(in: &buffer, container: &view, inputs: &inputs)
        var outputs = Self._makeView(view: view, inputs: inputs)
        outputs.displayList = outputs.displayList.identified(by: inputs.identity)
        return outputs
    }

    package static func makeDebuggableViewList(
        view: Self,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        guard inputs.base.constructionBudget?.isExhausted != true else {
            return _ViewListOutputs(displayList: DisplayList(commands: [.invalid]))
        }
        var inputs = inputs
        inputs.base = inputs.base.pushStableType(Self.self)
        var view = view
        var buffer = _DynamicPropertyBuffer()
        Self._makeProperties(in: &buffer, container: &view, inputs: &inputs.base)
        var outputs = Self._makeViewList(view: view, inputs: inputs)
        outputs.displayList = outputs.displayList.identified(by: inputs.base.identity)
        if outputs.views.ids.isEmpty, let count = outputs.views.staticCount {
            outputs.views.ids = (0..<count).map { inputs.base.identity.elementID(at: $0) }
        }
        outputs.nextImplicitID = inputs.implicitID + (outputs.views.staticCount ?? 0)
        return outputs
    }

    package func bodyError() -> Never {
        preconditionFailure("body() should not be called on \(Self.self)")
    }

    public static func _makeView(
        view: Self,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        Body.makeDebuggableView(view: view.body, inputs: inputs.child(at: 0))
    }

    public static func _makeViewList(
        view: Self,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        var inputs = inputs
        inputs.base = inputs.base.child(at: 0)
        return Body.makeDebuggableViewList(view: view.body, inputs: inputs)
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        Body._viewListCount(inputs: inputs)
    }

    package static func makeImplicitRoot(view: Self, inputs: _ViewInputs) -> _ViewOutputs {
        let outputs = Self._makeViewList(view: view, inputs: _ViewListInputs(inputs))
        return _ViewOutputs(
            displayList: outputs.displayList.withImplicitRoot(),
            viewResponders: outputs.viewResponders
        )
    }
}

extension Never: View {
    public var body: Never { self }
    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        nil
    }
}

package protocol PrimitiveView: View {}

extension PrimitiveView {
    public var body: Never {
        bodyError()
    }
}

/// Adapts a view-list-producing value to the unary `View` construction path.
/// OpenSwiftUI uses this shim when a list is consumed where a single view is
/// expected. The embedded implementation forwards construction directly and
/// does not introduce an additional graph node.
public struct _UnaryViewAdaptor<Content: View>: View, UnaryView, PrimitiveView {
    public var content: Content

    public init(_ content: Content) {
        self.content = content
    }

    package init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public static func _makeView(
        view: Self,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        Content.makeDebuggableView(view: view.content, inputs: inputs)
    }
}

package protocol UnaryView: View {}

extension UnaryView {
    public static func _makeViewList(
        view: Self,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        let outputs = Self._makeView(view: view, inputs: inputs.base)
        var displayList = DisplayList()
        displayList.append(.beginTraits(inputs.traits))
        displayList.append(outputs.displayList)
        displayList.append(.endTraits)
        return _ViewListOutputs(
            displayList: displayList,
            viewResponders: outputs.viewResponders,
            staticCount: 1,
            traits: inputs.traits
        )
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        1
    }
}

package protocol MultiView: View {}

extension MultiView {
    public static func _makeView(
        view: Self,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        Self.makeImplicitRoot(view: view, inputs: inputs)
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        nil
    }
}
