//
//  DebugScreensViewModel.swift
//  DuckDuckGo
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
import SwiftUI
import UIKit
import BrowserServicesKit
import Combine
import Core

/// The view mode for the debug view.  You shouldn't have to add or change anything here.
///  Please add new views/controllers to DebugScreensViewModel+Screens.swift.
class DebugScreensViewModel: ObservableObject {

    @Published var isInternalUser = false {
        didSet {
            persisteInternalUserState()
        }
    }

    @Published var isInspectibleWebViewsEnabled = false {
        didSet {
            persistInspectibleWebViewsState()
        }
    }

    @Published var filter = "" {
        didSet {
            refreshFilter()
        }
    }

    @Published var pinnedScreens: [DebugScreen] = []

    @Published var unpinnedScreens: [DebugScreen] = []

    @Published var isFiltering = false

    @UserDefaultsWrapper(key: .debugPinnedScreens, defaultValue: [])
    var pinnedTitles: [String]

    let dependencies: DebugScreen.Dependencies

    var pushController: ((UIViewController) -> Void)?

    var cancellables = Set<AnyCancellable>()

    init(dependencies: DebugScreen.Dependencies) {
        self.dependencies = dependencies
        refreshFilter()
        refreshToggles()
    }

    func persisteInternalUserState() {
        (dependencies.internalUserDecider as? DefaultInternalUserDecider)?
            .debugSetInternalUserState(isInternalUser)
    }

    func persistInspectibleWebViewsState() {
        let defaults = AppUserDefaults()
        let oldValue = defaults.inspectableWebViewEnabled
        defaults.inspectableWebViewEnabled = isInspectibleWebViewsEnabled

        if oldValue != isInspectibleWebViewsEnabled {
            NotificationCenter.default.post(Notification(name: AppUserDefaults.Notifications.inspectableWebViewsToggled))
        }
    }

    func refreshToggles() {
        self.isInternalUser = dependencies.internalUserDecider.isInternalUser
        self.isInspectibleWebViewsEnabled = AppUserDefaults().inspectableWebViewEnabled
    }

    func refreshFilter() {
        if filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.unpinnedScreens = screens.filter { !self.isPinned($0) }
            self.pinnedScreens = screens.filter { self.isPinned($0) }
            isFiltering = false
        } else {
            // When filtering we just ignore the pinning state
            self.pinnedScreens = []
            self.unpinnedScreens = screens.filter {
                $0.title.lowercased().contains(filter.lowercased())
            }
            isFiltering = true
        }

        func sorter(screen1: DebugScreen, screen2: DebugScreen) -> Bool {
            screen1.title < screen2.title
        }
        
        self.pinnedScreens = self.pinnedScreens.sorted(by: sorter)
        self.unpinnedScreens = self.unpinnedScreens.sorted(by: sorter)
    }

    func navigateToLegacyDebugController() {
        let storyboard = UIStoryboard(name: "Debug", bundle: nil)
        let controller = storyboard.instantiateViewController(identifier: "DebugMenu") { coder in
            let d = self.dependencies
            return RootDebugViewController(coder: coder,
                                    sync: d.syncService,
                                    bookmarksDatabase: d.bookmarksDatabase,
                                    internalUserDecider: d.internalUserDecider,
                                    tabManager: d.tabManager,
                                    fireproofing: d.fireproofing)
        }
        pushController?(controller)
    }

    func navigateToController(_ builder: DebugScreen) {
        switch builder {
        case .controller(_, let controllerBuilder):
            pushController?(controllerBuilder(self.dependencies))
        case .view(_, _):
            assertionFailure("Should not be pushing SwiftUI view as controller")
        }
    }

    func buildView(_ builder: DebugScreen) -> AnyView {
        switch builder {
        case .controller(_, _):
            return AnyView(FailedAssertionView("Unexpected view creation"))

        case .view(_, let viewBuilder):
            return AnyView(viewBuilder(self.dependencies))
        }
    }

    func isPinned(_ screen: DebugScreen) -> Bool {
        return Set<String>(pinnedTitles).contains(screen.title)
    }

    func togglePin(_ screen: DebugScreen) {
        if isPinned(screen) {
            var set = Set<String>(pinnedTitles)
            set.remove(screen.title)
            pinnedTitles = Array(set)
        } else {
            pinnedTitles.append(screen.title)
        }
        refreshFilter()
    }

}
