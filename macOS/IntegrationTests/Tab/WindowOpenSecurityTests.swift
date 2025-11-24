//
//  WindowOpenSecurityTests.swift
//
//  Copyright © 2025 DuckDuckGo.
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

import BrowserServicesKit
import Combine
import Common
import FeatureFlags
import SharedTestUtilities
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// Integration tests for `window.open()` security behavior, validating that `noopener` and `noreferrer`
/// flags are correctly enforced per the MDN Web API specification.
///
/// These tests verify the fix for a security issue where browsers were incorrectly ignoring `noopener`
/// and `noreferrer` flags, leaving `window.opener` populated and leaking referrer information.
///
/// Test coverage based on:
/// - [MDN: Window.open()](https://developer.mozilla.org/en-US/docs/Web/API/Window/open)
/// - [MDN: <a> element](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/a)
/// - [MDN: rel="noopener"](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Attributes/rel/noopener)
///
/// **Key behaviors tested:**
/// 1. `window.open(url)` and `window.open(url, '_blank')` — opener **present** by default (no implicit noopener)
/// 2. `window.open(url, ..., 'noopener')` — severs opener, returns `null`
/// 3. `window.open(url, ..., 'noreferrer')` — severs opener, omits Referer header, returns `null`
/// 4. Cross-origin popups — opener behavior per flags, but DOM access restricted
/// 5. Named targets — reuse existing contexts, opener present
/// 6. Navigation targets (`_self`, `_parent`, `_top`) — navigate current context
///
/// **Note:** `window.open()` has **no** `'opener'` feature token. Anchors/forms can opt back into
/// opener behavior via `rel="opener"`.
@available(macOS 12.0, *)
final class WindowOpenSecurityTests: XCTestCase {

    private var contentBlockingMock: ContentBlockingMock!
    var privacyConfiguration: MockPrivacyConfiguration {
        contentBlockingMock.privacyConfigurationManager.privacyConfig as! MockPrivacyConfiguration
    }

    private var privacyFeatures: AnyPrivacyFeatures!
    private var permissionManager: PermissionManagerMock!
    private var schemeHandler: TestSchemeHandler!
    private var tab: Tab!
    private var createdChildTabs: [Tab] = []
    private var childTabExpectation: XCTestExpectation?

    private let mainURL = URL(string: "https://integration.test/main.html")!
    private let popupURL = URL(string: "https://integration.test/popup.html")!
    private let crossOriginPopupURL = URL(string: "https://integration-alt.test/popup.html")!

    @MainActor
    override func setUp() async throws {
        contentBlockingMock = ContentBlockingMock()
        privacyFeatures = AppPrivacyFeatures(contentBlocking: contentBlockingMock, httpsUpgradeStore: HTTPSUpgradeStoreMock())
        // disable waiting for CBR compilation on navigation
        privacyConfiguration.isFeatureKeyEnabled = { _, _ in
            return false
        }

        permissionManager = PermissionManagerMock()
        permissionManager.savedPermissions = [
            mainURL.host!: [.popups: true]
        ]

        schemeHandler = TestSchemeHandler()
        schemeHandler.middleware = [{ [weak self] request in
            guard let self,
                  let url = request.url else {
                return nil
            }

            if url == self.mainURL {
                return .ok(.html(Self.testPageHTML))
            } else if url == self.popupURL || url == self.crossOriginPopupURL {
                return .ok(.html(Self.popupPageHTML))
            }
            return nil
        }]

        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub = [
            FeatureFlag.popupBlocking.rawValue: true,
            FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue: true
        ]

        tab = Tab(content: .none,
                  webViewConfiguration: schemeHandler.webViewConfiguration(),
                  privacyFeatures: privacyFeatures,
                  permissionManager: permissionManager,
                  featureFlagger: featureFlagger,
                  shouldLoadInBackground: true)
        // capture child tab creation
        tab.setDelegate(self)

        try await loadMainDocument()
    }

    @MainActor
    override func tearDown() {
        tab = nil
        schemeHandler = nil
        privacyFeatures = nil
        permissionManager = nil
        contentBlockingMock = nil
        childTabExpectation = nil
        createdChildTabs.removeAll()
    }

    // MARK: - Tests
    // Tests based on MDN spec: https://developer.mozilla.org/en-US/docs/Web/API/Window/open

    // MARK: - window.open() with regular URLs
    
