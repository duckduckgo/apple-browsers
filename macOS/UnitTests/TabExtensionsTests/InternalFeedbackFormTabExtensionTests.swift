//
//  InternalFeedbackFormTabExtensionTests.swift
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

import Combine
import JavaScriptCore
import PrivacyConfig
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class InternalFeedbackFormTabExtensionTests: XCTestCase {

    private var webViewSubject: PassthroughSubject<WKWebView, Never>!
    private var internalUserDecider: MockInternalUserDecider!
    private var builderInvocations: [(quickMode: Bool, diagnostics: String, screenshotBase64: String)]!

    override func setUp() {
        super.setUp()
        webViewSubject = PassthroughSubject<WKWebView, Never>()
        internalUserDecider = MockInternalUserDecider(isInternalUser: true)
        builderInvocations = []
    }

    override func tearDown() {
        webViewSubject = nil
        internalUserDecider = nil
        builderInvocations = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Returns a tagged script string so tests can assert which inputs the builder was called with.
    private func recordingBuilder() -> InternalFeedbackFormTabExtension.ScriptSourceBuilder {
        return { [weak self] quickMode, diagnostics, screenshotBase64 in
            self?.builderInvocations.append((quickMode, diagnostics, screenshotBase64))
            return "SCRIPT|quick=\(quickMode)|diag=\(diagnostics)|shot=\(screenshotBase64)"
        }
    }

    private func makeExtension(
        builder: InternalFeedbackFormTabExtension.ScriptSourceBuilder? = nil
    ) -> InternalFeedbackFormTabExtension {
        InternalFeedbackFormTabExtension(
            webViewPublisher: webViewSubject,
            internalUserDecider: internalUserDecider,
            scriptSourceBuilder: builder ?? recordingBuilder()
        )
    }

    // MARK: - Default (no popup context)

    func testWhenPopupContextIsNilThenScriptSourceUsesDefaultBuilderArguments() {
        let ext = makeExtension()

        let source = ext.scriptSourceForCurrentNavigation()

        XCTAssertEqual(source, "SCRIPT|quick=false|diag=|shot=")
        XCTAssertEqual(builderInvocations.count, 1)
        XCTAssertEqual(builderInvocations[0].quickMode, false)
        XCTAssertEqual(builderInvocations[0].diagnostics, "")
        XCTAssertEqual(builderInvocations[0].screenshotBase64, "")
    }

    func testWhenPopupContextIsNilThenDefaultScriptSourceIsCachedAcrossCalls() {
        let ext = makeExtension()

        _ = ext.scriptSourceForCurrentNavigation()
        _ = ext.scriptSourceForCurrentNavigation()
        _ = ext.scriptSourceForCurrentNavigation()

        XCTAssertEqual(builderInvocations.count, 1, "Default script source should be built once and cached")
    }

    // MARK: - Popup context

    func testWhenPopupContextIsSetThenScriptSourceReflectsContextValues() {
        let ext = makeExtension()
        ext.popupContext = InternalFeedbackFormPopupContext(
            quickMode: true,
            diagnostics: "diag-payload",
            screenshotData: Data([0xDE, 0xAD, 0xBE, 0xEF])
        )

        let source = ext.scriptSourceForCurrentNavigation()

        XCTAssertEqual(source, "SCRIPT|quick=true|diag=diag-payload|shot=3q2+7w==")
    }

    func testWhenPopupContextScreenshotIsNilThenScreenshotBase64IsEmpty() {
        let ext = makeExtension()
        ext.popupContext = InternalFeedbackFormPopupContext(
            quickMode: true,
            diagnostics: "no-shot",
            screenshotData: nil
        )

        _ = ext.scriptSourceForCurrentNavigation()

        XCTAssertEqual(builderInvocations.count, 1)
        XCTAssertEqual(builderInvocations[0].screenshotBase64, "", "Nil screenshot should map to empty string, not the literal \"nil\"")
    }

    func testWhenPopupContextChangesBetweenCallsThenScriptIsRebuiltWithLatestValues() {
        let ext = makeExtension()

        ext.popupContext = InternalFeedbackFormPopupContext(quickMode: true, diagnostics: "first", screenshotData: nil)
        let firstSource = ext.scriptSourceForCurrentNavigation()

        ext.popupContext = InternalFeedbackFormPopupContext(quickMode: true, diagnostics: "second", screenshotData: Data([0x01, 0x02]))
        let secondSource = ext.scriptSourceForCurrentNavigation()

        XCTAssertNotEqual(firstSource, secondSource, "A changed popup context must produce a freshly built script")
        XCTAssertEqual(builderInvocations.count, 2)
        XCTAssertEqual(builderInvocations[0].diagnostics, "first")
        XCTAssertEqual(builderInvocations[1].diagnostics, "second")
        XCTAssertEqual(builderInvocations[1].screenshotBase64, "AQI=")
    }

    func testWhenSamePopupContextIsUsedTwiceThenScriptIsStillRebuiltEachCall() {
        let ext = makeExtension()
        ext.popupContext = InternalFeedbackFormPopupContext(quickMode: true, diagnostics: "same", screenshotData: nil)

        _ = ext.scriptSourceForCurrentNavigation()
        _ = ext.scriptSourceForCurrentNavigation()

        XCTAssertEqual(builderInvocations.count, 2, "Popup mode must rebuild the script per call so reopening picks up a fresh screenshot")
    }

    // MARK: - Reverting to default

    func testWhenPopupContextIsSetThenClearedThenSubsequentCallReturnsCachedDefault() {
        let ext = makeExtension()

        // Prime the cached default first so the call count is deterministic.
        _ = ext.scriptSourceForCurrentNavigation()
        XCTAssertEqual(builderInvocations.count, 1)

        ext.popupContext = InternalFeedbackFormPopupContext(quickMode: true, diagnostics: "popup", screenshotData: nil)
        _ = ext.scriptSourceForCurrentNavigation()
        XCTAssertEqual(builderInvocations.count, 2)

        ext.popupContext = nil
        let afterClear = ext.scriptSourceForCurrentNavigation()

        XCTAssertEqual(afterClear, "SCRIPT|quick=false|diag=|shot=")
        XCTAssertEqual(builderInvocations.count, 2, "Clearing popup context should revert to the cached default without rebuilding")
    }

    // MARK: - JS literal escaping (regression: diagnostics with newlines/quotes/separators)

    /// Diagnostics include arbitrary user/system text — newlines, apostrophes, backslashes, and
    /// even U+2028/U+2029 (which terminate JS string literals). The helper must produce a literal
    /// that parses as valid JavaScript and round-trips back to the original string.
    func testJSStringLiteralProducesValidJSLiteralForAdversarialInput() throws {
        let adversarial = """
        Line 1 with 'apostrophe' and "quote"
        Line 2 with backslash \\ and literal \\n sequence
        Line 3 with U+2028 line sep:\u{2028}and U+2029 para sep:\u{2029}end
        Line 4 with carriage return\rand tab\tand null \0 byte
        Line 5 with </script> closer and Unicode 🦆
        """

        let literal = InternalFeedbackFormUserScript.jsStringLiteral(adversarial)

        let context = try XCTUnwrap(JSContext())
        var exception: JSValue?
        context.exceptionHandler = { _, value in exception = value }

        let result = context.evaluateScript("(\(literal))")

        XCTAssertNil(exception, "jsStringLiteral output must parse as JavaScript. Error: \(exception?.toString() ?? "")")
        XCTAssertEqual(result?.toString(), adversarial, "JS literal must round-trip back to the original string")
    }

    func testJSStringLiteralProducesEmptyStringLiteralForEmptyInput() throws {
        let literal = InternalFeedbackFormUserScript.jsStringLiteral("")

        let context = try XCTUnwrap(JSContext())
        let result = context.evaluateScript("(\(literal))")

        XCTAssertEqual(result?.toString(), "")
    }

    // MARK: - Protocol exposure

    func testProtocolExposesReadWritePopupContext() {
        let ext = makeExtension()
        let asProtocol: any InternalFeedbackFormTabExtensionProtocol = ext

        XCTAssertNil(asProtocol.popupContext)

        let context = InternalFeedbackFormPopupContext(quickMode: true, diagnostics: "via-protocol", screenshotData: nil)
        asProtocol.popupContext = context

        XCTAssertEqual(asProtocol.popupContext?.quickMode, true)
        XCTAssertEqual(asProtocol.popupContext?.diagnostics, "via-protocol")
        XCTAssertNil(asProtocol.popupContext?.screenshotData)
    }
}
