//
//  DockPreferencesModel.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import PixelKit
import PrivacyConfig

final class DockPreferencesModel: ObservableObject, PreferencesTabOpening {
    private let featureFlagger: FeatureFlagger
    private let dockCustomizer: DockCustomization?
    @Published private var addedToDock = false
    var windowControllersManager: WindowControllersManagerProtocol

    let canAddToDock: Bool

    var canShowDockInstructions: Bool {
        featureFlagger.isFeatureOn(.addToDockAppStore)
    }

    var isAddedToDock: Bool {
        addedToDock || dockCustomizer?.isAddedToDock == true
    }

    init(featureFlagger: FeatureFlagger,
         dockCustomizer: DockCustomization?,
         supportsAddToDock: Bool,
         windowControllersManager: WindowControllersManagerProtocol) {
        self.featureFlagger = featureFlagger
        self.dockCustomizer = dockCustomizer
        self.canAddToDock = dockCustomizer != nil && supportsAddToDock
        self.windowControllersManager = windowControllersManager
    }

    func addToDock(from preferences: PreferencePaneIdentifier) {
        guard let dockCustomizer else { return }
        switch preferences {
        case .defaultBrowser:
            PixelKit.fire(GeneralPixel.userAddedToDockFromDefaultBrowserSection,
                          includeAppVersionParameter: false)
        case .general:
            PixelKit.fire(GeneralPixel.userAddedToDockFromSettings,
                          includeAppVersionParameter: false)
        default:
            break
        }
        dockCustomizer.addToDock()
        addedToDock = true
    }

    @MainActor
    func openAddToDockHelpURL() {
        openNewTab(with: .addToDockHelpURL)
    }

    func refresh() {
        addedToDock = false
    }
}

private extension URL {
    static let addToDockHelpURL = URL(string: "https://support.apple.com/en-gb/guide/mac-help/mh35859/mac")!
}
