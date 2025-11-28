//
//  BrowsingMenuSheetCapability.swift
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

import BrowserServicesKit
import Persistence
import Foundation
import Core

protocol BrowsingMenuSheetCapable {
    var isAvailable: Bool { get }
    var isEnabled: Bool { get }
    var variant: BrowsingMenuClusteringVariant { get set }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool
}

enum BrowsingMenuClusteringVariant: String, CaseIterable, CustomStringConvertible {
    var description: String {
        switch self {
        case .a:
            "Production"
        case .b:
            "Easy Shortcuts"
        case .c:
            "Easy Privacy Tools"
        case .d:
            "Easy Privacy - No floating button"
        }
    }

    case a
    case b
    case c
    case d
}

enum BrowsingMenuSheetCapability {
    static func create(using featureFlagger: FeatureFlagger, keyValueStore: ThrowingKeyValueStoring) -> BrowsingMenuSheetCapable {
        if #available(iOS 17, *) {
            return BrowsingMenuSheetDefaultCapability(featureFlagger: featureFlagger, keyValueStore: keyValueStore)
        } else {
            return BrowsingMenuSheetUnavailableCapability()
        }
    }
}

struct BrowsingMenuSheetUnavailableCapability: BrowsingMenuSheetCapable {
    let isAvailable: Bool = false
    let isEnabled: Bool = false
    var variant: BrowsingMenuClusteringVariant = .a

    func setEnabled(_ enabled: Bool) -> Bool {
        false
    }
}

@available(iOS 17.0, *)
struct BrowsingMenuSheetDefaultCapability: BrowsingMenuSheetCapable {
    let featureFlagger: FeatureFlagger
    private let keyValueStore: ThrowingKeyValueStoring

    init(featureFlagger: FeatureFlagger, keyValueStore: ThrowingKeyValueStoring) {
        self.featureFlagger = featureFlagger
        self.keyValueStore = keyValueStore
    }

    var isAvailable: Bool {
        return featureFlagger.internalUserDecider.isInternalUser
    }

    var isEnabled: Bool {
        guard isAvailable else { return false }

        return featureFlagger.isFeatureOn(.browsingMenuSheetPresentation)
    }

    var variant: BrowsingMenuClusteringVariant {
        get {
            if let variant = try? keyValueStore.object(forKey: StorageKey.menuVariant) as? String {
                return BrowsingMenuClusteringVariant(rawValue: variant) ?? .a
            } else {
                return .a
            }
        }
        set {
            try? keyValueStore.set(newValue.rawValue, forKey: StorageKey.menuVariant)
        }
    }

    func setEnabled(_ enabled: Bool) -> Bool {

        guard isAvailable else { return false }

        let flag = FeatureFlag.browsingMenuSheetPresentation
        if let overrides = self.featureFlagger.localOverrides,
           overrides.override(for: flag) != enabled {

            overrides.toggleOverride(for: flag)
        }

        return isEnabled
    }

    private struct StorageKey {
        static let menuVariant = "browsingMenuVariantKey"
    }
}
