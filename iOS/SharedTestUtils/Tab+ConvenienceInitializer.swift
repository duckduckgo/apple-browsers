//
//  Tab+ConvenienceInitializer.swift
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
import Core
import AIChat
import DuckDuckGo

extension Tab {
    public convenience init(uid: String? = nil,
                            link: Link? = nil,
                            viewed: Bool = false,
                            desktop: Bool = AppWidthObserver.shared.isLargeWidth,
                            lastViewedDate: Date? = nil,
                            daxEasterEggLogoURL: String? = nil,
                            contextualChatURL: String? = nil,
                            supportsTabHistory: Bool = true,
                            isExternalLaunch: Bool = false,
                            shouldSuppressTrackerAnimationOnFirstLoad: Bool = false,
                            preferredTextEntryMode: TextEntryMode = .search,
                            aichatDebugSettings: AIChatDebugSettingsHandling = AIChatDebugSettings()) {
        self.init(uid: uid, link: link, viewed: viewed, desktop: desktop, lastViewedDate: lastViewedDate, daxEasterEggLogoURL: daxEasterEggLogoURL, contextualChatURL: contextualChatURL, supportsTabHistory: supportsTabHistory, fireTab: false, isExternalLaunch: isExternalLaunch, shouldSuppressTrackerAnimationOnFirstLoad: shouldSuppressTrackerAnimationOnFirstLoad, preferredTextEntryMode: preferredTextEntryMode, aichatDebugSettings: aichatDebugSettings)
    }
}
