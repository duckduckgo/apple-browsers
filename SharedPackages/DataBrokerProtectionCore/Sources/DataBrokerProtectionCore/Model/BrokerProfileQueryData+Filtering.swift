//
//  BrokerProfileQueryData+Filtering.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

public enum BrokerProfileQueryDataFetchReason {
    case oneTimeMigration
    case profileHistoryReporting
    case specificBrokerJobDispatch
}

public extension Array where Element == BrokerProfileQueryData {

    var excludingRemovedBrokers: [BrokerProfileQueryData] {
        filter { !$0.dataBroker.isRemoved }
    }

    var excludingBrokersRequiringSubscription: [BrokerProfileQueryData] {
        filter { !$0.dataBroker.scanRequiresSubscription }
    }

    var containsBrokersRequiringSubscription: Bool {
        contains { $0.dataBroker.scanRequiresSubscription }
    }

    func excludingIneligibleBrokers(isAuthenticatedUser: Bool) -> [BrokerProfileQueryData] {
        var result = excludingRemovedBrokers
        if !isAuthenticatedUser {
            result = result.excludingBrokersRequiringSubscription
        }
        return result
    }
}
