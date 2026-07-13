//
//  FloatingUIManager.swift
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

import Common
import Core
import Foundation
import PrivacyConfig

protocol FloatingUIManaging {
    var isFloatingUIEnabled: Bool { get }
}

final class FloatingUIManager: FloatingUIManaging {

    private let featureFlagger: any FeatureFlagger
    private let unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding
    private let isPad: () -> Bool

    init(featureFlagger: any FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         isPadProvider: @escaping () -> Bool = { DevicePlatform.isIpad },
         unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding = UnifiedToggleInputFeature()) {
        self.featureFlagger = featureFlagger
        self.isPad = isPadProvider
        self.unifiedToggleInputFeature = unifiedToggleInputFeature
    }

    var isFloatingUIEnabled: Bool {
        // Floating UI is iPhone-only and depends on Unified Toggle Input; if either isn't
        // available it stays off. These are remote-config driven, so no assert here.
        guard featureFlagger.isFeatureOn(.floatingUI), !isPad() else { return false }
        return unifiedToggleInputFeature.isAvailable
    }
}