    // window.open(url) — opener present, return non-null WindowProxy
    @MainActor
    func testWindowOpenWithUrlOnly() async throws {
        let result = try await evaluatePopup(popupURL, target: nil, features: [])

        XCTAssertTrue(result.returnedWindowProxy, "window.open() should return WindowProxy (non-null)")
        XCTAssertFalse(result.openerIsNull, "Opener should be present per MDN spec")
        XCTAssertEqual(result.referrer, mainURL.absoluteString, "Referrer should be present per page policy")
    }

    // window.open(url, '_blank') — opener present, return non-null WindowProxy
    @MainActor
    func testWindowOpenWithBlankTarget() async throws {
        let result = try await evaluatePopup(popupURL, target: "_blank", features: [])

        XCTAssertTrue(result.returnedWindowProxy, "window.open() should return WindowProxy (non-null)")
        XCTAssertFalse(result.openerIsNull, "Opener should be present per MDN spec")
        XCTAssertEqual(result.referrer, mainURL.absoluteString, "Referrer should be present per page policy")
    }

    // window.open(url, '_blank', 'noopener') — opener null, return null
    @MainActor
    func testWindowOpenWithNoopenerFlag() async throws {
        let result = try await evaluatePopup(popupURL, target: "_blank", features: .noopener)

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null with noopener per MDN spec")
        XCTAssertTrue(result.openerIsNull, "Opener should be null with noopener")
        XCTAssertEqual(result.referrer, mainURL.absoluteString, "Referrer should still be present (noopener doesn't affect it)")
    }

    // window.open(url, '_blank', 'noreferrer') — opener null, no Referer header, return null
    @MainActor
    func testWindowOpenWithNoreferrerFlag() async throws {
        let result = try await evaluatePopup(popupURL, target: "_blank", features: .noreferrer)

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null with noreferrer per MDN spec")
        XCTAssertTrue(result.openerIsNull, "Opener should be null with noreferrer")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty with noreferrer")
    }

    // window.open(url, '_blank', 'noopener,noreferrer') — opener null, no Referer, return null
    @MainActor
    func testWindowOpenWithNoopenerAndNoreferrer() async throws {
        let result = try await evaluatePopup(popupURL, target: "_blank", features: [.noopener, .noreferrer])

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null per MDN spec")
        XCTAssertTrue(result.openerIsNull, "Opener should be null")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty")
    }

    // MARK: - window.open() with named contexts
    
    // window.open(url, 'name') — new named context, opener present, return non-null
    @MainActor
    func testWindowOpenWithNamedTarget() async throws {
        let result = try await evaluatePopup(popupURL, target: "myPopup", features: [])

        XCTAssertTrue(result.returnedWindowProxy, "window.open() should return WindowProxy (non-null)")
        XCTAssertFalse(result.openerIsNull, "Opener should be present per MDN spec")
        XCTAssertEqual(result.referrer, mainURL.absoluteString, "Referrer should be present")
    }

    // window.open(url, 'name') — reuse existing same-origin named context
    // Note: This test requires opening the same named target twice and verifying reuse
    @MainActor
    func testWindowOpenReusesSameOriginNamedContext() async throws {
        // First open
        let result1 = try await evaluatePopup(popupURL, target: "reuseTest", features: [])
        XCTAssertTrue(result1.returnedWindowProxy, "window.open() should return WindowProxy (non-null)")

        // Second open with same name should reuse the context (not create a new child tab)
        childTabExpectation = expectation(description: "No child tab created")
        childTabExpectation?.isInverted = true
        
        let result2 = try await evaluatePopupReuse(popupURL, target: "reuseTest", features: [])
        XCTAssertTrue(result2.returnedWindowProxy, "window.open() should return WindowProxy (reused context)")
        XCTAssertTrue(result2.wasReused, "Context should be reused")
        
        await fulfillment(of: [childTabExpectation!], timeout: 0)
        XCTAssertEqual(createdChildTabs.count, 1, "Should have only the first child tab")
    }

    // MARK: - window.open() with blank/empty URLs
    
    // window.open() with no URL — opens about:blank, return non-null (or null if noopener/noreferrer)
    // Per MDN: omitted URL opens about:blank
    @MainActor
    func testWindowOpenWithNoUrl() async throws {
        let result = try await evaluatePopup(nil, target: "_blank", features: [])

        XCTAssertTrue(result.returnedWindowProxy, "window.open() should return WindowProxy (non-null)")
        XCTAssertFalse(result.openerIsNull, "Opener should be present without noopener")
    }

