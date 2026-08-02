//
//  TextField+Suggestions.swift
//  Containers
//
//  Created by Axel Martinez on 01/08/2026.
//

import Combine
import SwiftUI

extension TextField {
    /// Completes the field from `text`, once typing stops.
    ///
    /// Pass `nil` to suggest nothing: a field that is not being typed into, or
    /// one holding something that cannot be looked up. Any pending or in-flight
    /// lookup is abandoned and the menu closes.
    ///
    /// This is an extension on `TextField` rather than on `View`, so it has to
    /// come first in the chain — every later modifier returns `some View`.
    func suggestions(
        for text: String?,
        fetch: @escaping @Sendable (String) async throws -> [String]
    ) -> some View {
        modifier(TextFieldSuggestions(text: text, fetch: fetch))
    }
}

private struct TextFieldSuggestions: ViewModifier {
    let text: String?
    let fetch: @Sendable (String) async throws -> [String]

    @SwiftUI.State private var resolver = SuggestionResolver()

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                if resolver.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 6)
                } else if let failure = resolver.failure {
                    // An empty menu otherwise reads as "nothing matched".
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(failure)
                        .padding(.trailing, 6)
                        .accessibilityLabel(failure)
                }
            }
            .textInputSuggestions {
                ForEach(resolver.suggestions, id: \.self) { suggestion in
                    Text(suggestion)
                        .textInputCompletion(suggestion)
                }
            }
            .onChange(of: text) { _, newText in
                // Text matching what is on the menu means the user just picked
                // it, so close up rather than look the same thing up again.
                guard let newText, !newText.isEmpty,
                    !resolver.suggestions.contains(newText)
                else {
                    resolver.reset()
                    return
                }

                resolver.send(newText, using: fetch)
            }
            .onDisappear {
                resolver.reset()
            }
    }
}

/// Turns the stream of text produced while typing into at most one request,
/// made once typing stops.
///
/// Text arrives on every keystroke. Nothing is fetched until the stream stays
/// quiet for `debounce`, and text matching what is already loaded is dropped,
/// so holding down a key or retyping the same thing costs nothing.
@Observable
private final class SuggestionResolver {
    private(set) var suggestions: [String] = []
    private(set) var isLoading = false

    /// Why the last lookup came back empty, when it came back empty because it
    /// failed rather than because nothing matched.
    private(set) var failure: String?

    private let queries = PassthroughSubject<String?, Never>()

    /// Tied to this field and emptied whenever it stops suggesting, so an entry
    /// never outlives the image name or registry it was looked up against. That
    /// is what lets the text alone be the key.
    @ObservationIgnored private var cache = SuggestionCache()
    @ObservationIgnored private var fetch: (@Sendable (String) async throws -> [String])?
    @ObservationIgnored private var subscription: AnyCancellable?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var loadedText: String?

    init(debounce: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(300)) {
        self.subscription =
            queries
            .debounce(for: debounce, scheduler: DispatchQueue.main)
            .sink { [weak self] text in
                MainActor.assumeIsolated {
                    guard let text else { return }
                    self?.load(text)
                }
            }
    }

    /// Records the text typed so far, and the lookup to answer it with. The
    /// lookup is taken every time, so it never goes stale against the view.
    func send(
        _ text: String,
        using fetch: @escaping @Sendable (String) async throws -> [String]
    ) {
        self.fetch = fetch
        queries.send(text)
    }

    /// Drops any pending or in-flight lookup and empties the suggestion list.
    func reset() {
        queries.send(nil)
        fetchTask?.cancel()
        fetchTask = nil
        loadedText = nil
        suggestions = []
        failure = nil
        isLoading = false
        cache.removeAll()
    }

    private func load(_ text: String) {
        guard text != loadedText, let fetch else { return }

        fetchTask?.cancel()
        loadedText = text

        // Answered from memory, without the network or a flash of spinner.
        if let cached = cache.values(for: text) {
            suggestions = cached
            failure = nil
            isLoading = false
            return
        }

        isLoading = true

        fetchTask = Task {
            do {
                let results = try await fetch(text)

                // A cancelled task leaves `isLoading` alone: the text that
                // replaced it owns the spinner from here on.
                guard !Task.isCancelled else { return }

                cache.store(results, for: text)
                suggestions = results
                failure = nil
                isLoading = false
            } catch {
                guard !Task.isCancelled else { return }

                // Failures are not remembered, so retyping the same text
                // retries rather than resting on the empty result.
                loadedText = nil
                suggestions = []
                failure = error.localizedDescription
                isLoading = false
            }
        }
    }
}

/// Remembers what this field has already looked up, so backspacing a character
/// answers from memory instead of going back to the network.
private struct SuggestionCache {
    private struct Entry {
        let values: [String]
        let stored: ContinuousClock.Instant
    }

    private let ttl: Duration = .seconds(120)
    private let limit = 32

    private var entries: [String: Entry] = [:]

    func values(for text: String) -> [String]? {
        guard let entry = entries[text],
            entry.stored.duration(to: ContinuousClock.now) < ttl
        else {
            return nil
        }

        return entry.values
    }

    mutating func store(_ values: [String], for text: String) {
        entries[text] = Entry(values: values, stored: ContinuousClock.now)

        guard entries.count > limit else {
            return
        }

        // Drop what has already expired, and only if that was not enough,
        // the oldest of what is left.
        let now = ContinuousClock.now
        entries = entries.filter { $0.value.stored.duration(to: now) < ttl }

        guard entries.count > limit else {
            return
        }

        let excess =
            entries
            .sorted { $0.value.stored < $1.value.stored }
            .prefix(entries.count - limit)

        for entry in excess {
            entries[entry.key] = nil
        }
    }

    mutating func removeAll() {
        entries.removeAll()
    }
}
