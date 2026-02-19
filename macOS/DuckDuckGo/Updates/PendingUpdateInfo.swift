//
//  PendingUpdateInfo.swift
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

/// Struct used to persist pending update info across app restarts
public struct PendingUpdateInfo: Codable {
    public let version: String
    public let build: String
    public let date: Date
    public let releaseNotes: [String]
    public let releaseNotesSubscription: [String]
    public let isCritical: Bool

    public init(version: String, build: String, date: Date, releaseNotes: [String], releaseNotesSubscription: [String], isCritical: Bool) {
        self.version = version
        self.build = build
        self.date = date
        self.releaseNotes = releaseNotes
        self.releaseNotesSubscription = releaseNotesSubscription
        self.isCritical = isCritical
    }
}
