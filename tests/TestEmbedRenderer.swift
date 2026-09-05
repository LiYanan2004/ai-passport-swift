import EmbeddedSwiftUI

private final class RectStore {
    var values: [EmbeddedRect] = []
}

private struct IntegerTraitKey: _ViewTraitKey {
    static let defaultValue = 0
}

private struct BodyModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(3)
    }
}

private struct StateView: View {
    @State private var count = 0

    var body: some View {
        Text("Count \(count)")
    }

    func increment() {
        count += 1
    }
}

private struct BudgetContent: PrimitiveView, MultiView {
    let levels: Int
    let labels: Int

    static func _makeView(
        view: Self,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        _ViewOutputs(Self._makeViewList(
            view: view,
            inputs: _ViewListInputs(inputs)
        ))
    }

    static func _makeViewList(
        view: Self,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        var displayList = DisplayList()
        for _ in 0..<view.levels {
            displayList.append(.beginContainer(.overlay(alignment: .topLeading)))
        }
        for _ in 0..<view.labels {
            displayList.append(.text("budget", RenderEnvironment()))
        }
        for _ in 0..<view.levels {
            displayList.append(.endContainer)
        }
        return _ViewListOutputs(
            displayList: displayList,
            staticCount: view.labels
        )
    }
}

private func outputs<Content: View>(_ view: Content) -> _ViewOutputs {
    Content._makeView(view: view, inputs: _ViewInputs())
}

private func listOutputs<Content: View>(_ view: Content) -> _ViewListOutputs {
    Content._makeViewList(view: view, inputs: _ViewListInputs())
}

private func listCount<Content: View>(_ type: Content.Type) -> Int? {
    Content._viewListCount(inputs: _ViewListCountInputs())
}

private func commandsRecursively(
    in displayList: DisplayList
) -> [DisplayList.Command] {
    var result: [DisplayList.Command] = []
    for command in displayList.commands {
        result.append(command)
        switch command {
        case let .identity(_, content):
            result.append(contentsOf: commandsRecursively(in: content))
        case let .effect(_, content):
            result.append(contentsOf: commandsRecursively(in: content))
        default:
            break
        }
    }
    return result
}

private func firstTextEnvironment(
    in displayList: DisplayList
) -> RenderEnvironment? {
    for command in commandsRecursively(in: displayList) {
        if case let .text(_, environment) = command {
            return environment
        }
    }
    return nil
}

private func testViewProtocolAndLists() {
    precondition(listCount(Text.self) == 1)
    precondition(listCount(EmptyView.self) == 0)
    precondition(listCount(Optional<Text>.self) == 1)
    precondition(listCount(_ViewPair<Text, Text>.self) == 2)
    precondition(listCount(_ConditionalContent<Text, Text>.self) == 1)
    precondition(listCount(ForEach<Range<Int>, Int, Text>.self) == nil)

    let pair = ViewBuilder.buildPartialBlock(
        accumulated: Text("first"),
        next: Text("second")
    )
    let pairOutputs = listOutputs(pair)
    precondition(pairOutputs.views.count(style: _ViewList_IteratorStyle()) == 2)
    precondition(pairOutputs.displayList.commands.count == 2)
    precondition(pairOutputs.displayList.commands.allSatisfy {
        if case .identity = $0 { return true }
        return false
    })

    let budget = listOutputs(BudgetContent(levels: 2, labels: 3))
    precondition(budget.views.count(style: _ViewList_IteratorStyle()) == 3)
    precondition(budget.displayList.commands.count == 7)
}

private func testModifierConstructionAndEnvironment() {
    let modified = Text("modified").modifier(BodyModifier())
    let modifiedOutputs = outputs(modified)
    precondition(commandsRecursively(in: modifiedOutputs.displayList).contains {
        if case .beginContainer(.padding) = $0 {
            return true
        }
        return false
    })

    let styled = Text("styled")
        .font(.title)
        .foregroundColor(.green)
    let environment = firstTextEnvironment(in: outputs(styled).displayList)
    precondition(environment?.font == .title)
    precondition(environment?.foregroundColor == .green)

    let foregroundStyle = Rectangle()
        .fill()
        .foregroundStyle(Color.blue)
    guard case let .shape(shape)? = commandsRecursively(
        in: outputs(foregroundStyle).displayList
    ).first(where: {
        if case .shape = $0 { return true }
        return false
    }) else {
        preconditionFailure("Expected shape output")
    }
    precondition(shape.resolvedColor(.red) == .blue)
}

