//
//  WindowControllersManager+URLOpening.swift
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

import Foundation

extension WindowControllersManager: URLOpening {

    func open(_ url: URL) {
        guard let tabCollectionViewModel else {
            return
        }
        if NSApplication.shared.isCommandPressed && NSApplication.shared.isOptionPressed {
            WindowsManager.openNewWindow(with: url, source: .bookmark, isBurner: tabCollectionViewModel.isBurner)
        } else if NSApplication.shared.isCommandPressed && NSApplication.shared.isShiftPressed {
            tabCollectionViewModel.insertOrAppendNewTab(.contentFromURL(url, source: .bookmark), selected: true)
        } else if NSApplication.shared.isCommandPressed {
            tabCollectionViewModel.insertOrAppendNewTab(.contentFromURL(url, source: .bookmark), selected: false)
        } else {
            tabCollectionViewModel.selectedTabViewModel?.tab.setContent(.contentFromURL(url, source: .historyEntry))
        }
    }

    func openInNewTab(_ urls: [URL]) {
        guard let tabCollectionViewModel, !urls.isEmpty else {
            return
        }
        let tabs = urls.map { Tab(content: .url($0, source: .historyEntry), shouldLoadInBackground: true) }
        tabCollectionViewModel.append(tabs: tabs)
    }

    func openInNewWindow(_ urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }
        let tabs = urls.map { Tab(content: .url($0, source: .historyEntry), shouldLoadInBackground: true) }

        let newTabCollection = TabCollection(tabs: tabs)
        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: newTabCollection)
        openNewWindow(with: tabCollectionViewModel)
    }

    func openInNewFireWindow(_ urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }
        let burnerMode = BurnerMode(isBurner: true)
        let tabs = urls.map { Tab(content: .url($0, source: .historyEntry), shouldLoadInBackground: true, burnerMode: burnerMode) }
        let newTabCollection = TabCollection(tabs: tabs)
        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: newTabCollection, burnerMode: burnerMode)
        openNewWindow(with: tabCollectionViewModel, burnerMode: burnerMode)
    }

    // MARK: - Private

    @MainActor
    private var tabCollectionViewModel: TabCollectionViewModel? {
        lastKeyMainWindowController?.mainViewController.tabCollectionViewModel
    }
}
