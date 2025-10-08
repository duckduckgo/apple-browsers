//
//  NewTabPageOmnibarActionsHandler.swift
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
import AppKit
import Suggestions
import Common
import AIChat
import os.log
import PixelKit
import Combine

final class NewTabPageTabIDsProvider: NewTabPageTabIDsProviding {

    var tabIDsChangedPublisher: AnyPublisher<NewTabPage.NewTabPageDataModel.Tabs, Never>

    private let windowControllersManager: WindowControllersManagerProtocol

    private var cancellables = Set<AnyCancellable>()

    @MainActor
    init(windowControllersManager: WindowControllersManagerProtocol) {
        self.windowControllersManager = windowControllersManager

        tabIDsChangedPublisher = windowControllersManager
            .tabsChanged
            .receive(on: DispatchQueue.main)
            .map { [weak windowControllersManager] _ -> NewTabPageDataModel.Tabs in
                guard let manager = windowControllersManager else {
                    return NewTabPageDataModel.Tabs(tabId: "", tabIds: [])
                }
                return NewTabPageDataModel.Tabs(from: manager)
            }
            .removeDuplicates { old, new in
                old.tabId == new.tabId && old.tabIds == new.tabIds
            }
            .eraseToAnyPublisher()
    }

    @MainActor
    func getTabIDs() -> NewTabPage.NewTabPageDataModel.Tabs {
        return NewTabPageDataModel.Tabs(from: windowControllersManager)
    }

}

extension NewTabPageDataModel.Tabs {

    @MainActor
    init(from windowControllersManager: WindowControllersManagerProtocol) {
        // Gather all tab IDs where the tab content is New Tab Page
        let tabIDs = windowControllersManager.allTabCollectionViewModels
            .flatMap { viewModel in
                viewModel.tabs.filter { tab in
                    if case .newtab = tab.content {
                        return true
                    }
                    return false
                }
                .map { $0.uuid }
            }

        // Provide the currently selected tab if the New Tab Page is currently loaded
        let selectedTab = windowControllersManager.selectedTab
        let tabID: String
        if let tab = selectedTab, case .newtab = tab.content {
            tabID = tab.uuid
        } else {
            tabID = ""
        }

        self.init(tabId: tabID, tabIds: tabIDs)
    }

}
