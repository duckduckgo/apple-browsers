//
//  DataBrokerRunCustomJSONViewModel+History.swift
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
import DataBrokerProtectionCore

extension DataBrokerRunCustomJSONViewModel {

    func addScanStartedEvent(for query: BrokerProfileQueryData) {
        addHistoryEvent(HistoryEvent(brokerId: query.dataBroker.id ?? 0,
                                     profileQueryId: query.profileQuery.id ?? 0,
                                     type: .scanStarted))
    }

    func addScanResultEvents(for query: BrokerProfileQueryData, extractedProfiles: [ExtractedProfile]) {
        addHistoryEvent(HistoryEvent(brokerId: query.dataBroker.id ?? 0,
                                     profileQueryId: query.profileQuery.id ?? 0,
                                     type: extractedProfiles.isEmpty ? .noMatchFound : .matchesFound(count: extractedProfiles.count)))
    }

    func addScanErrorEvent(for query: BrokerProfileQueryData, error: Error) {
        addHistoryEvent(HistoryEvent(brokerId: query.dataBroker.id ?? 0,
                                     profileQueryId: query.profileQuery.id ?? 0,
                                     type: .error(error: (error as? DataBrokerProtectionError) ?? .unknown(error.localizedDescription))))
    }

    func addOptOutStartedEvent(for scanResult: ScanResult) {
        addHistoryEvent(HistoryEvent(extractedProfileId: scanResult.extractedProfile.id ?? 0,
                                     brokerId: scanResult.dataBroker.id ?? 0,
                                     profileQueryId: scanResult.profileQuery.id ?? 0,
                                     type: .optOutStarted))
    }

    func addOptOutConfirmedEvent(for scanResult: ScanResult) {
        addHistoryEvent(HistoryEvent(extractedProfileId: scanResult.extractedProfile.id ?? 0,
                                     brokerId: scanResult.dataBroker.id ?? 0,
                                     profileQueryId: scanResult.profileQuery.id ?? 0,
                                     type: .optOutConfirmed))
    }

    func addOptOutErrorEvent(for scanResult: ScanResult, error: Error) {
        addHistoryEvent(HistoryEvent(extractedProfileId: scanResult.extractedProfile.id ?? 0,
                                     brokerId: scanResult.dataBroker.id ?? 0,
                                     profileQueryId: scanResult.profileQuery.id ?? 0,
                                     type: .error(error: (error as? DataBrokerProtectionError) ?? .unknown(error.localizedDescription))))
    }

    func assignExtractedProfileIdIfNeeded(_ extractedProfile: ExtractedProfile) -> ExtractedProfile {
        if extractedProfile.id != nil {
            return extractedProfile
        }

        let assignedId = nextExtractedProfileId
        nextExtractedProfileId += 1

        return ExtractedProfile(id: assignedId,
                                name: extractedProfile.name,
                                alternativeNames: extractedProfile.alternativeNames,
                                addressFull: extractedProfile.addressFull,
                                addresses: extractedProfile.addresses,
                                phoneNumbers: extractedProfile.phoneNumbers,
                                relatives: extractedProfile.relatives,
                                profileUrl: extractedProfile.profileUrl,
                                reportId: extractedProfile.reportId,
                                age: extractedProfile.age,
                                email: extractedProfile.email,
                                removedDate: extractedProfile.removedDate,
                                identifier: extractedProfile.identifier)
    }

    private func addHistoryEvent(_ event: HistoryEvent) {
        DispatchQueue.main.async {
            self.debugEvents.append(DebugLogEvent(timestamp: event.date,
                                                  kind: .history,
                                                  profileQueryLabel: self.historyEventDetails(event),
                                                  summary: self.historyEventDescription(event),
                                                  details: ""))
        }
    }

    func historyEventDescription(_ event: HistoryEvent) -> String {
        switch event.type {
        case .noMatchFound: return "No Match"
        case .matchesFound(let count): return "Matches (\(count))"
        case .error(let error): return "Error: \(error.name) - \(error.localizedDescription)"
        case .optOutStarted: return "Opt-out Started"
        case .optOutRequested: return "Opt-out Requested"
        case .optOutSubmittedAndAwaitingEmailConfirmation: return "Opt-out Awaiting Email"
        case .optOutConfirmed: return "Opt-out Confirmed"
        case .scanStarted: return "Scan Started"
        case .reAppearence: return "Reappearance"
        case .matchRemovedByUser: return "Removed by User"
        }
    }

    func historyEventDetails(_ event: HistoryEvent) -> String {
        profileQueryLabels[event.profileQueryId] ?? "-"
    }
}
