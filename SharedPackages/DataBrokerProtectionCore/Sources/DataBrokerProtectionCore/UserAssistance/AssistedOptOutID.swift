//
//  AssistedOptOutID.swift
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

public struct AssistedOptOutID: Hashable, Sendable, CustomStringConvertible {
    public let brokerId: Int64
    public let profileQueryId: Int64
    public let extractedProfileId: Int64

    public init(brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) {
        self.brokerId = brokerId
        self.profileQueryId = profileQueryId
        self.extractedProfileId = extractedProfileId
    }

    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let brokerId = Int64(parts[0]),
              let profileQueryId = Int64(parts[1]),
              let extractedProfileId = Int64(parts[2]) else { return nil }
        self.init(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
    }

    public var description: String { "\(brokerId)-\(profileQueryId)-\(extractedProfileId)" }
}
