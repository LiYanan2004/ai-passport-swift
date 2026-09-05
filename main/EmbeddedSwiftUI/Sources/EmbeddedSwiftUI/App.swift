// Embedded adaptation of EmbeddedSwiftUI/App/App/App.swift.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

/// Embedded adaptation: omit the upstream Scene layer for a device with one
/// permanent display. App still owns a declarative root View and its lifecycle.
public protocol App {
    associatedtype Body: View
    @ViewBuilder var body: Body { get }
    init()
    static func main()
}
