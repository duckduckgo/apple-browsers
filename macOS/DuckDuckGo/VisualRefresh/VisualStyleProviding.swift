//
//  VisualStyleProviding.swift
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

protocol VisualStyleProviding {
    func addressBarHeight(for type: AddressBarSizeClass) -> CGFloat
    func addressBarTopPadding(for type: AddressBarSizeClass) -> CGFloat
    func addressBarBottomPadding(for type: AddressBarSizeClass) -> CGFloat
}

protocol VisualStyleManagerProviding {
    var style: any VisualStyleProviding { get }
}

enum AddressBarSizeClass {
    case `default`
    case homePage
    case popUpWindow

    var logoWidth: CGFloat {
        switch self {
        case .homePage: 44
        case .popUpWindow, .default: 0
        }
    }

    var isLogoVisible: Bool {
        switch self {
        case .homePage: true
        case .popUpWindow, .default: false
        }
    }
}

struct VisualStyle: VisualStyleProviding {
    private let addressBarHeightForDefault: CGFloat
    private let addressBarHeightForHomePage: CGFloat
    private let addressBarHeightForPopUpWindow: CGFloat
    private let addressBarTopPaddingForDefault: CGFloat
    private let addressBarTopPaddingForHomePage: CGFloat
    private let addressBarTopPaddingForPopUpWindow: CGFloat
    private let addressBarBottomPaddingForDefault: CGFloat
    private let addressBarBottomPaddingForHomePage: CGFloat
    private let addressBarBottomPaddingForPopUpWindow: CGFloat

    func addressBarHeight(for type: AddressBarSizeClass) -> CGFloat {
        switch type {
        case .default: return addressBarHeightForDefault
        case .homePage: return addressBarHeightForHomePage
        case .popUpWindow: return addressBarHeightForPopUpWindow
        }
    }

    func addressBarTopPadding(for type: AddressBarSizeClass) -> CGFloat {
        switch type {
        case .default: return addressBarTopPaddingForDefault
        case .homePage: return addressBarTopPaddingForHomePage
        case .popUpWindow: return addressBarTopPaddingForPopUpWindow
        }
    }

    func addressBarBottomPadding(for type: AddressBarSizeClass) -> CGFloat {
        switch type {
        case .default: return addressBarBottomPaddingForDefault
        case .homePage: return addressBarBottomPaddingForHomePage
        case .popUpWindow: return addressBarBottomPaddingForPopUpWindow
        }
    }

    static var legacy: VisualStyleProviding {
        return VisualStyle(addressBarHeightForDefault: 48,
                           addressBarHeightForHomePage: 52,
                           addressBarHeightForPopUpWindow: 42,
                           addressBarTopPaddingForDefault: 6,
                           addressBarTopPaddingForHomePage: 10,
                           addressBarTopPaddingForPopUpWindow: 0,
                           addressBarBottomPaddingForDefault: 6,
                           addressBarBottomPaddingForHomePage: 8,
                           addressBarBottomPaddingForPopUpWindow: 0)
    }

    static var current: VisualStyleProviding {
        return VisualStyle(addressBarHeightForDefault: 52,
                           addressBarHeightForHomePage: 52,
                           addressBarHeightForPopUpWindow: 52,
                           addressBarTopPaddingForDefault: 6,
                           addressBarTopPaddingForHomePage: 6,
                           addressBarTopPaddingForPopUpWindow: 6,
                           addressBarBottomPaddingForDefault: 6,
                           addressBarBottomPaddingForHomePage: 6,
                           addressBarBottomPaddingForPopUpWindow: 6)
    }
}

final class VisualStyleManager: VisualStyleManagerProviding {
    private let featureFlagger: FeatureFlagger

    private var cancellables: Set<AnyCancellable> = []

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger

        subscribeToLocalOverride()
    }

    var style: any VisualStyleProviding {
        return featureFlagger.isFeatureOn(.visualRefresh) ? VisualStyle.current : VisualStyle.legacy
    }

    private func subscribeToLocalOverride() {
        guard let overridesHandler = featureFlagger.localOverrides?.actionHandler as? FeatureFlagOverridesPublishingHandler<FeatureFlag> else {
            return
        }

        overridesHandler.flagDidChangePublisher
            .filter { $0.0 == .visualRefresh }
            .sink { (_, enabled) in
                /// Here I need to apply the visual changes. The easier way should be to restart the app.
                print("Visual refresh feature flag changed to \(enabled ? "enabled" : "disabled")")
            }
            .store(in: &cancellables)
    }
}
