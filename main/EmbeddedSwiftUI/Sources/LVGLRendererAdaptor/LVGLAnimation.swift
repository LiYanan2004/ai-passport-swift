import EmbeddedSwiftUI

extension Animation {
    public var effectiveDurationMilliseconds: UInt32 {
        lvglMilliseconds(resolvedTiming.duration)
    }

    public var delayMilliseconds: UInt32 {
        lvglMilliseconds(resolvedTiming.delay)
    }

    public var repeatDelayMilliseconds: UInt32 {
        lvglMilliseconds(resolvedTiming.repeatDelay)
    }

    public var repeatCountValue: Int32 {
        switch repetition {
        case .once: return 1
        case let .count(count, _): return Int32(clamping: count)
        case .forever: return -1
        }
    }
}

// LVGL stores duration/elapsed time as Int32 and doubles duration when
// handling repeat overruns. Keep that native arithmetic representable.
private let maximumLVGLAnimationMilliseconds = UInt32(Int32.max / 2)

private func lvglMilliseconds(_ seconds: Double) -> UInt32 {
    guard seconds > 0 else { return 0 }
    return UInt32(min(Double(maximumLVGLAnimationMilliseconds), seconds * 1_000))
}

struct LVGLNodeIdentity: Hashable {
    enum Kind: UInt8, Hashable {
        case stack
        case overlay
        case scroll
        case frame
        case padding
        case background
        case offset
        case opacity
        case scale
        case rotation
        case color
        case clip
        case spacer
        case layout
        case text
        case shape
        case image
    }

    let identity: DisplayList.Identity
    let kind: Kind
}

private struct LVGLAnimationContext {
    let durationMilliseconds: UInt32
    let repeatDelayMilliseconds: UInt32
    let repeatCount: Int32
    let autoreverses: Bool
    let curve: Animation.Curve
    let targetValue: Int32

    init(animation: Animation, targetValue: Int32) {
        durationMilliseconds = animation.effectiveDurationMilliseconds
        repeatDelayMilliseconds = animation.repeatDelayMilliseconds
        repeatCount = animation.repeatCountValue
        autoreverses = animation.autoreverses
        curve = animation.curve
        self.targetValue = targetValue
    }

    func matches(_ animation: Animation, targetValue: Int32) -> Bool {
        self.targetValue == targetValue
            && durationMilliseconds == animation.effectiveDurationMilliseconds
            && repeatDelayMilliseconds == animation.repeatDelayMilliseconds
            && repeatCount == animation.repeatCountValue
            && autoreverses == animation.autoreverses
            && curve == animation.curve
    }

    func value(at elapsedMilliseconds: UInt32, from start: Int32, to end: Int32) -> Int32 {
        let duration = durationMilliseconds
        guard duration > 0 else { return end }
        let cycle = duration + repeatDelayMilliseconds
        var sequence = elapsedMilliseconds / cycle
        var elapsed = elapsedMilliseconds % cycle
        if repeatCount > 0, sequence >= UInt32(repeatCount) {
            sequence = UInt32(repeatCount - 1)
            elapsed = duration
        }
        elapsed = min(elapsed, duration)
        let progress = Double(elapsed) / Double(duration)
        var curved: Double
        switch curve {
        case .linear: curved = bezier(progress, 0, 0, 1, 1)
        case .easeIn: curved = bezier(progress, 0.42, 0, 1, 1)
        case .easeOut: curved = bezier(progress, 0, 0, 0.58, 1)
        case .easeInOut: curved = bezier(progress, 0.42, 0, 0.58, 1)
        case let .timingCurve(firstX, firstY, secondX, secondY):
            curved = bezier(progress, firstX, firstY, secondX, secondY)
        case let .spring(mass, stiffness, damping, initialVelocity):
            curved = spring(Double(elapsed) / 1000, mass, stiffness, damping, initialVelocity)
        }
        if autoreverses, sequence & 1 != 0 {
            curved = 1 - curved
        }

        curved = min(1, max(0, curved))
        return start + Int32((Double(end - start) * curved).rounded())
    }

    private func bezier(
        _ progress: Double, _ firstX: Double, _ firstY: Double,
        _ secondX: Double, _ secondY: Double
    ) -> Double {
        func coordinate(_ parameter: Double, _ first: Double, _ second: Double) -> Double {
            let inverse = 1 - parameter
            return 3 * inverse * inverse * parameter * first
                + 3 * inverse * parameter * parameter * second + parameter * parameter * parameter
        }
        var lower = 0.0
        var upper = 1.0
        for _ in 0..<16 {
            let parameter = (lower + upper) * 0.5
            if coordinate(parameter, firstX, secondX) < progress {
                lower = parameter
            } else {
                upper = parameter
            }
        }
        return coordinate((lower + upper) * 0.5, firstY, secondY)
    }

