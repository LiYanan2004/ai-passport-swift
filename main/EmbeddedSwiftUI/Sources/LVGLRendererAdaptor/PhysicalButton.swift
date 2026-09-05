import EmbeddedSwiftUI

public enum PhysicalButton: Equatable {
    case up
    case down
    case ok

    public init?(bspValue: Int32) {
        switch bspValue {
        case 0: self = .up
        case 1: self = .down
        case 2: self = .ok
        default: return nil
        }
    }
}

package struct _PhysicalButtonModifier: PrimitiveViewModifier, MultiViewModifier {
    let button: PhysicalButton
    let action: () -> Void

    package static func _makeView(
        modifier: Self,
        inputs: _ViewInputs,
        body: @escaping (_ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var outputs = body(inputs)
        outputs.viewResponders.insert(
            ViewResponder(_PhysicalButtonAction(
                button: modifier.button,
                action: modifier.action
            )),
            at: 0
        )
        return outputs
    }

    package static func _makeViewList(
        modifier: Self,
        inputs: _ViewListInputs,
        body: @escaping (_ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        var outputs = body(inputs)
        outputs.viewResponders.insert(
            ViewResponder(_PhysicalButtonAction(
                button: modifier.button,
                action: modifier.action
            )),
            at: 0
        )
        return outputs
    }
}

package struct _PhysicalButtonAction {
    let button: PhysicalButton
    let action: () -> Void
}

extension View {
    public func onPhysicalButton(
        _ button: PhysicalButton,
        perform action: @escaping () -> Void
    ) -> some View {
        modifier(_PhysicalButtonModifier(button: button, action: action))
    }
}
