//
//  ContentScopeExperimentsManager.swift
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

import Foundation

public protocol ContentScopeExperimentsManaging {
    var allActiveContentScopeExperiments: Experiments { get }
    func resolveContentScopeScriptActiveExperiments() -> Experiments
}

extension DefaultFeatureFlagger: ContentScopeExperimentsManaging {
    public var allActiveContentScopeExperiments: Experiments {
        allActiveExperiments.filter {
            $0.value.parentID == PrivacyFeature.contentScopeExperiments.rawValue
        }
    }

    public func resolveContentScopeScriptActiveExperiments() -> Experiments {
        enrollAllContentScopeExperiments()
        return allActiveContentScopeExperiments
    }

    private func enrollAllContentScopeExperiments() {
        let contentScopeExperimentID = PrivacyFeature.contentScopeExperiments.rawValue
        guard let contentScopeExperiments = try? PrivacyConfigurationData(data: privacyConfigManager.currentConfig).features[contentScopeExperimentID] else { return }
        for subfeature in contentScopeExperiments.features {
            _ = resolveCohort(subfeature.key, parentID: PrivacyFeature.contentScopeExperiments.rawValue)
        }
    }

}