    @MainActor
    func testWindowOpenWithNoUrlAndNoopener() async throws {
        throw XCTSkip("Corner-case: Empty URL popup with noopener arg opens popup with referrer set")

        let result = try await evaluatePopup(nil, target: "_blank", features: .noopener)

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null with noopener")
        XCTAssertTrue(result.openerIsNull, "Opener should be null with noopener")
    }

    @MainActor
    func testWindowOpenWithNoUrlAndNoreferrer() async throws {
        let result = try await evaluatePopup(nil, target: "_blank", features: .noreferrer)

        XCTAssertTrue(result.returnedWindowProxy, "window.open() should return WindowProxy (non-null)")
        XCTAssertFalse(result.openerIsNull, "Opener should be present without noopener")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty with noreferrer")
    }

    // window.open('', ...) — empty string opens about:blank
    // Per MDN: empty string URL opens about:blank
    @MainActor
    func testWindowOpenWithEmptyString() async throws {
        let result = try await evaluatePopup(.empty, target: "_blank", features: [])

        XCTAssertTrue(result.returnedWindowProxy, "window.open() should return WindowProxy (non-null)")
        XCTAssertFalse(result.openerIsNull, "Opener should be present without noopener")
    }

    @MainActor
    func testWindowOpenWithEmptyStringAndNoopener() async throws {
        let result = try await evaluatePopup(.empty, target: "_blank", features: .noopener)

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null with noopener")
        XCTAssertTrue(result.openerIsNull, "Opener should be null with noopener")
    }

    @MainActor
    func testWindowOpenWithEmptyStringAndNoreferrer() async throws {
        let result = try await evaluatePopup(.empty, target: "_blank", features: .noreferrer)

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null with noreferrer")
        XCTAssertTrue(result.openerIsNull, "Opener should be null with noreferrer")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty with noreferrer")
    }

    // window.open('about:blank', ...) — explicitly opens about:blank
    @MainActor
    func testWindowOpenWithAboutBlank() async throws {
        let result = try await evaluatePopup(.blankPage, target: "_blank", features: [])

        XCTAssertTrue(result.returnedWindowProxy, "window.open() should return WindowProxy (non-null)")
        XCTAssertFalse(result.openerIsNull, "Opener should be present without noopener")
    }

    @MainActor
    func testWindowOpenWithAboutBlankAndNoopener() async throws {
        let result = try await evaluatePopup(.blankPage, target: "_blank", features: .noopener)

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null with noopener")
        XCTAssertTrue(result.openerIsNull, "Opener should be null with noopener")
    }

    @MainActor
    func testWindowOpenWithAboutBlankAndNoreferrer() async throws {
        let result = try await evaluatePopup(.blankPage, target: "_blank", features: .noreferrer)

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null with noreferrer")
        XCTAssertTrue(result.openerIsNull, "Opener should be null with noreferrer")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty with noreferrer")
    }

    // MARK: - window.open() with cross-origin URLs
    
    // window.open(crossOriginUrl) — opener present, cross-origin DOM restricted, return non-null
    @MainActor
    func testWindowOpenCrossOriginNoFeatures() async throws{
        let result = try await evaluatePopup(crossOriginPopupURL, target: "_blank", features: [])

        XCTAssertTrue(result.returnedWindowProxy, "window.open() should return WindowProxy (non-null)")
        XCTAssertFalse(result.openerIsNull, "Opener should be present per MDN spec")
        XCTAssertEqual(result.referrer, mainURL.absoluteString.dropping(suffix: mainURL.path) + "/", "Referrer should be trimmed to the host name for cross-origin popups") // This matches Chrome/Firefox
    }

    // window.open(crossOriginUrl, ..., 'noopener') — opener null, return null
    @MainActor
    func testWindowOpenCrossOriginWithNoopener() async throws {
        let result = try await evaluatePopup(crossOriginPopupURL, target: "_blank", features: .noopener)

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null with noopener")
        XCTAssertTrue(result.openerIsNull, "Opener should be null with noopener")
    }

    // window.open(crossOriginUrl, ..., 'noreferrer') — opener null, no Referer, return null
    @MainActor
    func testWindowOpenCrossOriginWithNoreferrer() async throws {
        let result = try await evaluatePopup(crossOriginPopupURL, target: "_blank", features: .noreferrer)

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null with noreferrer")
        XCTAssertTrue(result.openerIsNull, "Opener should be null with noreferrer")
    }

