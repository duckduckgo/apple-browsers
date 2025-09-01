//
//  MockSystemSettingsPiPTutorialEventMapper.swift
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

public final class MockSystemSettingsPiPTutorialEventMapper: SystemSettingsPiPTutorialEventMapper {
    public private(set) var didCallFireFailedToLoadPiPTutorialEvent = false
    public private(set) var capturedError: Error?
    public private(set) var capturedURLPath: String?

    public init() {}

    public func fireFailedToLoadPiPTutorialEvent(error: (any Error)?, urlPath: String?) {
        didCallFireFailedToLoadPiPTutorialEvent = true
        capturedError = error
        capturedURLPath = urlPath
    }
}
