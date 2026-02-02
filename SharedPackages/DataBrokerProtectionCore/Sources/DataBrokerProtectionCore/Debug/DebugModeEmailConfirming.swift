//
//  DebugModeEmailConfirming.swift
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

public struct DebugScanResult: Identifiable, Sendable {
    public let id: UUID
    public let dataBroker: DataBroker
    public let profileQuery: ProfileQuery
    public let extractedProfile: ExtractedProfile

    public init(id: UUID = UUID(),
                dataBroker: DataBroker,
                profileQuery: ProfileQuery,
                extractedProfile: ExtractedProfile) {
        self.id = id
        self.dataBroker = dataBroker
        self.profileQuery = profileQuery
        self.extractedProfile = extractedProfile
    }
}

public protocol DebugModeEmailConfirming {
    var emailConfirmationStore: EmailConfirmationSupporting { get }

    func checkForEmailConfirmation()
    func continueOptOutAfterEmailConfirmation(scanResult: DebugScanResult)

    func canCheckEmailConfirmation(for scanResult: DebugScanResult) -> Bool
    func canContinueOptOutAfterEmailConfirmation(for scanResult: DebugScanResult) -> Bool
    func isAwaitingEmailConfirmation(for scanResult: DebugScanResult) -> Bool
    func confirmationURL(for scanResult: DebugScanResult) -> URL?
}

public extension DebugModeEmailConfirming {
    func canCheckEmailConfirmation(for scanResult: DebugScanResult) -> Bool {
        guard scanResult.dataBroker.requiresEmailConfirmationDuringOptOut() else { return false }
        return isAwaitingEmailConfirmation(for: scanResult)
    }

    func canContinueOptOutAfterEmailConfirmation(for scanResult: DebugScanResult) -> Bool {
        guard scanResult.dataBroker.requiresEmailConfirmationDuringOptOut() else { return false }
        return confirmationURL(for: scanResult) != nil
    }

    func isAwaitingEmailConfirmation(for scanResult: DebugScanResult) -> Bool {
        guard let identifiers = confirmationIdentifiers(for: scanResult),
              let confirmations = try? emailConfirmationStore.fetchOptOutEmailConfirmationsAwaitingLink() else {
            return false
        }

        return confirmations.contains(where: { confirmation in
            confirmation.brokerId == identifiers.brokerId &&
            confirmation.profileQueryId == identifiers.profileQueryId &&
            confirmation.extractedProfileId == identifiers.extractedProfileId
        })
    }

    func confirmationURL(for scanResult: DebugScanResult) -> URL? {
        guard let identifiers = confirmationIdentifiers(for: scanResult),
              let confirmations = try? emailConfirmationStore.fetchOptOutEmailConfirmationsWithLink(),
              let match = confirmations.first(where: { confirmation in
                  confirmation.brokerId == identifiers.brokerId &&
                  confirmation.profileQueryId == identifiers.profileQueryId &&
                  confirmation.extractedProfileId == identifiers.extractedProfileId
              }),
              let link = match.emailConfirmationLink else { return nil }
        return URL(string: link)
    }

    func confirmationIdentifiers(for scanResult: DebugScanResult) -> (brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64)? {
        guard let extractedProfileId = scanResult.extractedProfile.id else { return nil }
        return (brokerId: DebugHelper.stableId(for: scanResult.dataBroker),
                profileQueryId: DebugHelper.stableId(for: scanResult.profileQuery),
                extractedProfileId: extractedProfileId)
    }
}
