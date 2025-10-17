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
    func markSubmissionCompleted(at date: Date)
    func complete()
}

final class OptOutSubmissionWideEventRecorder {
    static let sampleRate: Float = 1.0

    struct Identifier {
        let profileIdentifier: String?
        let brokerId: Int64
        let profileQueryId: Int64
        let extractedProfileId: Int64

        var toGlobalId: String {
            profileIdentifier?.sha256 ?? "\(brokerId)-\(profileQueryId)-\(extractedProfileId)"
        }
    }

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
                               identifier: Identifier,
                               dataBrokerURL: String,
                               dataBrokerVersion: String?,
                               recordFoundDate: Date) -> OptOutSubmissionWideEventRecorder? {
        guard let wideEvent else { return nil }

        let global = WideEventGlobalData(id: identifier.toGlobalId, sampleRate: sampleRate)
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
                                 identifier: Identifier) -> OptOutSubmissionWideEventRecorder? {
        guard let wideEvent,
              let existing: OptOutSubmissionWideEventData = wideEvent.getFlowData(OptOutSubmissionWideEventData.self,
                                                                                  globalID: identifier.toGlobalId) else {
            return nil
        }

        return OptOutSubmissionWideEventRecorder(wideEvent: wideEvent,
                                                 data: existing,
                                                 shouldStartFlow: false)
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

    private func completeInternal(status: WideEventStatus) {
        queue.async {
            guard !self.isCompleted else { return }
            self.isCompleted = true
            Task {
                _ = try? await self.wideEvent.completeFlow(self.data, status: status)
            }
        }
    }
}

extension OptOutSubmissionWideEventRecorder: OptOutSubmissionWideEventRecording {
    func markSubmissionCompleted(at date: Date) {
        setSubmissionEnd(date: date)
    }

    func complete() {
        completeInternal(status: .success)
    }
}
