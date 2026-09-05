//
//  EmbeddedStackLayout.swift
//  EmbeddedSwiftUICore

public struct _StackLayoutCache {
    var sizes: [EmbeddedSize] = []
    var proposals: [ProposedViewSize] = []
    var gaps: [Int32] = []
}

struct EmbeddedStackLayout {
    let vertical: Bool
    let spacing: Int32?
    let alignment: Alignment
    func major(_ size: EmbeddedSize) -> Int32 {
        vertical ? size.height : size.width
    }
    func minor(_ size: EmbeddedSize) -> Int32 {
        vertical ? size.width : size.height
    }
    func proposal(major: Int32?, cross: Int32?) -> ProposedViewSize {
        vertical ? .init(width: cross, height: major) : .init(width: major, height: cross)
    }
    func measure(
        _ offered: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout _StackLayoutCache
    ) -> EmbeddedSize {
        let count = subviews.count
        guard count > 0 else { cache = .init(); return .zero }
        let available = vertical ? offered.height : offered.width
        let cross = vertical ? offered.width : offered.height
        cache.sizes = Array(repeating: .zero, count: count)
        cache.proposals = Array(repeating: .unspecified, count: count)
        // Allocate less-flexible children first. Stable order breaks ties.
        var flexibility = Array(repeating: Int32(0), count: count)
        var minimumSizes = Array(repeating: Int32(0), count: count)
        var order = Array(0..<count)
        // Range probes only rank competing children. Skipping them for one
        // child avoids exponential measurements in deeply nested stacks.
        if available != nil, count > 1 {
            for index in 0..<count {
                let minimum = subviews[index].sizeThatFits(
                    proposal(major: 0, cross: cross)
                )
                let maximum = subviews[index].sizeThatFits(
                    proposal(major: subviews.maximumDimension, cross: cross)
                )
                minimumSizes[index] = major(minimum)
                flexibility[index] = max(0, major(maximum) - major(minimum))
            }
            for end in 1..<count {
                var index = end
                while index > 0 && (
                    subviews[order[index]].priority > subviews[order[index - 1]].priority
                        || (subviews[order[index]].priority == subviews[order[index - 1]].priority
                            && flexibility[order[index]] < flexibility[order[index - 1]])
                ) {
                    order.swapAt(index, index - 1); index -= 1
                }
            }
        }
        cache.gaps = (0..<max(0, count - 1)).map {
            spacing ?? subviews[$0].spacing.distance(
                to: subviews[$0 + 1].spacing, along: vertical ? .vertical : .horizontal
            )
        }
        let gaps = cache.gaps.reduce(0, +)
        var remaining = Int64(available ?? 0) - Int64(gaps)
        var reservedMinimum = minimumSizes.reduce(Int64(0)) { $0 + Int64($1) }
        var groupStart = 0
        while groupStart < count {
            let priority = subviews[order[groupStart]].priority
            var groupEnd = groupStart + 1
            while groupEnd < count, subviews[order[groupEnd]].priority == priority {
                groupEnd += 1
            }
            for position in groupStart..<groupEnd {
                reservedMinimum -= Int64(minimumSizes[order[position]])
            }
            // Embedded adaptation: retain upstream priority-group allocation
            // with integer probes, reserving lower-priority minima first.
            var groupRemaining = remaining - reservedMinimum
            for position in groupStart..<groupEnd {
                let index = order[position]
                let share = max(0, groupRemaining / Int64(groupEnd - position))
                let childProposal = proposal(
                    major: available == nil ? nil : Int32(clamping: share), cross: cross
                )
                let size = subviews[index].sizeThatFits(childProposal)
                cache.proposals[index] = childProposal
                cache.sizes[index] = size
                groupRemaining -= Int64(major(size))
                remaining -= Int64(major(size))
            }
            groupStart = groupEnd
        }
        var main = gaps, other: Int32 = 0
        for size in cache.sizes {
            main += major(size)
            other = max(other, minor(size))
        }
        return vertical ? .init(width: other, height: main) : .init(width: main, height: other)
    }
    func place(
        _ bounds: EmbeddedRect,
        subviews: LayoutSubviews,
        cache: _StackLayoutCache
    ) {
        var cursor = vertical ? bounds.y : bounds.x
        for index in 0..<subviews.count {
            let size = cache.sizes[index]
            let aligned = alignment.rect(dimensions: subviews[index].dimensions(in: cache.proposals[index]), in: bounds)
            subviews[index].place(
                at: EmbeddedPoint(
                    x: vertical ? aligned.x : cursor,
                    y: vertical ? cursor : aligned.y
                ),
                proposal: cache.proposals[index]
            )
            cursor += major(size) + (index < cache.gaps.count ? cache.gaps[index] : 0)
        }
    }
}
