//
//  InspectView.swift
//  Containers
//
//  Created by Axel Martinez on 2026/06/06.
//

import Foundation
import SwiftUI
import WebKit

struct InspectView: View {
    let json: String

    init(json: String) {
        self.json = json
    }

    init<Value: Encodable>(value: Value) {
        self.json = InspectJSONEncoder.encode(value)
    }

    var body: some View {
        JSONInspectWebView(html: JSONInspectDocument.html(for: json))
            .background(Color(nsColor: .textBackgroundColor))
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
            let message = error.localizedDescription.replacingOccurrences(
                of: "\"",
                with: "\\\""
            )
            return
                "{\n  \"error\" : \"Unable to encode inspect JSON: \(message)\"\n}"
        }
    }
}

private struct JSONInspectWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.currentHTML != html else {
            return
        }

        context.coordinator.currentHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(currentHTML: html)
    }

    final class Coordinator {
        var currentHTML: String

        init(currentHTML: String) {
            self.currentHTML = currentHTML
        }
    }
}

private enum JSONInspectDocument {
    static func html(for json: String) -> String {
        let scriptSafeJSON =
            json
            .replacingOccurrences(of: "</", with: "<\\/")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")

        return #"""
            <!doctype html>
            <html>
            <head>
                <meta charset="utf-8">
                <style>
                    :root {
                        color-scheme: light dark;
                        --background: Canvas;
                        --text: CanvasText;
                        --muted: color-mix(in srgb, CanvasText 55%, transparent);
                        --key: #9b4d00;
                        --string: #0a7f32;
                        --number: #1769c2;
                        --boolean: #8d35b2;
                        --null: #777777;
                        --punctuation: color-mix(in srgb, CanvasText 50%, transparent);
                        --row-hover: color-mix(in srgb, CanvasText 7%, transparent);
                    }
                    
                    @media (prefers-color-scheme: dark) {
                        :root {
                            --key: #f0b35a;
                            --string: #7bd88f;
                            --number: #80bfff;
                            --boolean: #d59cff;
                            --null: #a0a0a0;
                        }
                    }
                    
                    html, body {
                        min-height: 100%;
                        margin: 0;
                        background: var(--background);
                        color: var(--text);
                        font: 12px ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                        line-height: 1.55;
                        -webkit-user-select: text;
                        user-select: text;
                    }
                    
                    body {
                        box-sizing: border-box;
                        padding: 14px 16px 24px;
                        overflow: auto;
                    }
                    
                    .tree {
                        white-space: nowrap;
                    }
                    
                    details {
                        margin: 0;
                    }
                    
                    summary {
                        display: block;
                        cursor: default;
                        list-style: none;
                        border-radius: 4px;
                        margin-left: -4px;
                        padding-left: 4px;
                    }
                    
                    summary:hover {
                        background: var(--row-hover);
                    }
                    
                    summary::-webkit-details-marker {
                        display: none;
                    }
                    
                    summary::before {
                        content: "▸";
                        display: inline-block;
                        width: 14px;
                        color: var(--muted);
                    }
                    
                    details[open] > summary::before {
                        content: "▾";
                    }
                    
                    .children {
                        margin-left: 28px;
                    }
                    
                    .leaf {
                        margin-left: 14px;
                    }
                    
                    .key { color: var(--key); }
                    .string { color: var(--string); }
                    .number { color: var(--number); }
                    .boolean { color: var(--boolean); }
                    .null { color: var(--null); }
                    .punctuation { color: var(--punctuation); }
                    .meta { color: var(--muted); }
                    .error { color: #c53030; }
                </style>
            </head>
            <body>
                <main id="json" class="tree"></main>
                <script>
                    const payload = \#(scriptSafeJSON);
                    const root = document.getElementById('json');
                    
                    function span(className, text) {
                        const element = document.createElement('span');
                        element.className = className;
                        element.textContent = text;
                        return element;
                    }
                    
                    function quoted(value) {
                        return JSON.stringify(value);
                    }
                    
                    function appendKey(parent, key) {
                        if (key === undefined) return;
                        parent.appendChild(span('key', quoted(key)));
                        parent.appendChild(span('punctuation', ' : '));
                    }
                    
                    function appendPrimitive(parent, value, key) {
                        const line = document.createElement('div');
                        line.className = 'leaf';
                        appendKey(line, key);
                        
                        if (typeof value === 'string') {
                            line.appendChild(span('string', quoted(value)));
                        } else if (typeof value === 'number') {
                            line.appendChild(span('number', String(value)));
                        } else if (typeof value === 'boolean') {
                            line.appendChild(span('boolean', String(value)));
                        } else if (value === null) {
                            line.appendChild(span('null', 'null'));
                        }
                        
                        parent.appendChild(line);
                    }
                    
                    function appendNode(parent, value, key) {
                        if (value === null || typeof value !== 'object') {
                            appendPrimitive(parent, value, key);
                            return;
                        }
                        
                        const isArray = Array.isArray(value);
                        const entries = isArray ? value.map((item, index) => [String(index), item]) : Object.entries(value);
                        const details = document.createElement('details');
                        details.open = true;
                        
                        const summary = document.createElement('summary');
                        appendKey(summary, key);
                        summary.appendChild(span('punctuation', isArray ? '[' : '{'));
                        summary.appendChild(span('meta', entries.length === 1 ? ' 1 item ' : ` ${entries.length} items `));
                        summary.appendChild(span('punctuation', isArray ? ']' : '}'));
                        details.appendChild(summary);
                        
                        const children = document.createElement('div');
                        children.className = 'children';
                        
                        if (entries.length === 0) {
                            const empty = document.createElement('div');
                            empty.className = 'leaf meta';
                            empty.textContent = isArray ? '[]' : '{}';
                            children.appendChild(empty);
                        } else {
                            for (const [childKey, childValue] of entries) {
                                appendNode(children, childValue, isArray ? undefined : childKey);
                            }
                        }
                        
                        details.appendChild(children);
                        parent.appendChild(details);
                    }
                    
                    try {
                        appendNode(root, payload);
                    } catch (error) {
                        const message = document.createElement('div');
                        message.className = 'error';
                        message.textContent = `Unable to render JSON: ${error.message}`;
                        root.appendChild(message);
                    }
                </script>
            </body>
            </html>
            """#
    }
}
