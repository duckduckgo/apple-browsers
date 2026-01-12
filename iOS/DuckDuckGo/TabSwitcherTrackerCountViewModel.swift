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
import BrowserServicesKit
import Core
import PrivacyConfig

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
    private let featureFlagger: FeatureFlagger
    private var refreshTask: Task<Void, Never>?

    init(settings: TabSwitcherSettings, privacyStats: PrivacyStatsProviding, featureFlagger: FeatureFlagger) {
        self.settings = settings
        self.privacyStats = privacyStats
        self.featureFlagger = featureFlagger
    }

    func refresh() {
        guard featureFlagger.isFeatureOn(.tabSwitcherTrackerCount),
              settings.showTrackerCountInTabSwitcher else {
            refreshTask?.cancel()
            refreshTask = nil
            state = .hidden
            return
        }

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let count = await privacyStats.fetchPrivacyStatsTotalCount()

            guard !Task.isCancelled else { return }

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

    @discardableResult
    func refreshAsync() async -> State {
        guard featureFlagger.isFeatureOn(.tabSwitcherTrackerCount),
              settings.showTrackerCountInTabSwitcher else {
            refreshTask?.cancel()
            refreshTask = nil
            state = .hidden
            return state
        }

        refreshTask?.cancel()
        let count = await privacyStats.fetchPrivacyStatsTotalCount()

        guard count > 0 else {
            state = .hidden
            return state
        }

        let title = String(format: UserText.tabSwitcherTrackerCountTitle, count)
        let newState = State(isVisible: true,
                             title: title,
                             subtitle: UserText.tabSwitcherTrackerCountSubtitle)
        state = newState
        return newState
    }

    func hide() {
        settings.showTrackerCountInTabSwitcher = false
        state = .hidden
    }
}
