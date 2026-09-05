// Embedded adaptation of EmbeddedSwiftUICore/View/{ConditionalContent,OptionalView,EmptyView}.swift.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

public struct _ConditionalContent<TrueContent, FalseContent> {
    public enum Storage {
        case trueContent(TrueContent)
        case falseContent(FalseContent)
    }

    public let storage: Storage
}

extension _ConditionalContent: View, PrimitiveView
    where TrueContent: View, FalseContent: View {
    public static func _makeView(
        view: Self,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        switch view.storage {
        case let .trueContent(content):
            return TrueContent.makeDebuggableView(view: content, inputs: inputs.child(at: 0))
        case let .falseContent(content):
            return FalseContent.makeDebuggableView(view: content, inputs: inputs.child(at: 1))
        }
    }

    public static func _makeViewList(
        view: Self,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        switch view.storage {
        case let .trueContent(content):
            var inputs = inputs
            inputs.base = inputs.base.child(at: 0)
            return TrueContent.makeDebuggableViewList(view: content, inputs: inputs)
        case let .falseContent(content):
            var inputs = inputs
            inputs.base = inputs.base.child(at: 1)
            return FalseContent.makeDebuggableViewList(view: content, inputs: inputs)
        }
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        guard let trueCount = TrueContent._viewListCount(inputs: inputs),
              let falseCount = FalseContent._viewListCount(inputs: inputs),
              trueCount == falseCount else {
            return nil
        }
        return trueCount
    }

}

public struct EmptyView: PrimitiveView {
    public init() {

    }
    public static func _makeView(
        view: Self,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        _ViewOutputs()
    }
    public static func _makeViewList(
        view: Self,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        _ViewListOutputs()
    }
    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? { 0 }
}