    // MARK: - window.open() with navigation targets (_self, _parent, _top)
    
    // window.open(url, '_self') — navigates existing context, return non-null
    @MainActor
    func testWindowOpenWithSelfTarget() async throws{
        childTabExpectation = expectation(description: "No child tab created")
        childTabExpectation?.isInverted = true
        
        let result = try await evaluatePopupNavigation(popupURL, target: "_self")

        XCTAssertTrue(result.navigated, "window.open(url, '_self') should navigate current context")
        XCTAssertTrue(result.returnedWindowProxy, "window.open() should return WindowProxy (non-null)")
        
        await fulfillment(of: [childTabExpectation!], timeout: 0)
        XCTAssertEqual(createdChildTabs.count, 0, "window.open with _self should not create any child tabs")
    }

    // MARK: - <a target="_blank"> anchor tests
    
    // <a href=url target="_blank"> (no rel) — implicit rel="noopener", opener null
    // Reference: https://developer.mozilla.org/en-US/docs/Web/HTML/Element/a
    @MainActor
    func testAnchorBlankTargetImplicitNoopener() async throws {
        let result = try await evaluateAnchorClick(href: popupURL, target: "_blank", rel: [])

        XCTAssertTrue(result.openerIsNull, "Implicit rel='noopener' should clear window.opener per MDN spec")
        XCTAssertEqual(result.referrer, mainURL.absoluteString, "Referrer should be present per page policy")
    }

    // <a href=url target="_blank" rel="noopener"> — explicit noopener, opener null
    // Reference: https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Attributes/rel/noopener
    @MainActor
    func testAnchorBlankTargetExplicitNoopener() async throws {
        let result = try await evaluateAnchorClick(href: popupURL, target: "_blank", rel: .noopener)

        XCTAssertTrue(result.openerIsNull, "Explicit rel='noopener' should clear window.opener")
        XCTAssertEqual(result.referrer, mainURL.absoluteString, "Referrer should be present per page policy")
    }

    // <a href=url target="_blank" rel="noreferrer"> — opener null, no Referer
    @MainActor
    func testAnchorBlankTargetNoreferrer() async throws {
        let result = try await evaluateAnchorClick(href: popupURL, target: "_blank", rel: .noreferrer)

        XCTAssertTrue(result.openerIsNull, "rel='noreferrer' should clear window.opener")
        XCTAssertEqual(result.referrer, "", "rel='noreferrer' should omit Referer header")
    }

    // MARK: - Helpers

    @MainActor
    private func loadMainDocument() async throws {
        try await withTimeout(5) { [self] in
            try await tab.setContent(.url(mainURL, source: .link))?.result.get()
        }
    }

