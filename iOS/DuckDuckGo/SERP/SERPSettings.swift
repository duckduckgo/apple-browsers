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

public extension NSNotification.Name {
    static let serpSettingsChanged = Notification.Name("com.duckduckgo.serp.settings.changed")
}

final class SERPSettings: SERPSettingsProviding {

    enum Constant {
        static let allowFollowUpQuestionsKey = "serp.settings.allowFollowUpQuestions"
    }

    private let keyValueStore: KeyValueStoring
    private let aiChatSettings: AIChatSettingsProvider
    private let notificationCenter: NotificationCenter

    init(keyValueStore: KeyValueStoring = UserDefaults(suiteName: Global.appConfigurationGroupName) ?? UserDefaults(),
         aiChatSettings: AIChatSettingsProvider,
         notificationCenter: NotificationCenter = .default) {
        self.keyValueStore = keyValueStore
        self.aiChatSettings = aiChatSettings
        self.notificationCenter = notificationCenter
    }
    
    var isAIChatEnabled: Bool {
        aiChatSettings.isAIChatEnabled
    }

    var isAllowFollowUpQuestionsEnabled: Bool? {
        keyValueStore.object(forKey: Constant.allowFollowUpQuestionsKey) as? Bool
    }

    func enableAllowFollowUpQuestions(enable: Bool) {
        keyValueStore.set(enable, forKey: Constant.allowFollowUpQuestionsKey)
        notificationCenter.post(name: .serpSettingsChanged, object: nil)
        if enable {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsSERPFollowupTurnedOn)
        } else {
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsSERPFollowupTurnedOff)
        }
    }

    var didMigrate: Bool {
        isAllowFollowUpQuestionsEnabled != nil // If value is set, migration is done
    }
    
    func migrateAllowFollowUpQuestions(enable: Bool) {
        keyValueStore.set(enable, forKey: Constant.allowFollowUpQuestionsKey)
    }

}
