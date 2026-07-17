//
//  SerpSearchTokenInterceptor.swift
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
import Core
import Common
import AIChat

extension FeatureFlag.SearchTokenExperimentCohort {
    var paramValue: String {
        switch self {
        case .control:
            return "a"
        case .treatment:
            return "b"
        }
    }
}

/// Builds the Search Token experiment request mutations for SERP navigations. Pure and
/// WebKit-free so it is unit-testable; `TabViewController` performs the cancel+reload using
/// the request this returns.
enum SerpSearchTokenInterceptor {

    static let dindexParam = "dindexexp"
    static let tokenHeader = "X-DDG-Search-Token"

    /// A DuckDuckGo search-results URL that is not a Duck AI chat query.
    static func isSerpURL(_ url: URL) -> Bool {
        url.isDuckDuckGoSearch && !url.isDuckAIURL
    }

    /// Returns a copy of `request` with the experiment signals applied, or `nil` when the
    /// request is not a SERP navigation or already carries every signal it needs (caller then
    /// lets the navigation proceed unchanged).
    ///
    /// - Parameters:
    ///   - isTreatment: `true` = treatment arm, `false` = control. Both arms get the param.
    ///   - token: live search token; used only for the treatment header. `nil`/expired → header skipped.
    static func signalledRequest(for request: URLRequest,
                                 cohort: FeatureFlag.SearchTokenExperimentCohort,
                                 token: String?) -> URLRequest? {
        guard let url = request.url, isSerpURL(url) else { return nil }

        var mutated = request
        var changed = false

        // dindexexp — both arms: control = a, treatment = b.
        if url.getParameter(named: dindexParam) != cohort.paramValue {
            mutated.url = url
                .removingParameters(named: [dindexParam])
                .appendingParameter(name: dindexParam, value: cohort.paramValue)
            changed = true
        }

        // X-DDG-Search-Token — treatment only, requires a live token. (Inert until the token is wired in.)
        if cohort == .treatment, let token, request.value(forHTTPHeaderField: tokenHeader) == nil {
            mutated.setValue(token, forHTTPHeaderField: tokenHeader)
            changed = true
        }
        
        if changed {
            mutated.attribution = .user
            return mutated
        }

        return nil
    }
}