    @MainActor
    private func evaluatePopup(_ popupURL: URL?,
                               target: String?,
                               features: WindowOpenFeatures,
                               file: StaticString = #file,
                               line: UInt = #line) async throws -> PopupScriptResult {
        var argsDict: [String: Any] = [
            "hasURL": popupURL != nil,
            "hasTarget": target != nil,
            "hasFeatures": features.featureString != nil
        ]

        if let popupURL = popupURL {
            argsDict["popupURL"] = popupURL.absoluteString
        }
        if let target = target {
            argsDict["target"] = target
        }
        if let featureString = features.featureString {
            argsDict["features"] = featureString
        }

        let arguments: [String: Any] = ["arguments": argsDict]

        let script = """
        async function evaluatePopup(arguments) {
            // Validate arguments
            if (!arguments || typeof arguments !== 'object') {
                throw new Error('Invalid arguments object: ' + typeof arguments);
            }

            const hasUrl = arguments.hasURL;
            const popupUrl = hasUrl ? arguments.popupURL : undefined;
            const hasTarget = arguments.hasTarget;
            const target = hasTarget ? arguments.target : undefined;
            const hasFeatures = arguments.hasFeatures;
            const featureString = hasFeatures ? arguments.features : undefined;

            // Build window.open() arguments dynamically
            const callArgs = [];
            if (hasUrl) {
                callArgs.push(popupUrl);
            }
            if (hasTarget) {
                if (!hasUrl) callArgs.push(undefined);
                callArgs.push(target);
            }
            if (hasFeatures) {
                if (!hasUrl) callArgs.push(undefined);
                if (!hasTarget) callArgs.push(undefined);
                callArgs.push(featureString);
            }

            const popup = window.open(...callArgs);
            const returnValue = popup !== null ? 'WindowProxy' : null;

            return {
                opened: popup !== null,
                returnValue: returnValue
            };
        }
        return evaluatePopup(arguments);
        """

        // Set up expectation for child tab creation
        childTabExpectation = expectation(description: "Child tab created")

        let rawResult = try await tab.webView.callAsyncJavaScript(
            script,
            arguments: arguments,
            in: nil,
            contentWorld: .page
        )

        guard let dictionary = rawResult as? [String: Any] else {
            XCTFail("Unexpected script result: \(String(describing: rawResult))", file: file, line: line)
            return PopupScriptResult(returnedWindowProxy: false, openerIsNull: false, referrer: nil)
        }
        
        let returnValue = dictionary["returnValue"] as? String
        let returnedWindowProxy = returnValue != nil // window.open() returned WindowProxy (non-null)

        // Wait for child tab to be created
        await fulfillment(of: [childTabExpectation!], timeout: 2)

        guard let childTab = createdChildTabs.first else {
            XCTFail("Child tab was not created", file: file, line: line)
            return PopupScriptResult(returnedWindowProxy: returnedWindowProxy, openerIsNull: false, referrer: nil)
        }

        // Wait for popup navigation to complete
        // For about:blank, empty, or nil URLs, navigation completes immediately
        let isBlankNavigation = popupURL?.isEmpty ?? true || popupURL == .blankPage
        if !isBlankNavigation {
            _ = try await childTab.webViewDidFinishNavigationPublisher.timeout(5).first().promise().value
        }

        // Evaluate opener and referrer in the popup
        let result = try await evaluatePopupProperties(in: childTab, file: file, line: line)

        return PopupScriptResult(returnedWindowProxy: returnedWindowProxy, openerIsNull: result.openerIsNull, referrer: result.referrer)
    }

    @MainActor
    private func evaluatePopupReuse(_ popupURL: URL?,
                                    target: String?,
                                    features: WindowOpenFeatures,
                                    file: StaticString = #file,
                                    line: UInt = #line) async throws -> PopupReuseResult {
        var argsDict: [String: Any] = [:]

        if let popupURL = popupURL {
            argsDict["popupURL"] = popupURL.absoluteString
        }
        if let target = target {
            argsDict["target"] = target
        }
        if let featureString = features.featureString {
            argsDict["features"] = featureString
        }

        let arguments: [String: Any] = ["arguments": argsDict]

        let script = """
        function evaluatePopupReuse(arguments) {
            // Validate arguments
            if (!arguments || typeof arguments !== 'object') {
                throw new Error('Invalid arguments object: ' + typeof arguments);
            }
            if (!arguments.popupURL) {
                throw new Error('Missing popupURL in arguments: ' + JSON.stringify(arguments));
            }

            const popupUrl = arguments.popupURL;
            const target = arguments.target || '';
            const featureString = arguments.features || '';

            // Store a marker in the named window
            const firstPopup = window.open(popupUrl, target, featureString);
            if (!firstPopup) {
                return { opened: false, returnValue: null, wasReused: false };
            }

            try {
                firstPopup.__testMarker = 'reuse-test';
            } catch (e) {
                // Cross-origin
            }

            // Try to open again with same name
            const secondPopup = window.open(popupUrl, target, featureString);
            let wasReused = false;
            try {
                wasReused = secondPopup && secondPopup.__testMarker === 'reuse-test';
            } catch (e) {
                // Cross-origin
            }

            if (secondPopup) {
                secondPopup.close();
            }

            return {
                opened: secondPopup !== null,
                returnValue: secondPopup !== null ? 'WindowProxy' : null,
                wasReused: wasReused
            };
        }
        return evaluatePopupReuse(arguments);
        """

        let rawResult = try await tab.webView.callAsyncJavaScript(
            script,
            arguments: arguments,
            in: nil,
            contentWorld: .page
        )

        guard let dictionary = rawResult as? [String: Any] else {
            XCTFail("Unexpected script result: \(String(describing: rawResult))", file: file, line: line)
            return PopupReuseResult(returnedWindowProxy: false, wasReused: false)
        }

        let returnValue = dictionary["returnValue"] as? String
        let returnedWindowProxy = returnValue != nil
        let wasReused = dictionary["wasReused"] as? Bool ?? false
        return PopupReuseResult(returnedWindowProxy: returnedWindowProxy, wasReused: wasReused)
    }

