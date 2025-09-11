//
//  DataBrokerProtectionBackgroundActivityScheduler.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Common
import BrowserServicesKit
import os.log
import DataBrokerProtectionCore

public protocol DataBrokerProtectionBackgroundActivityScheduler {
    func startScheduler() async

    var delegate: DataBrokerProtectionBackgroundActivitySchedulerDelegate? { get set }
    var dataSource: DataBrokerProtectionBackgroundActivitySchedulerDataSource? { get set }

    var lastTriggerTimestamp: Date? { get }
}

public protocol DataBrokerProtectionBackgroundActivitySchedulerDelegate: AnyObject {
    func dataBrokerProtectionBackgroundActivitySchedulerDidTrigger(_ activityScheduler: DataBrokerProtectionBackgroundActivityScheduler) async
}

public protocol DataBrokerProtectionBackgroundActivitySchedulerDataSource: AnyObject {
    func emailConfirmationDataServiceForDataBrokerProtectionBackgroundActivityScheduler(_ activityScheduler: DataBrokerProtectionBackgroundActivityScheduler) -> EmailConfirmationDataServiceProvider?
}

public final class DefaultDataBrokerProtectionBackgroundActivityScheduler: DataBrokerProtectionBackgroundActivityScheduler, @unchecked Sendable {

    private let activity: NSBackgroundActivityScheduler
    private let schedulerIdentifier = "com.duckduckgo.macos.browser.databroker-protection-scheduler"

    public weak var delegate: DataBrokerProtectionBackgroundActivitySchedulerDelegate?
    public weak var dataSource: DataBrokerProtectionBackgroundActivitySchedulerDataSource?
    public private(set) var lastTriggerTimestamp: Date?

    public init(config: DataBrokerMacOSSchedulingConfig) {
        activity = NSBackgroundActivityScheduler(identifier: schedulerIdentifier)
        activity.repeats = true
        activity.interval = config.activitySchedulerTriggerInterval
        activity.tolerance = config.activitySchedulerIntervalTolerance
        activity.qualityOfService = config.activitySchedulerQOS
    }

    public func startScheduler() async {
        await withCheckedContinuation { continuation in
            activity.schedule { completion in
                Task {
                    self.lastTriggerTimestamp = Date()
                    Logger.dataBrokerProtection.log("Scheduler running...")

                    await self.delegate?.dataBrokerProtectionBackgroundActivitySchedulerDidTrigger(self)

                    Logger.dataBrokerProtection.log("Scheduler finished...")
                    completion(.finished)
                }
            }
            continuation.resume()
        }
    }
}
