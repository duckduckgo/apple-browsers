//
//  AIChatHistoryCleaner.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Foundation
import Combine
import PixelKit
import PrivacyConfig
import WebKit
import UserScript
import os.log
import AIChat

protocol AIChatHistoryCleaning {
    /// Whether the option to clear Duck.ai chat history should be displayed to the user.
    var shouldDisplayCleanAIChatHistoryOption: Bool { get }

    /// Publisher that emits updates to the `shouldDisplayCleanAIChatHistoryOption` property.
    var shouldDisplayCleanAIChatHistoryOptionPublisher: AnyPublisher<Bool, Never> { get }

    /// Deletes all Duck.ai chat history.
    @MainActor func cleanAIChatHistory() async
}

final class AIChatHistoryCleaner: AIChatHistoryCleaning {

    private let featureFlagger: FeatureFlagger
    private let aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable
    let notificationCenter: NotificationCenter
    private var featureDiscoveryObserver: NSObjectProtocol?
    private let pixelKit: PixelKit?
    private var historyCleaner: HistoryCleaning

    @Published
    private var aiChatWasUsedBefore: Bool

    @Published
    var shouldDisplayCleanAIChatHistoryOption: Bool = false

    var shouldDisplayCleanAIChatHistoryOptionPublisher: AnyPublisher<Bool, Never> {
        $shouldDisplayCleanAIChatHistoryOption.eraseToAnyPublisher()
    }

    init(featureFlagger: FeatureFlagger,
         aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable,
         featureDiscovery: FeatureDiscovery,
         notificationCenter: NotificationCenter = .default,
         pixelKit: PixelKit? = PixelKit.shared,
         privacyConfig: PrivacyConfigurationManaging) {
        self.featureFlagger = featureFlagger
        self.aiChatMenuConfiguration = aiChatMenuConfiguration
        self.notificationCenter = notificationCenter
        self.pixelKit = pixelKit
        aiChatWasUsedBefore = featureDiscovery.wasUsedBefore(.aiChat)

        self.historyCleaner = HistoryCleaner(featureFlagger: featureFlagger, privacyConfig: privacyConfig)
        subscribeToChanges()
    }

    deinit {
        if let token = featureDiscoveryObserver {
            notificationCenter.removeObserver(token)
        }
    }

    /// Launches a headless web view to clear Duck.ai chat history with a C-S-S feature.
    @MainActor
    func cleanAIChatHistory() async {
        guard featureFlagger.isFeatureOn(.aiChatDataClearing) else { return }
        let result = await historyCleaner.cleanAIChatHistory()

        switch result {
        case .success:
            pixelKit?.fire(AIChatPixel.aiChatDeleteHistorySuccessful, frequency: .dailyAndCount)
        case .failure(let error):
            Logger.aiChat.debug("Failed to clear Duck.ai chat history: \(error.localizedDescription)")
            pixelKit?.fire(AIChatPixel.aiChatDeleteHistoryFailed, frequency: .dailyAndCount)

            if let userScriptError = error as? UserScriptError {
                userScriptError.fireLoadJSFailedPixelIfNeeded()
            }
        }
    }

    private func subscribeToChanges() {
        featureDiscoveryObserver = notificationCenter.addObserver(forName: .featureDiscoverySetWasUsedBefore, object: nil, queue: .main) { [weak self] notification in
            guard let featureRaw = notification.userInfo?["feature"] as? String,
                  featureRaw == WasUsedBeforeFeature.aiChat.rawValue else { return }
            self?.aiChatWasUsedBefore = true
        }

        $aiChatWasUsedBefore.combineLatest(aiChatMenuConfiguration.valuesChangedPublisher.prepend(()))
            .map { [weak self] wasUsed, _ in
                guard let self else { return false }
                return wasUsed && aiChatMenuConfiguration.shouldDisplayAnyAIChatFeature && featureFlagger.isFeatureOn(.aiChatDataClearing)
            }
            .prepend(aiChatWasUsedBefore && aiChatMenuConfiguration.shouldDisplayAnyAIChatFeature && featureFlagger.isFeatureOn(.aiChatDataClearing))
            .removeDuplicates()
            .assign(to: &$shouldDisplayCleanAIChatHistoryOption)
    }
}
