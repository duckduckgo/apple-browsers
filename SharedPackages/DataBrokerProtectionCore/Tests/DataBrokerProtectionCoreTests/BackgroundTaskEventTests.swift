//
//  BackgroundTaskEventTests.swift
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

import XCTest
@testable import DataBrokerProtectionCore

final class BackgroundTaskEventTests: XCTestCase {

    func testLastBackgroundTaskSessionReturnsNilWhenNoStartedEventExists() {
        let events: [BackgroundTaskEvent] = [
            BackgroundTaskEvent(sessionId: "1", eventType: .completed, timestamp: .init()),
            BackgroundTaskEvent(sessionId: "2", eventType: .terminated, timestamp: .init())
        ]

        XCTAssertNil(BackgroundTaskSessionMetrics.lastBackgroundTaskSession(from: events))
    }

    func testLastBackgroundTaskSessionReturnsStartWhenSessionInProgress() {
        let start = BackgroundTaskEvent(sessionId: "in-progress", eventType: .started, timestamp: .init())
        let events = [start]

        let session = BackgroundTaskSessionMetrics.lastBackgroundTaskSession(from: events)

        XCTAssertNotNil(session)
        XCTAssertEqual(session?.start.sessionId, "in-progress")
        XCTAssertTrue(session?.isInProgress ?? false)
        XCTAssertNil(session?.end)
    }

    func testLastBackgroundTaskSessionReturnsMostRecentStart() {
        let olderStart = BackgroundTaskEvent(sessionId: "older", eventType: .started, timestamp: Date().addingTimeInterval(-3600))
        let newerStart = BackgroundTaskEvent(sessionId: "newer", eventType: .started, timestamp: Date())
        let newerCompletion = BackgroundTaskEvent(sessionId: "newer", eventType: .completed, timestamp: Date().addingTimeInterval(60), metadata: .init(durationInMs: 5000))
        let events = [newerStart, olderStart, newerCompletion]

        let session = BackgroundTaskSessionMetrics.lastBackgroundTaskSession(from: events)

        XCTAssertEqual(session?.start.sessionId, "newer")
        XCTAssertTrue(session?.isCompleted ?? false)
        XCTAssertEqual(session?.durationMs, 5000)
    }
}
