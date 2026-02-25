//
//  MockSnoozeManager.swift
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
@testable import VPN

@MainActor
final class MockSnoozeManager: SnoozeManaging {

    private(set) var startSnoozeCalled = false
    private(set) var lastSnoozeDuration: TimeInterval?

    private(set) var cancelSnoozeCalled = false

    func startSnooze(duration: TimeInterval) async {
        startSnoozeCalled = true
        lastSnoozeDuration = duration
    }

    func cancelSnooze() async {
        cancelSnoozeCalled = true
    }
}
