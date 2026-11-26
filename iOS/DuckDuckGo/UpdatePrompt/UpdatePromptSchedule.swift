//
//  UpdatePromptSchedule.swift
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

/// The newest version on the App Store, as published in the iOS release metadata file.
struct AppStoreRelease: Codable, Equatable {
    let version: String
    let releaseDate: Date
    let minimumOSVersion: String

    enum CodingKeys: String, CodingKey {
        case version = "latest_version"
        case releaseDate = "release_date"
        case minimumOSVersion = "minimum_os_version"
    }
}

/// The release metadata file. Same shape as the macOS one, plus `minimum_os_version`.
struct AppStoreReleaseMetadata: Decodable {
    let latest: AppStoreRelease

    enum CodingKeys: String, CodingKey {
        case latest = "latest_appstore_version"
    }

    static func decode(from data: Data) throws -> AppStoreReleaseMetadata {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            // Accepts dates with or without fractional seconds.
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO8601 date: \(string)")
        }
        return try decoder.decode(AppStoreReleaseMetadata.self, from: data)
    }
}

/// The reminders for one installed version, each a number of days after the clock starts.
enum UpdatePromptStep: Int, Codable, CaseIterable {
    case first = 1
    case second = 2
    case last = 3

    var days: Int {
        switch self {
        case .first: 2
        case .second: 7
        case .last: 14
        }
    }

    var next: UpdatePromptStep? {
        UpdatePromptStep(rawValue: rawValue + 1)
    }

    var pixelValue: String { String(rawValue) }
}

/// What has happened to the reminders for the installed version.
struct UpdatePromptState: Codable, Equatable {
    struct Shown: Codable, Equatable {
        let step: UpdatePromptStep
        let date: Date
    }

    let installedVersion: String
    /// Release date of the first newer version seen. Later releases don't move it.
    let clockStart: Date
    var lastShown: Shown?

    func recordingShown(_ step: UpdatePromptStep, at date: Date) -> UpdatePromptState {
        var state = self
        state.lastShown = Shown(step: step, date: date)
        return state
    }
}

/// Decides which reminder, if any, is due. No I/O.
enum UpdatePromptSchedule {

    struct Evaluation: Equatable {
        let state: UpdatePromptState?
        let step: UpdatePromptStep?
    }

    static func evaluate(installedVersion: String,
                         osVersion: String,
                         release: AppStoreRelease?,
                         state: UpdatePromptState?,
                         now: Date) -> Evaluation {
        guard let release,
              let installed = VersionNumber(installedVersion),
              let latest = VersionNumber(release.version),
              latest > installed else {
            return Evaluation(state: nil, step: nil)
        }

        let state = state?.installedVersion == installedVersion ? state : nil

        // People who can't install the update are never asked.
        guard let os = VersionNumber(osVersion),
              let minimumOS = VersionNumber(release.minimumOSVersion),
              os >= minimumOS else {
            return Evaluation(state: state, step: nil)
        }

        let current = state ?? UpdatePromptState(installedVersion: installedVersion, clockStart: release.releaseDate)
        guard let next = current.lastShown.map({ $0.step.next }) ?? .first,
              now >= current.clockStart.adding(days: next.days) else {
            return Evaluation(state: current, step: nil)
        }

        if let lastShown = current.lastShown,
           now < lastShown.date.adding(days: next.days - lastShown.step.days) {
            return Evaluation(state: current, step: nil)
        }

        return Evaluation(state: current, step: next)
    }
}

/// A dotted version compared per component, so 7.250.0 equals 7.250 and 7.100 is newer than 7.99.
struct VersionNumber: Comparable {
    let components: [Int]

    init?(_ string: String) {
        let components = string.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !components.isEmpty, components.allSatisfy({ $0 != nil }) else { return nil }
        self.components = components.compactMap { $0 }
    }

    static func < (lhs: VersionNumber, rhs: VersionNumber) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: VersionNumber, rhs: VersionNumber) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

private extension Date {
    func adding(days: Int) -> Date {
        addingTimeInterval(TimeInterval(days) * 24 * 60 * 60)
    }
}
