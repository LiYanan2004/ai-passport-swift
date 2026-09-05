// Embedded adaptation of OpenSwiftUICore/Modifier/ViewModifier.swift.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

public protocol ViewModifier {
    static func _makeProperties(
        in buffer: inout _DynamicPropertyBuffer,
        container: inout Self,
        inputs: inout _ViewInputs
    )
    static func _makeView(
        modifier: Self,
        inputs: _ViewInputs,
        body: @escaping (_ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs

    static func _makeViewList(
        modifier: Self,
        inputs: _ViewListInputs,
        body: @escaping (_ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs

    static func _viewListCount(
        inputs: _ViewListCountInputs,
        body: (_ViewListCountInputs) -> Int?
    ) -> Int?

    associatedtype Body: View

    @ViewBuilder
    func body(content: Content) -> Body

    typealias Content = _ViewModifier_Content<Self>
}

extension ViewModifier {
    public static func _makeProperties(
        in buffer: inout _DynamicPropertyBuffer,
        container: inout Self,
        inputs: inout _ViewInputs
    ) {}

    // Embedded adaptation: static registration replaces DynamicBody's field
    // reflection. Every composition level must install its own fields before
    // evaluating body, with a distinct structural identity.
    package static func makeDebuggableView(
        modifier: Self,
        inputs: _ViewInputs,
        body: @escaping (_ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var modifier = modifier
        var inputs = inputs.pushStableType(Self.self)
        var buffer = _DynamicPropertyBuffer()
        Self._makeProperties(in: &buffer, container: &modifier, inputs: &inputs)
        return Self._makeView(modifier: modifier, inputs: inputs, body: body)
    }

    package static func makeDebuggableViewList(
        modifier: Self,
        inputs: _ViewListInputs,
        body: @escaping (_ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        var modifier = modifier
        var inputs = inputs
        inputs.base = inputs.base.pushStableType(Self.self)
        var buffer = _DynamicPropertyBuffer()
        Self._makeProperties(in: &buffer, container: &modifier, inputs: &inputs.base)
        return Self._makeViewList(modifier: modifier, inputs: inputs, body: body)
    }

    public static func _makeView(
        modifier: Self,
        inputs: _ViewInputs,
        body: @escaping (_ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        let content = Content(
            makeView: body,
            makeViewList: { listInputs in
                let outputs = body(listInputs.base)
                var displayList = DisplayList()
                displayList.append(.beginTraits(listInputs.traits))
                displayList.append(outputs.displayList)
                displayList.append(.endTraits)
                return _ViewListOutputs(
                    displayList: displayList,
                    viewResponders: outputs.viewResponders,
                    staticCount: 1,
                    traits: listInputs.traits
                )
            }
        )
        return Body.makeDebuggableView(
            view: modifier.body(content: content), inputs: inputs.child(at: 0)
        )
    }

    public static func _makeViewList(
        modifier: Self,
        inputs: _ViewListInputs,
        body: @escaping (_ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        let content = Content(
            makeView: { viewInputs in
                _ViewOutputs.multiView(inputs: viewInputs, body: body)
            },
            makeViewList: body
        )
        return Body.makeDebuggableViewList(view: modifier.body(content: content), inputs: inputs)
    }

    public static func _viewListCount(
        inputs: _ViewListCountInputs,
        body: (_ViewListCountInputs) -> Int?
    ) -> Int? {
        if Body.self == Never.self { return body(inputs) }
        return withoutActuallyEscaping(body) { body in
            var inputs = inputs
            inputs.bodyCounts[ObjectIdentifier(Self.self)] = body
            return Body._viewListCount(inputs: inputs)
        }
    }
}

extension ViewModifier where Body == Never {
    public func body(content: Content) -> Never {
        bodyError()
    }
}

extension ViewModifier {
    package func bodyError() -> Never {
        preconditionFailure("body() should not be called on \(Self.self)")
    }
}

package protocol PrimitiveViewModifier: ViewModifier where Body == Never {}

package protocol UnaryViewModifier: ViewModifier {}

extension UnaryViewModifier {
    public static func _makeViewList(
        modifier: Self,
        inputs: _ViewListInputs,
        body: @escaping (_ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        let outputs = Self._makeView(
            modifier: modifier,
            inputs: inputs.base
        ) { viewInputs in
            _ViewOutputs.multiView(inputs: viewInputs, body: body)
        }
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

    public static func _viewListCount(
        inputs: _ViewListCountInputs,
        body: (_ViewListCountInputs) -> Int?
    ) -> Int? {
        1
    }
}

package protocol MultiViewModifier: ViewModifier {}

package protocol ViewInputsModifier: ViewModifier where Body == Never {
    static func _makeViewInputs(modifier: Self, inputs: inout _ViewInputs)
}

extension ViewInputsModifier {
    public static func _makeView(
        modifier: Self, inputs: _ViewInputs,
        body: @escaping (_ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var inputs = inputs
        _makeViewInputs(modifier: modifier, inputs: &inputs)
        return body(inputs)
    }

    public static func _makeViewList(
        modifier: Self, inputs: _ViewListInputs,
        body: @escaping (_ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        var inputs = inputs
        _makeViewInputs(modifier: modifier, inputs: &inputs.base)
        return body(inputs)
    }
}

extension MultiViewModifier {
    public static func _makeViewList(
        modifier: Self,
        inputs: _ViewListInputs,
        body: @escaping (_ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        body(inputs)
    }
}

public struct _ViewModifier_Content<Modifier: ViewModifier>: PrimitiveView {
    private let makeView: (_ViewInputs) -> _ViewOutputs
    private let makeViewList: (_ViewListInputs) -> _ViewListOutputs

    package init(
        makeView: @escaping (_ViewInputs) -> _ViewOutputs,
        makeViewList: @escaping (_ViewListInputs) -> _ViewListOutputs
    ) {
        self.makeView = makeView
        self.makeViewList = makeViewList
    }

    public static func _makeView(
        view: Self,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        view.makeView(inputs)
    }

    public static func _makeViewList(
        view: Self,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        view.makeViewList(inputs)
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        inputs.bodyCounts[ObjectIdentifier(Modifier.self)]?(inputs)
    }
}

public struct ModifiedContent<Content, Modifier> {
    public var content: Content
    public var modifier: Modifier

    public init(content: Content, modifier: Modifier) {
        self.content = content
        self.modifier = modifier
    }
}

extension ModifiedContent: View where Content: View, Modifier: ViewModifier {
    public var body: Never {
        bodyError()
    }

    public static func _makeView(
        view: Self,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        Modifier.makeDebuggableView(
            modifier: view.modifier,
            inputs: inputs.child(at: 1)
        ) { inputs in
            Content.makeDebuggableView(view: view.content, inputs: inputs.child(at: 0))
        }
    }

    public static func _makeViewList(
        view: Self,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        var modifierInputs = inputs
        modifierInputs.base = inputs.base.child(at: 1)
        return Modifier.makeDebuggableViewList(
            modifier: view.modifier,
            inputs: modifierInputs
        ) { inputs in
            var inputs = inputs
            inputs.base = inputs.base.child(at: 0)
            return Content.makeDebuggableViewList(view: view.content, inputs: inputs)
        }
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        Modifier._viewListCount(inputs: inputs) { inputs in
            Content._viewListCount(inputs: inputs)
        }
    }
}

extension ModifiedContent: ViewModifier
    where Content: ViewModifier, Modifier: ViewModifier {
    public static func _makeView(
        modifier: Self,
        inputs: _ViewInputs,
        body: @escaping (_ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        Modifier.makeDebuggableView(
            modifier: modifier.modifier,
            inputs: inputs.child(at: 1)
        ) { inputs in
            Content.makeDebuggableView(
                modifier: modifier.content,
                inputs: inputs.child(at: 0),
                body: body
            )
        }
    }

    public static func _makeViewList(
        modifier: Self,
        inputs: _ViewListInputs,
        body: @escaping (_ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        var modifierInputs = inputs
        modifierInputs.base = inputs.base.child(at: 1)
        return Modifier.makeDebuggableViewList(
            modifier: modifier.modifier,
            inputs: modifierInputs
        ) { inputs in
            var inputs = inputs
            inputs.base = inputs.base.child(at: 0)
            return Content.makeDebuggableViewList(
                modifier: modifier.content,
                inputs: inputs,
                body: body
            )
        }
    }

    public static func _viewListCount(
        inputs: _ViewListCountInputs,
        body: (_ViewListCountInputs) -> Int?
    ) -> Int? {
        Modifier._viewListCount(inputs: inputs) {
            Content._viewListCount(inputs: $0, body: body)
        }
    }
}

public struct EmptyModifier: PrimitiveViewModifier {
    public static let identity = EmptyModifier()

    public init() {}

    public static func _makeView(
        modifier: Self,
        inputs: _ViewInputs,
        body: @escaping (_ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        body(inputs)
    }

    public static func _makeViewList(
        modifier: Self,
        inputs: _ViewListInputs,
        body: @escaping (_ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        body(inputs)
    }
}

extension View {
    public func modifier<Modifier: ViewModifier>(
        _ modifier: Modifier
    ) -> ModifiedContent<Self, Modifier> {
        ModifiedContent(content: self, modifier: modifier)
    }
}

extension ViewModifier {
    public func concat<Modifier>(_ modifier: Modifier) -> ModifiedContent<Self, Modifier> {
        ModifiedContent(content: self, modifier: modifier)
    }
}
