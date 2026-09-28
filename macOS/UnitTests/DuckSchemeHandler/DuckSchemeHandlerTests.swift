//
//  DuckSchemeHandlerTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import AppKit
import Combine
import Common
import FoundationExtensions
import MaliciousSiteProtection
import NewTabPage
import PrivacyConfig
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class DuckSchemeHandlerTests: XCTestCase {

    var featureFlagger: MockFeatureFlagger!
    var handler: DuckURLSchemeHandler!

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger()

        handler = DuckURLSchemeHandler(featureFlagger: featureFlagger)
    }

    override func tearDown() {
        featureFlagger = nil
        handler = nil
        super.tearDown()
    }

    // MARK: - Favicon (async)

    @MainActor
    func testFaviconHandlerReturnsImageAfterAsyncDecode() async throws {
        let faviconManager = FaviconManagerMock()
        faviconManager.setImage(makeTestImage(), forHost: "example.com")
        let handler = DuckURLSchemeHandler(featureFlagger: featureFlagger, faviconManager: faviconManager)

        let pageURL = URL(string: "https://example.com")!
        let requestURL = try XCTUnwrap(URL.duckFavicon(for: pageURL))
        let task = MockSchemeTask(request: URLRequest(url: requestURL))
        let finished = expectation(description: "favicon task finished")
        task.onCompletion = { finished.fulfill() }

        handler.handleFavicon(urlSchemeTask: task)
        await fulfillment(of: [finished], timeout: 5)

        XCTAssertEqual(task.response?.mimeType, "image/png")
        XCTAssertNotNil(task.data)
        XCTAssertFalse(task.data?.isEmpty ?? true)
        XCTAssertNil(task.error)
    }

    @MainActor
    func testFaviconHandlerDoesNotCompleteStoppedTask() async throws {
        let faviconManager = FaviconManagerMock()
        faviconManager.setImage(makeTestImage(), forHost: "example.com")
        let handler = DuckURLSchemeHandler(featureFlagger: featureFlagger, faviconManager: faviconManager)

        let pageURL = URL(string: "https://example.com")!
        let requestURL = try XCTUnwrap(URL.duckFavicon(for: pageURL))
        let task = MockSchemeTask(request: URLRequest(url: requestURL))

        // Stop the task before the awaited decode completes; the pending completion must be skipped.
        handler.handleFavicon(urlSchemeTask: task)
        handler.webView(WKWebView(), stop: task)

        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(task.didFinishCalled)
        XCTAssertNil(task.response)
        XCTAssertNil(task.error)
    }

    // MARK: - Favicons inspector (duck://favicons)

    @MainActor
    func testFaviconsInspectorServesPageHTML() throws {
        let inspector = FaviconsDebugInspector(faviconManager: FaviconManagerMock())
        let task = MockSchemeTask(request: URLRequest(url: URL.favicons))

        inspector.handle(requestURL: URL.favicons, urlSchemeTask: task)

        XCTAssertEqual(task.response?.mimeType, "text/html")
        let html = String(data: try XCTUnwrap(task.data), encoding: .utf8) ?? ""
        XCTAssertTrue(html.contains("Favicons"))
        XCTAssertTrue(html.contains("/app.js"))
        XCTAssertTrue(task.didFinishCalled)
    }

    @MainActor
    func testFaviconsInspectorServesAppScript() throws {
        let inspector = FaviconsDebugInspector(faviconManager: FaviconManagerMock())
        let url = try XCTUnwrap(URL(string: "duck://favicons/app.js"))
        let task = MockSchemeTask(request: URLRequest(url: url))

        inspector.handle(requestURL: url, urlSchemeTask: task)

        XCTAssertEqual(task.response?.mimeType, "text/javascript")
        let js = String(data: try XCTUnwrap(task.data), encoding: .utf8) ?? ""
        XCTAssertTrue(js.contains("/api/list"))
        XCTAssertTrue(task.didFinishCalled)
    }

    @MainActor
    func testFaviconsInspectorListReturnsJSON() async throws {
        let faviconManager = FaviconManagerMock()
        let identifier = UUID()
        faviconManager.debugMetadata = [
            FaviconMetadata(identifier: identifier,
                            url: try XCTUnwrap("https://example.com/favicon.ico".url),
                            documentUrl: try XCTUnwrap("https://example.com".url),
                            dateCreated: Date(),
                            relation: .favicon)
        ]
        let inspector = FaviconsDebugInspector(faviconManager: faviconManager)
        let url = try XCTUnwrap(URL(string: "duck://favicons/api/list"))
        let task = MockSchemeTask(request: URLRequest(url: url))
        let finished = expectation(description: "list finished")
        task.onCompletion = { finished.fulfill() }

        inspector.handle(requestURL: url, urlSchemeTask: task)
        await fulfillment(of: [finished], timeout: 5)

        XCTAssertEqual(task.response?.mimeType, "application/json")
        let json = String(data: try XCTUnwrap(task.data), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("example.com"))
        XCTAssertTrue(json.contains(identifier.uuidString))
    }

    @MainActor
    func testFaviconsInspectorDeleteRemovesFaviconsAndReportsCount() async throws {
        let faviconManager = FaviconManagerMock()
        let identifier = UUID()
        faviconManager.debugMetadata = [
            FaviconMetadata(identifier: identifier,
                            url: try XCTUnwrap("https://example.com/favicon.ico".url),
                            documentUrl: try XCTUnwrap("https://example.com".url),
                            dateCreated: Date(),
                            relation: .favicon)
        ]
        let inspector = FaviconsDebugInspector(faviconManager: faviconManager)
        let url = try XCTUnwrap(URL(string: "duck://favicons/api/delete?ids=\(identifier.uuidString)"))
        let task = MockSchemeTask(request: URLRequest(url: url))
        let finished = expectation(description: "delete finished")
        task.onCompletion = { finished.fulfill() }

        inspector.handle(requestURL: url, urlSchemeTask: task)
        await fulfillment(of: [finished], timeout: 5)

        XCTAssertEqual(faviconManager.deletedIdentifiers, [[identifier]])
        let json = String(data: try XCTUnwrap(task.data), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"deleted\":1"))
    }

    @MainActor
    func testFaviconsInspectorIsNotServedToNonInternalUsers() throws {
        let featureFlagger = MockFeatureFlagger(internalUserDecider: MockInternalUserDecider(isInternalUser: false))
        let handler = DuckURLSchemeHandler(featureFlagger: featureFlagger, faviconManager: FaviconManagerMock())
        let task = MockSchemeTask(request: URLRequest(url: URL.favicons))

        // Route through the scheme handler (where the internal-user gate lives), not the inspector directly.
        handler.webView(WKWebView(), start: task)

        // For non-internal users duck://favicons falls through to the empty native UI page — not the inspector.
        let html = String(data: try XCTUnwrap(task.data), encoding: .utf8) ?? ""
        XCTAssertFalse(html.contains("Favicons"))
        XCTAssertFalse(html.contains("/app.js"))
    }

    @MainActor
    func testFaviconsInspectorIsServedToInternalUsers() throws {
        let featureFlagger = MockFeatureFlagger(internalUserDecider: MockInternalUserDecider(isInternalUser: true))
        let handler = DuckURLSchemeHandler(featureFlagger: featureFlagger, faviconManager: FaviconManagerMock())
        let task = MockSchemeTask(request: URLRequest(url: URL.favicons))

        handler.webView(WKWebView(), start: task)

        let html = String(data: try XCTUnwrap(task.data), encoding: .utf8) ?? ""
        XCTAssertTrue(html.contains("Favicons"))
        XCTAssertTrue(html.contains("/app.js"))
    }

    // MARK: - Permissions inspector (duck://permissions)

    /// The page ships as bundle resources rather than string literals, so a packaging mistake would
    /// otherwise surface as a blank debug page at runtime instead of a failing test.
    func testPermissionsInspectorPageResourcesAreBundled() throws {
        XCTAssertNotNil(Bundle.main.url(forResource: "permissions-inspector", withExtension: "html"))
        XCTAssertNotNil(Bundle.main.url(forResource: "permissions-inspector", withExtension: "js"))
    }

    @MainActor
    func testPermissionsInspectorServesPageHTML() throws {
        let inspector = makePermissionsInspector(permissionManager: PermissionManagerMock())
        let task = MockSchemeTask(request: URLRequest(url: URL.permissions))

        inspector.handle(requestURL: URL.permissions, urlSchemeTask: task)

        XCTAssertEqual(task.response?.mimeType, "text/html")
        let html = String(data: try XCTUnwrap(task.data), encoding: .utf8) ?? ""
        XCTAssertTrue(html.contains("Permissions"))
        XCTAssertTrue(html.contains("/app.js"))
        XCTAssertNil(task.error)
    }

    @MainActor
    func testPermissionsInspectorServesAppScript() throws {
        let inspector = makePermissionsInspector(permissionManager: PermissionManagerMock())
        let url = try XCTUnwrap(URL(string: "duck://permissions/app.js"))
        let task = MockSchemeTask(request: URLRequest(url: url))

        inspector.handle(requestURL: url, urlSchemeTask: task)

        XCTAssertEqual(task.response?.mimeType, "text/javascript")
        let js = String(data: try XCTUnwrap(task.data), encoding: .utf8) ?? ""
        XCTAssertTrue(js.contains("/api/list"))
        XCTAssertNil(task.error)
    }

    @MainActor
    func testPermissionsInspectorListReturnsPersistedRows() throws {
        let permissionManager = PermissionManagerMock()
        permissionManager.setPermission(.deny, forDomain: "example.com", permissionType: .camera)
        let inspector = makePermissionsInspector(permissionManager: permissionManager, fireproofDomains: ["example.com"])
        let url = try XCTUnwrap(URL(string: "duck://permissions/api/list"))
        let task = MockSchemeTask(request: URLRequest(url: url))

        inspector.handle(requestURL: url, urlSchemeTask: task)

        XCTAssertEqual(task.response?.mimeType, "application/json")
        let json = String(data: try XCTUnwrap(task.data), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"domainEncrypted\":\"example.com\""))
        XCTAssertTrue(json.contains("\"permissionType\":\"camera\""))
        // `deny` is stored as allow:false, isRemoved:false — the page dumps the columns, not the decision.
        XCTAssertTrue(json.contains("\"allow\":false"))
        XCTAssertTrue(json.contains("\"isRemoved\":false"))
        XCTAssertTrue(json.contains("\"isFireproof\":true"))
    }

    /// The point of the page: a row whose effective decision comes from a `PermissionDecisionOverriding`
    /// rather than from storage is reported as overridden, with both decisions visible.
    @MainActor
    func testPermissionsInspectorListFlagsOverriddenRows() throws {
        let permissionManager = PermissionManagerMock()
        permissionManager.setPermission(.deny, forDomain: "duck.ai", permissionType: .microphone)
        permissionManager.decisionOverride = { domain, type in
            (domain == "duck.ai" && type == .microphone) ? .allow : nil
        }
        let inspector = makePermissionsInspector(permissionManager: permissionManager)
        let url = try XCTUnwrap(URL(string: "duck://permissions/api/list"))
        let task = MockSchemeTask(request: URLRequest(url: url))

        inspector.handle(requestURL: url, urlSchemeTask: task)

        let json = String(data: try XCTUnwrap(task.data), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"allow\":false"))
        XCTAssertTrue(json.contains("\"effective\":\"allow\""))
        XCTAssertTrue(json.contains("\"isOverridden\":true"))
    }

    @MainActor
    func testPermissionsInspectorListMapsAutoplayEffectiveDecision() throws {
        let permissionManager = PermissionManagerMock()
        permissionManager.setPermission(.ask, forDomain: "example.com", permissionType: .autoplayPolicy)
        let inspector = makePermissionsInspector(permissionManager: permissionManager)
        let url = try XCTUnwrap(URL(string: "duck://permissions/api/list"))
        let task = MockSchemeTask(request: URLRequest(url: url))

        inspector.handle(requestURL: url, urlSchemeTask: task)

        let json = String(data: try XCTUnwrap(task.data), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"effective\":\"stop videos with sound\""))
        XCTAssertTrue(json.contains("\"effectiveDecision\":\"ask\""))
    }

    @MainActor
    func testPermissionsInspectorRemoveDeletesOnlyRequestedKeys() throws {
        let permissionManager = PermissionManagerMock()
        permissionManager.setPermission(.allow, forDomain: "example.com", permissionType: .camera)
        permissionManager.setPermission(.deny, forDomain: "example.com", permissionType: .microphone)
        let inspector = makePermissionsInspector(permissionManager: permissionManager)
        let url = try XCTUnwrap(URL(string: "duck://permissions/api/remove?keys=example.com%7Ccamera"))
        let task = MockSchemeTask(request: URLRequest(url: url))

        inspector.handle(requestURL: url, urlSchemeTask: task)

        XCTAssertNil(permissionManager.persistedDecision(forDomain: "example.com", permissionType: .camera))
        XCTAssertEqual(permissionManager.persistedDecision(forDomain: "example.com", permissionType: .microphone), .deny)
        let json = String(data: try XCTUnwrap(task.data), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"removed\":1"))
    }

    @MainActor
    func testPermissionsInspectorRemoveAllDeletesEveryPermissionAndReportsCount() throws {
        let permissionManager = PermissionManagerMock()
        permissionManager.setPermission(.allow, forDomain: "example.com", permissionType: .camera)
        permissionManager.setPermission(.deny, forDomain: "duckduckgo.com", permissionType: .notification)
        let inspector = makePermissionsInspector(permissionManager: permissionManager)
        let url = try XCTUnwrap(URL(string: "duck://permissions/api/removeAll"))
        let task = MockSchemeTask(request: URLRequest(url: url))

        inspector.handle(requestURL: url, urlSchemeTask: task)

        XCTAssertTrue(permissionManager.removeAllPermissionsCalled)
        XCTAssertTrue(permissionManager.savedPermissions.isEmpty)
        let json = String(data: try XCTUnwrap(task.data), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"removed\":2"))
    }

    @MainActor
    func testPermissionsInspectorIsNotServedToNonInternalUsers() throws {
        let featureFlagger = MockFeatureFlagger(internalUserDecider: MockInternalUserDecider(isInternalUser: false))
        let handler = DuckURLSchemeHandler(featureFlagger: featureFlagger,
                                           faviconManager: FaviconManagerMock(),
                                           permissionManager: PermissionManagerMock())
        let task = MockSchemeTask(request: URLRequest(url: URL.permissions))

        // Route through the scheme handler (where the internal-user gate lives), not the inspector directly.
        handler.webView(WKWebView(), start: task)

        // For non-internal users duck://permissions falls through to the empty native UI page — not the inspector.
        let html = String(data: try XCTUnwrap(task.data), encoding: .utf8) ?? ""
        XCTAssertFalse(html.contains("/app.js"))
        XCTAssertFalse(html.contains("PermissionManagedObject"))
    }

    @MainActor
    func testPermissionsInspectorIsServedToInternalUsers() throws {
        let featureFlagger = MockFeatureFlagger(internalUserDecider: MockInternalUserDecider(isInternalUser: true))
        let handler = DuckURLSchemeHandler(featureFlagger: featureFlagger,
                                           faviconManager: FaviconManagerMock(),
                                           permissionManager: PermissionManagerMock())
        let task = MockSchemeTask(request: URLRequest(url: URL.permissions))

        handler.webView(WKWebView(), start: task)

        let html = String(data: try XCTUnwrap(task.data), encoding: .utf8) ?? ""
        XCTAssertTrue(html.contains("Permissions"))
        XCTAssertTrue(html.contains("/app.js"))
    }

    /// End-to-end: loads `duck://permissions` in a real `WKWebView` through the real scheme handler and
    /// asserts the page's own script rendered the rows. Covers what the unit tests above can't — that the
    /// HTML, `/app.js` and `/api/list` all resolve as sub-resources of the `duck://` page context.
    @MainActor
    func testPermissionsPageLoadsAndRendersRowsInWebView() async throws {
        let permissionManager = PermissionManagerMock()
        permissionManager.setPermission(.allow, forDomain: "example.com", permissionType: .camera)
        permissionManager.setPermission(.deny, forDomain: "duckduckgo.com", permissionType: .notification)

        let featureFlagger = MockFeatureFlagger(internalUserDecider: MockInternalUserDecider(isInternalUser: true))
        let handler = DuckURLSchemeHandler(featureFlagger: featureFlagger,
                                           faviconManager: FaviconManagerMock(),
                                           permissionManager: permissionManager)
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: "duck")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)

        webView.load(URLRequest(url: .permissions))

        // The rows arrive after the page's own fetch of /api/list, so poll until the table is populated.
        var renderedRows = 0
        for _ in 0..<60 where renderedRows == 0 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            renderedRows = ((try? await webView.evaluateJavaScript("document.querySelectorAll('#rows tr').length")) as? Int) ?? 0
        }

        XCTAssertEqual(renderedRows, 2, "the page should render one row per persisted permission")

        let text = ((try? await webView.evaluateJavaScript("document.body.innerText")) as? String) ?? ""
        XCTAssertTrue(text.contains("example.com"), "rendered page should list the persisted domain")
        XCTAssertTrue(text.contains("camera"), "rendered page should list the permission type")
        XCTAssertTrue(text.contains("2 / 2 permissions"), "rendered page should report the row count")

        // The type dropdown is populated from the rows themselves and narrows the table.
        let optionsScript = "Array.prototype.map.call(document.getElementById('typeFilter').options, "
            + "function(o) { return o.value; }).join(',')"
        let options = ((try? await webView.evaluateJavaScript(optionsScript)) as? String) ?? ""
        XCTAssertEqual(options, ",camera,notification")

        let filterScript = "(function() { var s = document.getElementById('typeFilter'); s.value = 'camera'; "
            + "s.dispatchEvent(new Event('change')); return document.querySelectorAll('#rows tr').length; })()"
        let filteredRows = ((try? await webView.evaluateJavaScript(filterScript)) as? Int) ?? 0
        XCTAssertEqual(filteredRows, 1, "selecting a type should leave only that type's rows")
    }

    @MainActor
    private func makePermissionsInspector(permissionManager: PermissionManagerMock,
                                          fireproofDomains: [String] = []) -> PermissionsDebugInspector {
        let fireproofStatusProvider = MockDomainFireproofStatusProvider()
        fireproofStatusProvider.isFireproof = { fireproofDomains.contains($0) }
        return PermissionsDebugInspector(permissionManager: permissionManager, fireproofDomains: fireproofStatusProvider)
    }

    private func makeTestImage() -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 16, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.addRepresentation(rep)
        return image
    }

    func testWebViewFromOnboardingHandlerReturnsResponseAndData() throws {
        // Given
        let onboardingURL = URL(string: "duck://onboarding")!
        let webView = WKWebView()
        let schemeTask = MockSchemeTask(request: URLRequest(url: onboardingURL))

        // When
        handler.webView(webView, start: schemeTask)

        // Then
        XCTAssertEqual(schemeTask.response?.url, onboardingURL)
        XCTAssertEqual(schemeTask.response?.mimeType, "text/html")
        XCTAssertNotNil(schemeTask.data)
        XCTAssertTrue(schemeTask.data?.utf8String()?.contains("<title>Welcome</title>") ?? false)
        XCTAssertTrue(schemeTask.didFinishCalled)
        XCTAssertNil(schemeTask.error)
    }

    func testWebViewFromReleaseNoteHandlerReturnsResponseAndData() throws {
        // Given
        let releaseNotesURL = URL(string: "duck://release-notes")!
        let webView = WKWebView()
        let schemeTask = MockSchemeTask(request: URLRequest(url: releaseNotesURL))

        // When
        handler.webView(webView, start: schemeTask)

        // Then
        XCTAssertEqual(schemeTask.response?.url, releaseNotesURL)
        XCTAssertEqual(schemeTask.response?.mimeType, "text/html")
        XCTAssertNotNil(schemeTask.data)
        XCTAssertTrue(schemeTask.data?.utf8String()?.contains("<title>Browser Release Notes</title>") ?? false)
        XCTAssertTrue(schemeTask.didFinishCalled)
        XCTAssertNil(schemeTask.error)
    }

    @MainActor
    func testWebViewFromDuckPlayerHandlerReturnsResponseAndData() throws {
        // Given
        let duckPlayerURL = URL(string: "duck://player")!
        let webView = WKWebView()
        let schemeTask = MockSchemeTask(request: URLRequest(url: duckPlayerURL))

        // When
        handler.webView(webView, start: schemeTask)

        // Then
        XCTAssertNil(schemeTask.response)
        XCTAssertNil(schemeTask.data)
        XCTAssertFalse(schemeTask.didFinishCalled)
        XCTAssertNil(schemeTask.error)
    }

    func testWebViewFromNativeUIHandlerReturnsResponseAndData() throws {
        // Given
        let nativeURL = URL(string: "duck://newtab")!
        let webView = WKWebView()
        let schemeTask = MockSchemeTask(request: URLRequest(url: nativeURL))

        // When
        handler.webView(webView, start: schemeTask)

        // Then
        XCTAssertEqual(schemeTask.response?.url, nativeURL)
        XCTAssertEqual(schemeTask.response?.mimeType, "text/html")
        XCTAssertNotNil(schemeTask.data)
        XCTAssertEqual(schemeTask.data, DuckURLSchemeHandler.emptyHtml.utf8data)
        XCTAssertTrue(schemeTask.didFinishCalled)
        XCTAssertNil(schemeTask.error)
    }

    @MainActor
    func testSetOnboardingSchemeHandler_WhenNoneExists() {
        // Given
        let configuration = WKWebViewConfiguration()
        XCTAssertNil(configuration.urlSchemeHandler(forURLScheme: "duck"))

        // When
        configuration.applyStandardConfiguration(featureFlagger: MockFeatureFlagger(),
                                                 contentBlocking: MockContentBlocking(),
                                                 burnerMode: .regular)

        // Then
        XCTAssertNotNil(configuration.urlSchemeHandler(forURLScheme: "duck"))
        XCTAssertTrue(configuration.urlSchemeHandler(forURLScheme: "duck") is DuckURLSchemeHandler)
    }

    @MainActor
    func testErrorPageSchemeHandlerSetsError() {
        // Given
        let phishingUrl = URL(string: "https://privacy-test-pages.site/security/badware/phishing.html")!
        let encodedURL = URLTokenValidator.base64URLEncode(phishingUrl)
        let token = URLTokenValidator.shared.generateToken(for: phishingUrl)
        let errorURLString = "duck://error?reason=phishing&url=\(encodedURL)&token=\(token)"
        let errorURL = URL(string: errorURLString)!
        let webView = WKWebView()
        let schemeTask = MockSchemeTask(request: URLRequest(url: errorURL))

        // When
        handler.webView(webView, start: schemeTask)

        // Then
        let expectedError = MaliciousSiteError(code: .phishing, failingUrl: phishingUrl)
        XCTAssertEqual(schemeTask.error as NSError?, expectedError as NSError)
    }

    @MainActor
    func testErrorPageSchemeHandlerSetsError_WhenTokenInvalid() {
        // Given
        let url = URL(string: "https://privacy-test-pages.site/security/badware/phishing.html")!
        let encodedURL = URLTokenValidator.base64URLEncode(url)
        let token = "ababababababababababab"
        let errorURLString = "duck://error?reason=phishing&url=\(encodedURL)&token=\(token)"
        let errorURL = URL(string: errorURLString)!
        let webView = WKWebView()
        let schemeTask = MockSchemeTask(request: URLRequest(url: errorURL))

        // When
        handler.webView(webView, start: schemeTask)

        // Then
        XCTAssertNotNil(schemeTask.error)
        XCTAssertEqual((schemeTask.error! as? URLError)?.code, .badURL)
    }

    @MainActor

    class MockWebView: WKWebView {
        var lastURLRequest: URLRequest?
        var lastLoadedHTML: String?

        override func loadSimulatedRequest(_ request: URLRequest, responseHTML: String) -> WKNavigation {
            self.lastURLRequest = request
            self.lastLoadedHTML = responseHTML

            return WKNavigation()
        }
    }
}
