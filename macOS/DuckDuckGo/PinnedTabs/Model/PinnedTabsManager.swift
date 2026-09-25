//
//  PinnedTabsManager.swift
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

import AppKit
import Combine
import Common
import FoundationExtensions
import Foundation
import os.log
import PixelKit

final class PinnedTabsManager {

    private(set) var tabCollection: TabCollection
    private(set) var tabViewModels = [TabIdentifier: TabViewModel]()

    let didUnpinTabPublisher: AnyPublisher<Int, Never>

    /// Pins a newly created tab when `sourceCollection` is `nil`; otherwise moves the existing tab
    /// from that collection without reporting a WebKit close/open lifecycle transition.
    @MainActor
    @discardableResult
    func pinTab(_ tab: Tab, from sourceCollection: TabCollection?, at index: Int? = nil, firePixel: Bool = true) -> Bool {
        let destinationIndex = index ?? tabCollection.tabs.endIndex
        let didInsert: Bool
        if let sourceCollection {
            guard let sourceIndex = sourceCollection.firstIndex(of: tab) else {
                Logger.pinnedTabs.debug("PinnedTabsManager: unable to find tab in source collection")
                return false
            }
            didInsert = sourceCollection.moveTab(at: sourceIndex, to: tabCollection, at: destinationIndex)
        } else {
            didInsert = tabCollection.insert(tab, at: destinationIndex)
        }
        guard didInsert else { return false }

        if firePixel {
            PixelKit.fire(PinnedTabsPixel.userPinnedTab, frequency: .dailyAndStandard)
        }
        if #available(macOS 15.4, *), let webExtensionManager = NSApp.delegateTyped.webExtensionManager {
            webExtensionManager.eventsListener.didChangeTabProperties([.pinned], for: tab)
        }
        return true
    }

    @MainActor
    func removePinnedTab(at index: Int, published: Bool = false, firePixel: Bool = true) -> AnyTab? {
        guard let tab = tabCollection.tabs[safe: index] else {
            Logger.pinnedTabs.debug("PinnedTabsManager: unable to remove pinned tab")
            return nil
        }
        guard tabCollection.removeTab(at: index, published: published) else {
            Logger.pinnedTabs.debug("PinnedTabsManager: unable to remove pinned tab")
            return nil
        }
        didUnpinTabSubject.send(index)

        if firePixel {
            PixelKit.fire(PinnedTabsPixel.userUnpinnedTab, frequency: .dailyAndStandard)
        }
        if #available(macOS 15.4, *), case .loaded(let loadedTab) = tab,
           let webExtensionManager = NSApp.delegateTyped.webExtensionManager {
            webExtensionManager.eventsListener.didChangeTabProperties([.pinned], for: loadedTab)
        }
        return tab
    }

    @MainActor
    func unpinTab(at index: Int, movingTo destinationCollection: TabCollection, at destinationIndex: Int, firePixel: Bool = true) -> AnyTab? {
        guard let tab = tabCollection.tabs[safe: index],
              tabCollection.moveTab(at: index, to: destinationCollection, at: destinationIndex) else {
            Logger.pinnedTabs.debug("PinnedTabsManager: unable to unpin a tab")
            return nil
        }
        didUnpinTabSubject.send(index)

        if firePixel {
            PixelKit.fire(PinnedTabsPixel.userUnpinnedTab, frequency: .dailyAndStandard)
        }
        if #available(macOS 15.4, *), case .loaded(let loadedTab) = tab,
           let webExtensionManager = NSApp.delegateTyped.webExtensionManager {
            webExtensionManager.eventsListener.didChangeTabProperties([.pinned], for: loadedTab)
        }
        return tab
    }

    @MainActor
    func materializeIfNeeded(at index: Int) {
        guard case .unloaded(let unloaded) = tabCollection.tabs[safe: index] else { return }
        assertionFailure("Pinned tab should never be suspended")
        let tab = unloaded.materialize()
        tabCollection.replaceTab(at: index, with: .loaded(tab), keepHistory: false)
        tabViewModels[tab.uuid] = TabViewModel(tab: tab)
    }

    func isTabPinned(_ tab: Tab) -> Bool {
        tabCollection.contains(tab: tab)
    }

    func tabViewModel(at index: Int) -> TabViewModel? {
        guard index >= 0, tabCollection.tabs.count > index else {
            Logger.pinnedTabs.error("PinnedTabsManager: Index out of bounds")
            return nil
        }

        let tab = tabCollection.tabs[index]
        return tabViewModels[tab.uuid]
    }

    func tabBarViewModel(at index: Int) -> (any TabBarViewModel)? {
        guard index >= 0, tabCollection.tabs.count > index else {
            return nil
        }
        return tabViewModels[tabCollection.tabs[index].uuid]
    }

    func isDomainPinned(_ domain: String) -> Bool {
        pinnedDomains.contains(domain)
    }

    var pinnedDomains: Set<String> {
        Set(tabCollection.tabs.compactMap { $0.url?.host })
    }

    @MainActor
    func setUp(movingTabsFrom collection: TabCollection) {
        tabCollection.removeAll()
        for anyTab in collection.tabs {
            switch anyTab {
            case .loaded:
                tabCollection.append(tab: anyTab)
            case .unloaded(let unloaded):
                tabCollection.append(tab: .loaded(unloaded.materialize()))
            }
        }
        collection.clearAfterMerge()
    }

    init(tabCollection: TabCollection = .init()) {
        didUnpinTabPublisher = didUnpinTabSubject.eraseToAnyPublisher()
        self.tabCollection = tabCollection
        subscribeToPinnedTabs()
        subscribeToWindowWillClose()
    }

    private func subscribeToWindowWillClose() {
        windowWillCloseCancellable = NotificationCenter.default
            .publisher(for: NSWindow.willCloseNotification)
            .filter { $0.object is MainWindow }
            .asVoid()
            .sink { [weak self] in
                if NSApp.windows.filter({ $0 is MainWindow }).count == 1 {
                    self?.tabCollection.loadedTabs.forEach { $0.stopAllMediaAndLoading() }
                }
            }
    }

    // MARK: - Private

    private let didUnpinTabSubject = PassthroughSubject<Int, Never>()
    private var tabsCancellable: AnyCancellable?
    private var windowWillCloseCancellable: AnyCancellable?

    private func subscribeToPinnedTabs() {
        tabsCancellable = tabCollection.$tabs.sink { [weak self] newTabs in
            guard let self = self else { return }

            let newUUIDs = Set(newTabs.map(\.uuid))
            let oldUUIDs = Set(self.tabViewModels.keys)

            let removedUUIDs = oldUUIDs.subtracting(newUUIDs)
            for uuid in removedUUIDs {
                self.tabViewModels[uuid] = nil
            }

            let addedUUIDs = newUUIDs.subtracting(oldUUIDs)
            for tab in newTabs where addedUUIDs.contains(tab.uuid) {
                if case .loaded(let tab) = tab {
                    self.tabViewModels[tab.uuid] = TabViewModel(tab: tab)
                }
            }

            // Detect materialization: existing UUID changed from unloaded to loaded
            for tab in newTabs where !addedUUIDs.contains(tab.uuid) {
                if case .loaded(let tab) = tab, self.tabViewModels[tab.uuid] == nil {
                    self.tabViewModels[tab.uuid] = TabViewModel(tab: tab)
                }
            }
        }
    }
}

extension PinnedTabsManager {

    var isEmpty: Bool {
        tabCollection.tabs.count == 0
    }

}
