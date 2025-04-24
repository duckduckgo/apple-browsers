//
//  ExperimentalThemingManager.swift
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
import Core
import BrowserServicesKit

struct ExperimentalThemingManager {

    let featureFlagger: FeatureFlagger

    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        self.featureFlagger = featureFlagger
    }

    var isExperimentalThemingEnabled: Bool {
        featureFlagger.isFeatureOn(for: FeatureFlag.experimentalBrowserTheming, allowOverride: true)
    }

    var isRoundedCornersTreatmentEnabled: Bool {
        isExperimentalThemingEnabled && UIDevice.current.userInterfaceIdiom != .pad
    }

    func toggleExperimentalTheming() {
        featureFlagger.localOverrides?.toggleOverride(for: FeatureFlag.experimentalBrowserTheming)

        updateNeededDependencies()
    }

    private func updateNeededDependencies() {
        ThemeManager.shared.updateColorScheme()
    }
}
