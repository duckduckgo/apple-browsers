//
//  RemoteMessagingConfig.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

/// Model object that wraps the CoreData entity
public struct RemoteMessagingConfig {

    private enum Constants {
        static let oneDayInSeconds: TimeInterval = 24 * 60 * 60
    }

    let version: Int64
    let invalidate: Bool
    private let evaluationTimestamp: Date?

    public init(version: Int64, invalidate: Bool, evaluationTimestamp: Date?) {
        self.version = version
        self.invalidate = invalidate
        self.evaluationTimestamp = evaluationTimestamp
    }

    func expired() -> Bool {
        guard let evaluationTimestamp = evaluationTimestamp else {
            return false
        }

        let yesterday = Date(timeIntervalSinceNow: -Constants.oneDayInSeconds)
        return evaluationTimestamp < yesterday
    }
}
