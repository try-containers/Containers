//
//  InspectView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/06/06.
//

import AppKit
import Foundation
import SwiftUI

struct InspectView: View {
    private let root: JSONNode?
    private let json: String

    init(json: String) {
        self.json = json
        self.root = JSONParser.parse(json)
    }

    init<Value: Encodable>(value: Value) {
        self.init(json: InspectJSONEncoder.encode(value))
    }

    var body: some View {
        // A ScrollView centres content smaller than itself, so collapsing the
        // root left one line floating in the middle of the tab. Growing the
        // content to the viewport pins it to the corner instead — and it takes
        // a GeometryReader to know that size, since a scrollable axis proposes
        // nothing and `maxHeight: .infinity` has nothing to fill.
        GeometryReader { viewport in
            ScrollView([.vertical, .horizontal]) {
                Group {
                    if let root {
                        JSONNodeView(node: root)
                    } else {
                        // Not parseable: the text is still the answer.
                        Text(json)
                            .font(JSONStyle.font)
                            .textSelection(.enabled)
                    }
                }
                // JSON is read a line at a time; wrapping a digest across two
                // of them is worse than scrolling for it.
                .fixedSize()
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(
                    minWidth: viewport.size.width,
                    minHeight: viewport.size.height,
                    alignment: .topLeading
                )
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        // The JSON runs to any length, so the tab's bound is what it gets —
        // and a tree this size is not worth measuring twice a layout pass.
        .contentUnbounded()
    }
}

enum InspectJSONEncoder {
    static func encode<Value: Encodable>(_ value: Value) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [
                .prettyPrinted,
                .withoutEscapingSlashes,
            ]

            let data = try encoder.encode(value)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return
                "{\n  \"error\" : \"Unable to encode inspect JSON: \(error.localizedDescription)\"\n}"
        }
    }
}

// MARK: - Tree

private struct JSONNodeView: View {
    let node: JSONNode

    @State private var isExpanded = true

    var body: some View {
        switch node.value {
        case .object(let children):
            branch(children, open: "{", close: "}")
        case .array(let children):
            branch(children, open: "[", close: "]")
        case .leaf(let text, let role):
            row(key + JSONRun.text(text, role))
        }
    }

    private func branch(
        _ children: [JSONNode],
        open: String,
        close: String
    ) -> some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(children) { JSONNodeView(node: $0) }
            }
            // Outside a List a DisclosureGroup does not indent what it holds,
            // and a tree that does not step in is not a tree.
            .padding(.leading, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            row(
                key
                    + JSONRun.text(open, .punctuation)
                    + JSONRun.text(summary(children), .muted)
                    + JSONRun.text(close, .punctuation)
            )
        }
    }

    /// One `Text` per row rather than one per token: the colours ride on the
    /// string, so a row is a single view and selecting across it gives the
    /// whole line rather than a fragment.
    private func row(_ attributed: AttributedString) -> some View {
        Text(attributed)
            .font(JSONStyle.font)
            .textSelection(.enabled)
    }

    private func summary(_ children: [JSONNode]) -> String {
        switch children.count {
        case 0: " "
        case 1: " 1 item "
        default: " \(children.count) items "
        }
    }

    private var key: AttributedString {
        guard let key = node.key else { return AttributedString() }
        return JSONRun.text(key, .key) + JSONRun.text(" : ", .punctuation)
    }
}

private enum JSONRun {
    static func text(_ string: String, _ role: JSONRole) -> AttributedString {
        var run = AttributedString(string)
        run.foregroundColor = role.color
        return run
    }
}

private enum JSONStyle {
    static let font = Font.system(size: 12, design: .monospaced)
}

private enum JSONRole {
    case key, string, number, boolean, null, punctuation, muted

    var color: Color {
        switch self {
        case .muted: .secondary
        case .key: .init(nsColor: .inspect(light: 0x9B4D00, dark: 0xF0B35A))
        case .string: .init(nsColor: .inspect(light: 0x0A7F32, dark: 0x7BD88F))
        case .number: .init(nsColor: .inspect(light: 0x1769C2, dark: 0x80BFFF))
        case .boolean: .init(nsColor: .inspect(light: 0x8D35B2, dark: 0xD59CFF))
        case .null: .init(nsColor: .inspect(light: 0x777777, dark: 0xA0A0A0))
        case .punctuation: .secondary
        }
    }
}

