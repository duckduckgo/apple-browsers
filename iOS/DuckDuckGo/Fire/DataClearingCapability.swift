//
//  DataClearingCapability.swift
//  DuckDuckGo
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

import Core
import Foundation
import PrivacyConfig

protocol DataClearingCapable {
    var isFireButtonRefinementsEnabled: Bool { get }

    /// When enabled, the fire confirmation collapses to a single "Delete All" button
    /// if only one non-Duck.ai tab is open, since burning that tab equals burning all.
    var isSingleTabDeleteAllEnabled: Bool { get }
}

enum DataClearingCapability {
    static func create(using featureFlagger: FeatureFlagger,
                       fireModeCapability: FireModeCapable = FireModeCapability.create()) -> DataClearingCapable {
        DataClearingDefaultCapability(featureFlagger: featureFlagger, fireModeCapability: fireModeCapability)
    }
}

struct DataClearingDefaultCapability: DataClearingCapable {
    private let featureFlagger: FeatureFlagger
    private let fireModeCapability: FireModeCapable

    init(featureFlagger: FeatureFlagger, fireModeCapability: FireModeCapable) {
        self.featureFlagger = featureFlagger
        self.fireModeCapability = fireModeCapability
    }

    var isFireButtonRefinementsEnabled: Bool {
        if #available(iOS 17, *) {
            // On iOS 17+ the refinements are gated on fire mode being enabled.
            fireModeCapability.isFireModeEnabled
                && featureFlagger.isFeatureOn(for: FeatureFlag.fireButtonRefinements)
        } else {
            // Fire mode requires iOS 17+ so it's never enabled on older OSes,
            // but the refinements should still apply independently.
            featureFlagger.isFeatureOn(for: FeatureFlag.fireButtonRefinements)
        }
    }

    var isSingleTabDeleteAllEnabled: Bool {
        featureFlagger.isFeatureOn(for: FeatureFlag.fireButtonSingleTabDeleteAll)
    }
}
