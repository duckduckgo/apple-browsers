//
//  SitePermissionModel.swift
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

public enum SitePermissionType: String, CaseIterable, Sendable {
    case camera
    case microphone
    case location = "geolocation"
}

public enum SitePermissionDecision: String, CaseIterable, Sendable {
    case ask
    case allow
    case deny
}

/// Global defaults intentionally exclude Always Allow.
public enum GlobalSitePermissionDecision: String, CaseIterable, Sendable {
    case ask
    case deny
}

public struct SitePermissionKey: Hashable, Sendable {

    public let host: String

    /// Creates a permission key from a tab's committed main-frame URL.
    public init?(committedURL: URL) {
        guard let scheme = committedURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              var host = committedURL.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }

        if host.hasSuffix(".") {
            host.removeLast()
        }

        if host.hasPrefix("www.") {
            host.removeFirst("www.".count)
        }

        guard !host.isEmpty else { return nil }
        self.host = host
    }

    init?(storedHost: String) {
        guard !storedHost.isEmpty else { return nil }
        host = storedHost
    }
}
