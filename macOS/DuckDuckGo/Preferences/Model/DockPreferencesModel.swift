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

final class DockPreferencesModel: ObservableObject {
    private let featureFlagger: FeatureFlagger
    private let dockCustomizer: DockCustomization
    private let pixelFiring: PixelFiring?
    private let addToDockDemoVideoPresenter: AddToDockDemoVideoPresenting

    /// Whether the current build can add the app to the dock (programmatically).
    var canAddToDock: Bool {
        dockCustomizer.supportsAddingToDock
    }

    /// Whether instructions can be shown for how to add the app to the dock manually.
    var canShowDockInstructions: Bool {
        featureFlagger.isFeatureOn(.addToDockAppStore)
    }

    /// Whether the app is being added to the dock.
    /// Used to optimistically update settings when adding the app to the dock.
    @Published private var isBeingAddedToDock = false

    var isAddedToDock: Bool {
        isBeingAddedToDock || dockCustomizer.isAddedToDock
    }

    init(featureFlagger: FeatureFlagger,
         dockCustomizer: DockCustomization,
         pixelFiring: PixelFiring?,
         addToDockDemoVideoPresenter: AddToDockDemoVideoPresenting) {
        self.featureFlagger = featureFlagger
        self.dockCustomizer = dockCustomizer
        self.pixelFiring = pixelFiring
        self.addToDockDemoVideoPresenter = addToDockDemoVideoPresenter
    }

    func addToDock(from preferences: PreferencePaneIdentifier) {
        guard dockCustomizer.supportsAddingToDock else { return }
        switch preferences {
        case .defaultBrowser:
            pixelFiring?.fire(GeneralPixel.userAddedToDockFromDefaultBrowserSection,
                              frequency: .standard,
                              includeAppVersionParameter: false)
        case .general:
            pixelFiring?.fire(GeneralPixel.userAddedToDockFromSettings,
                             frequency: .standard,
                             includeAppVersionParameter: false)
        default:
            break
        }
        dockCustomizer.addToDock()
        isBeingAddedToDock = true
    }

    @MainActor
    func showAddToDockDemoVideo() {
        pixelFiring?.fire(GeneralPixel.settingsAddToDockShowMeHowClicked, frequency: .dailyAndCount)
        addToDockDemoVideoPresenter.presentAddToDockDemoVideo()
    }

    func refresh() {
        isBeingAddedToDock = false
    }
}
