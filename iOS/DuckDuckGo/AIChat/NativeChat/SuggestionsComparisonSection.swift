//
//  SuggestionsComparisonSection.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import DuckAILocalTasks
import SwiftUI

struct SuggestionsComparisonSection: View {
    @StateObject private var comparison = SuggestionsComparison()

    var body: some View {
        Section {
            Button(comparison.running ? "Cancel suggestions comparison" : "Compare suggestion variants") {
                if comparison.running { comparison.cancel() } else { comparison.run() }
            }
            .accessibilityIdentifier("NativeChatDebug.CompareSuggestions")
            Text("Same bounded Mallard sample, same engine as the sheet. Selected model title, headings and body; guided Foundation Models; English templates; 3 and 4 prompts. Models may already be warm. Page-load cache timing requires opening a real page and is shown in Last run.")
                .font(.caption)
            ForEach(comparison.rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.title).font(.headline)
                    Text(row.outcome)
                    ForEach(row.details, id: \.self) { Text($0).font(.caption) }
                    Text(row.output).font(.caption).textSelection(.enabled)
                }
            }
        } header: {
            Text("Suggested prompts comparison")
        }
    }
}

@MainActor
private final class SuggestionsComparison: ObservableObject {
    struct Row: Identifiable {
        let id = UUID()
        let title: String
        let outcome: String
        let details: [String]
        let output: String
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var running = false
    private var task: Task<Void, Never>?

    deinit { task?.cancel() }

    func cancel() {
        task?.cancel()
        task = nil
        running = false
    }

    func run() {
        guard !running else { return }
        rows = []
        running = true
        NotificationCenter.default.post(name: .nativeChatWillStart, object: nil)
        let selected = DuckAINativeSettings.shared.suggestionsVariant()
        let provider = NativeChatProviderFactory.makeProvider(for: .suggestedPrompts)
        var variants = SuggestionsVariant.Input.allCases.map { input in
            var variant = selected
            variant.method = .model
            variant.input = input
            variant.count = 3
            return variant
        }
        for method in [SuggestionsVariant.Method.foundationModels, .templates] {
            var variant = selected
            variant.method = method
            variant.input = .headings
            variant.count = 3
            variants.append(variant)
        }
        var four = selected
        four.count = 4
        variants.append(four)
        task = Task { [weak self] in
            for variant in variants {
                guard !Task.isCancelled else { break }
                let result = await SuggestionsEngine.run(page: Self.page, variant: variant, provider: provider)
                guard !Task.isCancelled else { break }
                let output: String
                if case .generated(let prompts, _) = result.result {
                    output = prompts.map(\.text).joined(separator: "\n")
                } else {
                    output = result.raw
                }
                self?.rows.append(Row(title: "\(variant.method.rawValue) · \(variant.input.rawValue) · \(variant.count)",
                                      outcome: LocalSuggestionsDiagnostics.outcome(result.result),
                                      details: LocalSuggestionsDiagnostics.details(run: result, variant: variant), output: output))
            }
            guard !Task.isCancelled else { return }
            self?.running = false
            self?.task = nil
        }
    }

    private static let page = PageSnapshot(
        title: "Mallard", url: URL(string: "https://en.wikipedia.org/wiki/Mallard"),
        content: "Mallards are dabbling ducks. Males have green heads; females are mottled brown. They eat plants, seeds and insects in shallow water. They nest near water and ducklings swim soon after hatching. Many domestic ducks descend from mallards.",
        language: "en", description: "The mallard is a common dabbling duck found across temperate regions.",
        headings: ["Description", "Distribution and habitat", "Feeding", "Breeding", "Conservation"])
}
