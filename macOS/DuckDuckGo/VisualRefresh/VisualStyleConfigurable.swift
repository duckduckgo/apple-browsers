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

import BrowserServicesKit
import FeatureFlags

protocol VisualStyleConfigurable {
    var toolbarHeight: CGFloat { get }
}

struct VisualStyle {
    let toolbarHeight: CGFloat

    static func oldStyle() -> VisualStyle {
        return VisualStyle(toolbarHeight: 44)
    }

    static func newStyle() -> VisualStyle {
        return VisualStyle(toolbarHeight: 64)
    }
}

final class VisualStyleManager: VisualStyleConfigurable {
    private let featureFlagger: FeatureFlagger

    private var isEnabled: Bool {
        featureFlagger.isFeatureOn(.visualRefresh)
    }

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    var toolbarHeight: CGFloat {
        currentStyle.toolbarHeight
    }

    private var currentStyle: VisualStyle {
        return isEnabled ? .newStyle() : .oldStyle()
    }
}
