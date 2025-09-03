//
//  HistoryEvent.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

public struct HistoryEvent: Identifiable, Sendable {
    public enum EventType: Codable, Equatable, Sendable {
        case noMatchFound
        case matchesFound(count: Int)
        case error(error: DataBrokerProtectionError)
        case optOutStarted
        case optOutRequested
        case optOutSubmittedAndAwaitingEmailConfirmation
        case optOutConfirmed
        case scanStarted
        case reAppearence
        case matchRemovedByUser
    }

    public let extractedProfileId: Int64?
    public let brokerId: Int64
    public let profileQueryId: Int64
    public let type: EventType
    public let date: Date

    public var id: String {
        return "\(extractedProfileId ?? 0)-\(brokerId)-\(profileQueryId)-\(date)"
    }

    public init(extractedProfileId: Int64? = nil,
                brokerId: Int64,
                profileQueryId: Int64,
                type: EventType,
                date: Date = Date()) {
        self.extractedProfileId = extractedProfileId
        self.brokerId = brokerId
        self.profileQueryId = profileQueryId
        self.date = date
        self.type = type
    }

    func matchesFound() -> Int {
        switch type {
        case .matchesFound(let matchesFound):
            return matchesFound
        default:
            return 0
        }
    }

    func isMatchEvent() -> Bool {
        switch type {
        case .noMatchFound, .matchesFound:
            return true
        default:
            return false
        }
    }

    func isMatchesFoundEvent() -> Bool {
        switch type {
        case .matchesFound:
            return true
        default:
            return false
        }
    }
}

public extension HistoryEvent {

    var isError: Bool {
        switch type {
        case .error:
            return true
        default:
            return false
        }
    }

    var error: String? {
        switch type {
        case .error(let error):
            return error.name
        default: return nil
        }
    }
}

public extension Array where Element == HistoryEvent {
    var closestHistoryEvent: HistoryEvent? {
        self.sorted(by: { $0.date > $1.date }).first
    }

    /// Determines if this collection of events indicates the record was removed by the user.
    ///
    /// This property checks both the most recent event and the entire history because:
    /// - The `.matchRemovedByUser` event is typically the most recent one, so we can exit early
    /// - However, if an opt-out operation is in progress, newer events might be added after the event
    ///
    /// - Returns: `true` if the record was removed by the user, `false` otherwise
    var doesBelongToUserRemovedRecord: Bool {
        closestHistoryEvent?.type == .matchRemovedByUser || contains(where: { $0.type == .matchRemovedByUser })
    }
}