    private func spring(
        _ elapsed: Double, _ mass: Double, _ stiffness: Double,
        _ damping: Double, _ initialVelocity: Double
    ) -> Double {
        guard mass > 0, stiffness > 0, damping >= 0 else { return 1 }
        let angularFrequency = (stiffness / mass).squareRoot()
        let dampingRatio = damping / (2 * (mass * stiffness).squareRoot())
        if dampingRatio < 1 {
            let decayFrequency = angularFrequency * (1 - dampingRatio * dampingRatio).squareRoot()
            let adjustment = (dampingRatio * angularFrequency - initialVelocity) / decayFrequency
            return 1 - exp(-dampingRatio * angularFrequency * elapsed)
                * (cos(decayFrequency * elapsed) + adjustment * sin(decayFrequency * elapsed))
        }
        return 1 - (1 + (angularFrequency - initialVelocity) * elapsed) * exp(-angularFrequency * elapsed)
    }
}

private struct LVGLSiblingIndexAnimationContext {
    let animation: LVGLAnimationContext
    let previousIndex: Int32
    let targetIndex: Int32
}

/// Applies the same bounded root transition and callback lifetime as the C port.
enum LVGLAnimation {
    static func replaceItems(
        _ previous: OpaquePointer?,
        with next: OpaquePointer,
        identityOf: (OpaquePointer) -> LVGLNodeIdentity?,
        transactionOf: (OpaquePointer) -> Transaction
    ) {
        guard let previous else { return }
        let rootTransaction = transactionOf(next)
        // Embedded adaptation: a root crossfade retains both LVGL trees. When
        // either tree uses a bitmap clip mask, their simultaneous draw layers
        // exceed the fixed no-PSRAM LVGL pool. Fall back to identity-matched
        // local animations and delete the old tree synchronously.
        let canOverlapTrees = !containsBitmapMask(previous) && !containsBitmapMask(next)
        if canOverlapTrees,
           !rootTransaction.disablesAnimations, let animation = rootTransaction.animation,
           !hasMatchingStructure(previous, next, identityOf: identityOf) {
            var pending = [next]
            var uniform = true
            while let node = pending.popLast() {
                if transactionOf(node) != rootTransaction { uniform = false; break }
                for index in 0..<lv_obj_get_child_count(node) {
                    if let child = lv_obj_get_child(node, Int32(index)) { pending.append(child) }
                }
            }
            if uniform {
                replace(previous, with: next, animation: animation, identityOf: identityOf)
                return
            }
        }
        lv_anim_refr_now()
        lv_obj_update_layout(previous)
        lv_obj_update_layout(next)
        let previousSiblingIndices = siblingIndices(in: previous, identityOf: identityOf)
        let nextSiblingIndices = siblingIndices(in: next, identityOf: identityOf)
        var oldNodes: [LVGLNodeIdentity: OpaquePointer] = [:]
        var pending = [previous]
        while let node = pending.popLast() {
            if let identity = identityOf(node) { oldNodes[identity] = node }
            for index in 0..<lv_obj_get_child_count(node) {
                if let child = lv_obj_get_child(node, Int32(index)) { pending.append(child) }
            }
        }
        var nextNodes: [(OpaquePointer, Int32, Int32)] = [(next, 0, 0)]
        while let (node, inheritedX, inheritedY) = nextNodes.popLast() {
            var deltaX: Int32 = 0
            var deltaY: Int32 = 0
            let transaction = transactionOf(node)
            if let identity = identityOf(node), let old = oldNodes[identity] {
                var oldBounds = lv_area_t()
                var newBounds = lv_area_t()
                lv_obj_get_coords(old, &oldBounds)
                lv_obj_get_coords(node, &newBounds)
                deltaX = oldBounds.x1 - newBounds.x1
                deltaY = oldBounds.y1 - newBounds.y1
                animateMatchingGeometry(
                    from: old, to: node,
                    animation: transaction.disablesAnimations ? nil : transaction.animation,
                    identityOf: identityOf,
                    previousSiblingIndices: previousSiblingIndices,
                    nextSiblingIndices: nextSiblingIndices,
                    inheritedDeltaX: inheritedX, inheritedDeltaY: inheritedY, recurse: false
                )
            }
            for index in 0..<lv_obj_get_child_count(node) {
                if let child = lv_obj_get_child(node, Int32(index)) {
                    nextNodes.append((child, deltaX, deltaY))
                }
            }
        }
        lv_obj_delete(previous)
    }

