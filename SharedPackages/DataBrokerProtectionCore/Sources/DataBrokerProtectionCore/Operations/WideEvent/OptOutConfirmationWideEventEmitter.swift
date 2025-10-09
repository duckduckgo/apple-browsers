//
//  OptOutConfirmationWideEventEmitter.swift
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

enum OptOutConfirmationWideEventEmitter {
    static let sampleRate: Float = 1.0

    static func emitSuccess(wideEvent: WideEventManaging?,
                            attemptID: UUID?,
                            recordFoundDate: Date,
                            confirmationDate: Date,
                            dataBrokerURL: String,
                            dataBrokerVersion: String?) {
        emit(wideEvent: wideEvent,
             attemptID: attemptID,
             recordFoundDate: recordFoundDate,
             confirmationDate: confirmationDate,
             dataBrokerURL: dataBrokerURL,
             dataBrokerVersion: dataBrokerVersion,
             status: .success)
    }

    static func emitFailure(wideEvent: WideEventManaging?,
                            attemptID: UUID?,
                            dataBrokerURL: String,
                            dataBrokerVersion: String?,
                            error: Error?) {
        emit(wideEvent: wideEvent,
             attemptID: attemptID,
             dataBrokerURL: dataBrokerURL,
             dataBrokerVersion: dataBrokerVersion,
             status: .failure,
             error: error)
    }

    static func emitCancelled(wideEvent: WideEventManaging?,
                              attemptID: UUID?,
                              dataBrokerURL: String,
                              dataBrokerVersion: String?,
                              error: Error?) {
        emit(wideEvent: wideEvent,
             attemptID: attemptID,
             dataBrokerURL: dataBrokerURL,
             dataBrokerVersion: dataBrokerVersion,
             status: .cancelled,
             error: error)
    }

    private static func emit(wideEvent: WideEventManaging?,
                             attemptID: UUID?,
                             recordFoundDate: Date = RecordFoundDateResolver.defaultDate,
                             confirmationDate: Date? = nil,
                             dataBrokerURL: String,
                             dataBrokerVersion: String?,
                             status: WideEventStatus,
                             error: Error? = nil) {
        guard let wideEvent, let attemptID else { return }

        let global = WideEventGlobalData(id: attemptID.uuidString, sampleRate: Self.sampleRate)
        let interval = confirmationDate.map { WideEvent.MeasuredInterval(start: recordFoundDate, end: $0) }
        let data = OptOutConfirmationWideEventData(globalData: global,
                                                   dataBrokerURL: dataBrokerURL,
                                                   dataBrokerVersion: dataBrokerVersion,
                                                   confirmationInterval: interval)

        if let error {
            data.errorData = WideEventErrorData(error: error)
        }

        wideEvent.startFlow(data)
        wideEvent.completeFlow(data, status: status) { _, _ in }
    }
}
