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

    // MARK: - imageModeURL

    func testImageModeURLAppendsMode() {
        let baseURL = URL(string: "https://duck.ai")!
        let result = AIChatURLParameters.imageModeURL(from: baseURL)
        XCTAssertEqual(result.absoluteString, "https://duck.ai?mode=image")
    }

    func testImageModeURLPreservesExistingQueryItems() {
        let baseURL = URL(string: "https://duck.ai?q=hello")!
        let result = AIChatURLParameters.imageModeURL(from: baseURL)

        let components = URLComponents(url: result, resolvingAgainstBaseURL: false)!
        let queryItems = components.queryItems ?? []
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "q", value: "hello")))
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "mode", value: "image")))
    }

    func testImageModeURLReplacesExistingModeParam() {
        let baseURL = URL(string: "https://duck.ai?mode=voice")!
        let result = AIChatURLParameters.imageModeURL(from: baseURL)

        let components = URLComponents(url: result, resolvingAgainstBaseURL: false)!
        let modeItems = (components.queryItems ?? []).filter { $0.name == "mode" }
        XCTAssertEqual(modeItems.count, 1)
        XCTAssertEqual(modeItems.first?.value, "image")
    }

    func testImageModeURLWithPath() {
        let baseURL = URL(string: "https://duck.ai/chat")!
        let result = AIChatURLParameters.imageModeURL(from: baseURL)
        XCTAssertEqual(result.absoluteString, "https://duck.ai/chat?mode=image")
    }

    // MARK: - settingsOpenURL

    func testSettingsOpenURLAppendsSettingsParam() {
        let baseURL = URL(string: "https://duck.ai")!
        let result = AIChatURLParameters.settingsOpenURL(from: baseURL)
        XCTAssertEqual(result.absoluteString, "https://duck.ai?settings=open")
    }

    func testSettingsOpenURLPreservesExistingQueryItems() {
        let baseURL = URL(string: "https://duck.ai?q=hello")!
        let result = AIChatURLParameters.settingsOpenURL(from: baseURL)

        let components = URLComponents(url: result, resolvingAgainstBaseURL: false)!
        let queryItems = components.queryItems ?? []
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "q", value: "hello")))
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "settings", value: "open")))
    }

    func testSettingsOpenURLReplacesExistingSettingsParam() {
        let baseURL = URL(string: "https://duck.ai?settings=closed")!
        let result = AIChatURLParameters.settingsOpenURL(from: baseURL)

        let components = URLComponents(url: result, resolvingAgainstBaseURL: false)!
        let settingsItems = (components.queryItems ?? []).filter { $0.name == "settings" }
        XCTAssertEqual(settingsItems.count, 1)
        XCTAssertEqual(settingsItems.first?.value, "open")
    }

    // MARK: - nativeCustomizeModalURL

    func testNativeCustomizeModalURLAppendsForceCustomizeParam() {
        let baseURL = URL(string: "https://duck.ai")!
        let result = AIChatURLParameters.nativeCustomizeModalURL(from: baseURL)
        XCTAssertEqual(result.absoluteString, "https://duck.ai?forceCustomize=true")
    }

    func testNativeCustomizeModalURLPreservesExistingQueryItems() {
        let baseURL = URL(string: "https://duck.ai?q=hello")!
        let result = AIChatURLParameters.nativeCustomizeModalURL(from: baseURL)

        let components = URLComponents(url: result, resolvingAgainstBaseURL: false)!
        let queryItems = components.queryItems ?? []
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "q", value: "hello")))
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "forceCustomize", value: "true")))
    }

    func testNativeInputURLAppendsNativeInputParameter() {
        let baseURL = URL(string: "https://duck.ai/chat")!
        let result = AIChatURLParameters.nativeInputURL(from: baseURL)
        XCTAssertEqual(result.absoluteString, "https://duck.ai/chat?native-input=true")
    }

    func testNativeInputURLPreservesExistingQueryItems() {
        let baseURL = URL(string: "https://duck.ai/chat?mode=voice")!
        let result = AIChatURLParameters.nativeInputURL(from: baseURL)

        let components = URLComponents(url: result, resolvingAgainstBaseURL: false)!
        let queryItems = components.queryItems ?? []
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "mode", value: "voice")))
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "native-input", value: "true")))
    }

    func testNativeInputURLReplacesExistingNativeInputParameter() {
        let baseURL = URL(string: "https://duck.ai/chat?native-input=false")!
        let result = AIChatURLParameters.nativeInputURL(from: baseURL)

        let components = URLComponents(url: result, resolvingAgainstBaseURL: false)!
        let nativeInputItems = (components.queryItems ?? []).filter { $0.name == "native-input" }
        XCTAssertEqual(nativeInputItems.count, 1)
        XCTAssertEqual(nativeInputItems.first?.value, "true")
    }

    func testRemovingNativeInputURLRemovesNativeInputParameter() {
        let baseURL = URL(string: "https://duck.ai/chat?native-input=true&mode=voice")!
        let result = AIChatURLParameters.removingNativeInputURL(from: baseURL)

        let components = URLComponents(url: result, resolvingAgainstBaseURL: false)!
        let queryItems = components.queryItems ?? []
        XCTAssertFalse(queryItems.contains { $0.name == "native-input" })
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "mode", value: "voice")))
    }

    func testRemovingNativeInputURLRemovesTrailingQueryWhenNativeInputIsOnlyParameter() {
        let baseURL = URL(string: "https://duck.ai/chat?native-input=true")!
        let result = AIChatURLParameters.removingNativeInputURL(from: baseURL)

        XCTAssertEqual(result.absoluteString, "https://duck.ai/chat")
    }

    func testUpdatingNativeInputURLAddsWhenAvailableAndSupported() {
        let baseURL = URL(string: "https://duck.ai/chat")!
        let result = AIChatURLParameters.updatingNativeInputURL(
            from: baseURL,
            isNativeInputAvailable: true,
            isSupportedURL: true
        )

        XCTAssertEqual(result.absoluteString, "https://duck.ai/chat?native-input=true")
    }

    func testUpdatingNativeInputURLRemovesWhenUnavailableAndSupported() {
        let baseURL = URL(string: "https://duck.ai/chat?native-input=true")!
        let result = AIChatURLParameters.updatingNativeInputURL(
            from: baseURL,
            isNativeInputAvailable: false,
            isSupportedURL: true
        )

        XCTAssertEqual(result.absoluteString, "https://duck.ai/chat")
    }

    func testUpdatingNativeInputURLLeavesUnsupportedURLUnchanged() {
        let baseURL = URL(string: "https://example.com/chat?native-input=true")!
        let result = AIChatURLParameters.updatingNativeInputURL(
            from: baseURL,
            isNativeInputAvailable: false,
            isSupportedURL: false
        )

        XCTAssertEqual(result, baseURL)
    }
}