    private static func containsBitmapMask(_ root: OpaquePointer) -> Bool {
        var pending = [root]
        while let node = pending.popLast() {
            if lv_obj_get_style_bitmap_mask_src(node, LV_PART_MAIN) != nil {
                return true
            }
            for index in 0..<lv_obj_get_child_count(node) {
                if let child = lv_obj_get_child(node, Int32(index)) {
                    pending.append(child)
                }
            }
        }
        return false
    }

    static func removeTree(_ root: OpaquePointer) {
        guard let parent = lv_obj_get_parent(root) else {
            lv_obj_delete(root)
            return
        }
        while lv_obj_get_child_count(parent) > 0 {
            if let child = lv_obj_get_child(parent, 0) {
                lv_obj_delete(child)
            }
        }
    }

    static func replace(
        _ previous: OpaquePointer?,
        with next: OpaquePointer,
        animation: Animation,
        identityOf: (OpaquePointer) -> LVGLNodeIdentity?
    ) {
        let duration = animation.effectiveDurationMilliseconds
        guard duration > 0 else {
            if let previous {
                lv_obj_delete(previous)
            }

            return
        }
        if previous != nil {
            // Resolve active effects at one timestamp before sampling the old
            // tree, matching SwiftUI's presentation-state animation handoff.
            lv_anim_refr_now()
        }
        if let previous, hasMatchingStructure(previous, next, identityOf: identityOf) {
            lv_obj_update_layout(previous)
            lv_obj_update_layout(next)
            animateMatchingGeometry(
                from: previous,
                to: next,
                animation: animation,
                identityOf: identityOf,
                previousSiblingIndices: siblingIndices(in: previous, identityOf: identityOf),
                nextSiblingIndices: siblingIndices(in: next, identityOf: identityOf)
            )
            lv_obj_delete(previous)
            return
        }
        if let parent = lv_obj_get_parent(next) {
            var index: Int32 = 0
            while index < lv_obj_get_child_count(parent) {
                let child = lv_obj_get_child(parent, index)
                if child != previous, child != next {
                    lv_obj_delete(child)
                } else {
                    index += 1
                }
            }
        }
        guard let storage = malloc(MemoryLayout<LVGLAnimationContext>.stride) else {
            if let previous {
                lv_obj_delete(previous)
            }

            return
        }
        let context = storage.bindMemory(to: LVGLAnimationContext.self, capacity: 1)
        context.initialize(to: LVGLAnimationContext(animation: animation, targetValue: 255))
        var transition = lv_anim_t()
        lv_anim_init(&transition)
        lv_anim_set_var(&transition, UnsafeMutableRawPointer(next))
        lv_anim_set_exec_cb(&transition, setAnimationOpacity)
        lv_anim_set_values(&transition, 0, 255)
        lv_anim_set_delay(&transition, animation.delayMilliseconds)
        lv_anim_set_path_cb(&transition, animationPath)
        lv_anim_set_user_data(&transition, storage)
        lv_anim_set_deleted_cb(&transition, releaseAnimationContext)
        let repeatCount = animation.repeatCountValue
        if repeatCount < 0 {
            lv_anim_set_duration(&transition, duration)
            lv_anim_set_repeat_delay(&transition, animation.repeatDelayMilliseconds)
            lv_anim_set_repeat_count(&transition, UInt32(LV_ANIM_REPEAT_INFINITE))
            if animation.autoreverses {
                lv_anim_set_reverse_duration(&transition, duration)
                lv_anim_set_reverse_delay(&transition, animation.repeatDelayMilliseconds)
            }
        } else {
            let totalDuration = UInt64(duration) * UInt64(repeatCount)
                + UInt64(animation.repeatDelayMilliseconds) * UInt64(repeatCount - 1)
            lv_anim_set_duration(&transition, UInt32(min(UInt64(maximumLVGLAnimationMilliseconds), totalDuration)))
        }
        guard lv_anim_start(&transition) != nil else {
            context.deinitialize(count: 1)
            free(storage)
            lv_obj_set_style_opa(next, 255, 0)
            if let previous {
                lv_obj_delete(previous)
            }

            return
        }
        if let previous {
            var removal = lv_anim_t()
            lv_anim_init(&removal)
            lv_anim_set_var(&removal, UnsafeMutableRawPointer(previous))
            lv_anim_set_exec_cb(&removal, setAnimationOpacity)
            lv_anim_set_values(&removal, 255, 0)
            lv_anim_set_duration(&removal, duration)
            lv_anim_set_delay(&removal, animation.delayMilliseconds)
            lv_anim_set_completed_cb(&removal, deleteAnimatedObject)
            if lv_anim_start(&removal) == nil {
                lv_obj_delete(previous)
            }
        }
    }

