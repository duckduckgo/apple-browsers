//
//  ResolvedFunnelOrigin.swift
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

public enum ResolvedFunnelOrigin: Equatable {
    case native
    case web
    case unknown(reportableOrigin: String?)

    public static func resolve(_ origin: String?, isNativeOrigin: (String) -> Bool, webOrigins: Set<String>) -> ResolvedFunnelOrigin? {
        guard let origin, !origin.isEmpty else { return nil }
        if isNativeOrigin(origin) {
            return .native
        }
        if webOrigins.contains(origin) {
            return .web
        }
        return .unknown(reportableOrigin: reportableOrigin(origin))
    }

    private static func reportableOrigin(_ origin: String) -> String? {
        let origin = origin.lowercased()
        guard origin.range(of: "^funnel_[a-z0-9_]{1,64}$", options: .regularExpression) != nil else {
            return nil
        }
        return origin
    }
}
