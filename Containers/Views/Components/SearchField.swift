//
//  SearchField.swift
//  Containers
//
//  Created by Axel Martinez on 5/2/26.
//

import SwiftUI

struct SearchField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = "Search"
        searchField.delegate = context.coordinator
        searchField.widthAnchor.constraint(equalToConstant: 280).isActive = true

        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        nsView.stringValue = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchField

        init(_ parent: SearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSSearchField else { return }
            parent.text = textField.stringValue
        }
    }
}