private func testTraitsAndEffects() {
    let traitOutputs = listOutputs(
        Text("trait")._trait(IntegerTraitKey.self, 17)
    )
    guard case let .beginTraits(traits)? = commandsRecursively(
        in: traitOutputs.displayList
    ).first(where: {
        if case .beginTraits = $0 { return true }
        return false
    }) else {
        preconditionFailure("Expected trait scope")
    }
    precondition(traits[IntegerTraitKey.self] == 17)

    let zIndexOutputs = listOutputs(
        Text("front").zIndex(4)
    )
    guard case let .beginTraits(zIndexTraits)? = commandsRecursively(
        in: zIndexOutputs.displayList
    ).first(where: {
        if case .beginTraits = $0 { return true }
        return false
    }) else {
        preconditionFailure("Expected zIndex trait scope")
    }
    precondition(zIndexTraits.zIndex == 4)

    let opacityOutputs = outputs(Text("opacity").opacity(0.5))
    guard case let .effect(effect, _)? = commandsRecursively(
        in: opacityOutputs.displayList
    ).first(where: {
        if case .effect = $0 { return true }
        return false
    }) else {
        preconditionFailure("Expected renderer effect")
    }
    guard case let .opacity(opacity) = effect.resolve(.init(width: 20, height: 10)) else {
        preconditionFailure("Expected opacity effect")
    }
    precondition(opacity == 0.5)

    let scaleOutputs = outputs(
        Text("scale").scaleEffect(x: 1.5, y: 0.5, anchor: .topLeading)
    )
    guard case let .effect(scaleEffect, _)? = commandsRecursively(
        in: scaleOutputs.displayList
    ).first(where: {
        if case .effect = $0 { return true }
        return false
    }),
          case let .geometry(transform) = scaleEffect.resolve(.init(width: 20, height: 10)),
          case let .scale(x, y, anchor) = transform.storage else {
        preconditionFailure("Expected geometry effect")
    }
    precondition(x == 1.5 && y == 0.5 && anchor == .topLeading)
}

private func testLayoutProxies() {
    let rectStore = RectStore()
    let first = LayoutSubview(
        storage: _LayoutSubviewStorage(
            sizeThatFits: { _ in EmbeddedSize(width: 20, height: 10) },
            place: { rectStore.values.append($0) }
        )
    )
    let second = LayoutSubview(
        storage: _LayoutSubviewStorage(
            sizeThatFits: { _ in EmbeddedSize(width: 30, height: 12) },
            place: { rectStore.values.append($0) }
        )
    )
    let subviews = LayoutSubviews([first, second])
    let layout = VStackLayout(alignment: .leading, spacing: 4)
    var cache = layout.makeCache(subviews: subviews)
    let size = layout.sizeThatFits(
        proposal: .unspecified,
        subviews: subviews,
        cache: &cache
    )
    precondition(size == EmbeddedSize(width: 30, height: 26))
    layout.placeSubviews(
        in: EmbeddedRect(width: 30, height: 26),
        proposal: ProposedViewSize(width: 30, height: 26),
        subviews: subviews,
        cache: &cache
    )
    precondition(rectStore.values == [
        EmbeddedRect(x: 0, y: 0, width: 20, height: 10),
        EmbeddedRect(x: 0, y: 14, width: 30, height: 12),
    ])
}

private func testStateAndLifecycleOutputs() {
    let host = EmbeddedViewHost {
        StateView()
    }
    precondition(host.needsRender)
    _ = host.makeViewOutputs()
    let revision = host.currentRevision
    host.acknowledgeRender(startedAt: revision)
    precondition(!host.needsRender)
    host.retainedContent.increment()
    precondition(host.needsRender)

    var appeared = false
    let appearanceOutputs = outputs(
        Text("appearance").onAppear {
            appeared = true
        }
    )
    guard case let .appearance(action)? = commandsRecursively(
        in: appearanceOutputs.displayList
    ).first(where: {
        if case .appearance = $0 { return true }
        return false
    }) else {
        preconditionFailure("Expected appearance output")
    }
    action.appear?()
    precondition(appeared)
}

