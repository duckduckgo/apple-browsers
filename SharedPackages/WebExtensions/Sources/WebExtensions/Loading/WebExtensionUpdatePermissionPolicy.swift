//
//  WebExtensionUpdatePermissionPolicy.swift
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

import WebKit

/// Uses the same required-access boundary as installation consent. Optional declarations confer no access themselves.
@available(macOS 15.4, iOS 18.4, *)
struct WebExtensionUpdatePermissionPolicy {
    private static let webSchemes = ["http", "https"]

    func canActivate(_ webExtension: WKWebExtension, settings: WebExtensionPermissionSettings?, now: Date = Date()) -> Bool {
        guard let settings else { return false }
        guard webExtension.requestedPermissions.allSatisfy({ (settings.grantedPermissions[$0.rawValue] ?? .distantPast) > now }) else { return false }
        // App permission dates record when approval happened; unlike WebKit's dates they are not expirations.
        guard WebExtensionAppPermission.allCases.allSatisfy({
            !webExtension.requiresPermission($0.rawValue) || settings.grantedAppPermissions[$0.rawValue] != nil
        }) else { return false }
        let approvedPatterns: [WKWebExtension.MatchPattern]
        do {
            approvedPatterns = try settings.grantedMatchPatterns.compactMap { pattern, expiry in
                let parsed = try WKWebExtension.MatchPattern(string: pattern)
                return expiry > now ? parsed : nil
            }
        } catch {
            return false
        }
        return webExtension.allRequestedMatchPatterns.allSatisfy { requested in
            covered(requested, by: approvedPatterns)
        }
    }

    private func covered(_ requested: WKWebExtension.MatchPattern, by approved: [WKWebExtension.MatchPattern]) -> Bool {
        if requested.scheme == "*" {
            // Separate HTTP and HTTPS approvals cover a wildcard scheme without broadening access.
            return Self.webSchemes.allSatisfy { scheme in
                guard let concrete = try? WKWebExtension.MatchPattern(string: scheme + requested.string.dropFirst()) else { return false }
                return approved.contains { covers($0, concrete) }
            }
        }
        return approved.contains { covers($0, requested) }
    }

    private func covers(_ approved: WKWebExtension.MatchPattern, _ requested: WKWebExtension.MatchPattern) -> Bool {
        // Native directional matching normalizes the requested host; retain its subdomain-wildcard distinction.
        if requested.host?.hasPrefix("*.") == true,
           approved.host?.hasPrefix("*.") != true, !approved.matchesAllHosts { return false }
        return approved.matches(requested, options: [])
    }
}
