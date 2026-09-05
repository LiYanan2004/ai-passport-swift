// Embedded adaptation of OpenSwiftUI's AppearanceActionModifier.

/// A modifier that triggers actions when its view appears and disappears.
public struct _AppearanceActionModifier: PrimitiveViewModifier {
    public var appear: (() -> Void)?
    public var disappear: (() -> Void)?
    package var phase = ViewPhase()

    public init(
        appear: (() -> Void)? = nil,
        disappear: (() -> Void)? = nil
    ) {
        self.appear = appear
        self.disappear = disappear
    }

    public static func _makeView(
        modifier: Self,
        inputs: _ViewInputs,
        body: @escaping (_ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var outputs = body(inputs)
        var displayList = DisplayList()
        var modifier = modifier
        modifier.phase = inputs.phase
        displayList.append(.appearance(modifier))
        displayList.append(outputs.displayList)
        outputs.displayList = displayList
        return outputs
    }

    public static func _makeViewList(
        modifier: Self,
        inputs: _ViewListInputs,
        body: @escaping (_ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        var outputs = body(inputs)
        var displayList = DisplayList()
        var modifier = modifier
        modifier.phase = inputs.base.phase
        displayList.append(.appearance(modifier))
        displayList.append(outputs.displayList)
        outputs.displayList = displayList
        return outputs
    }
}

extension View {
    public func onAppear(perform action: (() -> Void)? = nil) -> some View {
        modifier(_AppearanceActionModifier(appear: action, disappear: nil))
    }

    public func onDisappear(perform action: (() -> Void)? = nil) -> some View {
        modifier(_AppearanceActionModifier(appear: nil, disappear: action))
    }
}
