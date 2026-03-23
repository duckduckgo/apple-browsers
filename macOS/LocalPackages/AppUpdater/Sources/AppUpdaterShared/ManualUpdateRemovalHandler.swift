//
//  ManualUpdateRemovalHandler.swift
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

import FeatureFlags
import Persistence
import PrivacyConfig

/// Determines whether the manual update option should be hidden based on
/// install history and the `automaticUpdatesOnly` feature flag.
///
/// - Users who never had the manual option (`installBuild` set): picker is always hidden.
/// - Users who previously had the manual option (`installBuild` nil): picker hidden only when flag is on.
///
/// When the picker is hidden, consumers should treat automatic updates as
/// enabled regardless of the stored user preference.
///
public protocol ManualUpdateRemovalHandling {
    var userNeverHadManualUpdateOption: Bool { get }
    var shouldHideManualUpdateOption: Bool { get }
}

public final class ManualUpdateRemovalHandler: ManualUpdateRemovalHandling {

    private let settings: any ThrowingKeyedStoring<UpdateControllerSettings>
    private let featureFlagger: FeatureFlagger

    public init(settings: any ThrowingKeyedStoring<UpdateControllerSettings>,
                featureFlagger: FeatureFlagger) {
        self.settings = settings
        self.featureFlagger = featureFlagger
    }

    public var userNeverHadManualUpdateOption: Bool {
        (try? settings.installBuild) != nil
    }

    public var shouldHideManualUpdateOption: Bool {
        if userNeverHadManualUpdateOption { return true }
        return featureFlagger.isFeatureOn(.automaticUpdatesOnly)
    }
}
