//
//  RecordFoundDateResolver.swift
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

enum RecordFoundDateResolver {

    /// This resolves the found date for an extracted profile record based on history events
    ///
    /// - When no clear event exists, returns the earliest .matchesFound.
    /// - When a clear exists, returns the first .matchesFound that happens afterwards; if none exists, returns nil
    static func resolve(brokerQueryProfileData: BrokerProfileQueryData? = nil,
                        repository: DataBrokerProtectionRepository,
                        brokerId: Int64,
                        profileQueryId: Int64,
                        extractedProfileId: Int64) -> Date? {
        let optOutJob: OptOutJobData?
        if let brokerQueryProfileData {
            optOutJob = brokerQueryProfileData.optOutJobDataMatching(extractedProfileId)
        } else {
            optOutJob = try? repository.fetchOptOut(brokerId: brokerId,
                                                    profileQueryId: profileQueryId,
                                                    extractedProfileId: extractedProfileId)
        }

        if let historyDate = resolvedFoundDate(from: optOutJob?.historyEvents) {
            return historyDate
        }

        let repositoryEvents = try? repository.fetchOptOutHistoryEvents(brokerId: brokerId,
                                                                        profileQueryId: profileQueryId,
                                                                        extractedProfileId: extractedProfileId)

        if let historyDate = resolvedFoundDate(from: repositoryEvents) {
            return historyDate
        }

        return nil
    }

    /// We want to know how long an _active_ opt-out submission attempt has been running since the record was found
    /// - If the record was never cleared, stick to the first found date as the baseline
    /// - When the record has been removed at least once (either optOutConfirmed or manuallyRemovedByUser is triggered),
    /// the associated opt-out attempt is considered done. The subsequent match found starts a new attempt, so we want
    /// the timestamp of that next found date.
    /// - If the record is removed but there's no following match found event, we return nil to signal an issue
    private static func resolvedFoundDate(from events: [HistoryEvent]?) -> Date? {
        guard let events, !events.isEmpty else {
            return nil
        }

        let sortedEvents = events.sorted(by: { $0.date < $1.date })

        guard let latestClearDate = sortedEvents.last(where: { $0.isClearEvent() })?.date else {
            return sortedEvents.first(where: { $0.isMatchesFoundEvent() })?.date
        }

        return sortedEvents.first(where: { $0.isMatchesFoundEvent() && $0.date > latestClearDate })?.date
    }
}

extension BrokerProfileQueryData {
    fileprivate func optOutJobDataMatching(_ extractedProfileId: Int64) -> OptOutJobData? {
        optOutJobData.first(where: { $0.extractedProfile.id == extractedProfileId })
    }
}
