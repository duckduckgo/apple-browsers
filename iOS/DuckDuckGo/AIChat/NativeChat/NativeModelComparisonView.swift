//
//  NativeModelComparisonView.swift
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

import DuckAIChatCore
import DuckAIChatMLX
import DuckAIEvals
import SwiftUI
import UIKit

/// Runs one job on one built-in page through several models, one model at a time, and lays the numbers side by side.
struct NativeModelComparisonView: View {
    @StateObject private var model = NativeModelComparison()

    var body: some View {
        List {
            SuggestionsComparisonSection()
            Section {
                Picker("Job", selection: $model.job) {
                    ForEach(NativeModelComparison.Job.allCases) { Text($0.title).tag($0) }
                }
                Picker("Runs per model", selection: $model.runs) {
                    Text("1").tag(1)
                    Text("3").tag(3)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Each model is unloaded first, so load time is a cold start. With 3 runs, times are medians.")
            }
            Section("Models") {
                ForEach(model.candidates) { candidate in
                    Toggle(isOn: model.binding(for: candidate)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.name)
                            if !candidate.isRunnable {
                                Text(candidate.unavailableReason).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!candidate.isRunnable || model.isRunning)
                }
            }
            Section {
                if model.isRunning {
                    LabeledContent(model.progress, value: "…")
                    Button("Cancel", role: .destructive) { model.cancel() }
                } else {
                    Button("Run comparison") { model.run() }
                        .disabled(model.selected.isEmpty)
                        .accessibilityIdentifier("NativeChatDebug.RunComparison")
                }
                if let file = model.reportFile {
                    ShareLink("Share results", item: file)
                }
            }
            ForEach(model.results) { result in
                Section(result.name) {
                    LabeledContent("Outcome", value: result.outcome)
                    LabeledContent("Load (cold)", value: Self.seconds(result.loadTime))
                    LabeledContent("First token", value: Self.seconds(result.timeToFirstToken))
                    LabeledContent("Total", value: Self.seconds(result.totalTime))
                    LabeledContent("Speed", value: result.tokensPerSecond.map { String(format: "%.1f tok/s", $0) } ?? "–")
                    LabeledContent("Peak memory", value: result.peakMemoryBytes.map {
                        ByteCountFormatter.string(fromByteCount: $0, countStyle: .memory)
                    } ?? "–")
                    LabeledContent("Thermal", value: result.thermalState ?? "–")
                    Text(result.output.isEmpty ? "(no output)" : result.output)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Compare models")
    }

    private static func seconds(_ value: Double?) -> String {
        value.map { String(format: "%.2f s", $0) } ?? "–"
    }
}

@MainActor
final class NativeModelComparison: ObservableObject {

    enum Job: String, CaseIterable, Identifiable {
        case summarize, translate

        var id: String { rawValue }

        var title: String {
            switch self {
            case .summarize: "Summarize page"
            case .translate: "Translate page to German"
            }
        }

        var localTask: DuckAINativeSettings.LocalTask {
            switch self {
            case .summarize: .summarize
            case .translate: .translate
            }
        }

        var evalTask: EvalTask {
            switch self {
            case .summarize: .summarizePage
            case .translate: .translatePage
            }
        }
    }

    struct Candidate: Identifiable, Hashable {
        let model: DuckAINativeSettings.TaskModel
        let name: String
        let isRunnable: Bool
        let unavailableReason: String
        var id: String { model.storedValue }
    }

    struct Result: Identifiable, Codable {
        let id: String
        let name: String
        let outcome: String
        let loadTime: Double?
        let timeToFirstToken: Double?
        let totalTime: Double?
        let tokensPerSecond: Double?
        let peakMemoryBytes: Int64?
        let thermalState: String?
        let output: String
    }

    @Published var job: Job = .summarize
    @Published var runs = 1
    @Published var selected: Set<String> = []
    @Published private(set) var results: [Result] = []
    @Published private(set) var progress = ""
    @Published private(set) var reportFile: URL?
    private var task: Task<Void, Never>?

    var isRunning: Bool { task != nil }

    var candidates: [Candidate] {
        var list = [Candidate(model: .stub, name: "Stub", isRunnable: true, unavailableReason: "")]
        let foundationModels = NativeChatProviderFactory.isFoundationModelsAvailable
        list.append(Candidate(model: .foundationModels, name: "Apple Foundation Models", isRunnable: foundationModels,
                              unavailableReason: "Not available on this device"))
        list += ModelCatalog.all.map { model in
            Candidate(model: .mlx(id: model.id), name: model.displayName, isRunnable: TaskModelPicker.isDownloaded(model),
                      unavailableReason: "Not downloaded")
        }
        return list
    }

    func binding(for candidate: Candidate) -> Binding<Bool> {
        Binding(get: { self.selected.contains(candidate.id) },
                set: { if $0 { self.selected.insert(candidate.id) } else { self.selected.remove(candidate.id) } })
    }

    func run() {
        guard task == nil else { return }
        let chosen = candidates.filter { selected.contains($0.id) && $0.isRunnable }
        let evalCase = EvalCase(id: "compare-\(job.rawValue)", task: job.evalTask, page: Self.page, selection: nil,
                                languageName: job == .translate ? "German" : "English")
        let runs = runs
        let job = job
        results = []
        reportFile = nil
        task = Task { [weak self] in
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            for (index, candidate) in chosen.enumerated() {
                guard !Task.isCancelled else { break }
                self?.progress = "Running \(candidate.name) (\(index + 1) of \(chosen.count))"
                let result = await Self.measure(candidate, job: job, evalCase: evalCase, runs: runs)
                self?.results.append(result)
            }
            self?.reportFile = self?.save()
            self?.task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private static func measure(_ candidate: Candidate, job: Job, evalCase: EvalCase, runs: Int) async -> Result {
        let provider = NativeChatProviderFactory.provider(for: candidate.model, task: job.localTask)
        provider.unload()
        try? await Task.sleep(for: .milliseconds(300))
        let loadStart = ContinuousClock.now
        await provider.prepare()
        let loadTime = seconds(ContinuousClock.now - loadStart)
        let report = await EvalRunner(provider: provider, metrics: ProcessMetrics())
            .run([evalCase], runs: runs, device: UIDevice.current.model, osVersion: UIDevice.current.systemVersion)
        if case .mlx = candidate.model {
            provider.unload()
        }
        let records = report.records
        return Result(id: candidate.id, name: candidate.name,
                      outcome: records.map(\.outcome.rawValue).joined(separator: ", "),
                      loadTime: loadTime,
                      timeToFirstToken: median(records.compactMap(\.timeToFirstToken)),
                      totalTime: median(records.map(\.totalTime)),
                      tokensPerSecond: median(records.compactMap(\.tokensPerSecond)),
                      peakMemoryBytes: records.compactMap(\.peakMemoryBytes).max(),
                      thermalState: records.last?.thermalState,
                      output: records.last.map { $0.error ?? $0.output } ?? "")
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private func save() -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("duckai-compare-\(job.rawValue).json")
        guard let data = try? encoder.encode(results), (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    /// A fixed page, so every model reads the same input and no network is needed.
    private static let page = EvalPage(
        title: "Mallard",
        url: URL(string: "https://en.wikipedia.org/wiki/Mallard"),
        content: """
        The mallard is a dabbling duck that breeds across the temperate and subtropical Americas, Eurasia and North \
        Africa. Males have a glossy green head, a white collar and a grey body, while females are mottled brown, which \
        hides them while they sit on eggs. Mallards feed by tipping forward in shallow water to reach plants, seeds, \
        insects and small snails rather than diving. They form pairs in autumn, and the female lays eight to thirteen \
        eggs in a nest on the ground near water. Ducklings can swim and feed themselves within hours of hatching, but \
        they stay with their mother for about two months. Most domestic duck breeds descend from the mallard, and wild \
        mallards readily breed with related species, which threatens some of them. The species is common in city parks, \
        where people often feed it bread, a habit that can harm the birds and the water they live in.
        """,
        language: "en")
}
