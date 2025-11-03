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
import os.log

final class OptOutSubmissionWideEventRecorder: OptOutWideEventRecording {
    static let sampleRate: Float = 1.0

    let recorder: WideEventRecorder<OptOutSubmissionWideEventData>

    private init(recorder: WideEventRecorder<OptOutSubmissionWideEventData>) {
        self.recorder = recorder
    }

    static func makeIfPossible(wideEvent: WideEventManaging?,
                               identifier: OptOutWideEventIdentifier,
                               dataBrokerURL: String,
                               dataBrokerVersion: String?,
                               recordFoundDate: Date?) -> OptOutSubmissionWideEventRecorder? {
        guard let recorder = WideEventRecorder<OptOutSubmissionWideEventData>.makeIfPossible(
            wideEvent: wideEvent,
            identifier: identifier.toGlobalId,
            sampleRate: sampleRate,
            intervalStart: recordFoundDate,
            makeData: { global, interval in
                OptOutSubmissionWideEventData(globalData: global,
                                               dataBrokerURL: dataBrokerURL,
                                               dataBrokerVersion: dataBrokerVersion,
                                               submissionInterval: interval)
            }
        ) else { return nil }

        Logger.dataBrokerProtection.debug("PIR submission flow start")
        return OptOutSubmissionWideEventRecorder(recorder: recorder)
    }

    static func resumeIfPossible(wideEvent: WideEventManaging?,
                                 identifier: OptOutWideEventIdentifier) -> OptOutSubmissionWideEventRecorder? {
        guard let recorder = WideEventRecorder<OptOutSubmissionWideEventData>.resumeIfPossible(
            wideEvent: wideEvent,
            identifier: identifier.toGlobalId
        ) else {
            return nil
        }

        Logger.dataBrokerProtection.debug("PIR submission flow resume")
        return OptOutSubmissionWideEventRecorder(recorder: recorder)
    }

    @discardableResult
    static func startIfPossible(wideEvent: WideEventManaging?,
                                identifier: OptOutWideEventIdentifier,
                                dataBrokerURL: String,
                                dataBrokerVersion: String?,
                                recordFoundDate: Date?) -> OptOutSubmissionWideEventRecorder? {
        guard let recorder = WideEventRecorder<OptOutSubmissionWideEventData>.startIfPossible(
            wideEvent: wideEvent,
            identifier: identifier.toGlobalId,
            sampleRate: sampleRate,
            intervalStart: recordFoundDate,
            makeData: { global, interval in
                OptOutSubmissionWideEventData(globalData: global,
                                               dataBrokerURL: dataBrokerURL,
                                               dataBrokerVersion: dataBrokerVersion,
                                               submissionInterval: interval)
            }
        ) else {
            return nil
        }

        return OptOutSubmissionWideEventRecorder(recorder: recorder)
    }

    func markCompleted(at date: Date) {
        recorder.markCompleted(at: date, invalidIntervalReason: OptOutSubmissionWideEventData.StatusReason.recordFoundDateMissing.rawValue)
    }
}
