//
//  SERPSettings.swift
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

import Foundation
import BrowserServicesKit
import AIChat
import Core
import Persistence

final class SERPSettings: SERPSettingsProvider {
    private let keyValueStore: KeyValueStoring
    
    init(keyValueStore: KeyValueStoring = UserDefaults(suiteName: Global.appConfigurationGroupName) ?? UserDefaults()) {
        self.keyValueStore = keyValueStore
    }
    
    var isAllowFollowUpQuestionsEnabled: Bool {
        if let storedValue = keyValueStore.object(forKey: .allowFollowUpQuestionsKey) as? Bool {
            return storedValue
        }
        return .allowFollowUpQuestionsKeyDefaultValue
    }
    
    func enableAllowFollowUpQuestions(enable: Bool) {
        keyValueStore.set(enable, forKey: .allowFollowUpQuestionsKey)
#warning("Finish implementation")
        // triggerSettingsChangedNotification()
        if enable {
            // Pixel?
        } else {
            // Pixel?
        }
    }
}

// MARK: - Keys for storage

private extension String {
    static let allowFollowUpQuestionsKey = "serp.settings.allowFollowUpQuestions"
}

// MARK: - Default values for storage

private extension Bool {
    static let allowFollowUpQuestionsKeyDefaultValue: Bool = true
}
