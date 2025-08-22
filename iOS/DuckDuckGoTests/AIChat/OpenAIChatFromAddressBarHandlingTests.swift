//
//  OpenAIChatFromAddressBarHandlingTests.swift
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

import XCTest
@testable import Core
@testable import DuckDuckGo
import AIChat
import PersistenceTestingUtils

final class OpenAIChatFromAddressBarHandlingTests: XCTestCase {

    func testWhenTextFieldIsBlankThenJustOpen() {
        let sut = OpenAIChatFromAddressBarHandling()

        let ex = expectation(description: "expected action called")
        sut.determineOpeningStrategy(isTextFieldEditing: true, textFieldValue: "   ", currentURL: .example) {
            XCTFail("Incorrect action called with prompt \($0)")
        } open: {
            ex.fulfill()
        }

        wait(for: [ex], timeout: 1.0) // Timeout not strictly needed as it's sync
    }

    func testWhenTextFieldIsNilThenJustOpen() {
        let sut = OpenAIChatFromAddressBarHandling()

        let ex = expectation(description: "expected action called")
        sut.determineOpeningStrategy(isTextFieldEditing: true, textFieldValue: nil, currentURL: .example) {
            XCTFail("Incorrect action called with prompt \($0)")
        } open: {
            ex.fulfill()
        }

        wait(for: [ex], timeout: 1.0) // Timeout not strictly needed as it's sync
    }

    func testWhenNotEditingThenJustOpen() {
        let sut = OpenAIChatFromAddressBarHandling()

        let ex = expectation(description: "expected action called")
        sut.determineOpeningStrategy(isTextFieldEditing: false, textFieldValue: "https://www.example.com", currentURL: .example) {
            XCTFail("Incorrect action called with prompt \($0)")
        } open: {
            ex.fulfill()
        }

        wait(for: [ex], timeout: 1.0) // Timeout not strictly needed as it's sync
    }

    func testWhenEditingAndRandomTextIsSubmittedWithNoURLThenOpenAndSendTextAsPrompt() {
        let sut = OpenAIChatFromAddressBarHandling()

        let ex = expectation(description: "expected action called")
        sut.determineOpeningStrategy(isTextFieldEditing: true, textFieldValue: "moonlight", currentURL: nil) {
            XCTAssertEqual($0, "moonlight")
            ex.fulfill()
        } open: {
            XCTFail("Incorrect action called")
        }

        wait(for: [ex], timeout: 1.0) // Timeout not strictly needed as it's sync
    }

    func testWhenEditingAndRandomTextIsSubmittedThenOpenAndSendTextAsPrompt() {
        let sut = OpenAIChatFromAddressBarHandling()

        let ex = expectation(description: "expected action called")
        sut.determineOpeningStrategy(isTextFieldEditing: true, textFieldValue: "moonlight", currentURL: .example) {
            XCTAssertEqual($0, "moonlight")
            ex.fulfill()
        } open: {
            XCTFail("Incorrect action called")
        }

        wait(for: [ex], timeout: 1.0) // Timeout not strictly needed as it's sync
    }

    func testWhenEditingAndCurrentURLIsSubmittedThenOpenAndSendURLAsPromptDroppingScheme() {
        let sut = OpenAIChatFromAddressBarHandling()

        let ex = expectation(description: "expected action called")
        sut.determineOpeningStrategy(isTextFieldEditing: true, textFieldValue: "https://www.example.com", currentURL: .example) {
            XCTAssertEqual($0, "www.example.com")
            ex.fulfill()
        } open: {
            XCTFail("Incorrect action called")
        }

        wait(for: [ex], timeout: 1.0) // Timeout not strictly needed as it's sync
    }

}

private extension URL {

    static let example = URL(string: "https://www.example.com")!

}
