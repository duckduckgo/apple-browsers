//
//  NewTabPageLinkOpener.swift
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

import NewTabPage

struct NewTabPageLinkOpener: NewTabPageLinkOpening {

    @MainActor
    static func open(_ url: URL, source: Tab.Content.URLSource, sender: LinkOpenSender, sourceWindow: NSWindow?) {
        lazy var tabCollectionViewModel = WindowControllersManager.shared.mainWindowController(for: sourceWindow)?.mainViewController.tabCollectionViewModel
        switch sender {
        case .newTabContextMenuItem:
            guard let tabCollectionViewModel else { fallthrough }
            tabCollectionViewModel.insertOrAppendNewTab(.contentFromURL(url, source: .bookmark), selected: TabsPreferences.shared.switchToNewTabWhenOpened)
        case .newWindowContextMenuItem:
            WindowsManager.openNewWindow(with: url, source: .bookmark, isBurner: tabCollectionViewModel?.isBurner ?? false)
        case .script: // click/⌘-click/middle-click…
            WindowControllersManager.shared.open(url, source: source, target: sourceWindow, event: NSApp.currentEvent)
        }
    }

    func openLink(_ target: NewTabPageDataModel.OpenAction.Target) async {
        switch target {
        case .settings:
            openAppearanceSettings()
        }
    }

    private func openAppearanceSettings() {
        Task.detached { @MainActor in
            WindowControllersManager.shared.showPreferencesTab(withSelectedPane: .appearance)
        }
    }
}
