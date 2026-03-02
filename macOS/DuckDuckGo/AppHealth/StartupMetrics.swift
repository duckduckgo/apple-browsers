//
//  StartupMetrics.swift
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

// MARK: - StartupStep

enum StartupStep: String, Codable, CaseIterable {
    case appDelegateInit
    case appWillFinishLaunching
    case appDidFinishLaunchingBeforeRestoration
    case appDidFinishLaunchingAfterRestoration
    case appStateRestoration
    case mainMenuInit
    case timeToInteractive

    static let orderedSequence: [StartupStep] = [.appDelegateInit, .mainMenuInit, .appWillFinishLaunching, .appDidFinishLaunchingBeforeRestoration, .appStateRestoration, .appDidFinishLaunchingAfterRestoration, .timeToInteractive]
}

// MARK: - StartupMetrics

struct StartupMetrics {

    private(set) var intervals = [StartupStep: Interval]()

    @discardableResult
    mutating func update(step: StartupStep, startTime: TimeInterval, endTime: TimeInterval) -> Self {
        assert(startTime <= endTime)
        intervals[step] = Interval(start: startTime, end: endTime)
        return self
    }

    var isComplete: Bool {
        Set(StartupStep.allCases) == Set(intervals.keys)
    }

    func duration(step: StartupStep) -> TimeInterval? {
        intervals[step]?.duration
    }

    func timeElapsedBetween(endOf earliest: StartupStep, startOf latest: StartupStep) -> TimeInterval? {
        guard let earliest = intervals[earliest], let latest = intervals[latest] else {
            return nil
        }

        return latest.timeElapsedSince(endOf: earliest)
    }
}

// MARK: - StartupMetrics StringConvertible

extension StartupMetrics: CustomStringConvertible {

    var description: String {
        StartupStep.orderedSequence
            .compactMap { step in
                guard let interval = intervals[step] else {
                    return nil
                }

                return " - " + step.rawValue + ": " + String(interval.duration) + "\n"
            }
            .reduce("") { partialResult, slice in
                partialResult + slice
            }
    }
}

// MARK: - StartupMetrics.Interval

extension StartupMetrics {

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

// MARK: - StartupMetrics + Encodable

extension StartupMetrics: Encodable {

    enum CodingKeys: String, CodingKey {
        case appDelegateInit
        case appWillFinishLaunching
        case appDidFinishLaunchingBeforeRestoration
        case appDidFinishLaunchingAfterRestoration
        case appStateRestoration
        case mainMenuInit
        case timeToInteractive
        case appDelegateInitToWillFinishLaunching
        case appWillFinishToDidFinishLaunching
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        let keysToMilliseconds: [(CodingKeys, TimeInterval)] = StartupStep.allCases.compactMap { step in
            guard let duration = duration(step: step), let codingKey = CodingKeys(rawValue: step.rawValue) else {
                assertionFailure()
                return nil
            }

            return (codingKey, duration.toMilliseconds)
        }

        for (codingKey, milliseconds) in keysToMilliseconds {
            try container.encodeIfPresent(milliseconds, forKey: codingKey)
        }

        if let deltaMS = timeElapsedBetween(endOf: .appDelegateInit, startOf: .appWillFinishLaunching)?.toMilliseconds {
            try container.encode(deltaMS, forKey: .appDelegateInitToWillFinishLaunching)
        }

        if let deltaMS = timeElapsedBetween(endOf: .appWillFinishLaunching, startOf: .appDidFinishLaunchingBeforeRestoration)?.toMilliseconds {
            try container.encode(deltaMS, forKey: .appWillFinishToDidFinishLaunching)
        }
    }
}

// MARK: - TimeInterval Private Helpers

private extension TimeInterval {

    var toMilliseconds: TimeInterval {
        self * 1000
    }
}
