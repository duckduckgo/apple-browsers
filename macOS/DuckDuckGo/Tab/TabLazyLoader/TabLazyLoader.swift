//
//  TabLazyLoader.swift
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

final class TabLazyLoader<DataSource: TabLazyLoaderDataSource> {

    enum Const {
        static var maxNumberOfLazyLoadedTabs: Int { 20 }
        static var maxNumberOfLazyLoadedAdjacentTabs: Int { 10 }
        static var maxNumberOfConcurrentlyLoadedTabs: Int { 3 }
    }

    /**
     * Emits output when lazy loader finishes.
     *
     * The output is `true` if lazy loading was performed and `false` if no tabs were lazy loaded.
     */
    private(set) lazy var lazyLoadingDidFinishPublisher: AnyPublisher<Bool, Never> = {
        lazyLoadingDidFinishSubject.prefix(1).eraseToAnyPublisher()
    }()

    private(set) lazy var isLazyLoadingPausedPublisher: AnyPublisher<Bool, Never> = {
        isLazyLoadingPausedSubject.removeDuplicates().eraseToAnyPublisher()
    }()

    init?(dataSource: DataSource) {
        guard dataSource.qualifiesForLazyLoading else {
            Logger.tabLazyLoading.debug("Lazy loading not applicable")
            return nil
        }

        self.dataSource = dataSource

        if let selectedTabIndex = dataSource.selectedTabIndex,
           dataSource.loadedTabs.filter({ $0.isUrl }).count > Const.maxNumberOfLazyLoadedTabs {

            Logger.tabLazyLoading.debug("\(dataSource.loadedTabs.count) open URL tabs, will load adjacent tabs first")
            shouldLoadAdjacentTabs = true

            // Adjacent tab loading only applies to non-pinned tabs. If a pinned tab is selected,
            // start adjacent tab loading from the first tab (closest to pinned tabs section).
            adjacentItemEnumerator = .init(itemIndex: selectedTabIndex.isUnpinnedTab ? selectedTabIndex.item : 0)
        } else {
            shouldLoadAdjacentTabs = false
        }
    }

    func scheduleLazyLoading() {
        guard let currentTab = dataSource.selectedTab else {
            Logger.tabLazyLoading.debug("Lazy loading not applicable")
            lazyLoadingDidFinishSubject.send(false)
            return
        }

        trackUserSwitchingTabs()
        delayLazyLoadingUntilCurrentTabFinishesLoading(currentTab)
    }

    // MARK: - Private

    private let lazyLoadingDidFinishSubject = PassthroughSubject<Bool, Never>()
    private let isLazyLoadingPausedSubject = CurrentValueSubject<Bool, Never>(false)
    private let tabDidLoadSubject = PassthroughSubject<DataSource.Tab, Never>()

    private let numberOfTabsInProgress = CurrentValueSubject<Int, Never>(0)
    private var numberOfTabsRemaining = Const.maxNumberOfLazyLoadedTabs

    private let shouldLoadAdjacentTabs: Bool
    private var adjacentItemEnumerator: AdjacentItemEnumerator?
    private var numberOfAdjacentTabsRemaining = Const.maxNumberOfLazyLoadedAdjacentTabs

    private var idsOfTabsSelectedOrReloadedInThisSession = Set<DataSource.Tab.ID>()
    private var cancellables = Set<AnyCancellable>()

    private unowned var dataSource: DataSource

    private func trackUserSwitchingTabs() {
        dataSource.selectedTabPublisher
            .sink { [weak self] tab in
                self?.idsOfTabsSelectedOrReloadedInThisSession.insert(tab.id)
            }
            .store(in: &cancellables)
    }

    private func delayLazyLoadingUntilCurrentTabFinishesLoading(_ tab: DataSource.Tab) {
        guard tab.isUrl else {
            startLazyLoadingRecentlySelectedTabs()
            return
        }

        tab.loadingFinishedPublisher
            .sink { [weak self] _ in
                self?.startLazyLoadingRecentlySelectedTabs()
            }
            .store(in: &cancellables)
    }

