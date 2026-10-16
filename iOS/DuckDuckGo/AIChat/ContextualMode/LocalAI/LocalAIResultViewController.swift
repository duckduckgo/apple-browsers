//
//  LocalAIResultViewController.swift
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

import DesignResourcesKit
import LocalAI
import SwiftUI
import UIKit

/// PoC: streams an on-device answer inside the contextual sheet, in place of the Duck.ai web view.
final class LocalAIResultViewController: UIHostingController<LocalAIResultView> {

    private let model: LocalAIResultViewModel

    init(request: LocalAIRequest, engine: LocalAIEngine, onContinueInDuckAI: @escaping () -> Void) {
        model = LocalAIResultViewModel(request: request, engine: engine)
        super.init(rootView: LocalAIResultView(model: model, onContinueInDuckAI: onContinueInDuckAI))
        view.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        model.start()
    }

    func stop() {
        model.stop()
    }
}

@MainActor
final class LocalAIResultViewModel: ObservableObject {

    @Published private(set) var text = ""
    @Published private(set) var isRunning = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var stats: String?

    let request: LocalAIRequest
    let engine: LocalAIEngine
    private var task: Task<Void, Never>?

    init(request: LocalAIRequest, engine: LocalAIEngine) {
        self.request = request
        self.engine = engine
    }

    var title: String {
        switch (request.task, request.source) {
        case (.summarize, .page): "Summary of this page"
        case (.summarize, .selection): "Summary of this selection"
        case (.translate, .page): "Translation of this page"
        case (.translate, .selection): "Translation of this selection"
        }
    }

    func start() {
        guard task == nil else { return }
        isRunning = true
        task = Task { [weak self] in
            guard let self else { return }
            let (record, error) = await LocalAIRunner.run(self.request, engine: self.engine) { [weak self] chunk in
                self?.text += chunk
            }
            self.isRunning = false
            self.errorMessage = error?.localizedDescription
            self.stats = Self.describe(record)
        }
    }

    func stop() {
        task?.cancel()
    }

    deinit {
        task?.cancel()
    }

    private static func describe(_ record: LocalAIRunRecord) -> String {
        var parts: [String] = []
        if let firstToken = record.timeToFirstToken {
            parts.append(String(format: "first token %.1fs", firstToken))
        }
        if let rate = record.tokensPerSecond {
            parts.append(String(format: "%.0f tok/s", rate))
        }
        parts.append(String(format: "total %.1fs", record.totalTime))
        parts.append(ByteCountFormatter.string(fromByteCount: record.peakFootprintBytes, countStyle: .memory) + " peak")
        parts.append("thermal \(record.thermalStateAtEnd)")
        return parts.joined(separator: " · ")
    }
}

struct LocalAIResultView: View {

    @ObservedObject var model: LocalAIResultViewModel
    let onContinueInDuckAI: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.text.isEmpty && model.isRunning {
                        SwiftUI.ProgressView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text(Self.markdown(model.text))
                        .font(.body)
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundColor(Color(designSystemColor: .destructivePrimary))
                    }
                    if let stats = model.stats {
                        Text(stats)
                            .font(.caption.monospacedDigit())
                            .foregroundColor(Color(designSystemColor: .textSecondary))
                    }
                }
            }
            actions
        }
        .padding(16)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.title)
                .font(.headline)
                .accessibilityIdentifier("LocalAI.Result")
                .foregroundColor(Color(designSystemColor: .textPrimary))
            Label("On device · \(model.engine.modelName)", systemImage: "iphone")
                .font(.caption)
                .foregroundColor(Color(designSystemColor: .textSecondary))
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            if model.isRunning {
                Button("Stop", action: model.stop)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("LocalAI.Stop")
            }
            Spacer()
            Button("Continue in Duck.ai", action: onContinueInDuckAI)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("LocalAI.ContinueInDuckAI")
        }
    }

    /// Keeps line breaks so bullets and paragraphs survive; block-level Markdown isn't rendered.
    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
