//
//  MockDefaultBrowserPromptTypeDecider.swift
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

import SetDefaultBrowserCore

package final class MockDefaultBrowserPromptTypeDecider: DefaultBrowserPromptTypeDeciding {
    package var promptToReturn: DefaultBrowserPromptType?
    package var isPreparedPromptStillValidResult = true
    package var isRetainedPreparedPromptStillValidResult = true
    package private(set) var didCallPromptType: Bool = false
    package private(set) var didCallIsPreparedPromptStillValid = false
    package private(set) var didCallIsRetainedPreparedPromptStillValid = false

    package init() {}

    package func promptType() -> DefaultBrowserPromptType? {
        didCallPromptType = true
        return promptToReturn
    }

    package func isPreparedPromptStillValid() -> Bool {
        didCallIsPreparedPromptStillValid = true
        return isPreparedPromptStillValidResult
    }

    package func isRetainedPreparedPromptStillValid() -> Bool {
        didCallIsRetainedPreparedPromptStillValid = true
        return isRetainedPreparedPromptStillValidResult
    }

}
