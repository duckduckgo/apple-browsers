//
//  MockSystemSettingsPiPTutorialManager.swift
//  DuckDuckGo
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

@testable import SystemSettingsPiPTutorial

public final class MockSystemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging {
    public private(set) var didCallSetPresenter = false
    public private(set) var capturedPresenter: SystemSettingsPiPTutorialPresenting?

    public private(set) var didCallPlayPiPTutorialAndNavigateToDestination = false
    public private(set) var capturedDestination: SystemSettingsPiPTutorialDestination?

    public private(set) var didCallStopPiPTutorialIfNeeded = false

    public init() {}

    public func setPresenter(_ presenter: SystemSettingsPiPTutorialPresenting) {
        didCallSetPresenter = true
        capturedPresenter = presenter
    }

    public func playPiPTutorialAndNavigateTo(destination: SystemSettingsPiPTutorialDestination) {
        didCallPlayPiPTutorialAndNavigateToDestination = true
        capturedDestination = destination
    }

    public func stopPiPTutorialIfNeeded() {
        didCallStopPiPTutorialIfNeeded = true
    }


}