    private static func hasMatchingStructure(
        _ previous: OpaquePointer,
        _ next: OpaquePointer,
        identityOf: (OpaquePointer) -> LVGLNodeIdentity?
    ) -> Bool {
        guard let childPairs = matchingChildren(
            from: previous,
            to: next,
            identityOf: identityOf
        ) else {
            return false
        }
        for pair in childPairs {
            guard hasMatchingStructure(
                pair.previous,
                pair.next,
                identityOf: identityOf
            ) else {
                return false
            }
        }
        return true
    }

    private static func matchingChildren(
        from previous: OpaquePointer,
        to next: OpaquePointer,
        identityOf: (OpaquePointer) -> LVGLNodeIdentity?
    ) -> [(previous: OpaquePointer, next: OpaquePointer)]? {
        let childCount = lv_obj_get_child_count(previous)
        guard childCount == lv_obj_get_child_count(next) else { return nil }
        var nextChildrenByIdentity: [LVGLNodeIdentity: OpaquePointer] = [:]
        for index in 0..<childCount {
            guard let nextChild = lv_obj_get_child(next, Int32(index)),
                  let identity = identityOf(nextChild) else {
                return nil
            }
            nextChildrenByIdentity[identity] = nextChild
        }
        var pairs: [(previous: OpaquePointer, next: OpaquePointer)] = []
        pairs.reserveCapacity(Int(childCount))
        for index in 0..<childCount {
            guard let previousChild = lv_obj_get_child(previous, Int32(index)),
                  let identity = identityOf(previousChild),
                  let nextChild = nextChildrenByIdentity.removeValue(forKey: identity) else {
                return nil
            }
            pairs.append((previous: previousChild, next: nextChild))
        }
        return nextChildrenByIdentity.isEmpty ? pairs : nil
    }

    private static func siblingIndices(
        in root: OpaquePointer,
        identityOf: (OpaquePointer) -> LVGLNodeIdentity?
    ) -> [LVGLNodeIdentity: Int32] {
        var indices: [LVGLNodeIdentity: Int32] = [:]
        var pending = [root]
        while let parent = pending.popLast() {
            for index in 0..<lv_obj_get_child_count(parent) {
                guard let child = lv_obj_get_child(parent, Int32(index)) else { continue }
                if let identity = identityOf(child) {
                    indices[identity] = Int32(index)
                }
                pending.append(child)
            }
        }
        return indices
    }

