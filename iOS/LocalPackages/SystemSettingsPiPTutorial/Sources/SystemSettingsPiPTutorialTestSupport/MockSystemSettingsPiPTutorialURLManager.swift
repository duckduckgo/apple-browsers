//
//  MockSystemSettingsPiPTutorialURLManager.swift
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

import Foundation
@testable import SystemSettingsPiPTutorial

package final class MockSystemSettingsPiPTutorialURLManager: SystemSettingsPiPTutorialURLManaging {
    package private(set) var didCallRegisterProvider = false
    package private(set) var capturedProvider: PiPTutorialURLProvider?
    package private(set) var capturedRDestination: SystemSettingsPiPTutorialDestination?
    package private(set) var didCallUrlForDestination: Bool = false

    package var urlForDestinationResult: Result<URL, SystemSettingsPiPTutorialURLProviderError> = .success(SystemSettingsPiPTutorialDestination.mock.url)

    package init() {}

    package func register(_ provider: any PiPTutorialURLProvider, for destination: SystemSettingsPiPTutorialDestination) {
        didCallRegisterProvider = true
        capturedProvider = provider
        capturedRDestination = destination
    }

    package func url(for destination: SystemSettingsPiPTutorialDestination) throws(SystemSettingsPiPTutorialURLProviderError) -> URL {
        didCallUrlForDestination = true
        capturedRDestination = destination
        return try urlForDestinationResult.get()
    }
}
