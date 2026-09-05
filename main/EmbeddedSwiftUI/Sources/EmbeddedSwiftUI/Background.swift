//
//  EmbeddedBackground.swift
//  EmbeddedSwiftUICore

public struct _BackgroundModifier<Background: View>: PrimitiveViewModifier, MultiViewModifier {
    public var background: Background
    public var alignment: Alignment

    public init(background: Background, alignment: Alignment = .center) {
        self.background = background
        self.alignment = alignment
    }

    public static func _makeView(
        modifier: Self,
        inputs: _ViewInputs,
        body: @escaping (_ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var outputs = body(inputs.child(at: 0))
        var displayList = DisplayList()
        if let color = modifier.background as? Color {
            displayList.append(.beginContainer(.background(color)))
            displayList.append(outputs.displayList)
        } else {
            let backgroundOutputs = Background.makeDebuggableView(
                view: modifier.background,
                inputs: inputs.child(at: 1)
            )
            displayList.append(.beginContainer(.secondaryBackground(modifier.alignment)))
            displayList.append(backgroundOutputs.displayList)
            displayList.append(outputs.displayList)
            outputs.viewResponders =
                backgroundOutputs.viewResponders + outputs.viewResponders
        }
        displayList.append(.endContainer)
        outputs.displayList = displayList
        return outputs
    }

    public static func _makeViewList(
        modifier: Self,
        inputs: _ViewListInputs,
        body: @escaping (_ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        let bodyOutputs = body(inputs)
        let outputs = Self._makeView(
            modifier: modifier,
            inputs: inputs.base
        ) { _ in
            _ViewOutputs(
                displayList: bodyOutputs.displayList,
                viewResponders: bodyOutputs.viewResponders
            )
        }
        return _ViewListOutputs(outputs)
    }
}

extension View {
    public func background<Background: View>(
        alignment: Alignment = .center,
        @ViewBuilder content: @escaping () -> Background
    ) -> some View {
        modifier(_BackgroundModifier(background: content(), alignment: alignment))
    }

    public func background<Background: View>(
        @ViewBuilder _ background: @escaping () -> Background
    ) -> some View {
        self.background(background())
    }

    public func background<Background: View>(_ background: Background) -> some View {
        modifier(_BackgroundModifier(background: background))
    }
}
