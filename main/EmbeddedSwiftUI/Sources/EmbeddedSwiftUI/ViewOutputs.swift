// Embedded adaptation of OpenSwiftUICore/View/Input/ViewOutputs.swift.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

package struct ViewResponder {
    package let value: Any

    package init(_ value: Any) {
        self.value = value
    }
}

public struct _ViewOutputs {
    package var displayList: DisplayList
    package var viewResponders: [ViewResponder]

    package init(
        displayList: DisplayList = DisplayList(),
        viewResponders: [ViewResponder] = []
    ) {
        self.displayList = displayList
        self.viewResponders = viewResponders
    }

    package init(_ command: DisplayList.Command) {
        displayList = DisplayList(commands: [command])
        viewResponders = []
    }

    package init(_ outputs: _ViewListOutputs) {
        displayList = outputs.displayList
        viewResponders = outputs.viewResponders
    }

    package static func multiView(
        inputs: _ViewInputs,
        body: (_ViewListInputs) -> _ViewListOutputs
    ) -> Self {
        let outputs = body(_ViewListInputs(inputs))
        // A known unary child needs no extra layout node on the embedded heap.
        return Self(
            displayList: outputs.views.staticCount == 1
                ? outputs.displayList : outputs.displayList.withImplicitRoot(),
            viewResponders: outputs.viewResponders
        )
    }

    package mutating func append(_ outputs: _ViewOutputs) {
        displayList.append(outputs.displayList)
        viewResponders.append(contentsOf: outputs.viewResponders)
    }
}

public struct _ViewListOutputs {
    package var views: _StaticViewList
    package var nextImplicitID = 0

    package var displayList: DisplayList {
        get { views.displayList }
        set { views.displayList = newValue }
    }

    package var viewResponders: [ViewResponder] {
        get { views.viewResponders }
        set { views.viewResponders = newValue }
    }

    package init(
        displayList: DisplayList = DisplayList(),
        viewResponders: [ViewResponder] = [],
        staticCount: Int? = 0,
        traits: ViewTraitCollection = ViewTraitCollection()
    ) {
        views = _StaticViewList(
            displayList: displayList,
            viewResponders: viewResponders,
            staticCount: staticCount,
            traits: traits
        )
    }

    package init(_ outputs: _ViewOutputs) {
        views = _StaticViewList(
            displayList: outputs.displayList,
            viewResponders: outputs.viewResponders,
            staticCount: 1
        )
    }

    package mutating func append(_ outputs: _ViewListOutputs) {
        views.displayList.append(outputs.displayList)
        views.viewResponders.append(contentsOf: outputs.viewResponders)
        views.ids.append(contentsOf: outputs.views.ids)
        nextImplicitID = outputs.nextImplicitID
        if let count = views.staticCount,
           let appendedCount = outputs.views.staticCount {
            views.staticCount = count + appendedCount
        } else {
            views.staticCount = nil
        }
    }
}
