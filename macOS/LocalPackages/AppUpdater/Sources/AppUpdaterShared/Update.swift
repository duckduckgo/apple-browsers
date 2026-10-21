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

/// Represents an available app update from any source (Sparkle, App Store, etc.)
public final class Update {

    public enum UpdateType {
        case regular
        case critical
    }

    public let isInstalled: Bool
    public let type: UpdateType
    public let version: String
    public let build: String
    public let date: Date
    public let releaseNotes: [String]
    public let releaseNotesSubscription: [String]
    private let dateFormatterProvider: () -> DateFormatter

    /// Returns a date formatter configured with the standard date visualization format for release dates.
    ///
    /// This formatter uses `.long` date style with no time component, providing locale-appropriate
    /// date formatting across all update display contexts.
    ///
    /// - Returns: A configured `DateFormatter` instance for release date formatting.
    public static func releaseDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }

    public var title: String {
        dateFormatterProvider().string(from: date)
    }

    public init(isInstalled: Bool,
                type: Update.UpdateType,
                version: String,
                build: String,
                date: Date,
                releaseNotes: [String],
                releaseNotesSubscription: [String],
                dateFormatterProvider: @autoclosure @escaping () -> DateFormatter = Update.releaseDateFormatter()) {
        self.isInstalled = isInstalled
        self.type = type
        self.version = version
        self.build = build
        self.date = date
        self.releaseNotes = releaseNotes
        self.releaseNotesSubscription = releaseNotesSubscription
        self.dateFormatterProvider = dateFormatterProvider
    }
}

// MARK: - App Store Integration

extension Update {
    public convenience init(releaseMetadata: ReleaseMetadata, isInstalled: Bool, dateFormatterProvider: @autoclosure @escaping () -> DateFormatter = Update.releaseDateFormatter()) {
        // Parse release date
        let iso8601Formatter = ISO8601DateFormatter()
        let date = iso8601Formatter.date(from: releaseMetadata.releaseDate) ?? Date()

        self.init(isInstalled: isInstalled,
                  type: releaseMetadata.isCritical ? .critical : .regular,
                  version: releaseMetadata.latestVersion,
                  build: String(releaseMetadata.buildNumber),
                  date: date,
                  releaseNotes: [], // App Store doesn't provide detailed release notes via this API
                  releaseNotesSubscription: [],
                  dateFormatterProvider: dateFormatterProvider())
    }
}
