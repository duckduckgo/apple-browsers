//
//  DefaultBrowserAndDockPromptStoring.swift
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

protocol DefaultBrowserAndDockPromptLegacyStoring {
    func setPromptShown(_ shown: Bool)
    func didShowPrompt() -> Bool
}

protocol DefaultBrowserAndDockPromptStorageReading {
    var popoverShownDate: TimeInterval? { get }
    var bannerShownDate: TimeInterval? { get }
    var isBannerPermanentlyDismissed: Bool { get }
}

protocol DefaultBrowserAndDockPromptStorageWriting {
    var popoverShownDate: TimeInterval? { get set }
    var bannerShownDate: TimeInterval? { get set }
    var isBannerPermanentlyDismissed: Bool { get set }
}

extension DefaultBrowserAndDockPromptStorageReading {

    var hasSeenPopover: Bool {
        popoverShownDate != nil
    }

    var hasSeenBanner: Bool {
        bannerShownDate != nil
    }
    
}

typealias DefaultBrowserAndDockPromptStorage = DefaultBrowserAndDockPromptStorageReading & DefaultBrowserAndDockPromptStorageWriting

final class DefaultBrowserAndDockPromptLegacyStore: DefaultBrowserAndDockPromptLegacyStoring {
    private static let promptShownKey = "DefaultBrowserAndDockPromptShown"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func setPromptShown(_ shown: Bool) {
        userDefaults.set(shown, forKey: Self.promptShownKey)
    }

    func didShowPrompt() -> Bool {
        userDefaults.bool(forKey: Self.promptShownKey)
    }
}
