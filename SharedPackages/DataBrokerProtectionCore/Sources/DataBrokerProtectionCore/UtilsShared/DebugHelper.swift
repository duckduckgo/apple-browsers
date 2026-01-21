//
//  DebugHelper.swift
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

public enum DebugHelper {
    public static func djb2Hash(_ text: String) -> Int64 {
        var hash = 5381
        for char in text.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(char)
        }
        return Int64(hash)
    }

    public static func stableId(for broker: DataBroker) -> Int64 {
        djb2Hash(broker.url)
    }

    public static func stableId(for profileQuery: ProfileQuery) -> Int64 {
        let profileQueryText = "\(profileQuery.firstName) \(profileQuery.lastName) x \(profileQuery.city) \(profileQuery.state)"
        return djb2Hash(profileQueryText)
    }

    public static func stableId(for profile: ExtractedProfile) -> Int64? {
        guard let identifier = profile.identifier else { return nil }
        return djb2Hash(identifier)
    }
}
