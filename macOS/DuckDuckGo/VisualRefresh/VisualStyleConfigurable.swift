//
//  VisualStyleConfigurable.swift
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

import Combine
import BrowserServicesKit
import FeatureFlags

protocol VisualStyleConfigurable {
    var toolbarHeight: CGFloat { get }
}

struct VisualStyle {
    let toolbarHeight: CGFloat

    static var old: VisualStyle {
        return VisualStyle(toolbarHeight: 44)
    }

    static var new: VisualStyle {
        return VisualStyle(toolbarHeight: 64)
    }
}

final class VisualStyleManager: VisualStyleConfigurable {
    private let featureFlagger: FeatureFlagger

    private var cancellables: Set<AnyCancellable> = []

    private var isEnabled: Bool {
        featureFlagger.isFeatureOn(.visualRefresh)
    }

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger

        subscribeToLocalOverride()
    }

    var toolbarHeight: CGFloat {
        currentStyle.toolbarHeight
    }

    private var currentStyle: VisualStyle {
        return isEnabled ? .new : .old
    }

    private func subscribeToLocalOverride() {
        guard let overridesHandler = featureFlagger.localOverrides?.actionHandler as? FeatureFlagOverridesPublishingHandler<FeatureFlag> else {
            return
        }

        overridesHandler.flagDidChangePublisher
            .filter { $0.0 == .visualRefresh }
            .sink { (_, enabled) in
                /// Here I need to apply the visual changes. Should I restart the app?
                print("Visual refresh feature flag changed to \(enabled ? "enabled" : "disabled")")
            }
            .store(in: &cancellables)
    }
}
