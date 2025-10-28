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
import os.log

final class OptOutConfirmationWideEventRecorder: OptOutWideEventRecording {
    static let sampleRate: Float = 1.0

    let recorder: WideEventRecorder<OptOutConfirmationWideEventData>

    private init(recorder: WideEventRecorder<OptOutConfirmationWideEventData>) {
        self.recorder = recorder
    }

    static func makeIfPossible(wideEvent: WideEventManaging?,
                               identifier: OptOutWideEventIdentifier,
                               dataBrokerURL: String,
                               dataBrokerVersion: String?,
                               recordFoundDate: Date) -> OptOutConfirmationWideEventRecorder? {
        guard let recorder = WideEventRecorder<OptOutConfirmationWideEventData>.makeIfPossible(
            wideEvent: wideEvent,
            identifier: identifier.toGlobalId,
            sampleRate: sampleRate,
            intervalStart: recordFoundDate,
            makeData: { global, interval in
                OptOutConfirmationWideEventData(globalData: global,
                                                dataBrokerURL: dataBrokerURL,
                                                dataBrokerVersion: dataBrokerVersion,
                                                confirmationInterval: interval)
            }
        ) else { return nil }

        Logger.dataBrokerProtection.debug("PIR confirmation flow start")
        return OptOutConfirmationWideEventRecorder(recorder: recorder)
    }

    static func resumeIfPossible(wideEvent: WideEventManaging?,
                                 identifier: OptOutWideEventIdentifier) -> OptOutConfirmationWideEventRecorder? {
        guard let recorder = WideEventRecorder<OptOutConfirmationWideEventData>.resumeIfPossible(
            wideEvent: wideEvent,
            identifier: identifier.toGlobalId
        ) else {
            return nil
        }

        Logger.dataBrokerProtection.debug("PIR confirmation flow resume")
        return OptOutConfirmationWideEventRecorder(recorder: recorder)
    }

    @discardableResult
    static func startIfPossible(wideEvent: WideEventManaging?,
                                identifier: OptOutWideEventIdentifier,
                                dataBrokerURL: String,
                                dataBrokerVersion: String?,
                                recordFoundDateProvider: () -> Date?) -> OptOutConfirmationWideEventRecorder? {
        guard let recorder = WideEventRecorder<OptOutConfirmationWideEventData>.startIfPossible(
            wideEvent: wideEvent,
            identifier: identifier.toGlobalId,
            sampleRate: sampleRate,
            intervalStartProvider: recordFoundDateProvider,
            makeData: { global, interval in
                OptOutConfirmationWideEventData(globalData: global,
                                                 dataBrokerURL: dataBrokerURL,
                                                 dataBrokerVersion: dataBrokerVersion,
                                                 confirmationInterval: interval)
            }
        ) else {
            return nil
        }

        return OptOutConfirmationWideEventRecorder(recorder: recorder)
    }

    func markCompleted(at date: Date) {
        recorder.markCompleted(at: date, invalidIntervalReason: OptOutConfirmationWideEventData.StatusReason.recordFoundDateMissing.rawValue)
    }
}
