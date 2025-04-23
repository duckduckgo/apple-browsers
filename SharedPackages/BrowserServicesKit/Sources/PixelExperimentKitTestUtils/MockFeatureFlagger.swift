//
//  MockFeatureFlagger.swift
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
import PixelExperimentKit

public class MockFeatureFlagger: FeatureFlagger {
    public var experiments: Experiments = [:]

    public var internalUserDecider: any InternalUserDecider = MockInternalUserDecider()

    public var localOverrides: (any BrowserServicesKit.FeatureFlagLocalOverriding)?

    public init() {}

    public func resolveCohort<Flag>(for featureFlag: Flag, allowOverride: Bool) -> (any FeatureFlagCohortDescribing)? where Flag: FeatureFlagDescribing {
        nil
    }

    func resolveCohort<Flag>(for featureFlag: Flag) -> (any FeatureFlagCohortDescribing)? where Flag: FeatureFlagDescribing {
        return nil
    }

    public var allActiveExperiments: Experiments {
        return experiments
    }

    public func isFeatureOn<Flag>(for featureFlag: Flag, allowOverride: Bool) -> Bool where Flag: FeatureFlagDescribing {
        return false
    }
}
