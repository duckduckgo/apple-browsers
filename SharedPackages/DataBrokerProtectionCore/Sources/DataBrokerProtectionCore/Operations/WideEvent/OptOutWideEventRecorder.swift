//
//  OptOutWideEventRecorder.swift
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

protocol OptOutWideEventRecording: AnyObject {
    func recordStage(_ stage: Stage,
                     durationMilliseconds: Int?,
                     tries: Int,
                     actionID: String?)
    func markSubmissionCompleted(at date: Date,
                                 tries: Int,
                                 actionID: String?)
    func markConfirmationCompleted(at date: Date)
    func recordError(_ error: Error)
    func complete(status: WideEventStatus)
    func cancel()
}

final class OptOutWideEventRecorder {
    private let wideEvent: WideEventManaging
    private var data: OptOutWideEventData
    private let queue = DispatchQueue(label: "com.duckduckgo.dbp.optout-wide-event", qos: .utility)
    private let attemptID: UUID
    private var isCompleted = false

    private init(wideEvent: WideEventManaging,
                 data: OptOutWideEventData,
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
                               recordFoundDate: Date,
                               sampleRate: Float = 1.0) -> OptOutWideEventRecorder? {
        guard let wideEvent else { return nil }

        let global = WideEventGlobalData(id: attemptID.uuidString,
                                         sampleRate: sampleRate)
        let submissionInterval = WideEvent.MeasuredInterval(start: recordFoundDate, end: nil)
        let confirmationInterval = WideEvent.MeasuredInterval(start: recordFoundDate, end: nil)
        let data = OptOutWideEventData(globalData: global,
                                       dataBrokerURL: dataBrokerURL,
                                       dataBrokerVersion: dataBrokerVersion,
                                       submissionInterval: submissionInterval,
                                       confirmationInterval: confirmationInterval)

        return OptOutWideEventRecorder(wideEvent: wideEvent,
                                       data: data,
                                       attemptID: attemptID,
                                       shouldStartFlow: true)
    }

    static func resumeIfPossible(wideEvent: WideEventManaging?, attemptID: UUID) -> OptOutWideEventRecorder? {
        guard let wideEvent,
              let existing: OptOutWideEventData = wideEvent.getFlowData(OptOutWideEventData.self,
                                                                        globalID: attemptID.uuidString) else {
            return nil
        }

        return OptOutWideEventRecorder(wideEvent: wideEvent,
                                       data: existing,
                                       attemptID: attemptID,
                                       shouldStartFlow: false)
    }

    private func addStage(name: OptOutWideEventData.StageName,
                          durationMilliseconds: Int?,
                          tries: Int?,
                          actionID: String?) {
        queue.async {
            var sanitizedDuration = durationMilliseconds
            if let duration = sanitizedDuration, duration < 0 {
                sanitizedDuration = nil
            }

            let stage = OptOutWideEventData.Stage(name: name,
                                                  durationMilliseconds: sanitizedDuration,
                                                  tries: tries,
                                                  actionID: actionID)
            self.data.appendStage(stage)
            self.updateFlow()
        }
    }

    private func updateFlow() {
        wideEvent.updateFlow(data)
    }

    private func setSubmissionEnd(date: Date, tries: Int?, actionID: String?) {
        queue.async {
            self.data.submissionInterval?.end = date
            self.updateFlow()
        }
    }

    private func setConfirmationEnd(date: Date) {
        queue.async {
            self.data.confirmationInterval?.end = date
            self.updateFlow()
        }
    }

    private func setError(_ error: Error) {
        queue.async {
            self.data.errorData = WideEventErrorData(error: error)
            self.updateFlow()
        }
    }

    private func completeInternal(status: WideEventStatus) {
        queue.async {
            guard !self.isCompleted else { return }
            self.isCompleted = true
            Task {
                _ = try? await self.wideEvent.completeFlow(self.data, status: status)
            }
        }
    }

    private func mapStageName(_ stage: Stage) -> OptOutWideEventData.StageName {
        OptOutWideEventData.StageName(rawValue: stage.rawValue) ?? .other
    }
}

extension OptOutWideEventRecorder: OptOutWideEventRecording {
    func recordStage(_ stage: Stage,
                     durationMilliseconds: Int?,
                     tries: Int,
                     actionID: String?) {
        let sanitizedAction = actionID?.isEmpty == false ? actionID : nil
        let normalizedDuration: Int? = durationMilliseconds.map { max($0, 0) }
        addStage(name: mapStageName(stage),
                 durationMilliseconds: normalizedDuration,
                 tries: tries,
                 actionID: sanitizedAction)
    }

    func markSubmissionCompleted(at date: Date,
                                 tries: Int,
                                 actionID: String?) {
        setSubmissionEnd(date: date, tries: tries, actionID: actionID)
    }

    func markConfirmationCompleted(at date: Date) {
        setConfirmationEnd(date: date)
    }

    func recordError(_ error: Error) {
        setError(error)
    }

    func complete(status: WideEventStatus) {
        completeInternal(status: status)
    }

    func cancel() {
        completeInternal(status: .cancelled)
    }
}
