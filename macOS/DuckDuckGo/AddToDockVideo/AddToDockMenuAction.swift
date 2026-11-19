//
//  AddToDockMenuAction.swift
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

import FeatureFlags_macOS
import PixelKit
import PrivacyConfig

@MainActor
final class AddToDockMenuAction {

    enum Menu {
        case mainMenu
        case moreOptionsMenu
    }

    private let dockCustomization: DockCustomization
    private let featureFlagger: FeatureFlagger
    private let videoPresenter: AddToDockVideoPresenting
    private let pixelFiring: PixelFiring?

    init(dockCustomization: DockCustomization,
         featureFlagger: FeatureFlagger,
         videoPresenter: AddToDockVideoPresenting,
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.dockCustomization = dockCustomization
        self.featureFlagger = featureFlagger
        self.videoPresenter = videoPresenter
        self.pixelFiring = pixelFiring
    }

    var canShowMenuItem: Bool {
        (dockCustomization.supportsAddingToDock || featureFlagger.isFeatureOn(.appStoreAddToDockOnlyCTA))
            && !dockCustomization.isAddedToDock
    }

    func perform(from menu: Menu) {
        if dockCustomization.supportsAddingToDock {
            guard dockCustomization.addToDock() else { return }
            fireClickPixel(for: menu)
        } else if featureFlagger.isFeatureOn(.appStoreAddToDockOnlyCTA) {
            guard videoPresenter.present(primaryAction: .done) else { return }
            fireClickPixel(for: menu)
        }
    }

    private func fireClickPixel(for menu: Menu) {
        switch menu {
        case .mainMenu:
            pixelFiring?.fire(GeneralPixel.userAddedToDockFromMainMenu, frequency: .standard)
        case .moreOptionsMenu:
            pixelFiring?.fire(GeneralPixel.userAddedToDockFromMoreOptionsMenu, frequency: .dailyAndStandard)
        }
    }
}
