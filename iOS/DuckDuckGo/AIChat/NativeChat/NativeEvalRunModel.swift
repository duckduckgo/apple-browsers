//
//  NativeEvalRunModel.swift
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

import DuckAIEvals
import Foundation
import UIKit

/// Demo branch: runs the eval set through the selected provider on this device and saves the report and cases for
/// `scripts/duckai-native-evals/judge.py`.
@MainActor
final class NativeEvalRunModel: ObservableObject {

    enum State: Equatable {
        case idle
        case fetching
        case running(done: Int, total: Int)
        case finished(files: [URL])
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    var isRunning: Bool {
        switch state {
        case .fetching, .running: true
        default: false
        }
    }

    func run(runs: Int = 1) {
        guard !isRunning else { return }
        task = Task { [weak self] in await self?.perform(runs: runs) }
    }

    func cancel() {
        task?.cancel()
        state = .idle
    }

    private func perform(runs: Int) async {
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        state = .fetching
        do {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let articles = try await EvalArticles.fetch(cacheDirectory: caches.appendingPathComponent("duckai-evals"))
            let cases = EvalSet.make(articles: articles)
            let provider = NativeChatProviderFactory.makeProvider()
            await provider.prepare()
            state = .running(done: 0, total: cases.count * runs)
            let report = await EvalRunner(provider: provider, metrics: ProcessMetrics())
                .run(cases, runs: runs, device: UIDevice.current.model, osVersion: UIDevice.current.systemVersion) { done, total in
                    Task { @MainActor [weak self] in self?.state = .running(done: done, total: total) }
                }
            state = .finished(files: try save(report: report, cases: cases))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func save(report: EvalReport, cases: [EvalCase]) throws -> [URL] {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stamp = ISO8601DateFormatter().string(from: report.startedAt).replacingOccurrences(of: ":", with: "-")
        let folder = documents.appendingPathComponent("duckai-evals/\(stamp)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reportURL = folder.appendingPathComponent("report.json")
        let casesURL = folder.appendingPathComponent("cases.json")
        try encoder.encode(report).write(to: reportURL)
        try encoder.encode(cases).write(to: casesURL)
        return [reportURL, casesURL]
    }
}
