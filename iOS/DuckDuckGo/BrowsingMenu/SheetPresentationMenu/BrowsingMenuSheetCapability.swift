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

    func setEnabled(_ enabled: Bool)
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

    func setEnabled(_ enabled: Bool) {
        // no-op
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
        featureFlagger.isFeatureOn(.browsingMenuSheetPresentation)
    }

    var isEnabled: Bool {
        get {
            guard isAvailable else { return false }

            return (try? keyValueStore.object(forKey: StorageKey.experimentalBrowsingMenuEnabled) as? Bool) ?? false
        }
    }

    func setEnabled(_ enabled: Bool) {
        try? keyValueStore.set(enabled, forKey: StorageKey.experimentalBrowsingMenuEnabled)
    }

    private struct StorageKey {
        static let experimentalBrowsingMenuEnabled = "com_duckduckgo_experimentalBrowsingMenu_enabled"
    }
}