private final class StateAction {
    var binding: Binding<Int>?
}

private struct StatefulChild: View {
    @State private var count = 0
    let action: StateAction

    var body: some View {
        Text("\(count)").onAppear { action.binding = $count }
    }
}

private struct StatefulParent: View {
    let action: StateAction
    var body: some View { StatefulChild(action: action) }
}

private func firstText(_ list: DisplayList) -> String? {
    for command in commandsRecursively(in: list) {
        if case let .text(text, _) = command { return text }
    }
    return nil
}

private func testStateInstallation() {
    let action = StateAction()
    let host = EmbeddedViewHost { StatefulParent(action: action) }
    let initial = host.makeViewOutputs()
    precondition(firstText(initial.displayList) == "0")
    for command in commandsRecursively(in: initial.displayList) {
        if case let .appearance(modifier) = command { modifier.appear?() }
    }
    host.acknowledgeRender(startedAt: host.currentRevision)
    action.binding?.wrappedValue = 7
    precondition(host.needsRender)
    precondition(firstText(host.makeViewOutputs().displayList) == "7")
    host.acknowledgeRender(startedAt: host.currentRevision)
    host.unmount()
    action.binding?.wrappedValue = 9
    precondition(firstText(host.makeViewOutputs().displayList) == "0")
}

private struct TestRendererProvider: RendererProvider {
    var configuration: RendererConfiguration {
        RendererConfiguration(
            maximumNodes: 64, maximumDepth: 16, maximumDimension: 32767,
            defaultSpacing: 3, defaultPadding: EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2),
            listSpacing: 1, defaultFont: .body, defaultForegroundColor: .red,
            implicitRootLayout: VStackLayout(),
            systemColor: { _ in Color.Resolved(rgb: 0xff0000) }
        )
    }

    func measureText(_ text: String, environment: RenderEnvironment, proposal: ProposedViewSize) -> EmbeddedSize {
        EmbeddedSize(width: Int32(text.utf8.count * 5), height: 10)
    }

    func imageSize(named name: String) -> EmbeddedSize? { nil }
}

private func resolved<Content: View>(
    _ content: Content,
    previous: [_ViewList_ID: ValueTransactionSeed] = [:]
) -> DisplayListUpdate {
    var layout = DisplayListLayout(
        provider: TestRendererProvider(), transaction: Transaction(), previousAnimations: previous
    )
    return layout.update(
        Content.makeDebuggableView(view: content, inputs: _ViewInputs()).displayList,
        size: EmbeddedSize(width: 100, height: 60), alignment: .topLeading,
        version: DisplayList.Version()
    )!
}

private func flatten(_ items: [DisplayList.Item]) -> [DisplayList.Item] {
    items.flatMap { [$0] + flatten($0.children) }
}

private struct Row: Identifiable {
    let id: Int
}

private func testIdentityAndTransactions() {
    let first = resolved(ForEach([Row(id: 1), Row(id: 2)]) { row in Text("\(row.id)") })
    let second = resolved(ForEach([Row(id: 2), Row(id: 1)]) { row in Text("\(row.id)") })
    func identity(_ text: String, _ update: DisplayListUpdate) -> DisplayList.StableIdentity {
        flatten(update.displayList.items).first {
            if case let .text(value, _) = $0.value { return value == text }
            return false
        }!.stableIdentity
    }
    precondition(identity("1", first) == identity("1", second))
    precondition(identity("1", first) != identity("2", first))
    let explicit = resolved(ForEach([1, 2], id: \.self) { Text("\($0)") })
    precondition(identity("1", explicit) != identity("2", explicit))

    func content(_ value: Int) -> some View {
        HStack(spacing: 0) {
            Text("A").animation(.linear(duration: 1), value: value)
            Text("B").animation(.linear(duration: 5), value: value)
        }
    }
    let initial = resolved(content(0))
    let updated = resolved(content(1), previous: initial.animationValues)
    let durations = flatten(updated.displayList.items).compactMap { item -> Double? in
        guard case .text = item.value else { return nil }
        return item.transaction.animation?.duration
    }
    precondition(durations == [1, 5])

    var events: [Int] = []
    var effect = AppearanceEffect(modifier: .init(
        appear: { events.append(1) }, disappear: { events.append(2) }
    ))
    effect.appeared()
    effect.appeared()
    effect.disappeared()
    effect.disappeared()
    precondition(events == [1, 2])
}

