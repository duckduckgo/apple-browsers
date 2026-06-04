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

        let historyCleaner = HistoryCleaner.makeHistoryCleaner(featureFlagger: featureFlagger,
                                                               privacyConfig: privacyConfigurationManager,
                                                               nativeStorageHandler: nativeStorageHandler)

        let viewModel = AIChatSuggestionsViewModel(maxSuggestions: suggestionsReader.maxHistoryCount)

        let manager = AIChatHistoryManager(suggestionsReader: suggestionsReader,
                                           aiChatSettings: chatSettings,
                                           aiChatSyncCleaner: chatSyncCleaner,
                                           historyCleaner: historyCleaner,
                                           viewModel: viewModel,
                                           isIPadExperience: isIPadExperience,
                                           isFireTab: isFireTab)
        return (manager, viewModel)
    }
}
