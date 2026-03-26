//
//  TabLazyLoaderDataSource.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Common
import os.log

protocol TabLazyLoaderDataSource: AnyObject {
    associatedtype Tab: LazyLoadable

    var pinnedTabs: [Tab] { get }

    var tabs: [Tab] { get }
    var selectedTab: Tab? { get }
    var selectedTabIndex: TabIndex? { get }

    var selectedTabPublisher: AnyPublisher<Tab, Never> { get }

    var isSelectedTabLoading: Bool { get }
    var isSelectedTabLoadingPublisher: AnyPublisher<Bool, Never> { get }

    var allTabs: [AnyTab] { get }
    var suspendedTabCount: Int { get }
    func materialize(_ anyTab: AnyTab) -> Tab?
}

extension TabLazyLoaderDataSource {
    var qualifiesForLazyLoading: Bool {
        if suspendedTabCount > 0 {
            return true
        }

        if pinnedTabs.count > 0 {
            return true
        }

        let notSelectedURLTabsCount: Int = {
            let count = tabs.filter({ $0.isUrl }).count
            let isURLTabSelected = selectedTab?.isUrl ?? false
            return isURLTabSelected ? count-1 : count
        }()

        return notSelectedURLTabsCount > 0
    }
}

extension TabCollectionViewModel: TabLazyLoaderDataSource {

    var pinnedTabs: [Tab] {
        (pinnedTabsCollection?.tabs ?? []).compactMap(\.tab)
    }

    var tabs: [Tab] {
        tabCollection.tabs.compactMap(\.tab)
    }

    var selectedTab: Tab? {
        selectedTabViewModel?.tab
    }

    var selectedTabIndex: TabIndex? {
        selectionIndex
    }

    var selectedTabPublisher: AnyPublisher<Tab, Never> {
        $selectedTabViewModel.compactMap(\.?.tab).eraseToAnyPublisher()
    }

    var isSelectedTabLoading: Bool {
        selectedTabViewModel?.isLoading ?? false
    }

    var isSelectedTabLoadingPublisher: AnyPublisher<Bool, Never> {
        $selectedTabViewModel
            .compactMap { $0 }
            .flatMap(\.$isLoading)
            .eraseToAnyPublisher()
    }

    var suspendedTabCount: Int {
        let count = tabCollection.tabs.filter { if case .suspended = $0 { return true }; return false }.count
        return count
    }

    var allTabs: [AnyTab] { tabCollection.tabs }

    func materialize(_ anyTab: AnyTab) -> Tab? {
        guard let index = tabCollection.tabs.firstIndex(where: { $0.id == anyTab.id }) else { return nil }
        return materialize(at: .unpinned(index))
    }
}