    private static func animateMatchingGeometry(
        from previous: OpaquePointer,
        to next: OpaquePointer,
        animation: Animation?,
        identityOf: (OpaquePointer) -> LVGLNodeIdentity?,
        previousSiblingIndices: [LVGLNodeIdentity: Int32] = [:],
        nextSiblingIndices: [LVGLNodeIdentity: Int32] = [:],
        inheritedDeltaX: Int32 = 0,
        inheritedDeltaY: Int32 = 0,
        recurse: Bool = true
    ) {
        var previousCoordinates = lv_area_t()
        var nextCoordinates = lv_area_t()
        lv_obj_get_coords(previous, &previousCoordinates)
        lv_obj_get_coords(next, &nextCoordinates)
        let deltaX = previousCoordinates.x1 - nextCoordinates.x1
        let deltaY = previousCoordinates.y1 - nextCoordinates.y1
        let previousWidth = previousCoordinates.x2 - previousCoordinates.x1 + 1
        let previousHeight = previousCoordinates.y2 - previousCoordinates.y1 + 1
        let nextWidth = nextCoordinates.x2 - nextCoordinates.x1 + 1
        let nextHeight = nextCoordinates.y2 - nextCoordinates.y1 + 1
        let nextTranslationX = lv_obj_get_style_translate_x(next, LV_PART_MAIN)
        let nextTranslationY = lv_obj_get_style_translate_y(next, LV_PART_MAIN)
        let previousScaleX = lv_obj_get_style_transform_scale_x(previous, LV_PART_MAIN)
        let previousScaleY = lv_obj_get_style_transform_scale_y(previous, LV_PART_MAIN)
        let nextScaleX = lv_obj_get_style_transform_scale_x(next, LV_PART_MAIN)
        let nextScaleY = lv_obj_get_style_transform_scale_y(next, LV_PART_MAIN)
        let previousRotation = lv_obj_get_style_transform_rotation(previous, LV_PART_MAIN)
        let nextRotation = lv_obj_get_style_transform_rotation(next, LV_PART_MAIN)
        let previousPivotX = lv_obj_get_style_transform_pivot_x(previous, LV_PART_MAIN)
        let previousPivotY = lv_obj_get_style_transform_pivot_y(previous, LV_PART_MAIN)
        let nextPivotX = lv_obj_get_style_transform_pivot_x(next, LV_PART_MAIN)
        let nextPivotY = lv_obj_get_style_transform_pivot_y(next, LV_PART_MAIN)
        let previousOpacity = lv_obj_get_style_opa(previous, LV_PART_MAIN)
        let nextOpacity = lv_obj_get_style_opa(next, LV_PART_MAIN)
        let previousLayeredOpacity = lv_obj_get_style_opa_layered(previous, LV_PART_MAIN)
        let nextLayeredOpacity = lv_obj_get_style_opa_layered(next, LV_PART_MAIN)
        let previousBackgroundColor = lv_obj_get_style_bg_color(previous, LV_PART_MAIN)
        let nextBackgroundColor = lv_obj_get_style_bg_color(next, LV_PART_MAIN)
        let previousBackgroundOpacity = lv_obj_get_style_bg_opa(previous, LV_PART_MAIN)
        let nextBackgroundOpacity = lv_obj_get_style_bg_opa(next, LV_PART_MAIN)
        let childPairs = recurse ? (matchingChildren(
            from: previous,
            to: next,
            identityOf: identityOf
        ) ?? []) : []
        for pair in childPairs {
            animateMatchingGeometry(
                from: pair.previous,
                to: pair.next,
                animation: animation,
                identityOf: identityOf,
                previousSiblingIndices: previousSiblingIndices,
                nextSiblingIndices: nextSiblingIndices,
                inheritedDeltaX: deltaX,
                inheritedDeltaY: deltaY
            )
        }
        animateValue(
            of: next,
            replacing: previous,
            from: previousWidth,
            to: nextWidth,
            animation: animation,
            setter: setAnimationWidth
        )
        animateValue(
            of: next,
            replacing: previous,
            from: previousHeight,
            to: nextHeight,
            animation: animation,
            setter: setAnimationHeight
        )
        if previousBackgroundOpacity > 0 || nextBackgroundOpacity > 0 {
            animateValue(
                of: next,
                replacing: previous,
                from: Int32(previousBackgroundColor.red),
                to: Int32(nextBackgroundColor.red),
                animation: animation,
                setter: setAnimationBackgroundRed
            )
            animateValue(
                of: next,
                replacing: previous,
                from: Int32(previousBackgroundColor.green),
                to: Int32(nextBackgroundColor.green),
                animation: animation,
                setter: setAnimationBackgroundGreen
            )
            animateValue(
                of: next,
                replacing: previous,
                from: Int32(previousBackgroundColor.blue),
                to: Int32(nextBackgroundColor.blue),
                animation: animation,
                setter: setAnimationBackgroundBlue
            )
            animateValue(
                of: next,
                replacing: previous,
                from: Int32(previousBackgroundOpacity),
                to: Int32(nextBackgroundOpacity),
                animation: animation,
                setter: setAnimationBackgroundOpacity
            )
        }
        animateValue(
            of: next,
            replacing: previous,
            from: Int32(previousOpacity),
            to: Int32(nextOpacity),
            animation: animation,
            setter: setAnimationOpacity
        )
        animateValue(
            of: next,
            replacing: previous,
            from: Int32(previousLayeredOpacity),
            to: Int32(nextLayeredOpacity),
            animation: animation,
            setter: setAnimationLayeredOpacity
        )
        animateValue(
            of: next,
            replacing: previous,
            from: nextTranslationX + deltaX - inheritedDeltaX,
            to: nextTranslationX,
            animation: animation,
            setter: setAnimationTranslationX
        )
        animateValue(
            of: next,
            replacing: previous,
            from: nextTranslationY + deltaY - inheritedDeltaY,
            to: nextTranslationY,
            animation: animation,
            setter: setAnimationTranslationY
        )
        if previousScaleX == previousScaleY && nextScaleX == nextScaleY {
            animateValue(
                of: next,
                replacing: previous,
                from: previousScaleX,
                to: nextScaleX,
                animation: animation,
                setter: setAnimationUniformScale
            )
        } else {
            animateValue(
                of: next,
                replacing: previous,
                from: previousScaleX,
                to: nextScaleX,
                animation: animation,
                setter: setAnimationScaleX
            )
            animateValue(
                of: next,
                replacing: previous,
                from: previousScaleY,
                to: nextScaleY,
                animation: animation,
                setter: setAnimationScaleY
            )
        }
        animateValue(
            of: next,
            replacing: previous,
            from: previousRotation,
            to: nextRotation,
            animation: animation,
            setter: setAnimationRotation
        )
        animateValue(
            of: next,
            replacing: previous,
            from: previousPivotX,
            to: nextPivotX,
            animation: animation,
            setter: setAnimationPivotX
        )
        animateValue(
            of: next,
            replacing: previous,
            from: previousPivotY,
            to: nextPivotY,
            animation: animation,
            setter: setAnimationPivotY
        )
        if let identity = identityOf(next),
           let previousSiblingIndex = previousSiblingIndices[identity],
           let nextSiblingIndex = nextSiblingIndices[identity] {
            animateSiblingIndex(
                of: next,
                replacing: previous,
                previousIndex: previousSiblingIndex,
                targetIndex: nextSiblingIndex,
                animation: animation,
            )
        }
    }

