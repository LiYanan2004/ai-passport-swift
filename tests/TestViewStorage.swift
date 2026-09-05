import EmbeddedSwiftUI

@main
private struct TestViewStorage {
    static func main() {
        precondition(MemoryLayout<_ViewInputs>.stride <= 2 * MemoryLayout<UnsafeRawPointer>.stride)
        precondition(MemoryLayout<_ViewPair<Text, Text>>.stride == MemoryLayout<UnsafeRawPointer>.stride)

        var root = _ViewInputs()
        root.environment.font = .body
        root.environment.foregroundColor = .white
        root.transaction = Transaction(animation: .linear(duration: 1))
        var first = root.child(at: 0)
        var second = root.child(at: 1)
        first.environment.font = .title
        first.transaction.animation = .linear(duration: 2)
        second.environment.foregroundColor = .red
        precondition(root.environment.font == .body)
        precondition(root.environment.foregroundColor == .white)
        precondition(root.transaction.animation?.duration == 1)
        precondition(second.environment.font == .body)
        precondition(second.transaction.animation?.duration == 1)
        precondition(first.environment.foregroundColor == .white)
        precondition(first.environment.font == .title)

        var list = _ViewListInputs(root)
        var copiedList = list
        copiedList.base.environment.font = .caption
        list.base.transaction.disablesAnimations = true
        precondition(list.base.environment.font == .body)
        precondition(!copiedList.base.transaction.disablesAnimations)
        precondition(!root.transaction.disablesAnimations)
        precondition(first.identity != second.identity)
        print("View storage value semantics: PASS")
    }
}
