// Embedded adaptation of OpenSwiftUICore/Render/RendererEffect/RendererEffect.swift.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

package protocol _RendererEffect: MultiViewModifier, PrimitiveViewModifier {
    func effectValue(size: EmbeddedSize) -> DisplayList.Effect
    static var preservesEmptyContent: Bool { get }
}

package protocol RendererEffect: Animatable, _RendererEffect {}

extension _RendererEffect {
    package static var preservesEmptyContent: Bool { false }

    // Embedded adaptation: every item has local child coordinates. Archived,
    // flattened and scrapeable graph output is outside this renderer profile;
    // those upstream policy flags have no corresponding input representation.
    package static func _makeRendererEffect(
        effect: Self,
        inputs: _ViewInputs,
        body: @escaping (_ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var outputs = body(inputs)
        if preservesEmptyContent || outputs.displayList.containsRenderableContent {
            outputs.displayList = DisplayList(effect: effect, content: outputs.displayList)
        }
        return outputs
    }

    public static func _makeView(
        modifier: Self,
        inputs: _ViewInputs,
        body: @escaping (_ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        _makeRendererEffect(effect: modifier, inputs: inputs, body: body)
    }

    public static func _makeViewList(
        modifier: Self,
        inputs: _ViewListInputs,
        body: @escaping (_ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        var outputs = body(inputs)
        if preservesEmptyContent || outputs.displayList.containsRenderableContent {
            outputs.displayList = DisplayList(effect: modifier, content: outputs.displayList)
        }
        return outputs
    }

    public static func _viewListCount(
        inputs: _ViewListCountInputs,
        body: (_ViewListCountInputs) -> Int?
    ) -> Int? {
        body(inputs)
    }
}
