//
//  MockOmnibarDependency.swift
//  DuckDuckGo
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

import AIChat
import Foundation
import BrowserServicesKit
import UIKit
@testable import DuckDuckGo

struct MockOmnibarDependency: OmnibarDependencyProvider {
    
    var suggestionTrayDependencies: SuggestionTrayDependencies?
    var voiceSearchHelper: VoiceSearchHelperProtocol
    var featureFlagger: FeatureFlagger
    var aiChatSettings: AIChatSettingsProvider
    var appSettings: any AppSettings
    var daxEasterEggImageManager: DaxEasterEggImageManaging

    init(voiceSearchHelper: VoiceSearchHelperProtocol = MockVoiceSearchHelper(),
         featureFlagger: FeatureFlagger = MockFeatureFlagger(),
         aiChatSettings: AIChatSettingsProvider = MockAIChatSettingsProvider(),
         appSettings: AppSettings = AppSettingsMock(), daxEasterEggImageManager: DaxEasterEggImageManaging = MockDaxEasterEggImageManager()) {
        self.voiceSearchHelper = voiceSearchHelper
        self.featureFlagger = featureFlagger
        self.aiChatSettings = aiChatSettings
        self.appSettings = appSettings
        self.daxEasterEggImageManager = daxEasterEggImageManager
    }
}

final class MockDaxEasterEggImageManager: DaxEasterEggImageManaging {
    func getBestImageForFullScreen(url: URL, fallbackImage: UIImage?, completion: @escaping (UIImage?) -> Void) { }
    
    func getHighResImageFromMemoryCache(for url: URL) -> UIImage? { nil }
    
    func preloadFullResolutionImage(for url: URL) { }
    
    func clearExpiredImages() { }
}