private struct ProbeLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void) -> EmbeddedSize {
        precondition(subviews[0].sizeThatFits(.zero) == .zero)
        precondition(subviews[0].sizeThatFits(.init(width: 40, height: 20)) == .init(width: 40, height: 20))
        return EmbeddedSize(width: 40, height: 20)
    }

    func placeSubviews(in bounds: EmbeddedRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void) {
        precondition(bounds.size == EmbeddedSize(width: 40, height: 20))
        subviews[0].place(at: .init(), proposal: ProposedViewSize(bounds.size))
    }
}

private func testMeasuredDisplayList() {
    let custom = resolved(ProbeLayout() { Rectangle() })
    let shape = flatten(custom.displayList.items).first {
        if case .shape = $0.value { return true }
        return false
    }!
    precondition(shape.frame.size == EmbeddedSize(width: 40, height: 20))
    let stack = resolved(HStack(spacing: 0) { Rectangle(); Rectangle() }.frame(width: 100, height: 20))
    let widths = flatten(stack.displayList.items).compactMap { item -> Int32? in
        if case .shape = item.value { return item.frame.width }
        return nil
    }
    precondition(widths == [50, 50])
    let background = resolved(Text("A").background(Rectangle()))
    let wrapper = flatten(background.displayList.items).first {
        if case .container(.secondaryBackground) = $0.value { return true }
        return false
    }!
    precondition(wrapper.frame.size == EmbeddedSize(width: 5, height: 10))
}

private struct UnaryBodyModifier: ViewModifier {
    func body(content: Content) -> some View { VStack { content } }
}

private func testTraitDispatchAndModifierCounts() {
    precondition(firstText(outputs(Text("root").zIndex(1)).displayList) == "root")
    let zStack = resolved(
        ZStack {
            Text("front")
                .frame(width: 20, height: 20)
                .scaleEffect(1)
                .opacity(1)
                .offset(x: -4)
                .zIndex(1)
            Text("back")
                .frame(width: 20, height: 20)
                .scaleEffect(1)
                .opacity(1)
                .offset(x: 4)
                .zIndex(0)
        }
    )
    let overlay = flatten(zStack.displayList.items).first {
        if case .container(.overlay) = $0.value { return true }
        return false
    }!
    precondition(overlay.children.map { $0.traits.zIndex } == [1, 0])

    let modified = ViewBuilder.buildPartialBlock(
        accumulated: Text("a"), next: Text("b")
    ).modifier(UnaryBodyModifier())
    func count<Content: View>(_ content: Content) -> Int? { listCount(Content.self) }
    precondition(count(modified) == 1)
    let update = resolved(Text("x").zIndex(1).zIndex(2))
    precondition(!update.displayList.items.isEmpty)
}

private struct NumberKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    fileprivate var number: Int {
        get { self[NumberKey.self] }
        set { self[NumberKey.self] = newValue }
    }
}

private struct EnvironmentContent: View {
    @Environment(\.number) private var number
    var body: some View { Text("\(number)") }
}

private func testEnvironmentAndProjection() {
    let host = EmbeddedViewHost { EnvironmentContent().environment(\.number, 42) }
    precondition(firstText(host.makeViewOutputs().displayList) == "42")
    var transform = ProjectionTransform()
    transform.m11 = 2
    transform.m22 = 3
    transform.m31 = 10
    let identity = transform.concatenating(transform.inverted())
    precondition(abs(identity.m11 - 1) < 0.000001)
    precondition(abs(identity.m22 - 1) < 0.000001)
    precondition(abs(identity.m31) < 0.000001)
    let ellipse = Ellipse().path(in: ShapeRect(width: 100, height: 40))
    precondition(ellipse.elements.count == 6)
}

@main
private struct TestEmbeddedSwiftUI {
    static func main() {
        testViewProtocolAndLists()
        testModifierConstructionAndEnvironment()
        testTraitsAndEffects()
        testLayoutProxies()
        testStateAndLifecycleOutputs()
        testStateInstallation()
        testIdentityAndTransactions()
        testMeasuredDisplayList()
        testTraitDispatchAndModifierCounts()
        testEnvironmentAndProjection()
        print("EmbeddedSwiftUI tests: PASS")
    }
}
