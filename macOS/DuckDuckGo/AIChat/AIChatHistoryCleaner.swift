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

protocol AIChatHistoryCleaning {
    /// Whether the option to clear Duck.ai chat history should be displayed to the user.
    var shouldDisplayCleanAIChatHistoryOption: Bool { get }

    /// Publisher that emits updates to the `shouldDisplayCleanAIChatHistoryOption` property.
    var shouldDisplayCleanAIChatHistoryOptionPublisher: AnyPublisher<Bool, Never> { get }
}

final class AIChatHistoryCleaner: AIChatHistoryCleaning {

    @Published
    var shouldDisplayCleanAIChatHistoryOption: Bool = false

    var shouldDisplayCleanAIChatHistoryOptionPublisher: AnyPublisher<Bool, Never> {
        $shouldDisplayCleanAIChatHistoryOption.eraseToAnyPublisher()
    }

    init(featureFlagger: FeatureFlagger,
         aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable,
         featureDiscovery: FeatureDiscovery,
         notificationCenter: NotificationCenter = .default) {
        self.featureFlagger = featureFlagger
        self.aiChatMenuConfiguration = aiChatMenuConfiguration
        self.notificationCenter = notificationCenter
        aiChatWasUsedBefore = featureDiscovery.wasUsedBefore(.aiChat)

        subscribeToChanges()
    }

    deinit {
        if let token = featureDiscoveryObserver {
            notificationCenter.removeObserver(token)
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
                return wasUsed && aiChatMenuConfiguration.shouldDisplayAnyAIChatFeature && featureFlagger.isFeatureOn(.clearAIChatHistory)
            }
            .prepend(aiChatWasUsedBefore && aiChatMenuConfiguration.shouldDisplayAnyAIChatFeature && featureFlagger.isFeatureOn(.clearAIChatHistory))
            .removeDuplicates()
            .assign(to: &$shouldDisplayCleanAIChatHistoryOption)
    }

    private let featureFlagger: FeatureFlagger
    private let aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable
    private let notificationCenter: NotificationCenter
    private var featureDiscoveryObserver: NSObjectProtocol?

    @Published
    private var aiChatWasUsedBefore: Bool
}
