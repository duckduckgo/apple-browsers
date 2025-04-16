//
//  RemoteMessagingPercentileStoring.swift
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
import Persistence

public protocol RemoteMessagingPercentileStoring {
    func percentile(forMessageId: String) -> Float
}

public class RemoteMessagingPercentileUserDefaultsStore: RemoteMessagingPercentileStoring {

    enum Constants {
        static let remoteMessagingPercentileMapping = "com.duckduckgo.app.remoteMessagingPercentileMapping"
    }

    private let keyValueStore: KeyValueStoring

    public init(keyValueStore: KeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    public func percentile(forMessageId messageID: String) -> Float {
        var percentileMapping = (keyValueStore.object(forKey: Constants.remoteMessagingPercentileMapping) as? [String: Float]) ?? [:]

        if let percentile = percentileMapping[messageID] {
            return percentile
        } else {
            let newPercentile = Float.random(in: 0...1)
            percentileMapping[messageID] = newPercentile
            keyValueStore.set(percentileMapping, forKey: Constants.remoteMessagingPercentileMapping)

            return newPercentile
        }
    }

}
