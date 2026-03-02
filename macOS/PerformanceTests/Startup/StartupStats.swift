//
//  StartupStats.swift
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

// MARK: - StartupStats

/// Represents the Startup Metrics, at a given moment.
/// - Important: For simplicity reasons, this Structure is duplicated in the targer `macOS Browser`. Please do make sure to keep both stuctures in sync!
///
struct StartupStats: Codable {

    private(set) var intervals = [Step: Interval]()

    func duration(step: Step) -> TimeInterval? {
        intervals[step]?.duration
    }

    func timeElapsedBetween(endOf earliest: Step, startOf latest: Step) -> TimeInterval? {
        guard let earliest = intervals[earliest], let latest = intervals[latest] else {
            return nil
        }

        return latest.timeElapsedSince(endOf: earliest)
    }
}

// MARK: - StartupStats.Interval

extension StartupStats {

    enum Step: String, Codable, CaseIterable {
        case appDelegateInit
        case appWillFinishLaunching
        case appDidFinishLaunchingBeforeRestoration
        case appDidFinishLaunchingAfterRestoration
        case appStateRestoration
        case mainMenuInit
        case timeToInteractive
    }

    struct Interval: Codable {
        let start: TimeInterval
        let end: TimeInterval

        var duration: TimeInterval {
            end - start
        }

        func timeElapsedSince(endOf earliest: Interval) -> TimeInterval {
            start - earliest.end
        }
    }
}
