//
//  MockContentScopeExperimentManager.swift
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

public class MockContentScopeExperimentManager: ContentScopeExperimentsManaging {
    public var allActiveContentScopeExperiments: Experiments = [:]
    public var resolveContentScopeScriptActiveExperimentsCalled = false

    public init(allActiveContentScopeExperiments: Experiments = [:], resolveContentScopeScriptActiveExperimentsCalled: Bool = false) {
        self.allActiveContentScopeExperiments = allActiveContentScopeExperiments
        self.resolveContentScopeScriptActiveExperimentsCalled = resolveContentScopeScriptActiveExperimentsCalled
    }

    public func resolveContentScopeScriptActiveExperiments() -> Experiments {
        resolveContentScopeScriptActiveExperimentsCalled = true
        return allActiveContentScopeExperiments
    }
}
