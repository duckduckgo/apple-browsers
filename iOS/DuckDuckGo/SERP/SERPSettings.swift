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

final class SERPSettings: SERPSettingsProviding {
    private let keyValueStore: KeyValueStoring
    
    init(keyValueStore: KeyValueStoring = UserDefaults(suiteName: Global.appConfigurationGroupName) ?? UserDefaults()) {
        self.keyValueStore = keyValueStore
    }
    
    var isDuckAIEnabled: Bool {
        #warning("Finish implementation, keep it stored locally")
        return true
    }
    
    var isAllowFollowUpQuestionsEnabled: Bool? {
        keyValueStore.object(forKey: .allowFollowUpQuestionsKey) as? Bool
    }
    
    var didMigrate: Bool {
        /// If value is there, migration is done. Otherwise, return false
        if keyValueStore.object(forKey: .allowFollowUpQuestionsKey) != nil {
            return true
        }
        return false
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
    
    func migrateAllowFollowUpQuestions(enable: Bool) {
        keyValueStore.set(enable, forKey: .allowFollowUpQuestionsKey)
    }
}

// MARK: - Keys for storage

private extension String {
    static let allowFollowUpQuestionsKey = "serp.settings.allowFollowUpQuestions"
}
