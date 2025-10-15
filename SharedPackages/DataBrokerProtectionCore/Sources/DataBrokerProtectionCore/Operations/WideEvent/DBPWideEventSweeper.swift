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

public final class DBPWideEventSweeper {

    public enum Constants {
        public static let defaultSubmissionWindow: TimeInterval = .days(7)
        public static let defaultConfirmationWindow: TimeInterval = .days(14)
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
        queue.async { [weak self] in
            guard let self else { return }
            Task {
                await self.performSweep()
            }
        }
    }

    public func performSweep() async {
        await sweepPendingSubmissions()
        await sweepPendingConfirmations()
    }

    // MARK: - Submission

    private func sweepPendingSubmissions() async {
        let pendingSubmissions: [OptOutSubmissionWideEventData] = wideEvent.getAllFlowData(OptOutSubmissionWideEventData.self)

        guard !pendingSubmissions.isEmpty else { return }

        for data in pendingSubmissions {
            guard let interval = data.submissionInterval,
                  let start = interval.start,
                  interval.end == nil else {
                continue
            }

            let deadline = start.addingTimeInterval(submissionWindow)
            guard currentDateForTesting() >= deadline else {
                continue
            }

            let reason = OptOutSubmissionWideEventData.StatusReason.submissionWindowExpired.rawValue
            _ = try? await wideEvent.completeFlow(data, status: .unknown(reason: reason))
        }
    }

    // MARK: - Confirmation

    private func sweepPendingConfirmations() async {
        let pendingConfirmations: [OptOutConfirmationWideEventData] = wideEvent.getAllFlowData(OptOutConfirmationWideEventData.self)

        guard !pendingConfirmations.isEmpty else { return }

        for data in pendingConfirmations {
            guard let interval = data.confirmationInterval,
                  let start = interval.start,
                  interval.end == nil else {
                continue
            }

            let deadline = start.addingTimeInterval(confirmationWindow)
            guard currentDateForTesting() >= deadline else {
                continue
            }

            let reason = OptOutConfirmationWideEventData.StatusReason.confirmationWindowExpired.rawValue
            _ = try? await wideEvent.completeFlow(data, status: .unknown(reason: reason))
        }
    }
}
