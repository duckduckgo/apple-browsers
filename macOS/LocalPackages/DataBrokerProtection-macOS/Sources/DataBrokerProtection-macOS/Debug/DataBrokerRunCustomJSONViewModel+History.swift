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
        let brokerId = query.dataBroker.id ?? 0
        let profileQueryId = query.profileQuery.id ?? 0
        addHistoryEvent(HistoryEvent(brokerId: brokerId, profileQueryId: profileQueryId, type: .scanStarted))
    }

    func addScanResultEvents(for query: BrokerProfileQueryData, extractedProfiles: [ExtractedProfile]) {
        let brokerId = query.dataBroker.id ?? 0
        let profileQueryId = query.profileQuery.id ?? 0
        let eventType: HistoryEvent.EventType = extractedProfiles.isEmpty ? .noMatchFound : .matchesFound(count: extractedProfiles.count)
        addHistoryEvent(HistoryEvent(brokerId: brokerId, profileQueryId: profileQueryId, type: eventType))
    }

    func addScanErrorEvent(for query: BrokerProfileQueryData, error: Error) {
        let brokerId = query.dataBroker.id ?? 0
        let profileQueryId = query.profileQuery.id ?? 0
        let dbpError = (error as? DataBrokerProtectionError) ?? .unknown(error.localizedDescription)
        addHistoryEvent(HistoryEvent(brokerId: brokerId, profileQueryId: profileQueryId, type: .error(error: dbpError)))
    }

    func addOptOutStartedEvent(for scanResult: ScanResult) {
        let brokerId = scanResult.dataBroker.id ?? 0
        let profileQueryId = scanResult.profileQuery.id ?? 0
        let extractedProfileId = scanResult.extractedProfile.id ?? 0
        addHistoryEvent(HistoryEvent(extractedProfileId: extractedProfileId,
                                     brokerId: brokerId,
                                     profileQueryId: profileQueryId,
                                     type: .optOutStarted))
    }

    func addOptOutConfirmedEvent(for scanResult: ScanResult) {
        let brokerId = scanResult.dataBroker.id ?? 0
        let profileQueryId = scanResult.profileQuery.id ?? 0
        let extractedProfileId = scanResult.extractedProfile.id ?? 0
        addHistoryEvent(HistoryEvent(extractedProfileId: extractedProfileId,
                                     brokerId: brokerId,
                                     profileQueryId: profileQueryId,
                                     type: .optOutConfirmed))
    }

    func addOptOutErrorEvent(for scanResult: ScanResult, error: Error) {
        let brokerId = scanResult.dataBroker.id ?? 0
        let profileQueryId = scanResult.profileQuery.id ?? 0
        let extractedProfileId = scanResult.extractedProfile.id ?? 0
        let dbpError = (error as? DataBrokerProtectionError) ?? .unknown(error.localizedDescription)
        addHistoryEvent(HistoryEvent(extractedProfileId: extractedProfileId,
                                     brokerId: brokerId,
                                     profileQueryId: profileQueryId,
                                     type: .error(error: dbpError)))
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
        let summary = historyEventDescription(event)
        let profileQueryLabel = historyEventDetails(event)
        DispatchQueue.main.async {
            self.debugEvents.append(DebugLogEvent(timestamp: event.date,
                                                  kind: .history,
                                                  profileQueryLabel: profileQueryLabel,
                                                  summary: summary,
                                                  details: ""))
        }
    }
}
