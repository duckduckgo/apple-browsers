//
//  TestFeatureFlag.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

enum TestFeatureFlag: String, FeatureFlagDescribing {
    var defaultValue: Bool {
        false
    }

    var cohortType: (any FeatureFlagCohortDescribing.Type)? {
        switch self {
        case .nonOverridableFlag, .overridableFlagDisabledByDefault, .overridableFlagEnabledByDefault:
            nil
        case .overridableExperimentFlagWithCohortBByDefault:
            FakeExperimentCohort.self
        }
    }

    case nonOverridableFlag
    case overridableFlagDisabledByDefault
    case overridableFlagEnabledByDefault
    case overridableExperimentFlagWithCohortBByDefault

    var supportsLocalOverriding: Bool {
        switch self {
        case .nonOverridableFlag:
            return false
        case .overridableFlagDisabledByDefault, .overridableFlagEnabledByDefault, .overridableExperimentFlagWithCohortBByDefault:
            return true
        }
    }

    var source: FeatureFlagSource {
        switch self {
        case .nonOverridableFlag:
            return .internalOnly()
        case .overridableFlagDisabledByDefault:
            return .disabled
        case .overridableFlagEnabledByDefault:
            return .internalOnly()
        case .overridableExperimentFlagWithCohortBByDefault:
            return .internalOnly(FakeExperimentCohort.cohortB)
        }
    }

    enum FakeExperimentCohort: String, FeatureFlagCohortDescribing {
        case cohortA
        case cohortB
    }
}
