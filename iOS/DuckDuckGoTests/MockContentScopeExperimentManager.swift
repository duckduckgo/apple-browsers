//
//  MockContentScopeExperimentManager.swift
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

import Foundation
import BrowserServicesKit

class MockContentScopeExperimentManager: ContentScopeExperimentsManaging {
    var allActiveContentScopeExperiments: Experiments = [:]
    private var resolveResult: Experiments = [:]
    var resolveContentScopeScriptActiveExperimentsWasCalled = false
    private(set) var resolveContentScopeScriptActiveExperimentsCallCount = 0

    func resolveContentScopeScriptActiveExperiments() -> Experiments {
        resolveContentScopeScriptActiveExperimentsWasCalled = true
        resolveContentScopeScriptActiveExperimentsCallCount += 1
        return resolveResult
    }
    
    func setResolveResult(_ experiments: Experiments) {
        resolveResult = experiments
    }
}