private struct JSONNode: Identifiable {
    enum Value {
        case object([JSONNode])
        case array([JSONNode])
        case leaf(String, JSONRole)
    }

    /// The path to this node. Stable across re-parses, so a branch the user
    /// opened stays open when the view is rebuilt — a fresh id each parse
    /// silently reset every disclosure.
    let id: String
    /// Quoted, as written. `nil` for array elements and the root.
    let key: String?
    let value: Value
}

// MARK: - Parsing

/// Parses the encoder's own output rather than going through
/// `JSONSerialization`, which returns dictionaries and so loses the order the
/// keys were written in.
private enum JSONParser {
    static func parse(_ json: String) -> JSONNode? {
        var index = json.startIndex
        skipWhitespace(json, &index)

        guard let value = parseValue(json, &index, path: "") else { return nil }

        // Anything left over means this was not the JSON it looked like, and
        // showing the text as it stands beats showing a tree built from half
        // of it.
        skipWhitespace(json, &index)
        guard index == json.endIndex else { return nil }

        return JSONNode(id: "", key: nil, value: value)
    }

    private static func parseValue(
        _ json: String,
        _ index: inout String.Index,
        path: String
    ) -> JSONNode.Value? {
        skipWhitespace(json, &index)
        guard index < json.endIndex else { return nil }

        switch json[index] {
        case "{":
            return parseContainer(json, &index, close: "}", keyed: true, path: path)
        case "[":
            return parseContainer(json, &index, close: "]", keyed: false, path: path)
        case "\"":
            guard let text = parseString(json, &index) else { return nil }
            return .leaf(text, .string)
        default:
            return parseLiteral(json, &index)
        }
    }

    private static func parseContainer(
        _ json: String,
        _ index: inout String.Index,
        close: Character,
        keyed: Bool,
        path: String
    ) -> JSONNode.Value? {
        index = json.index(after: index)
        var children: [JSONNode] = []

        while true {
            skipWhitespace(json, &index)
            guard index < json.endIndex else { return nil }

            if json[index] == close {
                index = json.index(after: index)
                return keyed ? .object(children) : .array(children)
            }

            if json[index] == "," {
                index = json.index(after: index)
                continue
            }

            var key: String?
            if keyed {
                guard let parsed = parseString(json, &index) else { return nil }
                key = parsed

                skipWhitespace(json, &index)
                guard index < json.endIndex, json[index] == ":" else {
                    return nil
                }
                index = json.index(after: index)
            }

            let childPath = "\(path)/\(key ?? String(children.count))"
            guard
                let value = parseValue(json, &index, path: childPath)
            else { return nil }

            children.append(JSONNode(id: childPath, key: key, value: value))
        }
    }

    /// Returns the literal including its quotes, escapes untouched.
    private static func parseString(
        _ json: String,
        _ index: inout String.Index
    ) -> String? {
        guard index < json.endIndex, json[index] == "\"" else { return nil }

        let start = index
        index = json.index(after: index)

        while index < json.endIndex {
            if json[index] == "\\" {
                index =
                    json.index(index, offsetBy: 2, limitedBy: json.endIndex)
                    ?? json.endIndex
                continue
            }
            if json[index] == "\"" {
                index = json.index(after: index)
                return String(json[start..<index])
            }
            index = json.index(after: index)
        }

        return nil
    }

    private static func parseLiteral(
        _ json: String,
        _ index: inout String.Index
    ) -> JSONNode.Value? {
        let start = index

        while index < json.endIndex,
            !",}] \n\t\r".contains(json[index])
        {
            index = json.index(after: index)
        }

        guard start < index else { return nil }
        let text = String(json[start..<index])

        return switch text {
        case "true", "false": .leaf(text, .boolean)
        case "null": .leaf(text, .null)
        default: .leaf(text, .number)
        }
    }

    private static func skipWhitespace(
        _ json: String,
        _ index: inout String.Index
    ) {
        while index < json.endIndex, json[index].isWhitespace {
            index = json.index(after: index)
        }
    }
}

extension NSColor {
    /// One colour per appearance, resolved when it is drawn rather than when
    /// it is built, so the JSON recolours with the system.
    fileprivate static func inspect(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark =
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        }
    }

    fileprivate convenience init(rgb: Int) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