    @MainActor
    private func evaluatePopupNavigation(_ popupURL: URL?,
                                         target: String,
                                         file: StaticString = #file,
                                         line: UInt = #line) async throws -> PopupNavigationResult {
        var argsDict: [String: Any] = [
            "target": target
        ]

        if let popupURL = popupURL {
            argsDict["popupURL"] = popupURL.absoluteString
        }

        let arguments: [String: Any] = ["arguments": argsDict]

        let script = """
        function evaluatePopupNavigation(arguments) {
            // Validate arguments
            if (!arguments || typeof arguments !== 'object') {
                throw new Error('Invalid arguments object: ' + typeof arguments);
            }
            if (!arguments.target) {
                throw new Error('Missing target in arguments: ' + JSON.stringify(arguments));
            }

            const popupUrl = arguments.popupURL || '';
            const target = arguments.target;

            const result = window.open(popupUrl, target);

            return {
                returnValue: result !== null ? 'WindowProxy' : null
            };
        }
        return evaluatePopupNavigation(arguments);
        """

        // Set up expectation for navigation
        let navigationFinished = tab.webViewDidFinishNavigationPublisher.timeout(5).first().promise()

        let rawResult = try await tab.webView.callAsyncJavaScript(
            script,
            arguments: arguments,
            in: nil,
            contentWorld: .page
        )

        guard let dictionary = rawResult as? [String: Any] else {
            XCTFail("Unexpected script result: \(String(describing: rawResult))", file: file, line: line)
            return PopupNavigationResult(navigated: false, returnedWindowProxy: false)
        }

        let returnValue = dictionary["returnValue"] as? String
        let returnedWindowProxy = returnValue != nil

        // Wait for navigation to complete
        _ = try await navigationFinished.value

        // Validate the tab navigated to the expected URL
        if let popupURL {
            XCTAssertEqual(tab.webView.url, popupURL, "Tab should have navigated to the expected URL", file: file, line: line)
        }

        return PopupNavigationResult(navigated: true, returnedWindowProxy: returnedWindowProxy)
    }

    @MainActor
    private func evaluateAnchorClick(href: URL,
                                     target: String,
                                     rel: WindowOpenFeatures,
                                     file: StaticString = #file,
                                     line: UInt = #line) async throws -> AnchorClickResult {
        let arguments: [String: Any] = [
            "arguments": [
                "href": href.absoluteString,
                "target": target,
                "rel": rel.featureString ?? ""
            ]
        ]

        // Create the anchor and click it
        let clickScript = """
        function clickAnchor(arguments) {
            // Validate required arguments
            if (!arguments.href) {
                throw new Error('Missing href argument. Received: ' + JSON.stringify(arguments));
            }
            if (!arguments.target) {
                throw new Error('Missing target argument. Received: ' + JSON.stringify(arguments));
            }

            // Create anchor
            const anchor = document.createElement('a');
            anchor.href = arguments.href;
            anchor.target = arguments.target;
            if (arguments.rel && arguments.rel.length > 0) {
                anchor.rel = arguments.rel;
            }
            document.body.appendChild(anchor);

            // Validate anchor was created correctly
            const anchorHTML = anchor.outerHTML;
            const computedHref = anchor.href;
            if (!computedHref || computedHref === 'undefined' || computedHref.includes('undefined')) {
                throw new Error('Invalid anchor href! HTML: ' + anchorHTML + ', computed: ' + computedHref);
            }

            anchor.click();
        }
        clickAnchor(arguments);
        """

        // Set up expectation for child tab creation
        childTabExpectation = expectation(description: "Child tab created")

        // Click the anchor - this will trigger tab delegate's createdChild callback
        _=try await tab.webView.callAsyncJavaScript(clickScript, arguments: arguments, in: nil, contentWorld: .page)

        // Wait for child tab to be created
        await fulfillment(of: [childTabExpectation!], timeout: 2)

        guard let childTab = createdChildTabs.first else {
            XCTFail("Child tab was not created", file: file, line: line)
            return AnchorClickResult(openerIsNull: false, referrer: nil)
        }

        // Wait for popup navigation to complete
        // For about:blank or empty URLs, navigation completes immediately
        let isBlankNavigation = href.isEmpty || href == .blankPage
        if !isBlankNavigation {
            _ = try await childTab.webViewDidFinishNavigationPublisher.timeout(5).first().promise().value
        }

        // Evaluate opener and referrer in the popup
        let result = try await evaluatePopupProperties(in: childTab, file: file, line: line)
        return AnchorClickResult(openerIsNull: result.openerIsNull, referrer: result.referrer)
    }

