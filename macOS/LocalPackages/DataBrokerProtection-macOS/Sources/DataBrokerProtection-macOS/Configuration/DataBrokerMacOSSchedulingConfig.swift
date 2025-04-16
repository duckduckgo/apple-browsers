//
//  DataBrokerMacOSSchedulingConfig.swift
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

public enum DataBrokerMacOSSchedulingConfigMode {
    case normal
    case fastForIntegrationTests
}

public struct DataBrokerMacOSSchedulingConfig {

    let mode: DataBrokerMacOSSchedulingConfigMode

    public var activitySchedulerTriggerInterval: TimeInterval {
        switch mode {
        case .normal:
            return 20 * 60 // 20 minutes
        case .fastForIntegrationTests:
            return 1 * 60 // 1 minute
        }
    }

    public var activitySchedulerIntervalTolerance: TimeInterval {
        switch mode {
        case .normal:
            return 10 * 60 // 10 minutes
        case .fastForIntegrationTests:
            return 30 // 0.5 minutes
        }
    }

    public let activitySchedulerQOS: QualityOfService = .userInitiated

    public init(mode: DataBrokerMacOSSchedulingConfigMode) {
        self.mode = mode
    }
}
