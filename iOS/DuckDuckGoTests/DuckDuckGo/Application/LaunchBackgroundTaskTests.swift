//
//  LaunchBackgroundTaskTests.swift
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

import Testing
import UIKit
@testable import DuckDuckGo

@MainActor
@Suite("Launch background task")
struct LaunchBackgroundTaskTests {

    @available(iOS 16, *)
    @Test("Flag on: launch runs inside a background task that ends when launch ends", .timeLimit(.minutes(1)))
    func flagOnHoldsTaskDuringLaunch() {
        let runner = LaunchTaskRunnerSpy()
        var openTasksDuringLaunch: [UIBackgroundTaskIdentifier] = []

        AppDelegate.runHoldingLaunchBackgroundTask(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.launchBackgroundTask]),
                                                   runner: runner) {
            openTasksDuringLaunch = runner.openTasks
        }

        #expect(openTasksDuringLaunch.count == 1)
        #expect(runner.begun.count == 1)
        #expect(runner.openTasks.isEmpty)
    }

    @available(iOS 16, *)
    @Test("Flag on: an invalid task is not ended", .timeLimit(.minutes(1)))
    func flagOnInvalidTaskIsNotEnded() {
        let runner = LaunchTaskRunnerSpy(returnsInvalid: true)
        var launched = false

        AppDelegate.runHoldingLaunchBackgroundTask(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.launchBackgroundTask]),
                                                   runner: runner) {
            launched = true
        }

        #expect(launched)
        #expect(runner.ended.isEmpty)
    }

    @available(iOS 16, *)
    @Test("Flag off: launch runs without a background task", .timeLimit(.minutes(1)))
    func flagOffRunsLaunchWithoutTask() {
        let runner = LaunchTaskRunnerSpy()
        var launched = false

        AppDelegate.runHoldingLaunchBackgroundTask(featureFlagger: MockFeatureFlagger(), runner: runner) {
            launched = true
        }

        #expect(launched)
        #expect(runner.begun.isEmpty)
    }
}

@MainActor
private final class LaunchTaskRunnerSpy: BackgroundTaskRunning {

    private let returnsInvalid: Bool
    private(set) var begun: [UIBackgroundTaskIdentifier] = []
    private(set) var ended: [UIBackgroundTaskIdentifier] = []

    var openTasks: [UIBackgroundTaskIdentifier] { begun.filter { !ended.contains($0) } }

    init(returnsInvalid: Bool = false) {
        self.returnsInvalid = returnsInvalid
    }

    func beginBackgroundTask(withName name: String, expirationHandler: @escaping @MainActor () -> Void) -> UIBackgroundTaskIdentifier {
        let identifier = returnsInvalid ? UIBackgroundTaskIdentifier.invalid : UIBackgroundTaskIdentifier(rawValue: begun.count + 1)
        begun.append(identifier)
        return identifier
    }

    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        ended.append(identifier)
    }
}
