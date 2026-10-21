//
//  DuckAINativeDebugView.swift
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

import DuckAINative
import SwiftUI
import UIKit

struct DuckAINativeDebugView: View {

    @ObservedObject var settings: DuckAINativeSettings
    @StateObject private var evals = NativeEvalRunModel()

    init(settings: DuckAINativeSettings = .shared) {
        self.settings = settings
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Feature flag", value: settings.isFeatureAvailable ? "On" : "Off, enable duckAINativeMode")
                Picker("Chat", selection: $settings.routing.chat) {
                    Text("Web").tag(DuckAIRouting.Chat.web)
                    Text("Native").tag(DuckAIRouting.Chat.native)
                }
                Picker("Suggested prompts", selection: $settings.routing.suggestedPrompts) {
                    Text("Static").tag(DuckAIRouting.SuggestedPrompts.staticCatalog)
                    Text("Local model").tag(DuckAIRouting.SuggestedPrompts.localModel)
                }
                Picker("Page actions", selection: $settings.routing.pageActions) {
                    Text("Web").tag(DuckAIRouting.Action.web)
                    Text("Local").tag(DuckAIRouting.Action.local)
                }
                Picker("Selection actions", selection: $settings.routing.selectionActions) {
                    Text("Web").tag(DuckAIRouting.Action.web)
                    Text("Local").tag(DuckAIRouting.Action.local)
                }
            } header: {
                Text("Answered by a local model")
            } footer: {
                Text("Page and selection actions are Summarize and Translate. Chat covers typed prompts, other suggestions and Duck.ai entry points. Applies to new chats.")
            }
            Section("Try it") {
                Button("Open native chat") {
                    DuckAINativeDebugView.open(opening: nil)
                }
                .accessibilityIdentifier("NativeChatDebug.Open")
                Button("Open native chat with a prompt") {
                    DuckAINativeDebugView.open(opening: .prompt("Tell me about ducks"))
                }
                .accessibilityIdentifier("NativeChatDebug.OpenWithPrompt")
            }
            Section {
                switch evals.state {
                case .idle, .failed:
                    Button("Run eval set") { evals.run() }
                        .accessibilityIdentifier("NativeChatDebug.RunEvals")
                case .fetching:
                    LabeledContent("Fetching articles", value: "…")
                case .running(let done, let total):
                    SwiftUI.ProgressView(value: Double(done), total: Double(Swift.max(total, 1))) {
                        Text("Running \(done) of \(total)")
                    }
                case .finished(let files):
                    ShareLink("Share report and cases", items: files)
                    Button("Run again") { evals.run() }
                }
                if evals.isRunning {
                    Button("Cancel", role: .destructive) { evals.cancel() }
                }
                if case .failed(let message) = evals.state {
                    Text(message).foregroundStyle(.red)
                }
            } header: {
                Text("Evals")
            } footer: {
                Text("Runs every case through the selected provider, keeps the device awake, and saves report.json and cases.json for scripts/duckai-native-evals/judge.py.")
            }
            Section("Suggested prompts budget") {
                Picker("Budget", selection: $settings.suggestionsBudgetSeconds) {
                    Text("1.5 s").tag(1.5)
                    Text("3 s").tag(3.0)
                    Text("5 s").tag(5.0)
                    Text("10 s").tag(10.0)
                }
                .pickerStyle(.segmented)
            }
            MLXModelsDebugSection(settings: settings)
            Section("Provider") {
                Picker("Provider", selection: $settings.provider) {
                    Text("Automatic").tag(DuckAINativeSettings.ProviderChoice.automatic)
                    Text("Stub").tag(DuckAINativeSettings.ProviderChoice.stub)
                    Text("Apple Foundation Models").tag(DuckAINativeSettings.ProviderChoice.foundationModels)
                    Text("MLX").tag(DuckAINativeSettings.ProviderChoice.mlx)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .navigationTitle("Native Duck.ai (demo)")
    }

    private static let presenter = NativeChatPresenter()

    @MainActor
    private static func open(opening: Opening?) {
        let page = PageContext(title: "Duck", url: URL(string: "https://en.wikipedia.org/wiki/Duck"),
                               content: "Duck is the common name for many species of waterfowl in the family Anatidae.")
        guard let context = try? ChatContext(page: page, selections: [], opening: opening),
              let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first,
              var top = window.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        presenter.present(context, from: top)
    }
}
