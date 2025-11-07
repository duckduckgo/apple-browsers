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
    /// This initializes the metadata for the wide event based on history events
    ///
    /// Look for scan success event (matchesFound, noMatchFound) in the history
    /// - intervalStart is set to when the first .scanStarted after the most recent success event occurs,
    ///   falls back to referenceDate otherwise
    /// - attemptNumber is the number of .scanStarted events after the most recent success event + 1,
    ///   falls back 1 otherwise
    /// - attemptType follows OperationPreferredDateCalculator.dateForScanOperation logic:
    ///   - set to confirmationOptOutScan if the most recent event is optOutRequested
    ///   - set to maintenanceScan if the most recent event is either optOutConfirmed, noMatchFound, matchesFound, or reAppearence (sic)
    ///   - set to newScan if there has been no scan success event, maintenanceScan otherwise
    init(from scanJobData: ScanJobData, referenceDate: Date) {
        let sortedEvents = scanJobData.historyEvents.sorted { $0.date < $1.date }

        let lastSuccessDate = sortedEvents.last(where: { $0.isScanSuccessEvent() })?.date

        let eventsAfterLastSuccess = sortedEvents.filter { event in
            guard let lastSuccessDate else { return true }
            return event.date > lastSuccessDate
        }

        let attemptsInCurrentCycle = eventsAfterLastSuccess.filter { event in
            if case .scanStarted = event.type {
                return true
            }
            return false
        }

        let attemptNumber = max(attemptsInCurrentCycle.count + 1, 1)
        let intervalStart = attemptsInCurrentCycle.map { $0.date }.min() ?? referenceDate

        let latestEvent = sortedEvents.last
        let attemptType: ScanWideEventData.AttemptType
        switch latestEvent?.type {
        case .optOutRequested:
            attemptType = .confirmOptOutScan
        case .optOutConfirmed,
             .noMatchFound,
             .matchesFound,
             .reAppearence:
            attemptType = .maintenanceScan
        default:
            attemptType = (lastSuccessDate == nil) ? .newScan : .maintenanceScan
        }

        self.intervalStart = intervalStart
        self.attemptNumber = attemptNumber
        self.attemptType = attemptType
    }
}
