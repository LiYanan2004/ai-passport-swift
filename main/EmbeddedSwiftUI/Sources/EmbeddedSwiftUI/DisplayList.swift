// Embedded adaptation of OpenSwiftUICore/Render/DisplayList/DisplayList.swift.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

// Embedded adaptation: upstream display lists participate in a persistent
// graph. This profile emits short-lived construction commands and resolves
// them synchronously into Items before mounting, bounding retained state while
// preserving per-item identity, traits, transactions, and hierarchy.
package struct DisplayList {
    package typealias Identity = _DisplayList_Identity
    package typealias StableIdentity = _DisplayList_StableIdentity
    package typealias StableIdentityMap = _DisplayList_StableIdentityMap
    package typealias StableIdentityRoot = _DisplayList_StableIdentityRoot

    package struct Version: Comparable, Hashable {
        package var value: UInt64 = 0
        package init() {}
        package static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
    }

    package struct Item {
        package enum Value {
            case container(ContainerLayout)
            case text(String, RenderEnvironment)
            case shape(ShapeContent)
            case image(String, Bool)
            case effect(EffectContent)
        }

        package var frame: EmbeddedRect
        package var identity: Identity
        package var stableIdentity: StableIdentity
        package var version: Version
        package var value: Value
        package var children: [Item]
        package var traits: ViewTraitCollection
        package var transaction: Transaction
        package var focusable: Bool?
    }

    package enum Effect {
        case opacity(Double)
        case geometry(ProjectionTransform)
        case clip(_ClipShape, FillStyle)
    }

    package struct EffectContent {
        package let resolve: (EmbeddedSize) -> Effect

        package init<EffectType: _RendererEffect>(_ effect: EffectType) {
            resolve = { effect.effectValue(size: $0) }
        }

        package init<EffectType: GeometryEffect>(_ effect: EffectType) {
            resolve = { .geometry(effect.effectValue(size: $0)) }
        }
    }

    package struct ShapeContent {
        package let path: (ShapeRect) -> Path
        package let sizeThatFits: (ProposedViewSize) -> EmbeddedSize
        package let color: Color?
        package let resolvedColor: (Color) -> Color
        package let renderingStyle: ShapeRenderingStyle

        package init<Content: Shape, Style: ShapeStyle>(
            shape: Content,
            style: Style,
            renderingStyle: ShapeRenderingStyle,
            environment: EnvironmentValues
        ) {
            path = { shape.path(in: $0) }
            sizeThatFits = { shape.sizeThatFits($0) }
            color = style as? Color
            resolvedColor = { foreground in
                style._resolve(in: environment, foreground: environment.resolveForeground(foreground))
            }
            self.renderingStyle = renderingStyle
        }
    }

    package struct AnimationValue {
        let value: Any
        let isEqual: (Any) -> Bool

        package init<Value: Equatable>(_ value: Value) {
            self.value = value
            isEqual = { previous in
                guard let previous = previous as? Value else { return false }
                return previous == value
            }
        }

        package func matches(_ previous: AnimationValue) -> Bool {
            isEqual(previous.value)
        }
    }

    package enum Command {
        case invalid
        indirect case identity(_ViewList_ID, DisplayList)
        case beginIdentity(_ViewList_ID)
        case endIdentity
        case beginImplicitRoot
        case beginContainer(ContainerLayout)
        case endContainer
        case text(String, RenderEnvironment)
        case shape(ShapeContent)
        case image(String, Bool)
        case beginFocusable(Bool)
        case endFocusable
        case beginAnimation(Animation?, AnimationValue)
        case endAnimation
        case appearance(_AppearanceActionModifier)
        case beginTraits(ViewTraitCollection)
        case endTraits
        indirect case effect(EffectContent, DisplayList)
    }

    package var commands: [Command]
    package var items: [Item] = []

    package init(commands: [Command] = []) {
        self.commands = commands
    }

    package init<EffectType: _RendererEffect>(
        effect: EffectType,
        content: DisplayList
    ) {
        commands = [.effect(EffectContent(effect), content)]
    }

    package init<EffectType: GeometryEffect>(
        effect: EffectType,
        content: DisplayList
    ) {
        commands = [.effect(EffectContent(effect), content)]
    }

    package mutating func append(_ command: Command) {
        commands.append(command)
    }

    package mutating func append(_ displayList: DisplayList) {
        commands.append(contentsOf: displayList.commands)
    }

    package var containsRenderableContent: Bool {
        var pending = [self]
        while let list = pending.popLast() {
            for command in list.commands {
                switch command {
                case .text, .image, .shape, .beginContainer, .beginImplicitRoot, .invalid:
                    return true
                case let .identity(_, content), let .effect(_, content):
                    pending.append(content)
                default:
                    break
                }
            }
        }
        return false
    }

    package func identified(by identity: _ViewList_ID) -> Self {
        guard !commands.isEmpty else { return self }
        // Embedded adaptation: upstream identity scopes are graph nodes. Keep
        // the child list nested instead of copying its entire command array at
        // every View boundary; parsing enters the same identity scope in order.
        return Self(commands: [.identity(identity, self)])
    }

    package func withImplicitRoot() -> Self {
        Self(commands: [
            .beginImplicitRoot
        ] + commands + [.endContainer])
    }
}
