//
//  SearchField.swift
//  Containers
//
//  Created by Axel Martinez on 5/2/26.
//

import AppKit
import SwiftUI

struct SearchField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> SearchFieldContainer {
        let container = SearchFieldContainer()
        let searchField = container.searchField
        searchField.placeholderString = "Search"
        searchField.delegate = context.coordinator

        return container
    }

    func updateNSView(_ nsView: SearchFieldContainer, context: Context) {
        if nsView.searchField.stringValue != text {
            nsView.searchField.stringValue = text
        }
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

final class SearchFieldContainer: NSView {
    let searchField = NSSearchField()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        translatesAutoresizingMaskIntoConstraints = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(searchField)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 288),
            heightAnchor.constraint(equalToConstant: 34),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            searchField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
