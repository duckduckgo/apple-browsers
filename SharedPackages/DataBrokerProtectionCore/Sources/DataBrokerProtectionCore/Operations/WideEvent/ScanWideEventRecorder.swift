//
//  ScanWideEventRecorder.swift
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
import BrowserServicesKit
import PixelKit

final class ScanWideEventRecorder {
    struct Metadata {
        let intervalStart: Date
        let attemptNumber: Int
        let attemptType: ScanWideEventData.AttemptType
        let isFreeScan: Bool
    }

    static let sampleRate: Float = 1.0

    private let wideEvent: WideEventManaging
    private var data: ScanWideEventData
    private let queue = DispatchQueue(label: "com.duckduckgo.dbp.scan-wide-event", qos: .utility)
    private var isCompleted = false

    let attemptID: UUID

    private init(wideEvent: WideEventManaging,
                 data: ScanWideEventData,
                 attemptID: UUID,
                 shouldStartFlow: Bool) {
        self.wideEvent = wideEvent
        self.data = data
        self.attemptID = attemptID

        if shouldStartFlow {
            wideEvent.startFlow(data)
        }
    }

    static func makeIfPossible(wideEvent: WideEventManaging?,
                               attemptID: UUID,
                               dataBrokerURL: String,
                               dataBrokerVersion: String?,
                               metadata: Metadata) -> ScanWideEventRecorder? {
        guard let wideEvent else { return nil }

        let global = WideEventGlobalData(id: attemptID.uuidString, sampleRate: sampleRate)
        let interval = WideEvent.MeasuredInterval(start: metadata.intervalStart, end: nil)
        let data = ScanWideEventData(globalData: global,
                                     dataBrokerURL: dataBrokerURL,
                                     dataBrokerVersion: dataBrokerVersion,
                                     attemptType: metadata.attemptType,
                                     attemptNumber: metadata.attemptNumber,
                                     isFreeScan: metadata.isFreeScan,
                                     scanInterval: interval)

        return ScanWideEventRecorder(wideEvent: wideEvent,
                                     data: data,
                                     attemptID: attemptID,
                                     shouldStartFlow: true)
    }

    static func startIfPossible(wideEvent: WideEventManaging?,
                                attemptID: UUID,
                                dataBrokerURL: String,
                                dataBrokerVersion: String?,
                                metadata: Metadata) -> ScanWideEventRecorder? {
        if let existing = resumeIfPossible(wideEvent: wideEvent, attemptID: attemptID) {
            existing.updateMetadata(metadata)
            return existing
        }

        return makeIfPossible(wideEvent: wideEvent,
                              attemptID: attemptID,
                              dataBrokerURL: dataBrokerURL,
                              dataBrokerVersion: dataBrokerVersion,
                              metadata: metadata)
    }

    static func resumeIfPossible(wideEvent: WideEventManaging?,
                                 attemptID: UUID) -> ScanWideEventRecorder? {
        guard let wideEvent,
              let existing: ScanWideEventData = wideEvent.getFlowData(ScanWideEventData.self,
                                                                      globalID: attemptID.uuidString) else {
            return nil
        }

        return ScanWideEventRecorder(wideEvent: wideEvent,
                                     data: existing,
                                     attemptID: attemptID,
                                     shouldStartFlow: false)
    }

    private func updateMetadata(_ metadata: Metadata) {
        queue.async {
            self.data.attemptNumber = metadata.attemptNumber
            self.data.attemptType = metadata.attemptType
            self.data.isFreeScan = metadata.isFreeScan
            self.data.scanInterval?.start = metadata.intervalStart
            self.wideEvent.updateFlow(self.data)
        }
    }

    func complete(status: WideEventStatus, endDate: Date?, error: Error?) {
        queue.async {
            guard !self.isCompleted else { return }

            self.data.scanInterval?.end = endDate

            if let error {
                self.data.errorData = WideEventErrorData(error: error)
            }

            self.isCompleted = true

            Task {
                _ = try? await self.wideEvent.completeFlow(self.data, status: status)
            }
        }
    }
}

extension ScanWideEventRecorder.Metadata {
    /// This initializes the metadata for the wide event based on history events.
    ///
    /// attemptNumber / intervalStart are derived from the scan job's history:
    /// - intervalStart is set to when the first .scanStarted after the most recent scan success event
    ///   (matchesFound, noMatchFound) occurs, falling back to referenceDate.
    /// - attemptNumber is the count of .scanStarted events after the most recent scan success event + 1,
    ///   falling back to 1.
    ///
    /// attemptType mirrors the confirmOptOutScan branch of OperationPreferredDateCalculator.dateForScanOperation:
    /// - confirmOptOutScan if any opt-out job's most recent event is .optOutRequested.
    /// - maintenanceScan if there has been a prior scan success.
    /// - newScan otherwise.
    /// - Parameters:
    ///   - scanHistoryEvents: Scan job history events, sorted earliest-first.
    ///   - optOutsHistoryEvents: Each opt-out job's history events, sorted earliest-first within each inner array.
    init(scanHistoryEvents: [HistoryEvent],
         optOutsHistoryEvents: [[HistoryEvent]],
         referenceDate: Date,
         isFreeScan: Bool) {
        let lastSuccessDate = scanHistoryEvents.last(where: { $0.isScanSuccessEvent() })?.date

        let attemptsInCurrentCycle = scanHistoryEvents.filter { event in
            guard case .scanStarted = event.type else { return false }
            guard let lastSuccessDate else { return true }
            return event.date > lastSuccessDate
        }

        let attemptNumber = max(attemptsInCurrentCycle.count + 1, 1)
        let intervalStart = attemptsInCurrentCycle.first?.date ?? referenceDate

        let latestOptOutEvents = optOutsHistoryEvents.compactMap { $0.last }
        let hasPendingOptOutConfirmation = latestOptOutEvents.contains { $0.type == .optOutRequested }

        let attemptType: ScanWideEventData.AttemptType
        if hasPendingOptOutConfirmation {
            attemptType = .confirmOptOutScan
        } else if lastSuccessDate != nil {
            attemptType = .maintenanceScan
        } else {
            attemptType = .newScan
        }

        self.intervalStart = intervalStart
        self.attemptNumber = attemptNumber
        self.attemptType = attemptType
        self.isFreeScan = isFreeScan
    }
}
