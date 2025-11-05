//
//  MockStatisticsStore.swift
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

import BrowserServicesKit
import Foundation

public class MockStatisticsStore: StatisticsStore {

    public init() {}

    public var installDate: Date?
    public var atb: String?
    public var searchRetentionAtb: String?
    public var appRetentionAtb: String?
    public var duckAIRetentionAtb: String?

    public var hasInstallStatistics: Bool {
        return atb != nil
    }

    public var variant: String?
}
