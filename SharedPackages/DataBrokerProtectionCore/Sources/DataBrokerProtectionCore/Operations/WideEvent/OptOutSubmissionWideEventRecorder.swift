//
//  OptOutSubmissionWideEventRecorder.swift
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

protocol OptOutSubmissionWideEventRecording: AnyObject {
    func recordStage(_ stage: Stage,
                     duration: Double?,
                     tries: Int,
                     actionID: String?)
    func markSubmissionCompleted(at date: Date,
                                 tries: Int,
                                 actionID: String?)
    func complete(status: WideEventStatus)
    func complete(status: WideEventStatus, with error: Error?)
    func cancel(with error: Error?)
}

extension OptOutSubmissionWideEventRecording {
    func complete(status: WideEventStatus) {
        complete(status: status, with: nil)
    }
}

final class OptOutSubmissionWideEventRecorder {
    static let sampleRate: Float = 1.0

    private let wideEvent: WideEventManaging
    private var data: OptOutSubmissionWideEventData
    private let queue = DispatchQueue(label: "com.duckduckgo.dbp.optout-submission-wide-event", qos: .utility)
    private var isCompleted = false

    private init(wideEvent: WideEventManaging,
                 data: OptOutSubmissionWideEventData,
                 shouldStartFlow: Bool) {
        self.wideEvent = wideEvent
        self.data = data

        if shouldStartFlow {
            wideEvent.startFlow(data)
        }
    }

    static func makeIfPossible(wideEvent: WideEventManaging?,
                               attemptID: UUID,
                               dataBrokerURL: String,
                               dataBrokerVersion: String?,
                               recordFoundDate: Date) -> OptOutSubmissionWideEventRecorder? {
        guard let wideEvent else { return nil }

        let global = WideEventGlobalData(id: attemptID.uuidString, sampleRate: sampleRate)
        let submissionInterval = WideEvent.MeasuredInterval(start: recordFoundDate, end: nil)
        let data = OptOutSubmissionWideEventData(globalData: global,
                                                 dataBrokerURL: dataBrokerURL,
                                                 dataBrokerVersion: dataBrokerVersion,
                                                 submissionInterval: submissionInterval)

        return OptOutSubmissionWideEventRecorder(wideEvent: wideEvent,
                                                 data: data,
                                                 shouldStartFlow: true)
    }

    static func resumeIfPossible(wideEvent: WideEventManaging?,
                                 attemptID: UUID) -> OptOutSubmissionWideEventRecorder? {
        guard let wideEvent,
              let existing: OptOutSubmissionWideEventData = wideEvent.getFlowData(OptOutSubmissionWideEventData.self,
                                                                                  globalID: attemptID.uuidString) else {
            return nil
        }

        return OptOutSubmissionWideEventRecorder(wideEvent: wideEvent,
                                                 data: existing,
                                                 shouldStartFlow: false)
    }

    private func addStage(name: OptOutSubmissionWideEventData.StageName,
                          duration: Double?,
                          tries: Int?,
                          actionID: String?) {
        queue.async {
            let sanitizedDuration = duration.flatMap { max($0, 0) }
            let stage = OptOutSubmissionWideEventData.Stage(name: name,
                                                            duration: sanitizedDuration,
                                                            tries: tries,
                                                            actionID: actionID)
            self.data.appendStage(stage)
            self.updateFlow()
        }
    }

    private func updateFlow() {
        wideEvent.updateFlow(data)
    }

    private func setSubmissionEnd(date: Date) {
        queue.async {
            self.data.submissionInterval?.end = date
            self.updateFlow()
        }
    }

    private func setError(_ error: Error?) {
        guard let error else { return }
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

    private func mapStageName(_ stage: Stage) -> OptOutSubmissionWideEventData.StageName {
        if let mapped = OptOutSubmissionWideEventData.StageName(rawValue: stage.rawValue) {
            return mapped
        } else {
            assertionFailure("Unknown stage name")
            return .other
        }
    }
}

extension OptOutSubmissionWideEventRecorder: OptOutSubmissionWideEventRecording {
    func recordStage(_ stage: Stage,
                     duration: Double?,
                     tries: Int,
                     actionID: String?) {
        let sanitizedAction = actionID?.isEmpty == false ? actionID : nil
        let sanitizedDuration = duration.flatMap { max($0, 0) }
        addStage(name: mapStageName(stage),
                 duration: sanitizedDuration,
                 tries: tries,
                 actionID: sanitizedAction)
    }

    func markSubmissionCompleted(at date: Date,
                                 tries: Int,
                                 actionID: String?) {
        setSubmissionEnd(date: date)
    }

    func complete(status: WideEventStatus, with error: Error?) {
        setError(error)
        completeInternal(status: status)
    }

    func cancel(with error: Error?) {
        setError(error)
        completeInternal(status: .cancelled)
    }
}