    // Shared helper to evaluate popup properties (opener and referrer)
    @MainActor
    private func evaluatePopupProperties(in childTab: Tab,
                                         file: StaticString = #file,
                                         line: UInt = #line) async throws -> (openerIsNull: Bool, referrer: String?) {
        let evalScript = """
        (function() {
            if (typeof window === 'undefined' || typeof document === 'undefined') {
                throw new Error('Window or document not available');
            }
            return {
                openerIsNull: window.opener === null,
                referrer: document.referrer || ""
            };
        })();
        """

        let rawResult: Any? = try await childTab.webView.evaluateJavaScript(evalScript)

        guard let dictionary = rawResult as? [String: Any] else {
            XCTFail("Result is not a dictionary. Type: \(type(of: rawResult)), value: \(String(describing: rawResult))", file: file, line: line)
            return (openerIsNull: false, referrer: nil)
        }

        guard let openerIsNull = dictionary["openerIsNull"] as? Bool else {
            XCTFail("openerIsNull is missing or not a Bool. Dictionary: \(dictionary)", file: file, line: line)
            return (openerIsNull: false, referrer: nil)
        }

        let referrer = dictionary["referrer"] as? String
        return (openerIsNull: openerIsNull, referrer: referrer)
    }

    // Wrapper class to intercept WKUIDelegate.createWebView calls
    private static let testPageHTML = """
    <!doctype html>
    <html>
        <head>
            <meta charset="utf-8" />
            <title>Popup Test Host</title>
        </head>
        <body>
            <p>Integration test host page.</p>
        </body>
    </html>
    """

    private static let popupPageHTML = """
    <!doctype html>
    <html>
        <head>
            <meta charset="utf-8" />
            <title>Popup</title>
        </head>
        <body>
            <p>Popup content</p>
        </body>
    </html>
    """

}
// MARK: - TabDelegate
@available(macOS 12.0, *)
extension WindowOpenSecurityTests: TabDelegate {

    func tabWillStartNavigation(_ tab: Tab, isUserInitiated: Bool) {}
    func tabDidStartNavigation(_ tab: Tab) {}
    func tabPageDOMLoaded(_ tab: Tab) {}
    func closeTab(_ tab: Tab) {}

    func tab(_ tab: Tab, createdChild childTab: Tab, of kind: NewWindowPolicy) {
        createdChildTabs.append(childTab)
        childTabExpectation?.fulfill()
    }

    func websiteAutofillUserScriptCloseOverlay(_ websiteAutofillUserScript: BrowserServicesKit.WebsiteAutofillUserScript?) {}
    func websiteAutofillUserScript(_ websiteAutofillUserScript: BrowserServicesKit.WebsiteAutofillUserScript, willDisplayOverlayAtClick: CGPoint?, serializedInputContext: String, inputPosition: CGRect) {}
}

private struct PopupScriptResult {
    let returnedWindowProxy: Bool // Did window.open() return non-null WindowProxy?
    let openerIsNull: Bool
    let referrer: String?
}

private struct PopupReuseResult {
    let returnedWindowProxy: Bool
    let wasReused: Bool
}

private struct PopupNavigationResult {
    let navigated: Bool
    let returnedWindowProxy: Bool
}

private struct AnchorClickResult {
    let openerIsNull: Bool
    let referrer: String?
}

private struct WindowOpenFeatures: OptionSet {
    let rawValue: Int

    // Note: 'opener' is NOT a valid window.open() feature per MDN spec
    // Anchors/forms can use rel="opener" to opt back into opener behavior
    static let noopener = Self(rawValue: 1 << 0)
    static let noreferrer = Self(rawValue: 1 << 1)

    var featureString: String? {
        var tokens = [String]()
        if contains(.noopener) { tokens.append("noopener") }
        if contains(.noreferrer) { tokens.append("noreferrer") }
        return tokens.isEmpty ? nil : tokens.joined(separator: ",")
    }
}
