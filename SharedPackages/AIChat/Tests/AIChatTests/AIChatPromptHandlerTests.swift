//
//  AIChatPromptHandlerTests.swift
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
@testable import AIChat

final class AIChatPromptHandlerTests: XCTestCase {

    func testSetData() {
        let handler = AIChatPromptHandler.shared
        let testData: AIChatPromptHandler.DataType = .init(platform: "platform", query: .init(prompt: "Test Prompt", autoSubmit: false))

        handler.setData(testData)

        XCTAssertEqual(handler.consumeData(), testData, "The data should be set correctly.")
    }

    func testConsumeData() {
        let handler = AIChatPromptHandler.shared
        let testData: AIChatPromptHandler.DataType = .init(platform: "platform", query: .init(prompt: "Test Prompt", autoSubmit: false))

        handler.setData(testData)
        let consumedData = handler.consumeData()

        XCTAssertEqual(consumedData, testData, "The consumed data should match the set data.")
        XCTAssertNil(handler.consumeData(), "After consuming, the data should be nil.")
    }

    func testReset() {
        let handler = AIChatPromptHandler.shared
        let testData: AIChatPromptHandler.DataType = .init(platform: "platform", query: .init(prompt: "Test Prompt", autoSubmit: false))

        handler.setData(testData)
        handler.reset()

        XCTAssertNil(handler.consumeData(), "After reset, the data should be nil.")
    }
}
