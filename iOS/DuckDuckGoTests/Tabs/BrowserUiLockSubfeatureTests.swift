//
//  BrowserUiLockSubfeatureTests.swift
//  DuckDuckGoTests
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

import BrowserServicesKitTestsUtils
import Testing
import WebKit
@testable import DuckDuckGo

@MainActor
struct BrowserUiLockSubfeatureTests {

    private final class DelegateSpy: BrowserUiLockSubfeatureDelegate {
        var lockStates: [Bool] = []

        func browserUiLockSubfeature(_ subfeature: BrowserUiLockSubfeature, didChangeLocked isLocked: Bool) {
            lockStates.append(isLocked)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("featureName matches the content-scope-scripts feature", .timeLimit(.minutes(1)))
    func featureNameMatchesJavaScriptFeature() {
        #expect(BrowserUiLockSubfeature().featureName == "browserUiLock")
    }

    @available(iOS 16, macOS 13, *)
    @Test("only uiLockChanged has a handler", .timeLimit(.minutes(1)))
    func onlyUiLockChangedHasHandler() {
        let subfeature = BrowserUiLockSubfeature()

        #expect(subfeature.handler(forMethodNamed: "uiLockChanged") != nil)
        #expect(subfeature.handler(forMethodNamed: "somethingElse") == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("main-frame uiLockChanged forwards the locked state", .timeLimit(.minutes(1)))
    func mainFrameMessageForwardsLockState() async throws {
        let subfeature = BrowserUiLockSubfeature()
        let spy = DelegateSpy()
        subfeature.delegate = spy
        let handler = try #require(subfeature.handler(forMethodNamed: "uiLockChanged"))

        _ = try await handler(["locked": true], WKScriptMessage.mock())
        _ = try await handler(["locked": false], WKScriptMessage.mock())

        #expect(spy.lockStates == [true, false])
    }

    @available(iOS 16, macOS 13, *)
    @Test("uiLockChanged from a subframe is ignored", .timeLimit(.minutes(1)))
    func subframeMessageIsIgnored() async throws {
        let subfeature = BrowserUiLockSubfeature()
        let spy = DelegateSpy()
        subfeature.delegate = spy
        let handler = try #require(subfeature.handler(forMethodNamed: "uiLockChanged"))
        let subframe = WKFrameInfo.mock(isMainFrame: false, securityOriginHost: "example.com")

        _ = try await handler(["locked": true], WKScriptMessage.mock(webView: nil, frameInfo: subframe))

        #expect(spy.lockStates.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("uiLockChanged without a boolean locked value is ignored", .timeLimit(.minutes(1)))
    func malformedPayloadIsIgnored() async throws {
        let subfeature = BrowserUiLockSubfeature()
        let spy = DelegateSpy()
        subfeature.delegate = spy
        let handler = try #require(subfeature.handler(forMethodNamed: "uiLockChanged"))

        _ = try await handler(["locked": "yes"], WKScriptMessage.mock())
        _ = try await handler([:], WKScriptMessage.mock())

        #expect(spy.lockStates.isEmpty)
    }
}
