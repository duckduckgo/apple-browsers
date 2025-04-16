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
    static func open(_ url: URL, target: LinkOpenTarget, using tabCollectionViewModel: TabCollectionViewModel) {
        /// FE sends `.newWindow` always when activating a link with Shift key pressed,
        /// which is a Windows-specific behavior. We override it to `.newTab` and handle Shift key on the native side.
        let correctedTarget: LinkOpenTarget = (target == .newWindow && NSApplication.shared.isShiftPressed) ? .newTab : target

        if correctedTarget == .newWindow || NSApplication.shared.isCommandPressed && NSApplication.shared.isOptionPressed {
            WindowsManager.openNewWindow(with: url, source: .bookmark, isBurner: tabCollectionViewModel.isBurner)
        } else if correctedTarget == .newTab || NSApplication.shared.isCommandPressed {
            tabCollectionViewModel.insertOrAppendNewTab(.contentFromURL(url, source: .bookmark), selected: NSApplication.shared.isShiftPressed)
        } else {
            tabCollectionViewModel.selectedTabViewModel?.tab.setContent(.contentFromURL(url, source: .bookmark))
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
