//
//  DBPWideEventSweeper.swift
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

public final class DBPWideEventSweeper {

    public enum Constants {
        public static let buffer: TimeInterval = .days(7)
        public static let defaultSubmissionWindow: TimeInterval = .days(7) + buffer
        public static let defaultConfirmationWindow: TimeInterval = .days(14) + buffer
    }

    private let wideEvent: WideEventManaging
    private let submissionWindow: TimeInterval
    private let confirmationWindow: TimeInterval
    private let currentDateForTesting: () -> Date
    private let queue = DispatchQueue(label: "com.duckduckgo.dbp-wide-event-sweeper", qos: .utility)

    public init(wideEvent: WideEventManaging,
                submissionWindow: TimeInterval = Constants.defaultSubmissionWindow,
                confirmationWindow: TimeInterval = Constants.defaultConfirmationWindow,
                currentDateForTesting: @escaping () -> Date = Date.init) {
        self.wideEvent = wideEvent
        self.submissionWindow = submissionWindow
        self.confirmationWindow = confirmationWindow
        self.currentDateForTesting = currentDateForTesting
    }

    public func sweep() {
        Logger.dataBrokerProtection.debug("PIR wide event sweep requested")
        queue.async { [weak self] in
            guard let self else { return }
            Task {
                await self.performSweep()
            }
        }
    }

    public func performSweep() async {
        Logger.dataBrokerProtection.debug("PIR wide event sweep started")
        await sweepPendingSubmissions()
        await sweepPendingConfirmations()
        Logger.dataBrokerProtection.debug("PIR wide event sweep finished")
    }

    private func sweepPendingFlows<Data: WideEventDataMeasuringInterval>(
        _ type: Data.Type,
        window: TimeInterval,
        completionReason: String
    ) async {
        let pending: [Data] = wideEvent.getAllFlowData(type)

        guard !pending.isEmpty else { return }

        for data in pending {
            guard let interval = data.measuredInterval,
                  let start = interval.start,
                  interval.end == nil else {
                continue
            }

            let deadline = start.addingTimeInterval(window)
            guard currentDateForTesting() >= deadline else {
                continue
            }

            _ = try? await wideEvent.completeFlow(data, status: .unknown(reason: completionReason))
        }
    }

    // MARK: - Submission

    private func sweepPendingSubmissions() async {
        await sweepPendingFlows(
            OptOutSubmissionWideEventData.self,
            window: submissionWindow,
            completionReason: OptOutSubmissionWideEventData.StatusReason.submissionWindowExpired.rawValue
        )
    }

    // MARK: - Confirmation

    private func sweepPendingConfirmations() async {
        await sweepPendingFlows(
            OptOutConfirmationWideEventData.self,
            window: confirmationWindow,
            completionReason: OptOutConfirmationWideEventData.StatusReason.confirmationWindowExpired.rawValue
        )
    }
}