    private func startLazyLoadingRecentlySelectedTabs() {
        guard hasAnyTabsToLoad() else {
            Logger.tabLazyLoading.debug("No tabs to load")
            let loadedAnyTab = numberOfTabsRemaining < Const.maxNumberOfLazyLoadedTabs
            lazyLoadingDidFinishSubject.send(loadedAnyTab)
            return
        }

        tabDidLoadSubject
            .prefix(Const.maxNumberOfLazyLoadedTabs)
            .sink(receiveCompletion: { [weak self] _ in

                Logger.tabLazyLoading.debug("Lazy tab loading finished, preloaded \(Const.maxNumberOfLazyLoadedTabs) tabs")
                self?.lazyLoadingDidFinishSubject.send(true)

            }, receiveValue: { [weak self] tab in

                Logger.tabLazyLoading.debug("Tab did finish loading \(String(reflecting: tab.url))")
                self?.numberOfTabsInProgress.value -= 1

            })
            .store(in: &cancellables)

        willReloadNextTab
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.findAndReloadNextTab()
            }
            .store(in: &cancellables)
    }

    private var willReloadNextTab: AnyPublisher<Void, Never> {
        let readyToLoadNextTab = numberOfTabsInProgress
            .filter { [weak self] _ in
                guard let self = self else { return false }

                if self.dataSource.isSelectedTabLoading {
                    Logger.tabLazyLoading.debug("Selected tab is currently loading, pausing lazy loading until it finishes")
                    self.isLazyLoadingPausedSubject.send(true)
                    return false
                }
                self.isLazyLoadingPausedSubject.send(false)
                return true
            }
            .asVoid()

        let selectedTabDidFinishLoading = dataSource.isSelectedTabLoadingPublisher.filter({ !$0 }).asVoid()

        return Publishers.Merge(readyToLoadNextTab, selectedTabDidFinishLoading)
            .filter { [weak self] in
                (self?.numberOfTabsInProgress.value ?? 0) < Const.maxNumberOfConcurrentlyLoadedTabs
            }
            .eraseToAnyPublisher()
    }

    private func findAndReloadNextTab() {
        guard numberOfTabsRemaining > 0 else {
            Logger.tabLazyLoading.debug("Maximum allowed tabs loaded (\(Const.maxNumberOfLazyLoadedTabs)), skipping")
            return
        }

        if let tab = findTabToLoad() {
            lazyLoadTab(tab)
        } else if let index = findNextUnloadedTabIndex(),
                  let tab = dataSource.materialize(at: .unpinned(index)) {
            Logger.tabLazyLoading.debug("Will materialize and reload unloaded tab at index \(index)")
            lazyLoadTab(tab)
        } else if numberOfTabsInProgress.value == 0 {
            lazyLoadingDidFinishSubject.send(true)
        }
    }

    private func hasAnyTabsToLoad() -> Bool {
        if findRecentlySelectedTabToLoad(from: dataSource.loadedPinnedTabs) != nil { return true }

        if shouldLoadAdjacentTabs, numberOfAdjacentTabsRemaining > 0 {
            if findAdjacentTabToLoad() != nil {
                adjacentItemEnumerator?.reset()
                return true
            }
        }

        if findRecentlySelectedTabToLoad(from: dataSource.loadedTabs) != nil { return true }

        return findNextUnloadedTabIndex() != nil
    }

    private func findTabToLoad() -> DataSource.Tab? {
        if let tab = findRecentlySelectedTabToLoad(from: dataSource.loadedPinnedTabs) {
            Logger.tabLazyLoading.debug("Will reload recently selected pinned tab")
            return tab
        }

        if shouldLoadAdjacentTabs, numberOfAdjacentTabsRemaining > 0 {
            if let tab = findAdjacentTabToLoad() {
                numberOfAdjacentTabsRemaining -= 1
                Logger.tabLazyLoading.debug("Will reload adjacent tab #\(Const.maxNumberOfLazyLoadedAdjacentTabs - self.numberOfAdjacentTabsRemaining) of \(Const.maxNumberOfLazyLoadedAdjacentTabs)")
                return tab
            }
        }

        if let tab = findRecentlySelectedTabToLoad(from: dataSource.loadedTabs) {
            Logger.tabLazyLoading.debug("Will reload recently selected tab")
            return tab
        }

        return nil
    }

    private func findNextUnloadedTabIndex() -> Int? {
        let center = dataSource.selectedTabIndex.flatMap({ $0.isUnpinnedTab ? $0.item : nil }) ?? 0
        let count = dataSource.totalTabCount
        for offset in 0..<count {
            for candidate in [center + offset, center - offset] {
                guard candidate >= 0, candidate < count else { continue }
                if dataSource.isUnloaded(at: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    private func findAdjacentTabToLoad() -> DataSource.Tab? {
        while true {
            guard let nextIndex = adjacentItemEnumerator?.nextIndex(arraySize: dataSource.loadedTabs.count) else {
                return nil
            }
            let tab = dataSource.loadedTabs[nextIndex]
            if tab.isUrl {
                return tab
            }
        }
    }

    private func findRecentlySelectedTabToLoad(from collection: [DataSource.Tab]) -> DataSource.Tab? {
        collection
            .filter { $0.isUrl && !idsOfTabsSelectedOrReloadedInThisSession.contains($0.id) }
            .sorted { $0.isNewer(than: $1) }
            .first
    }

    private func lazyLoadTab(_ tab: DataSource.Tab) {
        subscribeToTabLoadingFinished(tab)
        idsOfTabsSelectedOrReloadedInThisSession.insert(tab.id)

        if let selectedTabWebViewSize = dataSource.selectedTab?.webViewSize {
            tab.webViewSize = selectedTabWebViewSize
        }

        tab.isLazyLoadingInProgress = true
        tab.reload()
        numberOfTabsRemaining -= 1
        numberOfTabsInProgress.value += 1
    }

    private func subscribeToTabLoadingFinished(_ tab: DataSource.Tab) {
        tab.loadingFinishedPublisher
            .sink(receiveValue: { [weak self] tab in
                tab.isLazyLoadingInProgress = false
                self?.tabDidLoadSubject.send(tab)
            })
            .store(in: &cancellables)
    }
}
