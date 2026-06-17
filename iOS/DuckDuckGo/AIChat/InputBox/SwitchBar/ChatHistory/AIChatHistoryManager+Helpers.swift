//
//  AIChatHistoryManager+Helpers.swift
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

import Foundation
import WebKit
import AIChat
import PrivacyConfig

extension AIChatHistoryManager {

    static func makeHistoryManager(isFireTab: Bool,
                                   isIPadExperience: Bool,
                                   featureFlagger: FeatureFlagger,
                                   privacyConfigurationManager: PrivacyConfigurationManaging,
                                   chatSyncCleaner: AIChatSyncCleaning?,
                                   chatSettings: AIChatSettingsProvider,
                                   nativeStorageHandler: DuckAiNativeStorageHandling?) -> (AIChatHistoryManager, AIChatSuggestionsViewModel)
    {
        let suggestionsReader: AIChatSuggestionsReading = {
            if isFireTab {
                return NilSuggestionsReader()
            }

            let reader = SuggestionsReader(
                featureFlagger: featureFlagger,
                privacyConfig: privacyConfigurationManager,
                nativeStorageHandler: nativeStorageHandler,
                featureFlagProvider: AIChatFeatureFlagProvider(featureFlagger: featureFlagger)
            )
            let historySettings = AIChatHistorySettings(privacyConfig: privacyConfigurationManager)
            return AIChatSuggestionsReader(suggestionsReader: reader, historySettings: historySettings)
        }()

        let chatDeleter = AIChatDeleter(
            historyCleanerProvider: { _, _ in
                HistoryCleaner.makeHistoryCleaner(featureFlagger: featureFlagger, privacyConfig: privacyConfigurationManager, nativeStorageHandler: nativeStorageHandler)
            },
            aiChatSyncCleaner: chatSyncCleaner ?? NilAIChatSyncCleaner()
        )

        let viewModel = AIChatSuggestionsViewModel(maxSuggestions: suggestionsReader.maxHistoryCount)

        let manager = AIChatHistoryManager(suggestionsReader: suggestionsReader,
                                           aiChatSettings: chatSettings,
                                           aiChatDeleter: chatDeleter,
                                           viewModel: viewModel,
                                           isIPadExperience: isIPadExperience,
                                           isFireTab: isFireTab,
                                           featureFlagger: featureFlagger)
        return (manager, viewModel)
    }
}

/// # Important:
///     At runtime `AIChatSyncCleaning` is never expected to be nil. This is a workaround to satisfy compile time requirements
final class NilAIChatSyncCleaner: AIChatSyncCleaning {
    func recordAutoClearBackgroundTimestamp(date: Date?) async {}
    func recordLocalClear(date: Date?) async {}
    func recordLocalClearFromAutoClearBackgroundTimestampIfPresent() async {}
    func recordChatDeletion(chatID: String) async {}
    func deleteIfNeeded() async {}
    func recordChatUpdate(chatID: String) async {}
    func updateIfNeeded() async {}
    func scheduleSync() {}
}