    private static func animateSiblingIndex(
        of object: OpaquePointer,
        replacing previous: OpaquePointer,
        previousIndex: Int32,
        targetIndex: Int32,
        animation: Animation?
    ) {
        guard previousIndex != targetIndex, let animation else { return }
        if let active = lv_anim_get(
            UnsafeMutableRawPointer(previous), setAnimationSiblingIndexProgress
        ), let storage = active.pointee.user_data {
            let context = storage.assumingMemoryBound(
                to: LVGLSiblingIndexAnimationContext.self
            ).pointee
            if context.previousIndex == previousIndex,
               context.targetIndex == targetIndex,
               context.animation.matches(animation, targetValue: targetIndex) {
                lv_anim_set_var(active, UnsafeMutableRawPointer(object))
                setAnimationSiblingIndexProgress(
                    UnsafeMutableRawPointer(object), active.pointee.current_value
                )
                return
            }
        }
        lv_obj_move_to_index(object, previousIndex)
        guard let storage = malloc(MemoryLayout<LVGLSiblingIndexAnimationContext>.stride) else {
            lv_obj_move_to_index(object, targetIndex)
            return
        }
        let context = storage.bindMemory(to: LVGLSiblingIndexAnimationContext.self, capacity: 1)
        context.initialize(to: LVGLSiblingIndexAnimationContext(
            animation: LVGLAnimationContext(animation: animation, targetValue: targetIndex),
            previousIndex: previousIndex,
            targetIndex: targetIndex
        ))
        var transition = lv_anim_t()
        lv_anim_init(&transition)
        lv_anim_set_var(&transition, UnsafeMutableRawPointer(object))
        lv_anim_set_exec_cb(&transition, setAnimationSiblingIndexProgress)
        lv_anim_set_values(&transition, previousIndex, targetIndex)
        lv_anim_set_duration(&transition, animation.effectiveDurationMilliseconds)
        lv_anim_set_delay(&transition, animation.delayMilliseconds)
        lv_anim_set_path_cb(&transition, lv_anim_path_step)
        lv_anim_set_repeat_delay(&transition, animation.repeatDelayMilliseconds)
        lv_anim_set_user_data(&transition, storage)
        lv_anim_set_deleted_cb(&transition, releaseSiblingIndexAnimationContext)
        let repeatCount = animation.repeatCountValue
        if repeatCount < 0 {
            lv_anim_set_repeat_count(&transition, UInt32(LV_ANIM_REPEAT_INFINITE))
            if animation.autoreverses {
                lv_anim_set_reverse_duration(&transition, animation.effectiveDurationMilliseconds)
                lv_anim_set_reverse_delay(&transition, animation.repeatDelayMilliseconds)
            }
        } else {
            lv_anim_set_repeat_count(&transition, UInt32(max(0, repeatCount)))
            if animation.autoreverses {
                lv_anim_set_reverse_duration(&transition, animation.effectiveDurationMilliseconds)
                lv_anim_set_reverse_delay(&transition, animation.repeatDelayMilliseconds)
            }
        }
        if lv_anim_start(&transition) == nil {
            context.deinitialize(count: 1)
            free(storage)
            lv_obj_move_to_index(object, targetIndex)
        }
    }

