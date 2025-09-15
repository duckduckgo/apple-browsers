//
//  AIChatService.swift
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

import UIKit
import Core
import AIChat

final class AIChatService: NSObject {

    private let aiChatSettings: AIChatSettingsProvider
    private let application: UIApplication
    init(aiChatSettings: AIChatSettingsProvider,
         application: UIApplication = UIApplication.shared) {

        self.aiChatSettings = aiChatSettings
        self.application = application
        super.init()
    }

    // MARK: - Resume

    @MainActor
    func resume() {
        Task {
            await refreshShortcuts()
        }
    }

    // MARK: - Suspend

    func suspend() {
        Task { @MainActor in
            await refreshShortcuts()
        }
    }

    @MainActor
    private func refreshShortcuts() async {
        let shortcutManaging = AIChatApplicationShortcutItemManager(application: application)
        shortcutManaging.update(showShortcut: aiChatSettings.isAIChatEnabled)
    }

}

struct AIChatApplicationShortcutItemManager {

    let application: UIApplication

    /// Leaving this non-private so it can be tested more easily since the UIApplication can't be mocked well
    func items(existingItems: [UIApplicationShortcutItem], showShortcut: Bool) -> [UIApplicationShortcutItem] {

        // Remove it from the current list
        var items = existingItems.filter { $0.type != ShortcutKey.aiChat }

        // If needed, add it to the list
        if showShortcut {
            items += [
                UIApplicationShortcutItem(type: ShortcutKey.aiChat,
                                          localizedTitle: UserText.duckAiFeatureName,
                                          localizedSubtitle: nil,
                                          icon: UIApplicationShortcutIcon(templateImageName: "ApplicationShortcutItemAIChat"),
                                          userInfo: nil)
            ]
        }

        return items
    }

    func update(showShortcut: Bool) {
        let app = UIApplication.shared
        app.shortcutItems = items(existingItems: app.shortcutItems ?? [], showShortcut: showShortcut)
    }

}
