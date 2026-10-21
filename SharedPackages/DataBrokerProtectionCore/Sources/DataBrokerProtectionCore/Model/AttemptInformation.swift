//
//  AttemptInformation.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

public struct AttemptInformation {
    public let extractedProfileId: Int64
    public let dataBroker: String
    public let attemptId: String
    public let lastStageDate: Date
    public let startDate: Date
}

extension AttemptInformation: Comparable {
    public static func < (lhs: AttemptInformation, rhs: AttemptInformation) -> Bool {
        if lhs.extractedProfileId != rhs.extractedProfileId {
            return lhs.extractedProfileId < rhs.extractedProfileId
        } else if lhs.dataBroker != rhs.dataBroker {
            return lhs.dataBroker < rhs.dataBroker
        } else {
            return lhs.startDate < rhs.startDate
        }
    }

    public static func == (lhs: AttemptInformation, rhs: AttemptInformation) -> Bool {
        lhs.attemptId == rhs.attemptId
    }
}
