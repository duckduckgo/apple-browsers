//
//  TabSwitcherTrackerCountViewModel.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Combine

@MainActor
final class TabSwitcherTrackerCountViewModel: ObservableObject {

    struct State: Equatable {
        let isVisible: Bool
        let title: String
        let subtitle: String

        static let hidden = State(isVisible: false, title: "", subtitle: "")
    }

    @Published private(set) var state: State = .hidden

    private var settings: TabSwitcherSettings
    private let privacyStats: PrivacyStatsProviding

    init(settings: TabSwitcherSettings, privacyStats: PrivacyStatsProviding) {
        self.settings = settings
        self.privacyStats = privacyStats
    }

    func refresh() {
        guard settings.showTrackerCountInTabSwitcher else {
            state = .hidden
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let count = await privacyStats.fetchPrivacyStatsTotalCount()
            guard count > 0 else {
                self.state = .hidden
                return
            }

            let title = String(format: UserText.tabSwitcherTrackerCountTitle, count)
            self.state = State(isVisible: true,
                               title: title,
                               subtitle: UserText.tabSwitcherTrackerCountSubtitle)
        }
    }

    func hide() {
        settings.showTrackerCountInTabSwitcher = false
        state = .hidden
    }
}
