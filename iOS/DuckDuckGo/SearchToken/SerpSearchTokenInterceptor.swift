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
import FeatureFlags_iOS

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
    static let tokenParam = "dindextoken"

    /// A DuckDuckGo search-results URL that is not a Duck AI chat query.
    static func isSerpURL(_ url: URL) -> Bool {
        url.isDuckDuckGoSearch && !url.isDuckAIURL
    }

    /// Removes the `dindextoken` param so the token never leaks into user-facing surfaces — the
    /// address bar, bookmarks/favorites, and copied/shared links. The token is experiment plumbing
    /// bound to the live network request only; call this anywhere the current URL is shown to or
    /// persisted for the user.
    static func strippingToken(from url: URL) -> URL {
        url.getParameter(named: tokenParam) == nil ? url : url.removingParameters(named: [tokenParam])
    }

    /// Returns a copy of `request` with the experiment signals applied, or `nil` when the
    /// request is not a SERP navigation or already carries every signal it needs (caller then
    /// lets the navigation proceed unchanged).
    ///
    /// - Parameters:
    ///   - cohort: `.treatment` / `.control`. Both arms get the `dindexexp` param.
    ///   - token: live search token; added as the `dindextoken` URL param for treatment only. `nil`/expired → param skipped.
    static func signalledRequest(for request: URLRequest,
                                 cohort: FeatureFlag.SearchTokenExperimentCohort,
                                 token: String?) -> URLRequest? {
        guard let url = request.url, isSerpURL(url) else { return nil }

        var newURL = url
        var changed = false

        // dindexexp — both arms: control = a, treatment = b.
        if url.getParameter(named: dindexParam) != cohort.paramValue {
            newURL = newURL
                .removingParameters(named: [dindexParam])
                .appendingParameter(name: dindexParam, value: cohort.paramValue)
            changed = true
        }

        // dindextoken — treatment only, requires a live token.
        if cohort == .treatment, let token, url.getParameter(named: tokenParam) != token {
            newURL = newURL
                .removingParameters(named: [tokenParam])
                .appendingParameter(name: tokenParam, value: token)
            changed = true
        }

        if changed {
            var mutated = request
            mutated.url = newURL
            mutated.attribution = .user
            return mutated
        }

        return nil
    }
}
