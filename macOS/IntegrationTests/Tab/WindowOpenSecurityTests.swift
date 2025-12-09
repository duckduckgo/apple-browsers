//
//  WindowOpenSecurityTests.swift
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
        let result = try await evaluatePopup(url: popupURL, target: nil, features: [])

        XCTAssertTrue(result.returnedWindowProxy, "window.open() should return WindowProxy (non-null)")
        XCTAssertFalse(result.openerIsNull, "Opener should be present per MDN spec")
        XCTAssertEqual(result.referrer, mainURL.absoluteString, "Referrer should be present per page policy")
    }

    // window.open(url, '_blank') — opener present, return non-null WindowProxy
    @MainActor
    func testWindowOpenWithBlankTarget() async throws {
        let result = try await evaluatePopup(url: popupURL, target: .blank, features: [])

        XCTAssertTrue(result.returnedWindowProxy, "window.open() should return WindowProxy (non-null)")
        XCTAssertFalse(result.openerIsNull, "Opener should be present per MDN spec")
        XCTAssertEqual(result.referrer, mainURL.absoluteString, "Referrer should be present per page policy")
    }

    // window.open(url, '_blank', 'noopener') — opener null, return null
    @MainActor
    func testWindowOpenWithNoopenerFlag() async throws {
        let result = try await evaluatePopup(url: popupURL, target: .blank, features: .noopener)

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null with noopener per MDN spec")
        XCTAssertTrue(result.openerIsNull, "Opener should be null with noopener")
        XCTAssertEqual(result.referrer, mainURL.absoluteString, "Referrer should still be present (noopener doesn't affect it)")
    }

    // window.open(url, '_blank', 'noreferrer') — opener null, no Referer header, return null
    @MainActor
    func testWindowOpenWithNoreferrerFlag() async throws {
        let result = try await evaluatePopup(url: popupURL, target: .blank, features: .noreferrer)

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null with noreferrer per MDN spec")
        XCTAssertTrue(result.openerIsNull, "Opener should be null with noreferrer")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty with noreferrer")
    }

    // window.open(url, '_blank', 'noopener,noreferrer') — opener null, no Referer, return null
    @MainActor
    func testWindowOpenWithNoopenerAndNoreferrer() async throws {
        let result = try await evaluatePopup(url: popupURL, target: .blank, features: [.noopener, .noreferrer])

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null per MDN spec")
        XCTAssertTrue(result.openerIsNull, "Opener should be null")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty")
    }

    // MARK: - window.open() with named contexts

    // window.open(url, 'name') — new named context, opener present, return non-null
    @MainActor
    func testWindowOpenWithNamedTarget() async throws {
        let result = try await evaluatePopup(url: popupURL, target: .named("myPopup"), features: [])

        XCTAssertTrue(result.returnedWindowProxy, "window.open() should return WindowProxy (non-null)")
        XCTAssertFalse(result.openerIsNull, "Opener should be present per MDN spec")
        XCTAssertEqual(result.referrer, mainURL.absoluteString, "Referrer should be present")
    }

    // window.open(url, 'name') — reuse existing same-origin named context
    // Note: This test requires opening the same named target twice and verifying reuse
    @MainActor
    func testWindowOpenReusesSameOriginNamedContext() async throws {
        // First open
        let result1 = try await evaluatePopup(url: popupURL, target: .named("reuseTest"), features: [])
        XCTAssertTrue(result1.returnedWindowProxy, "window.open() should return WindowProxy (non-null)")
        XCTAssertFalse(result1.openerIsNull, "Opener should be present per MDN spec")
        XCTAssertEqual(result1.referrer, mainURL.absoluteString, "Referrer should be present")

        // Second open with same name should reuse the context (not create a new child tab)
        childTabExpectation = expectation(description: "No child tab created")
        childTabExpectation?.isInverted = true

        let result2 = try await evaluatePopupReuse(popupURL, target: .named("reuseTest"), features: [])
        XCTAssertTrue(result2.returnedWindowProxy, "window.open() should return WindowProxy (reused context)")
        XCTAssertTrue(result2.wasReused, "Context should be reused")

        await fulfillment(of: [childTabExpectation!], timeout: 0)
        XCTAssertEqual(createdChildTabs.count, 1, "Should have only the first child tab")
    }

    // MARK: - window.open() with blank/empty URLs

    // window.open() with no arguments — opens about:blank, return non-null
    // Per MDN: omitted URL opens about:blank
    @MainActor
    func testWindowOpenWithNoArguments() async throws {
        let result = try await evaluatePopup(url: nil, target: nil, features: [])

        XCTAssertTrue(result.returnedWindowProxy, "window.open() should return WindowProxy (non-null)")
        XCTAssertFalse(result.openerIsNull, "Opener should be present without noopener")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty for empty URL") // this matches Firefox behavior
    }

    // window.open(undefined, target) — omitted URL with target
    @MainActor
    func testWindowOpenWithNoUrl() async throws {
        let result = try await evaluatePopup(url: nil, target: .blank, features: [])

        XCTAssertTrue(result.returnedWindowProxy, "window.open() should return WindowProxy (non-null)")
        XCTAssertFalse(result.openerIsNull, "Opener should be present without noopener")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty for empty URL") // this matches Firefox behavior
    }

    @MainActor
    func testWindowOpenWithNoUrlAndNoopener() async throws {
        let result = try await evaluatePopup(url: nil, target: .blank, features: .noopener)

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null with noopener")
        XCTAssertTrue(result.openerIsNull, "Opener should be null with noopener")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty for empty URL") // this matches Firefox behavior
    }

    @MainActor
    func testWindowOpenWithNoUrlAndNoreferrer() async throws {
        let result = try await evaluatePopup(url: nil, target: .blank, features: .noreferrer)

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null with noreferrer – noreferrer implies noopener")
        XCTAssertTrue(result.openerIsNull, "Opener should be null with noreferrer – noreferrer implies noopener")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty with noreferrer")
    }

    // window.open('', ...) — empty string opens about:blank
    // Per MDN: empty string URL opens about:blank
    @MainActor
    func testWindowOpenWithEmptyString() async throws {
        let result = try await evaluatePopup(url: .empty, target: .blank, features: [])

        XCTAssertTrue(result.returnedWindowProxy, "window.open() should return WindowProxy (non-null)")
        XCTAssertFalse(result.openerIsNull, "Opener should be present without noopener")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty for empty URL") // this matches Firefox behavior
    }

    @MainActor
    func testWindowOpenWithEmptyStringAndNoopener() async throws {
        let result = try await evaluatePopup(url: .empty, target: .blank, features: .noopener)

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null with noopener")
        XCTAssertTrue(result.openerIsNull, "Opener should be null with noopener")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty for empty URL") // this matches Firefox behavior
    }

    @MainActor
    func testWindowOpenWithEmptyStringAndNoreferrer() async throws {
        let result = try await evaluatePopup(url: .empty, target: .blank, features: .noreferrer)

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null with noreferrer")
        XCTAssertTrue(result.openerIsNull, "Opener should be null with noreferrer")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty with noreferrer")
    }

    // window.open('about:blank', ...) — explicitly opens about:blank
    @MainActor
    func testWindowOpenWithAboutBlank() async throws {
        let result = try await evaluatePopup(url: .blankPage, target: .blank, features: [])

        XCTAssertTrue(result.returnedWindowProxy, "window.open() should return WindowProxy (non-null)")
        XCTAssertFalse(result.openerIsNull, "Opener should be present without noopener")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty for about:blank") // this matches Firefox behavior
    }

    @MainActor
    func testWindowOpenWithAboutBlankAndNoopener() async throws {
        let result = try await evaluatePopup(url: .blankPage, target: .blank, features: .noopener)

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null with noopener")
        XCTAssertTrue(result.openerIsNull, "Opener should be null with noopener")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty for about:blank") // this matches Firefox behavior
    }

    @MainActor
    func testWindowOpenWithAboutBlankAndNoreferrer() async throws {
        let result = try await evaluatePopup(url: .blankPage, target: .blank, features: .noreferrer)

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null with noreferrer")
        XCTAssertTrue(result.openerIsNull, "Opener should be null with noreferrer")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty for about:blank") // this matches Firefox behavior
    }

    // MARK: - window.open() with cross-origin URLs

    // window.open(crossOriginUrl) — opener present, cross-origin DOM restricted, return non-null
    @MainActor
    func testWindowOpenCrossOriginNoFeatures() async throws{
        let result = try await evaluatePopup(url: crossOriginPopupURL, target: .blank, features: [])

        XCTAssertTrue(result.returnedWindowProxy, "window.open() should return WindowProxy (non-null)")
        XCTAssertFalse(result.openerIsNull, "Opener should be present per MDN spec")
        XCTAssertEqual(result.referrer, mainURL.absoluteString.dropping(suffix: mainURL.path) + "/", "Referrer should be trimmed to the host name for cross-origin popups") // This matches Chrome/Firefox
    }

    // window.open(crossOriginUrl, ..., 'noopener') — opener null, return null
    @MainActor
    func testWindowOpenCrossOriginWithNoopener() async throws {
        let result = try await evaluatePopup(url: crossOriginPopupURL, target: .blank, features: .noopener)

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null with noopener")
        XCTAssertTrue(result.openerIsNull, "Opener should be null with noopener")
        XCTAssertEqual(result.referrer, mainURL.absoluteString.dropping(suffix: mainURL.path) + "/", "Referrer should be trimmed to the host name for cross-origin popups")
    }

    // window.open(crossOriginUrl, ..., 'noreferrer') — opener null, no Referer, return null
    @MainActor
    func testWindowOpenCrossOriginWithNoreferrer() async throws {
        let result = try await evaluatePopup(url: crossOriginPopupURL, target: .blank, features: .noreferrer)

        XCTAssertFalse(result.returnedWindowProxy, "window.open() should return null with noreferrer")
        XCTAssertTrue(result.openerIsNull, "Opener should be null with noreferrer")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty with noreferrer")
    }

    // MARK: - window.open() with navigation targets (_self, _parent, _top)

    // window.open(url, '_self') — navigates existing context, return non-null
    @MainActor
    func testWindowOpenWithSelfTarget() async throws{
        childTabExpectation = expectation(description: "No child tab created")
        childTabExpectation?.isInverted = true

        let result = try await evaluatePopupNavigation(url: popupURL, target: .self)

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
        let result = try await evaluateAnchorClick(href: popupURL, target: .blank, rel: [])

        XCTAssertTrue(result.openerIsNull, "Implicit rel='noopener' should clear window.opener per MDN spec")
        XCTAssertEqual(result.referrer, mainURL.absoluteString, "Referrer should be present per page policy")
    }

    // <a href=url target="_blank" rel="noopener"> — explicit noopener, opener null
    // Reference: https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Attributes/rel/noopener
    @MainActor
    func testAnchorBlankTargetExplicitNoopener() async throws {
        let result = try await evaluateAnchorClick(href: popupURL, target: .blank, rel: .noopener)

        XCTAssertTrue(result.openerIsNull, "Explicit rel='noopener' should clear window.opener")
        XCTAssertEqual(result.referrer, mainURL.absoluteString, "Referrer should be present per page policy")
    }

    // <a href=url target="_blank" rel="noreferrer"> — opener null, no Referer
    @MainActor
    func testAnchorBlankTargetNoreferrer() async throws {
        let result = try await evaluateAnchorClick(href: popupURL, target: .blank, rel: .noreferrer)

        XCTAssertTrue(result.openerIsNull, "rel='noreferrer' should clear window.opener")
        XCTAssertEqual(result.referrer, "", "rel='noreferrer' should omit Referer header")
    }

    // <a href=url target="_blank" rel="noopener noreferrer"> — combined flags
    @MainActor
    func testAnchorBlankTargetNoopenerAndNoreferrer() async throws {
        let result = try await evaluateAnchorClick(href: popupURL, target: .blank, rel: [.noopener, .noreferrer])

        XCTAssertTrue(result.openerIsNull, "rel='noopener noreferrer' should clear window.opener")
        XCTAssertEqual(result.referrer, "", "rel='noopener noreferrer' should omit Referer header")
    }

    // <a href="about:blank" target="_blank"> — about:blank with implicit noopener
    @MainActor
    func testAnchorBlankTargetAboutBlank() async throws {
        let result = try await evaluateAnchorClick(href: .blankPage, target: .blank, rel: [])

        XCTAssertTrue(result.openerIsNull, "Implicit rel='noopener' should clear window.opener")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty for about:blank")
    }

    // <a href="about:blank" target="_blank" rel="noopener"> — about:blank with explicit noopener
    @MainActor
    func testAnchorBlankTargetAboutBlankWithNoopener() async throws {
        let result = try await evaluateAnchorClick(href: .blankPage, target: .blank, rel: .noopener)

        XCTAssertTrue(result.openerIsNull, "rel='noopener' should clear window.opener")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty for about:blank")
    }

    // <a href="about:blank" target="_blank" rel="noreferrer"> — about:blank with noreferrer
    @MainActor
    func testAnchorBlankTargetAboutBlankWithNoreferrer() async throws {
        let result = try await evaluateAnchorClick(href: .blankPage, target: .blank, rel: .noreferrer)

        XCTAssertTrue(result.openerIsNull, "rel='noreferrer' should clear window.opener")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty for about:blank")
    }

    // <a href="about:blank" target="_blank" rel="noopener noreferrer"> — about:blank with both flags
    @MainActor
    func testAnchorBlankTargetAboutBlankWithNoopenerAndNoreferrer() async throws {
        let result = try await evaluateAnchorClick(href: .blankPage, target: .blank, rel: [.noopener, .noreferrer])

        XCTAssertTrue(result.openerIsNull, "rel='noopener noreferrer' should clear window.opener")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty for about:blank")
    }

    // <a href=url target="name"> — named target should preserve opener and referrer
    // Note: Unlike target="_blank", named targets do NOT have implicit noopener
    @MainActor
    func testAnchorNamedTarget() async throws {
        let result = try await evaluateAnchorClick(href: popupURL, target: .named("testPopup"), rel: [])

        XCTAssertFalse(result.openerIsNull, "Named target should preserve window.opener")
        XCTAssertEqual(result.referrer, mainURL.absoluteString, "Referrer should be present")
    }

    // <a href=url target="name" rel="noopener"> — named target with explicit noopener
    @MainActor
    func testAnchorNamedTargetWithNoopener() async throws {
        let result = try await evaluateAnchorClick(href: popupURL, target: .named("testPopup"), rel: .noopener)

        XCTAssertTrue(result.openerIsNull, "rel='noopener' should clear window.opener")
        XCTAssertEqual(result.referrer, mainURL.absoluteString, "Referrer should be present")
    }

    // <a href=url target="name" rel="noreferrer"> — named target with noreferrer
    @MainActor
    func testAnchorNamedTargetWithNoreferrer() async throws {
        let result = try await evaluateAnchorClick(href: popupURL, target: .named("testPopup"), rel: .noreferrer)

        XCTAssertTrue(result.openerIsNull, "rel='noreferrer' should clear window.opener")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty with noreferrer")
    }

    // <a href=url target="name" rel="noopener noreferrer"> — named target with both flags
    @MainActor
    func testAnchorNamedTargetWithNoopenerAndNoreferrer() async throws {
        let result = try await evaluateAnchorClick(href: popupURL, target: .named("testPopup"), rel: [.noopener, .noreferrer])

        XCTAssertTrue(result.openerIsNull, "rel='noopener noreferrer' should clear window.opener")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty with noreferrer")
    }

    // <a href=url> (no target) — same-tab navigation, rel attributes should have no effect
    @MainActor
    func testAnchorSameTabNavigation() async throws {
        let result = try await evaluateAnchorClick(href: popupURL, target: nil, rel: [])

        XCTAssertEqual(result.openerIsNull, true, "window.opener should be null (not a popup)")
        XCTAssertEqual(result.referrer, mainURL.absoluteString, "Referrer should be present")
    }

    // <a href=url rel="noopener"> (no target) — same-tab navigation, noopener should have no effect
    @MainActor
    func testAnchorSameTabNavigationWithNoopener() async throws {
        let result = try await evaluateAnchorClick(href: popupURL, target: nil, rel: .noopener)

        XCTAssertEqual(result.openerIsNull, true, "window.opener should be null (not a popup)")
        XCTAssertEqual(result.referrer, mainURL.absoluteString, "Referrer should be present, noopener doesn't affect it")
    }

    // <a href=url rel="noreferrer"> (no target) — same-tab navigation, noreferrer should suppress referrer
    @MainActor
    func testAnchorSameTabNavigationWithNoreferrer() async throws {
        let result = try await evaluateAnchorClick(href: popupURL, target: nil, rel: .noreferrer)

        XCTAssertEqual(result.openerIsNull, true, "window.opener should be null (not a popup)")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty with rel='noreferrer' even in same-tab navigation")
    }

    // <a href=url rel="noopener noreferrer"> (no target) — same-tab navigation with both flags
    @MainActor
    func testAnchorSameTabNavigationWithNoopenerAndNoreferrer() async throws {
        let result = try await evaluateAnchorClick(href: popupURL, target: nil, rel: [.noopener, .noreferrer])

        XCTAssertEqual(result.openerIsNull, true, "window.opener should be null (not a popup)")
        XCTAssertEqual(result.referrer, "", "Referrer should be empty with rel='noopener noreferrer' even in same-tab navigation")
    }

    // MARK: - Helpers

    @MainActor
    private func loadMainDocument() async throws {
        try await withTimeout(5) { [self] in
            try await tab.setContent(.url(mainURL, source: .link))?.result.get()
        }
    }

    @MainActor
    private func evaluatePopup(url popupURL: URL?,
                               target: WindowOpenTarget?,
                               features: WindowOpenFeatures,
                               file: StaticString = #file,
                               line: UInt = #line) async throws -> PopupScriptResult {
        var argsDict = [String: Any]()
        argsDict["url"] = popupURL?.absoluteString
        argsDict["target"] = target?.stringValue
        argsDict["features"] = features.featureString

        let arguments: [String: Any] = ["arguments": argsDict]

        let script = """
        async function evaluatePopup(arguments) {
            // Validate arguments
            if (!arguments || typeof arguments !== 'object') {
                throw new Error('Invalid arguments object: ' + typeof arguments);
            }

            const url = arguments.url;
            const target = arguments.target;
            const features = arguments.features;

            // Call window.open() with appropriate number of arguments
            // Check from most specific (3 args) to least specific (0 args)
            let popup;
            if (features !== undefined) {
                popup = window.open(url, target, features);
            } else if (target !== undefined) {
                popup = window.open(url, target);
            } else if (url !== undefined) {
                popup = window.open(url);
            } else {
                popup = window.open();
            }

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
                                    target: WindowOpenTarget?,
                                    features: WindowOpenFeatures,
                                    file: StaticString = #file,
                                    line: UInt = #line) async throws -> PopupReuseResult {
        var argsDict = [String: Any]()
        argsDict["popupURL"] = popupURL?.absoluteString
        argsDict["target"] = target?.stringValue
        argsDict["features"] = features.featureString

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
    private func evaluatePopupNavigation(url popupURL: URL?,
                                         target: WindowOpenTarget,
                                         file: StaticString = #file,
                                         line: UInt = #line) async throws -> PopupNavigationResult {
        var argsDict = [String: Any]()
        argsDict["popupURL"] = popupURL?.absoluteString
        argsDict["target"] = target.stringValue

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
                                     target: WindowOpenTarget?,
                                     rel: WindowOpenFeatures,
                                     file: StaticString = #file,
                                     line: UInt = #line) async throws -> AnchorClickResult {
        var argsDict = [String: Any]()
        argsDict["href"] = href.absoluteString
        argsDict["target"] = target?.stringValue
        argsDict["rel"] = rel.featureString?.replacingOccurrences(of: ",", with: " ") ?? ""

        let arguments: [String: Any] = ["arguments": argsDict]

        // Create the anchor and click it
        let clickScript = """
        function clickAnchor(arguments) {
            // Validate required arguments
            if (!arguments.href) {
                throw new Error('Missing href argument. Received: ' + JSON.stringify(arguments));
            }

            // Create anchor
            const anchor = document.createElement('a');
            anchor.href = arguments.href;
            if (arguments.target) {
                anchor.target = arguments.target;
            }
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
        childTabExpectation?.isInverted = (target == nil)

        // For about:blank or empty URLs, navigation completes immediately
        let isBlankNavigation = href.isEmpty || href == .blankPage
        var navigationFinished: Future<Void, TimeoutError>?
        if target == nil, !isBlankNavigation {
            navigationFinished = tab.webViewDidFinishNavigationPublisher.timeout(5).first().promise()
        }

        // Click the anchor - this will trigger tab delegate's createdChild callback
        _=try await tab.webView.callAsyncJavaScript(clickScript, arguments: arguments, in: nil, contentWorld: .page)

        // Wait for child tab to be created
        await fulfillment(of: [childTabExpectation!], timeout: (target == nil ? 0.1 : 2))

        let targetTab = try XCTUnwrap(target == nil ? tab : createdChildTabs.first, "Child tab was not created", file: file, line: line)
        if target != nil, !isBlankNavigation {
            navigationFinished = targetTab.webViewDidFinishNavigationPublisher.timeout(5).first().promise()
        }

        // Wait for popup navigation to complete
        _ = try await navigationFinished?.value

        // Evaluate opener and referrer in the popup
        let result = try await evaluatePopupProperties(in: targetTab, file: file, line: line)
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
    var isInPopUpWindow: Bool { false }

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

enum WindowOpenTarget {
    case blank          // "_blank"
    case `self`         // "_self"
    case parent         // "_parent"
    case top            // "_top"
    case named(String)  // Custom name like "myPopup"

    var stringValue: String {
        switch self {
        case .blank: return "_blank"
        case .self: return "_self"
        case .parent: return "_parent"
        case .top: return "_top"
        case .named(let name): return name
        }
    }
}

private struct WindowOpenFeatures: OptionSet {
    let rawValue: Int

    static let noopener = Self(rawValue: 1 << 0)
    static let noreferrer = Self(rawValue: 1 << 1)

    var featureString: String? {
        var tokens = [String]()
        if contains(.noopener) { tokens.append("noopener") }
        if contains(.noreferrer) { tokens.append("noreferrer") }
        return tokens.isEmpty ? nil : tokens.joined(separator: ",")
    }
}
