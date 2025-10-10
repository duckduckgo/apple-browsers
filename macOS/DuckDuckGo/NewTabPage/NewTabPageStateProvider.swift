//
//  NewTabPageStateProvider.swift
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
import WebKit
import BrowserServicesKit

final class NewTabPageStateProvider: NewTabPageStateProviding {

    var stateChangedPublisher: AnyPublisher<Void, Never>

    private let windowControllersManager: WindowControllersManagerProtocol
    private let featureFlagger: FeatureFlagger

    private var cancellables = Set<AnyCancellable>()

    @MainActor
    init(windowControllersManager: WindowControllersManagerProtocol,
         featureFlagger: FeatureFlagger) {
        self.windowControllersManager = windowControllersManager
        self.featureFlagger = featureFlagger

        stateChangedPublisher = windowControllersManager
            .tabsChanged
            .receive(on: DispatchQueue.main)
            .filter { _ in
                featureFlagger.isFeatureOn(.newTabPageTabIDs) &&
                !featureFlagger.isFeatureOn(.newTabPagePerTab)
            }
            .eraseToAnyPublisher()
    }

    @MainActor
    func getState() -> [NewTabPage.WindowNewTabPageStateData]? {
        guard featureFlagger.isFeatureOn(.newTabPageTabIDs) &&
                !featureFlagger.isFeatureOn(.newTabPagePerTab) else {
            return nil
        }

        return windowControllersManager.mainWindowControllers.compactMap { controller in
            let webView = controller.mainViewController.browserTabViewController.newTabPageWebViewModel.webView
            let tabs = NewTabPageDataModel.Tabs(from: controller)
            return NewTabPage.WindowNewTabPageStateData(tabs: tabs, webView: webView)
        }
    }

}

extension NewTabPageDataModel.Tabs {

    @MainActor
    init(from mainWindowController: MainWindowController) {
        // Gather tab IDs that are currently showing a New Tab Page
        let tabIDs: [String] = mainWindowController.mainViewController.tabCollectionViewModel.tabViewModels.values
            .compactMap { viewModel in
                guard case .newtab = viewModel.tab.content else {
                    return nil
                }
                return viewModel.tab.uuid
            }

        // Get the selected tab, only if it's a new tab page
        let selectedTabID: String = {
            guard
                let selected = mainWindowController.mainViewController.tabCollectionViewModel.selectedTabViewModel?.tab,
                case .newtab = selected.content
            else {
                return ""
            }
            return selected.uuid
        }()

        self.init(tabId: selectedTabID, tabIds: tabIDs)
    }

}
