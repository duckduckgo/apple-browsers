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

    private struct LaunchFailed: Error {}

    @available(iOS 16, macOS 13, *)
    @Test("Flag on: launch runs inside a background task that ends when launch ends", .timeLimit(.minutes(1)))
    func flagOnHoldsTaskDuringLaunch() {
        let runner = LaunchTaskRunnerSpy()
        var openTasksDuringLaunch = 0

        LaunchBackgroundTask.run(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.launchBackgroundTask]), runner: runner) {
            openTasksDuringLaunch = runner.openTasks
        }

        #expect(openTasksDuringLaunch == 1)
        #expect(runner.openTasks == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Flag on: the background task ends when launch throws", .timeLimit(.minutes(1)))
    func flagOnEndsTaskWhenLaunchThrows() {
        let runner = LaunchTaskRunnerSpy()

        #expect(throws: LaunchFailed.self) {
            try LaunchBackgroundTask.run(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.launchBackgroundTask]), runner: runner) {
                throw LaunchFailed()
            }
        }
        #expect(runner.begun == 1)
        #expect(runner.openTasks == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Flag off: launch runs without a background task", .timeLimit(.minutes(1)))
    func flagOffRunsLaunchWithoutTask() {
        let runner = LaunchTaskRunnerSpy()

        let launched = LaunchBackgroundTask.run(featureFlagger: MockFeatureFlagger(), runner: runner) { true }

        #expect(launched)
        #expect(runner.begun == 0)
    }
}

@MainActor
private final class LaunchTaskRunnerSpy: BackgroundTaskRunning {

    private(set) var begun = 0
    private var ended = 0

    var openTasks: Int { begun - ended }

    func beginBackgroundTask(withName name: String, expirationHandler: @escaping @MainActor () -> Void) -> UIBackgroundTaskIdentifier {
        begun += 1
        return UIBackgroundTaskIdentifier(rawValue: begun)
    }

    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        ended += 1
    }
}
