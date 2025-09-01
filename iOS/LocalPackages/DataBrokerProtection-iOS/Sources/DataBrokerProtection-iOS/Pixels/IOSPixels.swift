//
//  IOSPixels.swift
//  DuckDuckGo
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
import Common
import BrowserServicesKit
import PixelKit
import DataBrokerProtectionCore

public enum IOSPixels {
    // Background Task Scheduling events
    case backgroundTaskStarted
    case backgroundTaskExpired(duration: Double)
    case backgroundTaskEndedHavingCompletedAllJobs(duration: Double)
    case backgroundTaskSchedulingFailed(error: Error?)
}

extension IOSPixels: PixelKitEvent {
    public var name: String {
        switch self {
        case .backgroundTaskStarted: return "m_ios_dbp_background-task_started"
        case .backgroundTaskExpired: return "m_ios_dbp_background-task_expired"
        case .backgroundTaskEndedHavingCompletedAllJobs: return "m_ios_dbp_background-task_ended-having-completed-all-jobs"
        case .backgroundTaskSchedulingFailed: return "m_ios_dbp_background-task_scheduling-failed"
        }
    }

    public var params: [String: String]? {
        parameters
    }

    public var parameters: [String: String]? {
        switch self {
        case .backgroundTaskStarted,
                .backgroundTaskSchedulingFailed:
            return [:]
        case .backgroundTaskExpired(let duration),
                .backgroundTaskEndedHavingCompletedAllJobs(let duration):
            return [DataBrokerProtectionSharedPixels.Consts.durationInMs: String(duration)]
        }
    }
}

public class IOSPixelsHandler: EventMapping<IOSPixels> {

    let pixelKit: PixelKit

    public init(pixelKit: PixelKit) {
        self.pixelKit = pixelKit

        super.init { _, _, _, _ in
        }

        self.eventMapper = { event, _, _, _ in
            switch event {
            case .backgroundTaskStarted,
                    .backgroundTaskExpired,
                    .backgroundTaskEndedHavingCompletedAllJobs:
                self.pixelKit.fire(event)
            case .backgroundTaskSchedulingFailed(let error):
                self.pixelKit.fire(DebugEvent(event, error: error))
            }
        }
    }

    override init(mapping: @escaping EventMapping<IOSPixels>.Mapping) {
        fatalError("Use init()")
    }
}
