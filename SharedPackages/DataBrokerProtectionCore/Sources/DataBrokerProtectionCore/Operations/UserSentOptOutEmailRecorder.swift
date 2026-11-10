//
//  UserSentOptOutEmailRecorder.swift
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
import Common
import os.log

public enum UserSentOptOutEmailError: Error, LocalizedError {
    case recordNotFound(recordId: Int64)

    public var errorDescription: String? {
        switch self {
        case .recordNotFound(let recordId):
            return "No extracted profile with id \(recordId)"
        }
    }
}

public struct UserSentOptOutEmailRecorder {

    private let database: DataBrokerProtectionRepository
    private let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>
    private let featureFlagger: OptOutRetryErrorFeatureFlagging
    private let vpnConnectionState: String
    private let vpnBypassStatus: String

    public init(database: DataBrokerProtectionRepository,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                featureFlagger: OptOutRetryErrorFeatureFlagging,
                vpnBypassService: VPNBypassFeatureProvider? = nil) {
        self.database = database
        self.pixelHandler = pixelHandler
        self.featureFlagger = featureFlagger
        self.vpnConnectionState = vpnBypassService?.connectionStatus ?? "unknown"
        self.vpnBypassStatus = vpnBypassService?.bypassStatus.rawValue ?? "unknown"
    }

    /// Records every record it can and throws the first failure afterwards, so one bad id doesn't drop the others.
    public func record(recordIds: [Int64], now: Date = Date()) throws {
        var firstError: Error?
        for recordId in recordIds {
            do {
                try record(recordId: recordId, now: now)
            } catch {
                Logger.dataBrokerProtection.error("Failed to record user-sent opt-out email for \(recordId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                firstError = firstError ?? error
            }
        }
        if let firstError {
            throw firstError
        }
    }

    private func record(recordId: Int64, now: Date) throws {
        guard let (brokerId, profileQueryId, profile) = try database.fetchExtractedProfile(with: recordId),
              let broker = try database.fetchBroker(with: brokerId) else {
            throw UserSentOptOutEmailError.recordNotFound(recordId: recordId)
        }

        guard profile.removedDate == nil else {
            Logger.dataBrokerProtection.log("User-sent opt-out email for \(recordId, privacy: .public) skipped, the record is already removed")
            return
        }

        let events = try database.fetchOptOutHistoryEvents(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: recordId)
        guard !events.doesBelongToUserRemovedRecord else {
            Logger.dataBrokerProtection.log("User-sent opt-out email for \(recordId, privacy: .public) skipped, the user removed the record")
            return
        }

        let attemptId = UUID()
        try database.addAttempt(extractedProfileId: recordId,
                                attemptUUID: attemptId,
                                dataBroker: broker.url,
                                lastStageDate: now,
                                startTime: now)

        try database.add(HistoryEvent(extractedProfileId: recordId,
                                      brokerId: brokerId,
                                      profileQueryId: profileQueryId,
                                      type: .optOutByUserEmail,
                                      date: now))

        let dateUpdater = OperationPreferredDateUpdater(database: database, featureFlagger: featureFlagger)
        try dateUpdater.updateChildrenBrokerForParentBroker(broker, profileQueryId: profileQueryId)
        try dateUpdater.updateOperationDataDates(origin: .optOut,
                                                 brokerId: brokerId,
                                                 profileQueryId: profileQueryId,
                                                 extractedProfileId: recordId,
                                                 schedulingConfig: broker.schedulingConfig)

        if broker.performsOptOutWithinParent() {
            try database.updatePreferredRunDate(nil, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: recordId)
        }

        pixelHandler.fire(.optOutSubmitSuccess(dataBroker: broker.url,
                                               attemptId: attemptId,
                                               duration: 0,
                                               awakeDuration: 0,
                                               tries: events.filter { $0.type == .optOutStarted }.count,
                                               parent: broker.parent ?? "",
                                               emailPattern: nil,
                                               vpnConnectionState: vpnConnectionState,
                                               vpnBypassStatus: vpnBypassStatus,
                                               emailSent: true))
    }
}
