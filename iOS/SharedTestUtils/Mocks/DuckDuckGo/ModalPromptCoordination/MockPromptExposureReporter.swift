//
//  MockPromptExposureReporter.swift
//  DuckDuckGo
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

@testable import DuckDuckGo

@MainActor
final class MockPromptExposureReporter: PromptExposureReporting {
    private(set) var shownPrompts: [PromptExposureID] = []
    private(set) var remoteMessageIDs: [String] = []
    private(set) var finishedPrompts: [PromptExposurePromptType] = []
    private(set) var foregroundCallCount = 0
    private(set) var resetCallCount = 0

    func reportPromptShown(_ id: PromptExposureID) { shownPrompts.append(id) }
    func reportRemoteMessageCardShown(messageID: String) { remoteMessageIDs.append(messageID) }
    func recordCoordinatedPromptFinished(_ type: PromptExposurePromptType) { finishedPrompts.append(type) }
    func appDidEnterForeground() { foregroundCallCount += 1 }
    func reset() { resetCallCount += 1 }
}
