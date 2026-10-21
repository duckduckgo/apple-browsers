//
//  DuckAINativeSettings.swift
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
import DuckAINative
import FeatureFlags_iOS
import Foundation
import PrivacyConfig

final class DuckAINativeSettings: ObservableObject {

    /// The jobs a local model does. Each picks its own model.
    enum LocalTask: String, CaseIterable {
        case chat
        case summarize
        case translate
        case suggestedPrompts
    }

    enum TaskModel: Hashable {
        /// Chat: the MLX model that fits this device, or the stub on the simulator. Other jobs: whatever chat uses.
        case automatic
        case stub
        case foundationModels
        case mlx(id: String)

        init(storedValue: String) {
            switch storedValue {
            case "stub": self = .stub
            case "foundationModels": self = .foundationModels
            case let value where value.hasPrefix("mlx:"): self = .mlx(id: String(value.dropFirst(4)))
            default: self = .automatic
            }
        }

        var storedValue: String {
            switch self {
            case .automatic: "automatic"
            case .stub: "stub"
            case .foundationModels: "foundationModels"
            case .mlx(let id): "mlx:\(id)"
            }
        }
    }

    static let shared = DuckAINativeSettings()

    @Published var routing: DuckAIRouting {
        didSet { save(routing) }
    }

    @Published var taskModels: [LocalTask: TaskModel] {
        didSet {
            for (task, model) in taskModels {
                defaults.set(model.storedValue, forKey: Keys.taskModel(task))
            }
        }
    }

    @Published var suggestionsBudgetSeconds: Double {
        didSet { defaults.set(suggestionsBudgetSeconds, forKey: Keys.suggestionsBudget) }
    }

    private let defaults: UserDefaults
    private let featureFlagger: FeatureFlagger

    init(defaults: UserDefaults = .standard, featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        self.defaults = defaults
        self.featureFlagger = featureFlagger
        routing = DuckAIRouting(
            chat: defaults.string(forKey: Keys.chat).flatMap(DuckAIRouting.Chat.init) ?? .web,
            suggestedPrompts: defaults.string(forKey: Keys.suggestedPrompts).flatMap(DuckAIRouting.SuggestedPrompts.init) ?? .staticCatalog,
            pageActions: defaults.string(forKey: Keys.pageActions).flatMap(DuckAIRouting.Action.init) ?? .web,
            selectionActions: defaults.string(forKey: Keys.selectionActions).flatMap(DuckAIRouting.Action.init) ?? .web
        )
        suggestionsBudgetSeconds = defaults.object(forKey: Keys.suggestionsBudget) as? Double ?? 1.5
        taskModels = Dictionary(uniqueKeysWithValues: LocalTask.allCases.map { task in
            (task, TaskModel(storedValue: defaults.string(forKey: Keys.taskModel(task)) ?? ""))
        })
    }

    var isFeatureAvailable: Bool {
        featureFlagger.isFeatureOn(.duckAINativeMode)
    }

    /// The one check every surface asks before opening a new chat.
    var opensNewChatsNatively: Bool {
        isFeatureAvailable && routing.answersNatively(.chat)
    }

    /// The contextual sheet's suggestions: page and selection actions follow their own rows, other suggestions follow Chat.
    func answersNatively(suggestionID: String) -> Bool {
        isFeatureAvailable && routing.answersNatively(DuckAIRouting.entry(forSuggestionID: suggestionID))
    }

    var generatesSuggestedPromptsLocally: Bool {
        isFeatureAvailable && routing.generatesSuggestedPromptsLocally
    }

    private func save(_ routing: DuckAIRouting) {
        defaults.set(routing.chat.rawValue, forKey: Keys.chat)
        defaults.set(routing.suggestedPrompts.rawValue, forKey: Keys.suggestedPrompts)
        defaults.set(routing.pageActions.rawValue, forKey: Keys.pageActions)
        defaults.set(routing.selectionActions.rawValue, forKey: Keys.selectionActions)
    }

    /// `duckAINative.mode` predates the routing table; keeping it lets the `duckAINative.mode` launch argument still pick Chat.
    private enum Keys {
        static let chat = "duckAINative.mode"
        static let suggestedPrompts = "duckAINative.suggestedPrompts"
        static let pageActions = "duckAINative.pageActions"
        static let selectionActions = "duckAINative.selectionActions"
        static let suggestionsBudget = "duckAINative.suggestionsBudget"

        static func taskModel(_ task: LocalTask) -> String {
            "duckAINative.model.\(task.rawValue)"
        }
    }
}
