//
//  QuickActionsMediumWidgetTests.swift
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

import Testing
import Foundation
@testable import Core
@testable import DuckDuckGo

@Suite("Quick Actions Medium Widget")
struct QuickActionsMediumWidgetTests {

    @Test("When destination is built for the medium source then URL carries quickActionsMedium and the shortcut identifier", .timeLimit(.minutes(1)))
    @available(iOS 17.0, *)
    func whenMediumDestinationBuiltThenURLCarriesSourceAndShortcut() {
        let url = ShortcutOption.duckAI.destination(for: .quickActionsMedium)

        #expect(url.getParameter(named: WidgetSourceType.sourceKey) == WidgetSourceType.quickActionsMedium.rawValue)
        #expect(url.getParameter(named: WidgetSourceType.shortcutKey) == ShortcutOption.duckAI.rawValue)
    }

    @Test("When destination is built for the small widget source then URL carries quickActions and the shortcut identifier", .timeLimit(.minutes(1)))
    @available(iOS 17.0, *)
    func whenSmallDestinationBuiltThenURLCarriesSourceAndShortcut() {
        let url = ShortcutOption.passwords.destination(for: .quickActions)

        #expect(url.getParameter(named: WidgetSourceType.sourceKey) == WidgetSourceType.quickActions.rawValue)
        #expect(url.getParameter(named: WidgetSourceType.shortcutKey) == ShortcutOption.passwords.rawValue)
    }

    @Test("When bookmarks destination is built then it routes to ddgOpenBookmarks rather than ddgFavorites",
          .timeLimit(.minutes(1)),
          arguments: [WidgetSourceType.quickActions, WidgetSourceType.quickActionsMedium])
    @available(iOS 17.0, *)
    func whenBookmarksDestinationBuiltThenRoutesToOpenBookmarks(source: WidgetSourceType) {
        let url = ShortcutOption.bookmarks.destination(for: source)

        #expect(url.scheme == AppDeepLinkSchemes.openBookmarks.rawValue)
        #expect(url.getParameter(named: WidgetSourceType.shortcutKey) == ShortcutOption.bookmarks.rawValue)
    }

    @Test("Every shortcut option yields a unique shortcut parameter so they remain distinguishable in pixels", .timeLimit(.minutes(1)))
    @available(iOS 17.0, *)
    func everyShortcutOptionYieldsUniqueShortcutParameter() {
        let shortcutValues = ShortcutOption.allCases.map { option in
            option.destination(for: .quickActionsMedium).getParameter(named: WidgetSourceType.shortcutKey)
        }

        #expect(Set(shortcutValues).count == ShortcutOption.allCases.count)
        #expect(shortcutValues.allSatisfy { $0 != nil })
    }
}
