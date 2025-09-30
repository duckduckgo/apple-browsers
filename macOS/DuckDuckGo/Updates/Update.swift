//
//  Update.swift
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

#if SPARKLE
import Sparkle
#endif

/// Represents an available app update from any source (Sparkle, App Store, etc.)
final class Update {

    enum UpdateType {
        case regular
        case critical
    }

    let isInstalled: Bool
    let type: UpdateType
    let version: String
    let build: String
    let date: Date
    let releaseNotes: [String]
    let releaseNotesSubscription: [String]
    let needsLatestReleaseNote: Bool

    var title: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM dd yyyy"
        return formatter.string(from: date)
    }

    internal init(isInstalled: Bool,
                  type: Update.UpdateType,
                  version: String,
                  build: String,
                  date: Date,
                  releaseNotes: [String],
                  releaseNotesSubscription: [String],
                  needsLatestReleaseNote: Bool) {
        self.isInstalled = isInstalled
        self.type = type
        self.version = version
        self.build = build
        self.date = date
        self.releaseNotes = releaseNotes
        self.releaseNotesSubscription = releaseNotesSubscription
        self.needsLatestReleaseNote = needsLatestReleaseNote
    }
}

// MARK: - Sparkle Integration

#if SPARKLE
extension Update {
    convenience init(appcastItem: SUAppcastItem, isInstalled: Bool, needsLatestReleaseNote: Bool) {
        let isCritical = appcastItem.isCriticalUpdate
        let version = appcastItem.displayVersionString
        let build = appcastItem.versionString
        let date = appcastItem.date ?? Date()
        let (releaseNotes, releaseNotesSubscription) = ReleaseNotesParser.parseReleaseNotes(from: appcastItem.itemDescription)

        self.init(isInstalled: isInstalled,
                  type: isCritical ? .critical : .regular,
                  version: version,
                  build: build,
                  date: date,
                  releaseNotes: releaseNotes,
                  releaseNotesSubscription: releaseNotesSubscription,
                  needsLatestReleaseNote: needsLatestReleaseNote)
    }
}
#endif

// MARK: - App Store Integration

extension Update {
    convenience init(releaseMetadata: ReleaseMetadata, isInstalled: Bool) {
        // Parse release date
        let dateFormatter = ISO8601DateFormatter()
        let date = dateFormatter.date(from: releaseMetadata.releaseDate) ?? Date()

        self.init(isInstalled: isInstalled,
                  type: releaseMetadata.isCritical ? .critical : .regular,
                  version: releaseMetadata.latestVersion,
                  build: String(releaseMetadata.buildNumber),
                  date: date,
                  releaseNotes: [], // App Store doesn't provide detailed release notes via this API
                  releaseNotesSubscription: [],
                  needsLatestReleaseNote: false)
    }
}
