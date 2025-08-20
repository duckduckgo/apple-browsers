//
//  BrokerProfileDataComparators.swift
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

extension ScanJobData {
    public enum ScanType {
        case initial
        case confirmOptOut
        case retry
        case maintenance
        case other
    }

    public func scanType() -> ScanType {
        guard let lastEvent = historyEvents.last else {
            return .initial
        }

        switch lastEvent.type {
        case .optOutConfirmed, .noMatchFound, .matchesFound, .reAppearence:
            return .maintenance
        case .error:
            return .retry
        case .optOutStarted, .scanStarted:
            return .other
        case .optOutRequested:
            return .confirmOptOut
        case .matchRemovedByUser:
            return .other
        }
    }
}

public struct BrokerJobDataComparators {
    public typealias Predicate = (BrokerJobData, BrokerJobData) -> Bool

    public static let `default` = byEarliestPreferredRunDateFirst

    /// A predicate that sorts BrokerJobData based on their preferred run dates
    /// - Jobs with non-nil preferred run dates are sorted in ascending order (earliest date first).
    /// - Opt-out jobs with nil preferred run dates come last, maintaining their original relative order.
    public static let byEarliestPreferredRunDateFirst: Predicate = { lhs, rhs in
        switch (lhs.preferredRunDate, rhs.preferredRunDate) {
        case (nil, nil):
            return false
        case (_, nil):
            return true
        case (nil, _):
            return false
        case (let lhsRunDate?, let rhsRunDate?):
            return lhsRunDate < rhsRunDate
        }
    }

    /// A predicate that sorts BrokerJobData based on a custom priority rank for use in background tasks
    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1210630341292032?focus=true
    public static let byPriorityForBackgroundTask: Predicate = { lhs, rhs in
        /// Smaller rank goes first
        /// Initial scans (1) -> Opt-outs (2) -> Confirm opt-out scans (3) -> Retry scans (4)
        /// -> Maintenance scans (5) -> Other scans (6) -> Everything else (7)
        func priorityRank(for job: BrokerJobData) -> Int {
            if let scanJob = job as? ScanJobData {
                switch scanJob.scanType() {
                case .initial:
                    return 1
                case .confirmOptOut:
                    return 3
                case .retry:
                    return 4
                case .maintenance:
                    return 5
                case .other:
                    return 6
                }
            } else if job is OptOutJobData {
                return 2
            }

            return 7
        }

        let lhsRank = priorityRank(for: lhs)
        let rhsRank = priorityRank(for: rhs)

        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }

        /// Both are opt-outs -> Sort by ascending attempt counts
        if let lhsOptOut = lhs as? OptOutJobData,
           let rhsOptOut = rhs as? OptOutJobData {
            return lhsOptOut.attemptCount < rhsOptOut.attemptCount
        }

        /// Both are scans -> Sort by preferred run date
        if lhs is ScanJobData && rhs is ScanJobData {
            return byEarliestPreferredRunDateFirst(lhs, rhs)
        }

        return false
    }
}
