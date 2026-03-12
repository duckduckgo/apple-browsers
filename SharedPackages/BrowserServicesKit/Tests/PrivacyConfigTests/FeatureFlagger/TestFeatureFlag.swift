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

import PrivacyConfig

enum TestFeatureFlag: String, FeatureFlagDescribing {
    var defaultValue: FeatureFlagDefaultValue {
        switch self {
        case .overridableFlagInternalByDefault:
            .internalOnly
        case .overridableExperimentFlagWithCohortBByDefault:
            .internalOnlyWithCohort(FakeExperimentCohort.cohortB)
        default:
            .disabled
        }
    }

    var cohortType: (any FeatureFlagCohortDescribing.Type)? {
        switch self {
        case .nonOverridableFlag, .overridableFlagDisabledByDefault, .overridableFlagInternalByDefault:
            nil
        case .overridableExperimentFlagWithCohortBByDefault:
            FakeExperimentCohort.self
        }
    }

    case nonOverridableFlag
    case overridableFlagDisabledByDefault
    case overridableFlagInternalByDefault
    case overridableExperimentFlagWithCohortBByDefault

    var supportsLocalOverriding: Bool {
        switch self {
        case .nonOverridableFlag:
            return false
        case .overridableFlagDisabledByDefault, .overridableFlagInternalByDefault, .overridableExperimentFlagWithCohortBByDefault:
            return true
        }
    }

    var source: FeatureFlagSource {
        switch self {
        case .nonOverridableFlag:
            return .remoteReleasable(.feature(.intentionallyLocalOnlyFeatureForTests))
        case .overridableFlagDisabledByDefault:
            return .disabled
        case .overridableFlagInternalByDefault:
            return .remoteReleasable(.feature(.intentionallyLocalOnlyFeatureForTests))
        case .overridableExperimentFlagWithCohortBByDefault:
            return .remoteReleasable(.feature(.intentionallyLocalOnlyFeatureForTests))
        }
    }

    enum FakeExperimentCohort: String, FeatureFlagCohortDescribing {
        case cohortA
        case cohortB
    }
}
