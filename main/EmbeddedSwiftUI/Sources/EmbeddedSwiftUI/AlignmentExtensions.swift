extension Alignment: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.horizontal == rhs.horizontal && lhs.vertical == rhs.vertical
    }
}

extension Alignment {
    public static var leading: Alignment { .init(horizontal: .leading, vertical: .center) }
    public static var trailing: Alignment { .init(horizontal: .trailing, vertical: .center) }
    public static var top: Alignment { .init(horizontal: .center, vertical: .top) }
    public static var bottom: Alignment { .init(horizontal: .center, vertical: .bottom) }
    public static var topTrailing: Alignment { .init(horizontal: .trailing, vertical: .top) }
    public static var bottomLeading: Alignment { .init(horizontal: .leading, vertical: .bottom) }
}

public enum Edge {
    public struct Set: OptionSet, Equatable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
        public static let top = Edge.Set(rawValue: 1 << 0)
        public static let leading = Edge.Set(rawValue: 1 << 1)
        public static let bottom = Edge.Set(rawValue: 1 << 2)
        public static let trailing = Edge.Set(rawValue: 1 << 3)
        public static let horizontal = Edge.Set([.leading, .trailing])
        public static let vertical = Edge.Set([.top, .bottom])
        public static let all = Edge.Set([.horizontal, .vertical])
    }
}
