//
//  MockRemoteMessagePercentileStore.swift
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
import RemoteMessaging

public class MockRemoteMessagePercentileStore: RemoteMessagingPercentileStoring {

    public var percentileStorage: [String: Float]
    public var defaultPercentage: Float

    public init(percentileStorage: [String: Float] = [:], defaultPercentage: Float = 0) {
        self.percentileStorage = percentileStorage
        self.defaultPercentage = defaultPercentage
    }

    public func percentile(forMessageId messageID: String) -> Float {
        if let percentile = percentileStorage[messageID] {
            return percentile
        }

        percentileStorage[messageID] = defaultPercentage
        return defaultPercentage
    }

}
