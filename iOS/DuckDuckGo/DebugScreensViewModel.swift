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
    @Published var actions: [DebugScreen] = []
    @Published var filtered: [DebugScreen] = []

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
        func sorter(screen1: DebugScreen, screen2: DebugScreen) -> Bool {
            screen1.title < screen2.title
        }

        self.actions = screens.filter { $0.isAction && !self.isPinned($0) }.sorted(by: sorter)
        self.unpinnedScreens = screens.filter { !$0.isAction && !self.isPinned($0) }.sorted(by: sorter)
        self.pinnedScreens = screens.filter { self.isPinned($0) }.sorted(by: sorter)

        if filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.filtered = []
        } else {
            self.filtered = screens.filter {
                $0.title.lowercased().contains(filter.lowercased())
            }.sorted(by: sorter)
        }
    }

    func executeAction(_ screen: DebugScreen) {
        switch screen {
        case .action(_, let action):
            action(self.dependencies)
            ActionMessageView.present(message: "\(screen.title) - DONE")

        case .view, .controller:
            assertionFailure("Should not be pushing SwiftUI view as controller")
        }
    }

    func navigateToController(_ screen: DebugScreen) {
        switch screen {
        case .controller(_, let controllerBuilder):
            pushController?(controllerBuilder(self.dependencies))
        case .view, .action:
            assertionFailure("Should not be pushing SwiftUI view as controller")
        }
    }

    func buildView(_ screen: DebugScreen) -> AnyView {
        switch screen {
        case .controller, .action:
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
