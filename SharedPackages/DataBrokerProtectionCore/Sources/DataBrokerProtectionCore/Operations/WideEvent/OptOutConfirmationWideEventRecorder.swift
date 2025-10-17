//
//  OptOutConfirmationWideEventRecorder.swift
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

protocol OptOutConfirmationWideEventRecording: AnyObject {
    func markConfirmationCompleted(at date: Date)
}

final class OptOutConfirmationWideEventRecorder {
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
    private var data: OptOutConfirmationWideEventData
    private let queue = DispatchQueue(label: "com.duckduckgo.dbp.optout-confirmation-wide-event", qos: .utility)
    private var isCompleted = false

    private init(wideEvent: WideEventManaging,
                 data: OptOutConfirmationWideEventData,
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
                               recordFoundDate: Date) -> OptOutConfirmationWideEventRecorder? {
        guard let wideEvent else { return nil }

        let global = WideEventGlobalData(id: identifier.toGlobalId, sampleRate: sampleRate)
        let interval = WideEvent.MeasuredInterval(start: recordFoundDate, end: nil)
        let data = OptOutConfirmationWideEventData(globalData: global,
                                                   dataBrokerURL: dataBrokerURL,
                                                   dataBrokerVersion: dataBrokerVersion,
                                                   confirmationInterval: interval)

        return OptOutConfirmationWideEventRecorder(wideEvent: wideEvent,
                                                   data: data,
                                                   shouldStartFlow: true)
    }

    static func resumeIfPossible(wideEvent: WideEventManaging?,
                                 identifier: Identifier) -> OptOutConfirmationWideEventRecorder? {
        guard let wideEvent,
              let existing: OptOutConfirmationWideEventData = wideEvent.getFlowData(OptOutConfirmationWideEventData.self,
                                                                                    globalID: identifier.toGlobalId) else {
            return nil
        }

        return OptOutConfirmationWideEventRecorder(wideEvent: wideEvent,
                                                   data: existing,
                                                   shouldStartFlow: false)
    }

    static func prepareIfPossible(wideEvent: WideEventManaging?,
                                  identifier: Identifier,
                                  dataBrokerURL: String,
                                  dataBrokerVersion: String?,
                                  recordFoundDateProvider: () -> Date) -> OptOutConfirmationWideEventRecorder? {
        if let recorder = resumeIfPossible(wideEvent: wideEvent, identifier: identifier) {
            return recorder
        }

        return makeIfPossible(wideEvent: wideEvent,
                              identifier: identifier,
                              dataBrokerURL: dataBrokerURL,
                              dataBrokerVersion: dataBrokerVersion,
                              recordFoundDate: recordFoundDateProvider())
    }

    private func updateFlow() {
        wideEvent.updateFlow(data)
    }

    private func setConfirmationEnd(date: Date) {
        queue.async {
            self.data.confirmationInterval?.end = date
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

extension OptOutConfirmationWideEventRecorder: OptOutConfirmationWideEventRecording {
    func markConfirmationCompleted(at date: Date) {
        setConfirmationEnd(date: date)
        completeInternal(status: .success)
    }
}
