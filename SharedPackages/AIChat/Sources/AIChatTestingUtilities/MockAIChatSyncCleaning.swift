//
//  MockAIChatSyncCleaning.swift
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
import AIChat

public final class MockAIChatSyncCleaning: AIChatSyncCleaning {

    public private(set) var recordAutoClearBackgroundTimestampDates: [Date?] = []
    public private(set) var recordLocalClearDates: [Date?] = []
    public private(set) var recordLocalClearFromAutoClearBackgroundTimestampIfPresentCallCount = 0
    public private(set) var recordChatDeletionCalls: [String] = []
    public private(set) var deleteIfNeededCallCount = 0

    public init() {}

    public func recordAutoClearBackgroundTimestamp(date: Date?) async {
        recordAutoClearBackgroundTimestampDates.append(date)
    }

    public func recordLocalClear(date: Date?) async {
        recordLocalClearDates.append(date)
    }

    public func recordLocalClearFromAutoClearBackgroundTimestampIfPresent() async {
        recordLocalClearFromAutoClearBackgroundTimestampIfPresentCallCount += 1
    }

    public func recordChatDeletion(chatID: String) async {
        recordChatDeletionCalls.append(chatID)
    }

    public func deleteIfNeeded() async {
        deleteIfNeededCallCount += 1
    }
}
