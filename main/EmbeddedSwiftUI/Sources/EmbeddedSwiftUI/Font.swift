// Embedded adaptation of EmbeddedSwiftUICore/View/Text/Font/{Font,SystemFont,TextStyle}.swift.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

/// Embedded adaptation: retain upstream system-font entry points but resolve
/// them to the nearest statically linked bitmap face, bounding flash and RAM
/// use on a device without a vector-font engine.
public struct Font: Equatable {
    public enum TextStyle { case largeTitle, title, title2, title3, headline, body, callout, subheadline, footnote, caption, caption2 }
    public let pointSize: Int32
    private init(_ pointSize: Int32) {
        self.pointSize = pointSize
    }
    public static func system(size: Double) -> Font {
        guard size.isFinite else { return .body }
        let sizes: [Int32] = [12, 14, 16, 18, 20, 24, 28]
        var nearest = sizes[0]
        for candidate in sizes.dropFirst() {
            if abs(Double(candidate) - size) < abs(Double(nearest) - size) {
                nearest = candidate
            }
        }
        return Font(nearest)
    }
    public static func system(_ style: TextStyle) -> Font {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .body: return .body
        case .callout: return .callout
        case .subheadline: return .subheadline
        case .footnote: return .footnote
        case .caption: return .caption
        case .caption2: return .caption2
        }
    }
    public static let largeTitle = Font(28)
    public static let title = Font(24)
    public static let title2 = Font(20)
    public static let title3 = Font(18)
    public static let headline = Font(18)
    public static let body = Font(16)
    public static let callout = Font(16)
    public static let subheadline = Font(14)
    public static let footnote = Font(12)
    public static let caption = Font(12)
    public static let caption2 = Font(12)
}