    private static func animateValue(
        of object: OpaquePointer,
        replacing previous: OpaquePointer,
        from start: Int32,
        to end: Int32,
        animation: Animation?,
        setter: lv_anim_exec_xcb_t?
    ) {
        // Embedded adaptation: replacing the object tree is bounded by the
        // LVGL pool. Retarget the existing animation in place when its model
        // target is unchanged; LVGL retains delay, time, reverse phase and
        // context ownership without a second interpolation engine.
        if let animation,
           let active = lv_anim_get(UnsafeMutableRawPointer(previous), setter),
           let storage = active.pointee.user_data,
           storage.assumingMemoryBound(to: LVGLAnimationContext.self).pointee.matches(
               animation, targetValue: end
           ) {
            lv_anim_set_var(active, UnsafeMutableRawPointer(object))
            setter?(UnsafeMutableRawPointer(object), active.pointee.current_value)
            return
        }
        guard start != end, let animation else { return }
        setter?(UnsafeMutableRawPointer(object), start)
        guard let storage = malloc(MemoryLayout<LVGLAnimationContext>.stride) else {
            setter?(UnsafeMutableRawPointer(object), end)
            return
        }
        let context = storage.bindMemory(to: LVGLAnimationContext.self, capacity: 1)
        context.initialize(to: LVGLAnimationContext(animation: animation, targetValue: end))
        var transition = lv_anim_t()
        lv_anim_init(&transition)
        lv_anim_set_var(&transition, UnsafeMutableRawPointer(object))
        lv_anim_set_exec_cb(&transition, setter)
        lv_anim_set_values(&transition, start, end)
        lv_anim_set_delay(&transition, animation.delayMilliseconds)
        lv_anim_set_path_cb(&transition, animationPath)
        lv_anim_set_user_data(&transition, storage)
        lv_anim_set_deleted_cb(&transition, releaseAnimationContext)
        let repeatCount = animation.repeatCountValue
        if repeatCount < 0 {
            lv_anim_set_duration(&transition, animation.effectiveDurationMilliseconds)
            lv_anim_set_repeat_delay(&transition, animation.repeatDelayMilliseconds)
            lv_anim_set_repeat_count(&transition, UInt32(LV_ANIM_REPEAT_INFINITE))
            if animation.autoreverses {
                lv_anim_set_reverse_duration(&transition, animation.effectiveDurationMilliseconds)
                lv_anim_set_reverse_delay(&transition, animation.repeatDelayMilliseconds)
            }
        } else {
            let totalDuration = UInt64(animation.effectiveDurationMilliseconds) * UInt64(repeatCount)
                + UInt64(animation.repeatDelayMilliseconds) * UInt64(repeatCount - 1)
            lv_anim_set_duration(&transition, UInt32(min(UInt64(maximumLVGLAnimationMilliseconds), totalDuration)))
        }
        if lv_anim_start(&transition) == nil {
            context.deinitialize(count: 1)
            free(storage)
            setter?(UnsafeMutableRawPointer(object), end)
        }
    }
}

private func setAnimationOpacity(_ object: UnsafeMutableRawPointer?, _ opacity: Int32) {
    if let object {
        lv_obj_set_style_opa(OpaquePointer(object), UInt8(opacity), 0)
    }
}

private func setAnimationLayeredOpacity(_ object: UnsafeMutableRawPointer?, _ opacity: Int32) {
    if let object {
        lv_obj_set_style_opa_layered(OpaquePointer(object), UInt8(opacity), 0)
    }
}

private func setAnimationWidth(_ object: UnsafeMutableRawPointer?, _ width: Int32) {
    if let object {
        lv_obj_set_width(OpaquePointer(object), width)
    }
}

private func setAnimationHeight(_ object: UnsafeMutableRawPointer?, _ height: Int32) {
    if let object {
        lv_obj_set_height(OpaquePointer(object), height)
    }
}

private func setAnimationBackgroundRed(_ object: UnsafeMutableRawPointer?, _ red: Int32) {
    guard let object else { return }
    let node = OpaquePointer(object)
    var color = lv_obj_get_style_bg_color(node, LV_PART_MAIN)
    color.red = UInt8(red)
    lv_obj_set_style_bg_color(node, color, 0)
}

private func setAnimationBackgroundGreen(_ object: UnsafeMutableRawPointer?, _ green: Int32) {
    guard let object else { return }
    let node = OpaquePointer(object)
    var color = lv_obj_get_style_bg_color(node, LV_PART_MAIN)
    color.green = UInt8(green)
    lv_obj_set_style_bg_color(node, color, 0)
}

private func setAnimationBackgroundBlue(_ object: UnsafeMutableRawPointer?, _ blue: Int32) {
    guard let object else { return }
    let node = OpaquePointer(object)
    var color = lv_obj_get_style_bg_color(node, LV_PART_MAIN)
    color.blue = UInt8(blue)
    lv_obj_set_style_bg_color(node, color, 0)
}

