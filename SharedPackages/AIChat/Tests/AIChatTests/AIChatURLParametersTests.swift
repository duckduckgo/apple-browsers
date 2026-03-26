//
//  AIChatURLParametersTests.swift
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

import XCTest
@testable import AIChat

final class AIChatURLParametersTests: XCTestCase {
    func testVoiceModeURLAppendsMode() {
        let baseURL = URL(string: "https://duck.ai")!
        let result = AIChatURLParameters.voiceModeURL(from: baseURL)
        XCTAssertEqual(result.absoluteString, "https://duck.ai?mode=voice")
    }

    func testVoiceModeURLPreservesExistingQueryItems() {
        let baseURL = URL(string: "https://duck.ai?q=hello")!
        let result = AIChatURLParameters.voiceModeURL(from: baseURL)

        let components = URLComponents(url: result, resolvingAgainstBaseURL: false)!
        let queryItems = components.queryItems ?? []
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "q", value: "hello")))
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "mode", value: "voice")))
    }

    func testVoiceModeURLReplacesExistingModeParam() {
        let baseURL = URL(string: "https://duck.ai?mode=chat")!
        let result = AIChatURLParameters.voiceModeURL(from: baseURL)

        let components = URLComponents(url: result, resolvingAgainstBaseURL: false)!
        let modeItems = (components.queryItems ?? []).filter { $0.name == "mode" }
        XCTAssertEqual(modeItems.count, 1)
        XCTAssertEqual(modeItems.first?.value, "voice")
    }

    func testVoiceModeURLWithPath() {
        let baseURL = URL(string: "https://duck.ai/chat")!
        let result = AIChatURLParameters.voiceModeURL(from: baseURL)
        XCTAssertEqual(result.absoluteString, "https://duck.ai/chat?mode=voice")
    }
}
