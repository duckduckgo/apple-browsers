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
                            profileIdentifier: String?,
                            recordFoundDate: Date,
                            confirmationDate: Date,
                            dataBrokerURL: String,
                            dataBrokerVersion: String?) {
        guard let wideEvent,
              let identifier = profileIdentifier?.sha256 else { return }

        let global = WideEventGlobalData(id: identifier, sampleRate: sampleRate)
        let interval = WideEvent.MeasuredInterval(start: recordFoundDate, end: confirmationDate)
        let data = OptOutConfirmationWideEventData(globalData: global,
                                                   dataBrokerURL: dataBrokerURL,
                                                   dataBrokerVersion: dataBrokerVersion,
                                                   confirmationInterval: interval)

        wideEvent.startFlow(data)
        wideEvent.completeFlow(data, status: .success) { _, _ in }
    }
}
