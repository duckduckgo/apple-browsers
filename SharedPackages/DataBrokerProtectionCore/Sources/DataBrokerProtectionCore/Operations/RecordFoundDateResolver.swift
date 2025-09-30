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

    private static let migrationDefaultDate = Date(timeIntervalSince1970: 0)

    /// This resolves the found date for an extracted profile record
    ///
    /// It mirrors DBPUIDataBrokerProfileMatch flow:
    /// 1. use stored createdDate when valid
    /// 2. otherwise retrieve the first matches-found timestamp from job or DB history
    /// 3. otherwise defer to the supplied fallback
    static func resolve(optOutJob: OptOutJobData?,
                        repository: DataBrokerProtectionRepository,
                        brokerId: Int64,
                        profileQueryId: Int64,
                        extractedProfileId: Int64,
                        fallback: Date) -> Date {
        if let createdDate = validCreatedDate(from: optOutJob) {
            return createdDate
        }

        if let historyDate = firstFoundDate(from: optOutJob?.historyEvents) {
            return historyDate
        }

        if let historyDate = firstFoundDateFromRepository(repository: repository,
                                                          brokerId: brokerId,
                                                          profileQueryId: profileQueryId,
                                                          extractedProfileId: extractedProfileId) {
            return historyDate
        }

        return fallback
    }

    private static func validCreatedDate(from optOutJob: OptOutJobData?) -> Date? {
        guard let createdDate = optOutJob?.createdDate else { return nil }
        return createdDate == migrationDefaultDate ? nil : createdDate
    }

    private static func firstFoundDate(from events: [HistoryEvent]?) -> Date? {
        events?
            .filter { $0.isMatchesFoundEvent() }
            .min(by: { $0.date < $1.date })?.date
    }

    private static func firstFoundDateFromRepository(repository: DataBrokerProtectionRepository,
                                                     brokerId: Int64,
                                                     profileQueryId: Int64,
                                                     extractedProfileId: Int64) -> Date? {
        guard let events = try? repository.fetchOptOutHistoryEvents(brokerId: brokerId,
                                                                    profileQueryId: profileQueryId,
                                                                    extractedProfileId: extractedProfileId) else {
            return nil
        }

        return firstFoundDate(from: events)
    }

}
