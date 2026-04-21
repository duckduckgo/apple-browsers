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

protocol TabLazyLoaderDataSource: AnyObject {
    associatedtype Tab: LazyLoadable

    var loadedPinnedTabs: [Tab] { get }

    var loadedTabs: [Tab] { get }
    var selectedTab: Tab? { get }
    var selectedTabIndex: TabIndex? { get }

    var selectedTabPublisher: AnyPublisher<Tab, Never> { get }

    var isSelectedTabLoading: Bool { get }
    var isSelectedTabLoadingPublisher: AnyPublisher<Bool, Never> { get }

    var totalTabCount: Int { get }
    var unloadedTabCount: Int { get }
    func isUnloaded(at index: Int) -> Bool
    func materialize(at index: TabIndex) -> Tab?
}

extension TabLazyLoaderDataSource {
    var qualifiesForLazyLoading: Bool {
        if unloadedTabCount > 0 {
            return true
        }

        if loadedPinnedTabs.count > 0 {
            return true
        }

        let notSelectedURLTabsCount: Int = {
            let count = loadedTabs.filter({ $0.isUrl }).count
            let isURLTabSelected = selectedTab?.isUrl ?? false
            return isURLTabSelected ? count-1 : count
        }()

        return notSelectedURLTabsCount > 0
    }
}

extension TabCollectionViewModel: TabLazyLoaderDataSource {

    var loadedPinnedTabs: [Tab] {
        pinnedTabsCollection?.loadedTabs ?? []
    }

    var loadedTabs: [Tab] {
        tabCollection.loadedTabs
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
        let isLoading = selectedTabViewModel?.isLoading ?? false
        let isStalled = selectedTabViewModel?.tab.hasOnlyStalledResources ?? false
        return isLoading && !isStalled
    }

    var isSelectedTabLoadingPublisher: AnyPublisher<Bool, Never> {
        $selectedTabViewModel
            .compactMap { $0 }
            .flatMap { tabViewModel -> AnyPublisher<Bool, Never> in
                tabViewModel.$isLoading
                    .combineLatest(tabViewModel.tab.stalledResourcePublisher.map { true }.prepend(false))
                    .map { isLoading, isStalled in
                        isLoading && !isStalled
                    }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    var unloadedTabCount: Int {
        tabCollection.tabs.filter { if case .unloaded = $0 { return true }; return false }.count
    }

    var totalTabCount: Int { tabCollection.tabs.count }

    func isUnloaded(at index: Int) -> Bool {
        guard tabCollection.tabs.indices.contains(index) else { return false }
        if case .unloaded = tabCollection.tabs[index] { return true }
        return false
    }
}
