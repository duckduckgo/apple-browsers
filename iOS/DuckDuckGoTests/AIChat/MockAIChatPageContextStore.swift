//
//  MockAIChatPageContextStore.swift
//  DuckDuckGoTests
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

import AIChat
import UIKit
@testable import DuckDuckGo

/// Mock implementation of AIChatPageContextStoring for testing
final class MockAIChatPageContextStore: AIChatPageContextStoring {

    private(set) var latestContext: AIChatPageContextData?
    private(set) var latestFavicon: UIImage?
    private(set) var updateCallCount = 0
    private(set) var clearCallCount = 0

    var hasContext: Bool {
        latestContext != nil
    }

    func update(_ context: AIChatPageContextData?) {
        updateCallCount += 1
        latestContext = context
        latestFavicon = nil
    }

    func clear() {
        clearCallCount += 1
        latestContext = nil
        latestFavicon = nil
    }

    func reset() {
        latestContext = nil
        latestFavicon = nil
        updateCallCount = 0
        clearCallCount = 0
    }
}
