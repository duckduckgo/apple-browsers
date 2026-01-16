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

import Core
import Foundation
import Persistence
import PrivacyConfig

protocol BrowsingMenuSheetCapable {
    var isExperimentalMenuOptInEnabled: Bool { get }
    var isEnabled: Bool { get }
    var isSettingsOptionVisible: Bool { get }

    func setEnabled(_ enabled: Bool)
}

enum BrowsingMenuSheetCapability {
    static func create(
        using featureFlagger: FeatureFlagger,
        keyValueStore: ThrowingKeyValueStoring,
    ) -> BrowsingMenuSheetCapable {
        if #available(iOS 17, *) {
            return BrowsingMenuSheetDefaultCapability(
                featureFlagger: featureFlagger,
                keyValueStore: keyValueStore
            )
        } else {
            return BrowsingMenuSheetUnavailableCapability()
        }
    }
}

struct BrowsingMenuSheetUnavailableCapability: BrowsingMenuSheetCapable {
    let isExperimentalMenuOptInEnabled: Bool = false
    let isEnabled: Bool = false
    let isSettingsOptionVisible: Bool = false

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

    var isExperimentalMenuOptInEnabled: Bool {
        featureFlagger.isFeatureOn(.browsingMenuSheetPresentation)
    }

    var isEnabled: Bool {
        if isEnabledByDefault {
            if featureFlagger.internalUserDecider.isInternalUser {
                return storedEnabledValue ?? true
            }
            return true
        }
        return isExperimentalMenuOptInEnabled && (storedEnabledValue ?? false)
    }

    var isSettingsOptionVisible: Bool {
        if isEnabledByDefault {
            return featureFlagger.internalUserDecider.isInternalUser
        }
        return isExperimentalMenuOptInEnabled
    }

    func setEnabled(_ enabled: Bool) {
        try? keyValueStore.set(enabled, forKey: StorageKey.experimentalBrowsingMenuEnabled)
    }

    // MARK: - Private

    private var isEnabledByDefault: Bool {
        featureFlagger.isFeatureOn(.browsingMenuSheetEnabledByDefault)
    }

    private var storedEnabledValue: Bool? {
        try? keyValueStore.object(forKey: StorageKey.experimentalBrowsingMenuEnabled) as? Bool
    }

    private struct StorageKey {
        static let experimentalBrowsingMenuEnabled = "com_duckduckgo_experimentalBrowsingMenu_enabled"
    }
}
