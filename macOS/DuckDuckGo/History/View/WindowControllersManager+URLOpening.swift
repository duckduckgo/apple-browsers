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

import AppKit
import Foundation

extension WindowControllersManager: URLOpening {

    func openInNewTab(_ urls: [URL], sourceWindow: NSWindow?) {
        guard let mainWindowController = mainWindowController(for: sourceWindow), !urls.isEmpty else { return }

        let tabs = urls.map { Tab(content: .url($0, source: .historyEntry), shouldLoadInBackground: true) }

        let tabCollectionViewModel = mainWindowController.mainViewController.tabCollectionViewModel
        tabCollectionViewModel.append(tabs: tabs, andSelect: TabsPreferences.shared.switchToNewTabWhenOpened)
    }

    func openInNewWindow(_ urls: [URL], sourceWindow: NSWindow?) {
        guard !urls.isEmpty else { return }

        let tabs = urls.map { Tab(content: .url($0, source: .historyEntry), shouldLoadInBackground: true) }

        let newTabCollection = TabCollection(tabs: tabs)
        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: newTabCollection)
        openNewWindow(with: tabCollectionViewModel)
    }

    func openInNewFireWindow(_ urls: [URL], sourceWindow: NSWindow?) {
        guard !urls.isEmpty else {
            return
        }
        let burnerMode = BurnerMode(isBurner: true)
        let tabs = urls.map { Tab(content: .url($0, source: .historyEntry), shouldLoadInBackground: true, burnerMode: burnerMode) }
        let newTabCollection = TabCollection(tabs: tabs)
        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: newTabCollection, burnerMode: burnerMode)
        openNewWindow(with: tabCollectionViewModel, burnerMode: burnerMode)
    }

}
