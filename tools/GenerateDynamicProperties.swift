import Foundation
import SwiftParser
import SwiftSyntax

// Embedded adaptation: generate the field-registration calls that OpenSwiftUI
// obtains from AttributeGraph metadata. This tool runs on the build host only,
// keeping SwiftSyntax and runtime reflection out of the firmware.
private func typeName(_ type: TypeSyntax) -> String {
    if let identifier = type.as(IdentifierTypeSyntax.self) { return identifier.name.text }
    if let member = type.as(MemberTypeSyntax.self) { return member.name.text }
    return type.trimmedDescription
}

private final class PropertyDeclarations: SyntaxVisitor {
    var inheritance: [String: Set<String>] = [:]

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, inheritance: node.inheritanceClause)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, inheritance: node.inheritanceClause)
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        record(typeName(node.extendedType), inheritance: node.inheritanceClause)
        return .visitChildren
    }

    private func record(_ name: String, inheritance clause: InheritanceClauseSyntax?) {
        inheritance[name, default: []].formUnion(clause?.inheritedTypes.map { typeName($0.type) } ?? [])
    }

    func conforms(_ name: String, to protocols: Set<String>, visited: Set<String> = []) -> Bool {
        if protocols.contains(name) { return true }
        guard !visited.contains(name) else { return false }
        return inheritance[name, default: []].contains {
            conforms($0, to: protocols, visited: visited.union([name]))
        }
    }
}

private final class DynamicPropertyRewriter: SyntaxRewriter {
    let declarations: PropertyDeclarations

    init(declarations: PropertyDeclarations) {
        self.declarations = declarations
        super.init()
    }

    override func visit(_ node: StructDeclSyntax) -> DeclSyntax {
        var declaration = node
        let registeredProperties = node.memberBlock.members.flatMap { member -> [String] in
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  !variable.modifiers.contains(where: {
                      $0.name.tokenKind == .keyword(.static)
                  }) else { return [] }
            let wrapped = variable.attributes.contains { attribute in
                guard let attribute = attribute.as(AttributeSyntax.self) else { return false }
                return declarations.conforms(typeName(attribute.attributeName), to: ["State", "Binding", "Environment", "DynamicProperty"])
            }
            return variable.bindings.compactMap { binding in
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self),
                      binding.accessorBlock == nil else { return nil }
                if wrapped { return "_\(name.identifier.text)" }
                if let type = binding.typeAnnotation?.type,
                   declarations.conforms(typeName(type), to: ["DynamicProperty"]) {
                    return name.identifier.text
                }
                return nil
            }
        }
        guard !registeredProperties.isEmpty,
              declarations.conforms(node.name.text, to: ["View", "ViewModifier", "DynamicProperty"]) else {
            return super.visit(node)
        }
        let hasRegistration = node.memberBlock.members.contains {
            $0.decl.as(FunctionDeclSyntax.self)?.name.text == "_makeProperties"
        }
        guard !hasRegistration else { return super.visit(node) }
        let visibility = node.modifiers.contains { $0.name.tokenKind == .keyword(.public) }
            ? "public " : ""
        let statements = registeredProperties.enumerated().map { index, name in
            "buffer.append(&container.\(name), fieldOffset: \(index), inputs: &inputs)"
        }.joined(separator: "\n")
        let generated = Parser.parse(source: """

        \(visibility)static func _makeProperties(
            in buffer: inout _DynamicPropertyBuffer,
            container: inout Self,
            inputs: inout _ViewInputs
        ) {
            \(statements)
        }
        """)
        for item in generated.statements {
            guard let member = item.item.as(DeclSyntax.self) else { continue }
            declaration.memberBlock.members.append(MemberBlockItemSyntax(decl: member))
        }
        return super.visit(declaration)
    }
}

@main
private struct GenerateDynamicProperties {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2 else {
            throw NSError(
                domain: "GenerateDynamicProperties", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Expected input.swift output.swift"]
            )
        }
        let source = try String(contentsOfFile: arguments[0], encoding: .utf8)
        let tree = Parser.parse(source: source)
        guard !tree.hasError else {
            throw NSError(
                domain: "GenerateDynamicProperties", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Swift source: \(arguments[0])"]
            )
        }
        // Imported conformances need explicit registration: SwiftSyntax has no
        // type checker. Local wrappers, qualified names and extension-declared
        // conformances are resolved without runtime reflection in the firmware.
        let declarations = PropertyDeclarations(viewMode: .sourceAccurate)
        declarations.walk(tree)
        let rewritten = DynamicPropertyRewriter(declarations: declarations).rewrite(tree)
        try rewritten.description.write(toFile: arguments[1], atomically: true, encoding: .utf8)
    }
}
