import EmbeddedSwiftUI

package enum LVGLSystemColorDefinition: SystemColorDefinition {
    package static func value(
        for type: SystemColorType,
        environment: EnvironmentValues
    ) -> Color.Resolved {
        let rgb: UInt32
        switch type {
        case .black: rgb = 0x000000
        case .white: rgb = 0xffffff
        case .red: rgb = 0xff0000
        case .green: rgb = 0x00ff00
        case .blue: rgb = 0x0000ff
        case .yellow: rgb = 0xffff00
        case .orange: rgb = 0xff8800
        case .purple: rgb = 0x8833ff
        case .gray: rgb = 0x8e8e93
        }
        return Color.Resolved(rgb: rgb)
    }
}
