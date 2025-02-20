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

/// The view mode for the debug view.  You shouldn't have to add or change anything here.
///  Please use DebugScreensViewModel+Views to add new views/controllers.
class DebugScreensViewModel: ObservableObject {

    @Published var isInternalUser = false {
        didSet {
            persisteInternalUserState()
        }
    }

    @Published var filter = "" {
        didSet {
            refreshFilter()
        }
    }

    @Published var visibleScreens: [DebugScreen] = []

    let dependencies: DebugScreen.Dependencies

    let pushController: (UIViewController) -> Void

    var cancellables = Set<AnyCancellable>()

    init(dependencies: DebugScreen.Dependencies,
         pushController: @escaping (UIViewController) -> Void) {

        self.dependencies = dependencies
        self.pushController = pushController
        self.isInternalUser = dependencies.internalUserDecider.isInternalUser

        refreshFilter()
    }

    func persisteInternalUserState() {
        (dependencies.internalUserDecider as? DefaultInternalUserDecider)?
            .debugSetInternalUserState(isInternalUser)
    }

    func refreshInternalUserState() {
        isInternalUser = dependencies.internalUserDecider.isInternalUser
    }

    func refreshFilter() {
        if filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.visibleScreens = screens
        } else {
            self.visibleScreens = screens.filter {
                $0.title.lowercased().contains(filter.lowercased())
            }
        }
        self.visibleScreens = self.visibleScreens.sorted(by: {
            $0.title < $1.title
        })
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
        pushController(controller)
    }

    func navigateToController(_ builder: DebugScreen) {
        switch builder {
        case .controller(_, let controllerBuilder):
            pushController(controllerBuilder(self.dependencies))
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

}
