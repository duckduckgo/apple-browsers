//
//  ReleaseMetadata.swift
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

public struct ReleaseMetadata: Codable {
    public let latestVersion: String
    public let buildNumber: Int
    public let releaseDate: String
    public let isCritical: Bool

    public init(latestVersion: String, buildNumber: Int, releaseDate: String, isCritical: Bool) {
        self.latestVersion = latestVersion
        self.buildNumber = buildNumber
        self.releaseDate = releaseDate
        self.isCritical = isCritical
    }

    public enum CodingKeys: String, CodingKey {
        case latestVersion = "latest_version"
        case buildNumber = "build_number"
        case releaseDate = "release_date"
        case isCritical = "is_critical"
    }
}
