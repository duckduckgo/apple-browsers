//
//  OnboardingPersonalization+AdBlocking.swift
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

import Foundation
import Onboarding
import Persistence
import WebExtensions

/// Store adapter backing the **YouTube ad blocking** toggle on the Block Ads onboarding step.
///
/// Maps the onboarding toggle onto App Settings → Ad Blocking → *Block ads on YouTube*:
/// - `true`  → ad blocking **On** (the app default, shown selected when the step first loads)
/// - `false` → ad blocking **Off**
/// - See: [Block Ads: Setup step](https://app.asana.com/1/137249556945/task/1216445221863468?focus=true)
final class OnboardingYouTubeAdBlockingAdapter: OnboardingYouTubeAdBlockingPersonalizationStore {
    private let keyValueStore: ThrowingKeyValueStoring
    private let adBlockingAvailability: AdBlockingAvailabilityProviding
    private let notificationCenter: NotificationCenter

    private var youTubeAdBlockingStorage: any ThrowingKeyedStoring<YouTubeAdBlockingKeys> {
        keyValueStore.throwingKeyedStoring()
    }

    init(
        keyValueStore: ThrowingKeyValueStoring,
        adBlockingAvailability: AdBlockingAvailabilityProviding,
        notificationCenter: NotificationCenter = .default
    ) {
        self.keyValueStore = keyValueStore
        self.adBlockingAvailability = adBlockingAvailability
        self.notificationCenter = notificationCenter
    }

    /// Whether "Block ads on YouTube" is enabled.
    ///
    /// - Get: the user's stored choice, or the rollout-driven app default
    ///   (`defaultYouTubeAdBlockingEnabled`) when they haven't chosen yet — this is the "On (app default)"
    ///   state the step shows on first load, mirroring `SettingsViewModel`.
    /// - Set: `true` → On, `false` → Off; a no-op when the value is unchanged.
    var isYouTubeAdBlockingEnabled: Bool {
        get {
            (try? youTubeAdBlockingStorage.value(for: \YouTubeAdBlockingKeys.youTubeAdBlockingEnabled))
                ?? adBlockingAvailability.defaultYouTubeAdBlockingEnabled
        }
        set {
            guard newValue != isYouTubeAdBlockingEnabled else { return }
            try? youTubeAdBlockingStorage.set(newValue, for: \YouTubeAdBlockingKeys.youTubeAdBlockingEnabled)
            // Drives MainCoordinator → syncEmbeddedExtensions(), which loads/unloads the
            // ad-blocking extension. Without this the change won't take effect until a later sync.
            notificationCenter.post(
                name: YouTubeAdBlockingStorageKeys.youTubeAdBlockingEnabledDidChangeNotification,
                object: nil
            )
        }
    }

}
