//
//  EmbeddedViewPair.swift
//  EmbeddedSwiftUICore

/// Builder list storage: flatten siblings for the enclosing Layout container.
public struct _ViewPair<First: View, Second: View>: PrimitiveView, MultiView {
    // Embedded adaptation: OpenSwiftUI's tuple machinery is unavailable and
    // nested value pairs copied all descendants into each RISC-V call frame.
    // Immutable shared storage keeps static pair semantics and structural paths
    // while bounding stack use on the ESP32-C3.
    private final class Storage {
        let first: First
        let second: Second

        init(first: First, second: Second) {
            self.first = first
            self.second = second
        }
    }

    // The immutable pair owns its children once; recursively passing a View
    // must not copy every descendant into each call frame.
    private let storage: Storage
    var first: First { storage.first }
    var second: Second { storage.second }

    init(first: First, second: Second) {
        storage = Storage(first: first, second: second)
    }

    public static func _makeView(
        view: Self,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        Self.makeImplicitRoot(view: view, inputs: inputs)
    }

    public static func _makeViewList(
        view: Self,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        var firstInputs = inputs
        firstInputs.base = inputs.base.child(at: 0)
        var outputs = First.makeDebuggableViewList(view: view.first, inputs: firstInputs)
        var secondInputs = inputs
        secondInputs.base = inputs.base.child(at: 1)
        secondInputs.implicitID = outputs.nextImplicitID
        outputs.append(Second.makeDebuggableViewList(view: view.second, inputs: secondInputs))
        return outputs
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        guard let firstCount = First._viewListCount(inputs: inputs),
              let secondCount = Second._viewListCount(inputs: inputs) else {
            return nil
        }
        return firstCount + secondCount
    }
}
