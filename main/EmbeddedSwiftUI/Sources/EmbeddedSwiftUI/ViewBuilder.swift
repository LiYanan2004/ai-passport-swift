// Embedded adaptation of EmbeddedSwiftUICore/View/ViewBuilder.swift.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

@resultBuilder
public struct ViewBuilder {
    public static func buildExpression<Content>(_ content: Content) -> Content where Content: View {
        content
    }

    public static func buildBlock() -> EmptyView {
        EmptyView()
    }

    public static func buildBlock<Content>(_ content: Content) -> Content where Content: View {
        content
    }

    // Embedded adaptation: a statically typed pair replaces tuple metadata and
    // variadic graph dispatch, which Embedded Swift cannot provide.
    public static func buildPartialBlock<Content>(first: Content) -> Content where Content: View {
        first
    }

    public static func buildPartialBlock<Accumulated, Next>(
        accumulated: Accumulated, next: Next
    ) -> _ViewPair<Accumulated, Next> where Accumulated: View, Next: View {
        _ViewPair(first: accumulated, second: next)
    }

    public static func buildIf<Content>(_ content: Content?) -> Content? where Content: View {
        content
    }

    public static func buildEither<TrueContent, FalseContent>(first: TrueContent) -> _ConditionalContent<TrueContent, FalseContent> where TrueContent: View, FalseContent: View {
        .init(storage: .trueContent(first))
    }

    public static func buildEither<TrueContent, FalseContent>(second: FalseContent) -> _ConditionalContent<TrueContent, FalseContent> where TrueContent: View, FalseContent: View {
        .init(storage: .falseContent(second))
    }

    public static func buildLimitedAvailability<Content: View>(_ content: Content) -> Content {
        content
    }
}

public typealias ViewPair<First: View, Second: View> = _ViewPair<First, Second>
