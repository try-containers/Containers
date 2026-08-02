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

    @State private var isLoaded = false

    init(json: String) {
        self.json = json
    }

    init<Value: Encodable>(value: Value) {
        self.json = InspectJSONEncoder.encode(value)
    }

    var body: some View {
        JSONInspectWebView(
            html: JSONInspectDocument.html(for: json),
            onLoad: { isLoaded = true }
        )
        .background(Color(nsColor: .textBackgroundColor))
        // The JSON runs to any length and the web view has no height of its
        // own, so the tab's bound is what it gets.
        .contentUnbounded()
        // Holds the window until the page has painted; resizing over a web
        // view that is still loading lays it out mid-render.
        .contentReady(isLoaded)
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
    let onLoad: @MainActor () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
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
        Coordinator(currentHTML: html, onLoad: onLoad)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var currentHTML: String
        let onLoad: @MainActor () -> Void

        init(currentHTML: String, onLoad: @escaping @MainActor () -> Void) {
            self.currentHTML = currentHTML
            self.onLoad = onLoad
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoad()
        }

        /// A page that failed is still a result to be sized to.
        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            onLoad()
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            onLoad()
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
