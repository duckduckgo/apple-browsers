//
//  LocalAIDebugView.swift
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

import Core
import FeatureFlags_iOS
import LocalAI
import PrivacyConfig
import SwiftUI

/// PoC debug screen: pick an engine and model, download models in-app, try a prompt, run the benchmark.
struct LocalAIDebugView: View {

    @ObservedObject var service: LocalAIContextualService
    @ObservedObject var store: LocalAIModelStore
    let featureFlagger: FeatureFlagger

    @State private var quickTestOutput = ""
    @State private var quickTestTask: Task<Void, Never>?
    @State private var benchmarkProgress: (done: Int, total: Int)?
    @State private var benchmarkTask: Task<Void, Never>?
    @State private var benchmarkMessage: String?
    @State private var lastReport: URL?
    @State private var interruptedCount = LocalAIInterruptedRunTracker.interruptedCount()

    init(service: LocalAIContextualService = .shared, featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        self.service = service
        self.store = service.modelStore
        self.featureFlagger = featureFlagger
    }

    var body: some View {
        List {
            statusSection
            engineSection
            modelsSection
            quickTestSection
            benchmarkSection
        }
        .navigationTitle("On-device AI (PoC)")
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            row("Feature flag", featureFlagger.isFeatureOn(.localAIContextualActions) ? "On" : "Off — enable localAIContextualActions")
            row("Engine", service.currentEngine?.unavailableReason ?? "Ready")
            row("Device memory", ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory))
            row("Available to app now", LocalAIDeviceMetrics.availableMemory().map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .memory) } ?? "–")
            HStack {
                row("Interrupted generations", "\(interruptedCount)")
                Button("Reset") {
                    LocalAIInterruptedRunTracker.reset()
                    interruptedCount = 0
                }
            }
        } header: {
            Text("Status")
        } footer: {
            Text("An interrupted generation is one the app died during, most likely killed by iOS for memory.")
        }
    }

    private var engineSection: some View {
        Section("Engine and actions") {
            Picker("Engine", selection: $service.engineKind) {
                ForEach(LocalAIEngineKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            ForEach(LocalAISuggestion.allCases, id: \.self) { suggestion in
                Toggle(suggestion.rawValue, isOn: Binding(get: { service.isEnabled(suggestion) },
                                                          set: { service.setEnabled($0, for: suggestion) }))
            }
            Toggle("Keep model loaded after the sheet closes", isOn: $service.keepsModelLoaded)
            Picker("Page text for summaries", selection: $service.summaryPageCharacterLimit) {
                ForEach(LocalAIContextualService.summaryPageCharacterLimits, id: \.self) { limit in
                    Text("\(limit) characters").tag(limit)
                }
            }
            Picker("MLX prefill step", selection: $service.prefillStepSize) {
                ForEach(LocalAIContextualService.prefillStepSizes, id: \.self) { size in
                    Text("\(size) tokens").tag(size)
                }
            }
            Button("Unload models now", action: service.unloadModels)
        }
    }

    private var modelsSection: some View {
        Section {
            ForEach(LocalAIModelCatalog.all) { model in
                modelRow(model)
            }
        } header: {
            Text("MLX models")
        } footer: {
            Text("Downloaded from Hugging Face into Application Support, excluded from backup. Keep the app open while downloading.")
        }
    }

    private func modelRow(_ model: LocalAIModel) -> some View {
        let state = store.state(of: model)
        let fits = LocalAIModelCatalog.fits(model, physicalMemory: ProcessInfo.processInfo.physicalMemory)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: store.selectedModelID == model.id ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(.accentColor)
                    .onTapGesture { store.selectedModelID = model.id }
                VStack(alignment: .leading) {
                    Text(model.displayName)
                    Text("\(ByteCountFormatter.string(fromByteCount: model.approximateBytes, countStyle: .file)) · \(model.licence)\(fits ? "" : " · needs \(model.minimumPhysicalMemoryGB) GB RAM")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            switch state {
            case .notDownloaded:
                Button("Download") { store.download(model) }
                    .disabled(store.isDownloading)
            case .downloading(let fraction, let received, let total):
                SwiftUI.ProgressView(value: fraction) {
                    Text("\(ByteCountFormatter.string(fromByteCount: received, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                        .font(.caption)
                }
                Button("Cancel", role: .destructive, action: store.cancelDownload)
            case .downloaded(let bytes):
                HStack {
                    Text("Downloaded, \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) on disk")
                        .font(.caption)
                    Spacer()
                    Button("Delete", role: .destructive) {
                        service.unloadModels()
                        store.delete(model)
                    }
                }
            case .failed(let message):
                Text(message).font(.caption).foregroundColor(.red)
                Button("Retry") { store.download(model) }
                    .disabled(store.isDownloading)
            }
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }

    private var quickTestSection: some View {
        Section("Quick test") {
            Button(quickTestTask == nil ? "Summarize a sample paragraph" : "Stop") {
                if let quickTestTask {
                    quickTestTask.cancel()
                    self.quickTestTask = nil
                } else {
                    runQuickTest()
                }
            }
            .disabled(service.currentEngine?.unavailableReason != nil)
            if !quickTestOutput.isEmpty {
                Text(quickTestOutput).font(.callout).textSelection(.enabled)
            }
        }
    }

    private var benchmarkSection: some View {
        Section {
            if let benchmarkProgress {
                SwiftUI.ProgressView(value: Double(benchmarkProgress.done), total: Double(max(benchmarkProgress.total, 1))) {
                    Text("\(benchmarkProgress.done) of \(benchmarkProgress.total) runs")
                }
                Button("Cancel", role: .destructive) { benchmarkTask?.cancel() }
            } else {
                Button("Run benchmark with \(service.engineKind.displayName)", action: runBenchmark)
                    .disabled(service.currentEngine?.unavailableReason != nil)
            }
            if let benchmarkMessage {
                Text(benchmarkMessage).font(.caption)
            }
            if let lastReport {
                ShareLink(item: lastReport) {
                    Label("Share \(lastReport.lastPathComponent)", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("Benchmark")
        } footer: {
            Text("28 Wikipedia-based requests × \(LocalAIBenchmarkRunner.runsPerCase) runs. The articles are fetched once, then cached, so later runs work offline.")
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary).multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Actions

    private func runQuickTest() {
        guard let engine = service.currentEngine else { return }
        quickTestOutput = ""
        let sample = """
        The Eiffel Tower is a wrought-iron lattice tower on the Champ de Mars in Paris, France. It is named after the engineer \
        Gustave Eiffel, whose company designed and built the tower from 1887 to 1889. Locally nicknamed "La dame de fer", it was \
        constructed as the centrepiece of the 1889 World's Fair, and to crown the centennial anniversary of the French Revolution.
        """
        let request = LocalAIRequest(task: .summarize, source: .selection([sample]), language: LocalAIContextualService.userLanguageName)
        quickTestTask = Task {
            let (record, error) = await LocalAIRunner.run(request, engine: engine) { quickTestOutput += $0 }
            quickTestOutput += "\n\n" + (error?.localizedDescription ?? String(format: "load %.2fs, read %d tokens in %.2fs, first token %.2fs, %.0f tok/s, %@ peak",
                                                                                    record.loadTime ?? 0, record.promptTokens ?? 0, record.promptTime ?? 0,
                                                                                    record.timeToFirstToken ?? 0, record.tokensPerSecond ?? 0,
                                                                                    ByteCountFormatter.string(fromByteCount: record.peakFootprintBytes, countStyle: .memory)))
            quickTestTask = nil
        }
    }

    private func runBenchmark() {
        guard let engine = service.currentEngine else { return }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalAIBenchmark", isDirectory: true)
        benchmarkMessage = "Preparing articles…"
        benchmarkProgress = (0, 0)
        UIApplication.shared.isIdleTimerDisabled = true
        benchmarkTask = Task {
            defer {
                UIApplication.shared.isIdleTimerDisabled = false
                benchmarkProgress = nil
                benchmarkTask = nil
                interruptedCount = LocalAIInterruptedRunTracker.interruptedCount()
            }
            do {
                let cases = try await LocalAIBenchmarkSet.cases(language: "English", cacheDirectory: documents.appendingPathComponent("articles", isDirectory: true))
                benchmarkMessage = "Running…"
                let file = try await LocalAIBenchmarkRunner().run(cases: cases, engine: engine, device: UIDevice.current.model + " " + Self.hardwareIdentifier,
                                                                  osVersion: UIDevice.current.systemVersion, outputDirectory: documents) { done, total in
                    benchmarkProgress = (done, total)
                }
                lastReport = file
                benchmarkMessage = "Saved \(file.lastPathComponent)"
            } catch {
                benchmarkMessage = "Stopped: \(error.localizedDescription)"
            }
        }
    }

    /// e.g. `iPhone16,1`, so reports say which model ran them.
    private static var hardwareIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { buffer in
            String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8) ?? "unknown"
        }
    }
}
