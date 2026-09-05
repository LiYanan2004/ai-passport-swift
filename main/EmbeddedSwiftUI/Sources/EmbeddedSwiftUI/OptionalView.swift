//
//  EmbeddedOptionalView.swift
//  EmbeddedSwiftUICore

extension Optional: View, PrimitiveView where Wrapped: View {
    public static func _makeView(
        view: Self,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        if let content = view {
            return Wrapped.makeDebuggableView(view: content, inputs: inputs.child(at: 0))
        }
        return _ViewOutputs()
    }

    public static func _makeViewList(
        view: Self,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        if let content = view {
            var inputs = inputs
            inputs.base = inputs.base.child(at: 0)
            return Wrapped.makeDebuggableViewList(view: content, inputs: inputs)
        }
        return _ViewListOutputs()
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        Wrapped._viewListCount(inputs: inputs)
    }
}
