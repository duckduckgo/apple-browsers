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
    var isFloatingTabSwitcherEnabled: Bool { get }
}

final class FloatingUIManager: FloatingUIManaging {

    private let featureFlagger: any FeatureFlagger
    private let unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding
    private let isPad: () -> Bool
    private let isSupportedOS: () -> Bool
    private let isTabSwitcherSupportedOS: () -> Bool

    init(featureFlagger: any FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         isPadProvider: @escaping () -> Bool = { DevicePlatform.isIpad },
         isSupportedOSProvider: @escaping () -> Bool = { if #available(iOS 26, *) { true } else { false } },
         isTabSwitcherSupportedOSProvider: @escaping () -> Bool = { if #available(iOS 18, *) { true } else { false } },
         unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding = UnifiedToggleInputFeature()) {
        self.featureFlagger = featureFlagger
        self.isPad = isPadProvider
        self.isSupportedOS = isSupportedOSProvider
        self.isTabSwitcherSupportedOS = isTabSwitcherSupportedOSProvider
        self.unifiedToggleInputFeature = unifiedToggleInputFeature
    }

    var isFloatingUIEnabled: Bool {
        // iPhone-only, iOS 26+ (for obscuredContentInsets), and requires Unified Toggle Input.
        guard featureFlagger.isFeatureOn(.floatingUI), !isPad(), isSupportedOS() else { return false }
        return unifiedToggleInputFeature.isAvailable
    }

    var isFloatingTabSwitcherEnabled: Bool {
        featureFlagger.isFeatureOn(.floatingUI) && !isPad() && isTabSwitcherSupportedOS()
    }
}
