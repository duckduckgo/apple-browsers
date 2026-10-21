//
//  LocalAIContextualService.swift
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

import AIChat
import Combine
import FeatureFlags_iOS
import Foundation
import LocalAI
import LocalAIMLX
import PrivacyConfig
import UIKit

/// PoC: decides whether a contextual-sheet suggestion is answered on the device, and owns the engines
/// and the downloaded models. Everything is behind `.localAIContextualActions` and debug settings.
@MainActor
final class LocalAIContextualService: ObservableObject {

    static let shared = LocalAIContextualService()

    let modelStore = LocalAIModelStore()

    @Published var engineKind: LocalAIEngineKind {
        didSet {
            defaults.set(engineKind.rawValue, forKey: Keys.engine)
            if oldValue != engineKind { engine(for: oldValue)?.unload() }
        }
    }

    /// Unloading on dismissal frees ~1.5 GB but makes every first token pay for a model load.
    @Published var keepsModelLoaded: Bool {
        didSet { defaults.set(keepsModelLoaded, forKey: Keys.keepsModelLoaded) }
    }

    @Published private(set) var enabledSuggestions: Set<LocalAISuggestion>

    /// MLX's prompt step size, to compare how fast a page is read (512 is MLX's default). 2,048 crashed
    /// the app on an iPhone 17 Pro Max during the first translate, most likely its prefill buffers.
    @Published var prefillStepSize: Int {
        didSet {
            defaults.set(prefillStepSize, forKey: Keys.prefillStepSize)
            mlxEngine.prefillStepSize = prefillStepSize
        }
    }
    static let prefillStepSizes = [512, 1024]

    /// How much of the page a summary reads. A summary can't be sent in pieces, so its first words wait
    /// for the whole read; 4,000 characters is roughly 1,000 tokens instead of ~2,500 for the full 9,500.
    @Published var summaryPageCharacterLimit: Int {
        didSet { defaults.set(summaryPageCharacterLimit, forKey: Keys.summaryPageCharacterLimit) }
    }
    static let summaryPageCharacterLimits = [2_000, 4_000, 9_500]

    private let defaults: UserDefaults
    private lazy var mlxEngine = MLXLocalAIEngine(store: modelStore)
    /// About the speed of a 2B model on a phone, so Stop and follow-ups can be tried in the simulator.
    private let stubEngine = StubLocalAIEngine(tokensPerSecond: 8)
    private var foundationModelsEngine: LocalAIEngine?
    private var cancellables = Set<AnyCancellable>()

    private enum Keys {
        static let engine = "localAI.engine"
        static let keepsModelLoaded = "localAI.keepsModelLoaded"
        static let disabledSuggestions = "localAI.disabledSuggestions"
        static let prefillStepSize = "localAI.prefillStepSize"
        static let summaryPageCharacterLimit = "localAI.summaryPageCharacterLimit"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if targetEnvironment(simulator)
        let defaultEngine = LocalAIEngineKind.stub
        #else
        let defaultEngine = LocalAIEngineKind.mlx
        #endif
        engineKind = defaults.string(forKey: Keys.engine).flatMap(LocalAIEngineKind.init(rawValue:)) ?? defaultEngine
        keepsModelLoaded = defaults.bool(forKey: Keys.keepsModelLoaded)
        let storedStepSize = defaults.object(forKey: Keys.prefillStepSize) as? Int ?? 512
        prefillStepSize = Self.prefillStepSizes.contains(storedStepSize) ? storedStepSize : 512
        summaryPageCharacterLimit = defaults.object(forKey: Keys.summaryPageCharacterLimit) as? Int ?? 4_000
        let disabled = Set(defaults.stringArray(forKey: Keys.disabledSuggestions) ?? [])
        enabledSuggestions = Set(LocalAISuggestion.allCases.filter { !disabled.contains($0.rawValue) })

        if #available(iOS 26.0, *) {
            foundationModelsEngine = FoundationModelsLocalAIEngine()
        }
        mlxEngine.prefillStepSize = prefillStepSize
        LocalAIInterruptedRunTracker.recordInterruptedRunIfAny(defaults: defaults)

        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in self?.unloadModels() }
            .store(in: &cancellables)
        modelStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var currentEngine: LocalAIEngine? {
        engine(for: engineKind)
    }

    func engine(for kind: LocalAIEngineKind) -> LocalAIEngine? {
        switch kind {
        case .mlx: mlxEngine
        case .foundationModels: foundationModelsEngine
        case .stub: stubEngine
        }
    }

    func isEnabled(_ suggestion: LocalAISuggestion) -> Bool {
        enabledSuggestions.contains(suggestion)
    }

    func setEnabled(_ enabled: Bool, for suggestion: LocalAISuggestion) {
        if enabled {
            enabledSuggestions.insert(suggestion)
        } else {
            enabledSuggestions.remove(suggestion)
        }
        let disabled = LocalAISuggestion.allCases.filter { !enabledSuggestions.contains($0) }.map(\.rawValue)
        defaults.set(disabled, forKey: Keys.disabledSuggestions)
    }

    /// Whether to try answering `suggestionID` locally. Context is checked later, once it's attached.
    func handlesLocally(suggestionID: String, featureFlagger: FeatureFlagger) -> Bool {
        guard featureFlagger.isFeatureOn(.localAIContextualActions),
              let suggestion = LocalAISuggestion(rawValue: suggestionID),
              isEnabled(suggestion),
              let currentEngine else { return false }
        return currentEngine.unavailableReason == nil
    }

    func request(suggestionID: String, page: AIChatPageContextData?, selections: [AIChatSelectionContextData]) -> LocalAIRequest? {
        let isSummary = LocalAISuggestion(rawValue: suggestionID) == .summarizePage
        return LocalAIRequest(suggestionID: suggestionID,
                              language: Self.userLanguageName,
                              page: page.map { LocalAIPage(title: $0.title, url: $0.url,
                                                           content: isSummary ? Self.prefix($0.content, upTo: summaryPageCharacterLimit) : $0.content) },
                              selections: selections.map(\.content))
    }

    /// Cuts at the last space before `limit`, so a word isn't split.
    static func prefix(_ text: String, upTo limit: Int) -> String {
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        return String(cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut)
    }

    /// Loads the model while the user reads the suggestions, so tapping one only has to read the page.
    func sheetDidAppear(featureFlagger: FeatureFlagger) {
        guard featureFlagger.isFeatureOn(.localAIContextualActions),
              !enabledSuggestions.isEmpty,
              let currentEngine, currentEngine.unavailableReason == nil else { return }
        currentEngine.preload()
    }

    func sheetDidDismiss() {
        guard !keepsModelLoaded else { return }
        unloadModels()
    }

    func unloadModels() {
        LocalAIEngineKind.allCases.forEach { engine(for: $0)?.unload() }
    }

    /// English name of the UI language: models follow English instructions best.
    static var userLanguageName: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
    }
}
