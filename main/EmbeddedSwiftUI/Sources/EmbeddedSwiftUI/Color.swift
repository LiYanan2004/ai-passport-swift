//
//  EmbeddedColor.swift
//  EmbeddedSwiftUICore

public enum SystemColorType: Equatable, Sendable {
    case black, white, red, green, blue, yellow, orange, purple, gray
}

public protocol SystemColorDefinition {
    static func value(for type: SystemColorType, environment: EnvironmentValues) -> Color.Resolved
}

/// Constant colors keep their components; system colors resolve in the adaptor.
public struct Color: PrimitiveView, UnaryView, Equatable, Sendable {
    public struct Resolved: Equatable, Sendable {
        public var rgb: UInt32
        public var opacity: UInt8

        public init(rgb: UInt32, opacity: UInt8 = 255) {
            self.rgb = rgb
            self.opacity = opacity
        }
    }

    private enum Storage: Equatable, Sendable {
        case constant(Resolved)
        case system(SystemColorType)
    }

    private let storage: Storage

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        storage = .constant(Resolved(
            rgb: UInt32(Self.component(red)) << 16 | UInt32(Self.component(green)) << 8 | UInt32(Self.component(blue)),
            opacity: Self.component(opacity)
        ))
    }

    public init(white: Double, opacity: Double = 1) {
        self.init(red: white, green: white, blue: white, opacity: opacity)
    }

    private init(system: SystemColorType) {
        storage = .system(system)
    }

    private static func component(_ value: Double) -> UInt8 {
        if value.isNaN || value <= 0 {
            return 0
        }
        if value >= 1 {
            return 255
        }
        return UInt8(value * 255 + 0.5)
    }

    public static let black = Color(system: .black)
    public static let white = Color(system: .white)
    public static let red = Color(system: .red)
    public static let green = Color(system: .green)
    public static let blue = Color(system: .blue)
    public static let yellow = Color(system: .yellow)
    public static let orange = Color(system: .orange)
    public static let purple = Color(system: .purple)
    public static let gray = Color(system: .gray)
    public static let clear = Color(white: 0, opacity: 0)

    package func resolve(in configuration: RendererConfiguration) -> Resolved {
        switch storage {
        case let .constant(value): return value
        case let .system(type): return configuration.systemColor(type)
        }
    }

    public func resolve(in environment: EnvironmentValues) -> Resolved {
        switch storage {
        case let .constant(value): return value
        case let .system(type):
            guard let definition = environment.systemColorDefinition else {
                preconditionFailure("System colors require a renderer color definition")
            }
            return definition(type)
        }
    }

    @_disfavoredOverload
    public init(rgb: UInt32, opacity: UInt8 = 255) {
        storage = .constant(Resolved(rgb: rgb, opacity: opacity))
    }

    public static func _makeView(view: Self, inputs: _ViewInputs) -> _ViewOutputs {
        _ViewOutputs(displayList: DisplayList(commands: [
            .beginContainer(.color(view)),
            .endContainer,
        ]))
    }
}