private func setAnimationBackgroundOpacity(_ object: UnsafeMutableRawPointer?, _ opacity: Int32) {
    if let object {
        lv_obj_set_style_bg_opa(OpaquePointer(object), UInt8(opacity), 0)
    }
}

private func setAnimationTranslationX(_ object: UnsafeMutableRawPointer?, _ x: Int32) {
    if let object {
        lv_obj_set_style_translate_x(OpaquePointer(object), x, 0)
    }
}

private func setAnimationTranslationY(_ object: UnsafeMutableRawPointer?, _ y: Int32) {
    if let object {
        lv_obj_set_style_translate_y(OpaquePointer(object), y, 0)
    }
}

private func setAnimationScaleX(_ object: UnsafeMutableRawPointer?, _ scale: Int32) {
    if let object {
        let node = OpaquePointer(object)
        lv_obj_set_style_transform_scale_x(node, scale, 0)
        // Embedded adaptation: LVGL caches the bounds of an opacity layer.
        // Refresh its parent as scale changes so the transformed child is not
        // clipped to the target frame's smaller offscreen layer.
        if let parent = lv_obj_get_parent(node) {
            lv_obj_refresh_ext_draw_size(parent)
        }
    }
}

private func setAnimationUniformScale(_ object: UnsafeMutableRawPointer?, _ scale: Int32) {
    if let object {
        let node = OpaquePointer(object)
        lv_obj_set_style_transform_scale_x(node, scale, 0)
        lv_obj_set_style_transform_scale_y(node, scale, 0)
        if let parent = lv_obj_get_parent(node) {
            lv_obj_refresh_ext_draw_size(parent)
        }
    }
}

private func setAnimationScaleY(_ object: UnsafeMutableRawPointer?, _ scale: Int32) {
    if let object {
        let node = OpaquePointer(object)
        lv_obj_set_style_transform_scale_y(node, scale, 0)
        // Embedded adaptation: LVGL caches the bounds of an opacity layer.
        // Refresh its parent as scale changes so the transformed child is not
        // clipped to the target frame's smaller offscreen layer.
        if let parent = lv_obj_get_parent(node) {
            lv_obj_refresh_ext_draw_size(parent)
        }
    }
}

private func setAnimationSiblingIndexProgress(
    _ object: UnsafeMutableRawPointer?, _ progress: Int32
) {
    if let object {
        lv_obj_move_to_index(OpaquePointer(object), progress)
    }
}

private func releaseSiblingIndexAnimationContext(
    _ animation: UnsafeMutablePointer<lv_anim_t>?
) {
    guard let animation, let storage = animation.pointee.user_data else { return }
    storage.assumingMemoryBound(to: LVGLSiblingIndexAnimationContext.self).deinitialize(count: 1)
    free(storage)
    animation.pointee.user_data = nil
}

private func setAnimationRotation(_ object: UnsafeMutableRawPointer?, _ rotation: Int32) {
    if let object {
        lv_obj_set_style_transform_rotation(OpaquePointer(object), rotation, 0)
    }
}

private func setAnimationPivotX(_ object: UnsafeMutableRawPointer?, _ x: Int32) {
    if let object {
        lv_obj_set_style_transform_pivot_x(OpaquePointer(object), x, 0)
    }
}

private func setAnimationPivotY(_ object: UnsafeMutableRawPointer?, _ y: Int32) {
    if let object {
        lv_obj_set_style_transform_pivot_y(OpaquePointer(object), y, 0)
    }
}

private func animationPath(_ animation: UnsafePointer<lv_anim_t>?) -> Int32 {
    guard let animation else { return 0 }
    guard let storage = animation.pointee.user_data else { return animation.pointee.end_value }
    return storage.assumingMemoryBound(to: LVGLAnimationContext.self).pointee.value(
        at: UInt32(max(0, animation.pointee.act_time)),
        from: animation.pointee.start_value, to: animation.pointee.end_value)
}

private func releaseAnimationContext(_ animation: UnsafeMutablePointer<lv_anim_t>?) {
    guard let animation, let storage = animation.pointee.user_data else { return }
    storage.assumingMemoryBound(to: LVGLAnimationContext.self).deinitialize(count: 1)
    free(storage)
    animation.pointee.user_data = nil
}

private func deleteAnimatedObject(_ animation: UnsafeMutablePointer<lv_anim_t>?) {
    if let object = animation?.pointee.var {
        lv_obj_delete(OpaquePointer(object))
    }
}
