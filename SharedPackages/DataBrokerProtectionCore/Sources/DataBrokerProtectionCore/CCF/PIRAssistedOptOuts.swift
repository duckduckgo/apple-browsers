//
//  PIRAssistedOptOuts.swift
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

#if os(macOS) && DEBUG
import Foundation

/// An opt-out, or a scan, that waits for the user to start it, because the broker needs a person partway through.
public struct PIRAssistedOptOut: Sendable, Hashable {
    public let brokerId: Int64
    public let profileQueryId: Int64
    /// The record to remove; nil for a scan.
    public let extractedProfileId: Int64?
    public let brokerName: String
    public let brokerURL: String
}

/// Opt-outs for brokers that need a person run only when the user starts them, once per start.
public enum PIRAssistedOptOuts {
    private static let lock = NSLock()
    private static var started = Set<String>()

    private static func key(brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64?) -> String {
        extractedProfileId.map { "opt-out-\($0)" } ?? "scan-\(brokerId)-\(profileQueryId)"
    }

    /// Everything the job filter holds back that the user can start: first runs, and reruns once they are due.
    public static func pending(in database: DataBrokerProtectionRepository,
                               config: BrokerJobExecutionConfig = BrokerJobExecutionConfig(),
                               now: Date = Date()) throws -> [PIRAssistedOptOut] {
        func isDue(_ job: BrokerJobData) -> Bool { job.preferredRunDate.map { $0 <= now } ?? false }
        return try database.fetchActiveBrokerProfileQueryData()
            .filter { config.needsUser(forBrokerAt: $0.dataBroker.url) && !$0.dataBroker.performsOptOutWithinParent() }
            .flatMap { data -> [PIRAssistedOptOut] in
                guard let brokerId = data.dataBroker.id, let profileQueryId = data.profileQuery.id else { return [] }
                let holdsScan = config.holdsScan(forBrokerAt: data.dataBroker.url)
                let scan = holdsScan && (data.scanJobData.lastRunDate == nil || isDue(data.scanJobData))
                    ? [PIRAssistedOptOut(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: nil,
                                         brokerName: data.dataBroker.name, brokerURL: data.dataBroker.url)]
                    : []
                return scan + data.optOutJobData
                    .filter { $0.extractedProfile.removedDate == nil && !$0.isAwaitingEmailConfirmation }
                    .filter { $0.submittedSuccessfullyDate == nil || isDue($0) }
                    .compactMap { job in
                        job.extractedProfile.id.map {
                            PIRAssistedOptOut(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: $0,
                                              brokerName: data.dataBroker.name, brokerURL: data.dataBroker.url)
                        }
                    }
            }
    }

    public static func start(brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64?,
                             in database: DataBrokerProtectionRepository) throws {
        if let extractedProfileId {
            try database.updatePreferredRunDate(Date(), brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
        } else {
            try database.updatePreferredRunDate(Date(), brokerId: brokerId, profileQueryId: profileQueryId)
        }
        markStarted(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
    }

    static func markStarted(brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64?) {
        _ = lock.withLock { started.insert(key(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)) }
    }

    /// Lets a started opt-out or scan run once; a failed attempt waits for the user again instead of retrying.
    static func consumeStart(brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64?) -> Bool {
        let key = key(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
        return lock.withLock { started.remove(key) != nil }
    }
}

private extension OptOutJobData {
    /// The confirmation runs without the user, so the user's part is done.
    var isAwaitingEmailConfirmation: Bool {
        historyEvents.max(by: { $0.date < $1.date })?.type == .optOutSubmittedAndAwaitingEmailConfirmation
    }
}
#endif
