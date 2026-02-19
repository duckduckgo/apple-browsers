//
//  MockFeatureFlagger+AppUpdater.swift
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
import PrivacyConfig
import FeatureFlags

@testable import DuckDuckGo_Privacy_Browser

extension MockFeatureFlagger {
    /// Convenience property for setting enabled update-related feature flags in tests.
    /// Maps to the underlying `featuresStub` dictionary.
    public var enabledUpdateFeatureFlags: [FeatureFlag] {
        get {
            let updateFlags: [FeatureFlag] = [
                .autoUpdateInDEBUG,
                .autoUpdateInREVIEW,
                .updatesWontAutomaticallyRestartApp,
                .appStoreUpdateFlow,
                .updatesSimplifiedFlow
            ]
            return updateFlags.filter { flag in
                featuresStub[flag.rawValue] == true
            }
        }
        set {
            // Clear all update controller flags first
            let updateFlags: [FeatureFlag] = [
                .autoUpdateInDEBUG,
                .autoUpdateInREVIEW,
                .updatesWontAutomaticallyRestartApp,
                .appStoreUpdateFlow,
                .updatesSimplifiedFlow
            ]
            for flag in updateFlags {
                featuresStub[flag.rawValue] = false
            }
            // Set the enabled flags
            for flag in newValue {
                featuresStub[flag.rawValue] = true
            }
        }
    }
}
