//
//  EscapeHatchModel+Previews.swift
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
import Combine
import Persistence

#if DEBUG

struct StaticEscapeHatchTabsSource: EscapeHatchTabsSource {
    let tabs: [Tab]

    func tabsPublisher(for mode: BrowsingMode) -> AnyPublisher<[Tab], Never> {
        Just(tabs)
            .eraseToAnyPublisher()
    }
}

extension EscapeHatchTabsSource where Self == StaticEscapeHatchTabsSource {

    static func staticTabsSource(count: Int, includes targetTab: Tab) -> Self {
        let tabs = (0..<count).map { _ in
            Tab(fireTab: false)
        }

        return StaticEscapeHatchTabsSource(tabs: tabs + [targetTab])
    }
}

extension EscapeHatchModel {
    /// Factory for #Preview / test code: stubs action closures as no-ops so call sites stay readable.
    static func preview(title: String, subtitle: String, tabType: TabType, domain: String?, targetTab: Tab, tabCount: Int, isActionsEnabled: Bool = true, afterInactivityOption: AfterInactivityOption = .lastUsedTab, keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard) -> EscapeHatchModel {
        EscapeHatchModel(
            title: title,
            subtitle: subtitle,
            tabType: tabType,
            domain: domain,
            targetTab: targetTab,
            tabsSource: .staticTabsSource(count: tabCount, includes: targetTab),
            isActionsEnabled: isActionsEnabled,
            afterInactivityOptionAdapter: AfterInactivityOptionAdapter(
                initialOption: afterInactivityOption,
                keyValueStore: keyValueStore
            ),
            onCardTap: {},
            onTabSwitcherTap: {},
            onCloseTab: {},
            onBurnTabWithConfirmation: { _ in },
            onBurnTabImmediately: {}
        )
    }
}

#endif
