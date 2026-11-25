//
//  AskAboutLinkTests.swift
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

import AIChat
import AppKit
import Combine
import BrowserServicesKit
import Common
import DDGNavigation
import FeatureFlags_macOS
@_spi(Testing) import PixelKit
import PrivacyConfig
import PrivacyConfigTestsUtils
import SharedTestUtilities
import Testing
import WebKit
import WebKitExtensions
@testable import DuckDuckGo_Privacy_Browser

// MARK: - Link context menu

@MainActor
@Suite("Ask About Page in a link's context menu")
struct AskAboutLinkMenuTests {

    private let featureFlagger = MockFeatureFlagger()
    private let attacher = LinkContextAttacherSpy()
    private static let page = URL(string: "https://example.com/article")!
    private static let serp = URL(string: "https://duckduckgo.com/?q=privacy")!

    init() {
        featureFlagger.featuresStub[FeatureFlag.aiChatPageContext.rawValue] = true
    }

    private func setFlags(serp: Bool, other: Bool) {
        featureFlagger.featuresStub[FeatureFlag.aiChatAskAboutSerpPage.rawValue] = serp
        featureFlagger.featuresStub[FeatureFlag.aiChatAskAboutLinkedPage.rawValue] = other
    }

    private func makeManager(tabContent: Tab.TabContent, isLoadedInSidebar: Bool = false) -> ContextMenuManager {
        ContextMenuManager(contextMenuSubfeaturePublisher: Empty<ContextMenuSubfeature?, Never>(),
                           contentPublisher: Just(tabContent),
                           tabsPreferences: TabsPreferences(persistor: MockTabsPreferencesPersistor(), windowControllersManager: WindowControllersManagerMock()),
                           isLoadedInSidebar: isLoadedInSidebar,
                           internalUserDecider: MockInternalUserDecider(),
                           aiChatMenuConfiguration: AIChatMenuConfiguration(storage: MockAIChatPreferencesStorage(),
                                                                            remoteSettings: MockRemoteAISettings(),
                                                                            featureFlagger: featureFlagger),
                           aiChatLinkContextAttacher: attacher,
                           tld: TLD())
    }

    private func openMenu(_ manager: ContextMenuManager, link: String) -> NSMenu {
        let menu = NSMenu()
        for identifier: WKMenuItemIdentifier in [.openLinkInNewWindow, .copyLink, .shareMenu] {
            let item = NSMenuItem(title: identifier.rawValue, action: nil, keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
            menu.addItem(item)
        }
        manager.willShowContextMenu(withSelectedText: nil, linkURL: link)
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        manager.webView(WebView(featureFlagger: featureFlagger, privacyConfig: MockPrivacyConfiguration()), willOpenContextMenu: menu, with: event)
        return menu
    }

    private func click(_ item: NSMenuItem) {
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
    }

    private func askAboutPageItem(in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { $0.title == UserText.aiChatMenuAskAboutPage }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Each page kind follows its own flag", .timeLimit(.minutes(1)),
          arguments: [(false, false), (true, false), (false, true), (true, true)])
    func eachPageKindFollowsItsFlag(serpFlag: Bool, otherFlag: Bool) {
        setFlags(serp: serpFlag, other: otherFlag)

        let onSERP = openMenu(makeManager(tabContent: .url(Self.serp, source: .link)), link: "https://example.com/result")
        let onPage = openMenu(makeManager(tabContent: .url(Self.page, source: .link)), link: "https://example.com/other")

        #expect((askAboutPageItem(in: onSERP) != nil) == serpFlag)
        #expect((askAboutPageItem(in: onPage) != nil) == otherFlag)
    }

    @available(iOS 16, macOS 13, *)
    @Test("No item without page context", .timeLimit(.minutes(1)))
    func noItemWithoutPageContext() {
        setFlags(serp: true, other: true)
        featureFlagger.featuresStub[FeatureFlag.aiChatPageContext.rawValue] = false
        let menu = openMenu(makeManager(tabContent: .url(Self.page, source: .link)), link: "https://example.com/other")
        #expect(askAboutPageItem(in: menu) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The item sits under a Duck.ai header after the link items", .timeLimit(.minutes(1)))
    func itemSitsUnderDuckAIHeader() throws {
        setFlags(serp: false, other: true)
        let menu = openMenu(makeManager(tabContent: .url(Self.page, source: .link)), link: "https://example.com/other")

        let index = try #require(menu.items.firstIndex { $0.title == UserText.aiChatMenuAskAboutPage })
        #expect(menu.items[index - 1].title == UserText.aiChatTitle)
        #expect(menu.items[index - 2].isSeparatorItem)
        #expect(menu.items.last?.identifier?.rawValue == WKMenuItemIdentifier.shareMenu.rawValue)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Links that can't be read in the background get no item", .timeLimit(.minutes(1)),
          arguments: ["mailto:someone@example.com", "ftp://example.com/file", "https://user:secret@example.com/", "javascript:alert(1)"])
    func unsupportedLinksGetNoItem(link: String) {
        setFlags(serp: true, other: true)
        let menu = openMenu(makeManager(tabContent: .url(Self.page, source: .link)), link: link)
        #expect(askAboutPageItem(in: menu) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Pages that aren't plain web pages get no item", .timeLimit(.minutes(1)),
          arguments: ["file:///Users/someone/page.html", "https://user:secret@example.com/"])
    func unsupportedPagesGetNoItem(page: String) throws {
        setFlags(serp: true, other: true)
        let menu = openMenu(makeManager(tabContent: .url(try #require(URL(string: page)), source: .link)), link: "https://example.com/a")
        #expect(askAboutPageItem(in: menu) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("No item in the sidebar's own web view or on a Duck.ai tab", .timeLimit(.minutes(1)))
    func noItemInSidebarOrDuckAITab() {
        setFlags(serp: true, other: true)
        let sidebar = openMenu(makeManager(tabContent: .url(Self.page, source: .link), isLoadedInSidebar: true), link: "https://example.com/a")
        let duckAITab = openMenu(makeManager(tabContent: .aiChat(URL(string: "https://duck.ai")!)), link: "https://example.com/a")

        #expect(askAboutPageItem(in: sidebar) == nil)
        #expect(askAboutPageItem(in: duckAITab) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turning the flag on while running shows the item on the next menu", .timeLimit(.minutes(1)))
    func flagFlipWhileRunning() {
        let manager = makeManager(tabContent: .url(Self.page, source: .link))
        setFlags(serp: false, other: false)
        #expect(askAboutPageItem(in: openMenu(manager, link: "https://example.com/a")) == nil)

        setFlags(serp: false, other: true)
        #expect(askAboutPageItem(in: openMenu(manager, link: "https://example.com/a")) != nil)

        setFlags(serp: false, other: false)
        #expect(askAboutPageItem(in: openMenu(manager, link: "https://example.com/a")) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Clicking asks about the link, typed by the page it's on", .timeLimit(.minutes(1)))
    func clickAsksAboutTheLink() throws {
        setFlags(serp: true, other: true)

        // Menu items hold their target weakly, as WebKit's menu does.
        let serpManager = makeManager(tabContent: .url(Self.serp, source: .link))
        let serpMenu = openMenu(serpManager, link: "https://example.com/result")
        let serpItem = try #require(askAboutPageItem(in: serpMenu))
        click(serpItem)

        let pageManager = makeManager(tabContent: .url(Self.page, source: .link))
        let pageMenu = openMenu(pageManager, link: "https://example.com/other")
        let pageItem = try #require(askAboutPageItem(in: pageMenu))
        click(pageItem)
        withExtendedLifetime((serpManager, pageManager)) {}

        #expect(attacher.requests == [LinkContextAttacherSpy.Request(url: URL(string: "https://example.com/result")!, linkType: .serp),
                                      LinkContextAttacherSpy.Request(url: URL(string: "https://example.com/other")!, linkType: .other)])
    }
}

@MainActor
private final class LinkContextAttacherSpy: AIChatLinkContextAttaching {
    struct Request: Equatable {
        let url: URL
        let linkType: AIChatLinkAskAboutPageType
        var source: AIChatLinkAskAboutPageSource = .contextMenu
    }
    private(set) var requests: [Request] = []

    func askAboutLink(_ url: URL, linkType: AIChatLinkAskAboutPageType, source: AIChatLinkAskAboutPageSource) {
        requests.append(Request(url: url, linkType: linkType, source: source))
    }
}

// MARK: - Same-origin rule

@Suite("Linked page main-frame navigations stay on their origin")
struct LinkedPageSameOriginTests {

    @available(iOS 16, macOS 13, *)
    @Test("Same scheme, host and port is the same origin", .timeLimit(.minutes(1)), arguments: [
        ("https://example.com/a", "https://example.com/b?x=1#y"),
        ("https://EXAMPLE.com/a", "https://example.com/b"),
        ("https://example.com/a", "https://example.com:443/b"),
        ("http://example.com:80/a", "http://example.com/b"),
        ("http://example.com/a", "https://example.com/b"),
        ("http://example.com:80/a", "https://EXAMPLE.com:443/b"),
    ])
    func sameOrigin(initial: String, next: String) {
        #expect(LinkedPageLoad.isSameOrigin(URL(string: next)!, as: URL(string: initial)!))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Any change of scheme, host or port leaves the origin", .timeLimit(.minutes(1)), arguments: [
        ("https://example.com/a", "http://example.com/a"),
        ("https://example.com/a", "https://www.example.com/a"),
        ("https://example.com/a", "https://example.com:8443/a"),
        ("https://example.com/a", "https://evil.com/a"),
        ("https://example.com/a", "about:blank"),
        ("http://example.com/a", "https://www.example.com/a"),
        ("http://example.com:8080/a", "https://example.com/a"),
        ("http://example.com/a", "https://example.com:8443/a"),
    ])
    func crossOrigin(initial: String, next: String) {
        #expect(!LinkedPageLoad.isSameOrigin(URL(string: next)!, as: URL(string: initial)!))
    }
}

// MARK: - Retrying without the session

@MainActor
@Suite("Retrying a linked page without the user's session")
struct LinkedPageRetryTests {

    private static let page = AIChatPageContextData(title: "Page", favicon: [], url: "https://b.test/", content: "Text",
                                                    truncated: false, fullContentLength: 4)

    @available(iOS 16, macOS 13, *)
    @Test("A redirect to another origin is read again without the session", .timeLimit(.minutes(1)))
    func redirectRetriesWithoutSession() async {
        var attempts: [Bool] = []
        let result = await LinkedPageContextLoader.read(with: { withSession in
            attempts.append(withSession)
            return withSession ? .failed(.redirectBlocked) : .success(Self.page)
        })

        #expect(result == .success(Self.page))
        #expect(attempts == [true, false])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Any other outcome of the first read is final", .timeLimit(.minutes(1)),
          arguments: [LinkedPageContextLoadResult.success(page), .failed(.httpError), .failed(.timeout), .prevented("pdf")])
    func otherOutcomesAreFinal(first: LinkedPageContextLoadResult) async {
        var attempts: [Bool] = []
        let result = await LinkedPageContextLoader.read(with: { withSession in
            attempts.append(withSession)
            return first
        })

        #expect(result == first)
        #expect(attempts == [true])
    }
}

// MARK: - Hidden web view load

@MainActor
@Suite("Loading a linked page out of sight")
struct LinkedPageLoadTests {

    private let schemeHandler = TestSchemeHandler()

    private func load(_ url: String,
                      extracted: String = "Page text",
                      redirects: LinkedPageLoad.Redirects = .sameOriginOnly,
                      extractionDelay: UInt64 = 0) async -> LinkedPageContextLoadResult {
        let load = LinkedPageLoad(configuration: schemeHandler.webViewConfiguration(), redirects: redirects) { webView in
            // Like the page-context script, reading takes a moment, and reads the page shown when it started.
            let readURL = webView.url?.absoluteString ?? ""
            try? await Task.sleep(nanoseconds: extractionDelay)
            return AIChatPageContextData(title: readURL, favicon: [], url: readURL, content: extracted, truncated: false, fullContentLength: extracted.count)
        }
        return await load.run(URLRequest(url: URL(string: url)!))
    }

    /// The page the content was read from (the result's `url` is where the frame ended up).
    private func readURL(_ result: LinkedPageContextLoadResult) -> String? {
        guard case .success(let page) = result else { return nil }
        return page.title
    }

    @available(iOS 16, macOS 13, *)
    @Test("A script redirector on the same origin is read on the page it goes to", .timeLimit(.minutes(1)))
    func sameOriginScriptRedirectorReadsFinalPage() async {
        schemeHandler.middleware = [{ request in
            request.url?.path == "/final"
                ? .ok(.html("<html><body>Final</body></html>"))
                : .ok(.html("<html><body>Redirecting<script>setTimeout(() => { location.href = '/final' }, 50)</script></body></html>"))
        }]

        let result = await load("https://a.test/start", extractionDelay: 500_000_000)

        #expect(readURL(result) == "https://a.test/final")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A page that meta-refreshes right after load is read on the page it goes to, even when reading is instant", .timeLimit(.minutes(1)))
    func immediateMetaRefreshReadsFinalPage() async {
        schemeHandler.middleware = [{ request in
            request.url?.path == "/final"
                ? .ok(.html("<html><body>Final</body></html>"))
                : .ok(.html("<html><head><meta http-equiv=\"refresh\" content=\"0;url=/final\"></head><body>Stub</body></html>"))
        }]

        let result = await load("https://a.test/start")

        #expect(readURL(result) == "https://a.test/final")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A hop to another origin without the session goes through the tab's protections", .timeLimit(.minutes(1)))
    func crossOriginHopIsProtected() async {
        schemeHandler.middleware = [{ request in
            request.url?.host == "a.test"
                ? .ok(.html("<html><body>Redirecting<script>setTimeout(() => { location.href = 'https://b.test/tracked?utm_source=x' }, 50)</script></body></html>"))
                : .ok(.html("<html><body>Other site</body></html>"))
        }]
        var protectedURLs: [String] = []
        let redirects = LinkedPageLoad.Redirects.anyOrigin(protect: { request in
            protectedURLs.append(request.url?.absoluteString ?? "")
            var request = request
            request.url = URL(string: "https://b.test/clean")
            return request
        })

        let result = await load("https://a.test/", redirects: redirects, extractionDelay: 500_000_000)

        #expect(readURL(result) == "https://b.test/clean")
        #expect(protectedURLs == ["https://b.test/tracked?utm_source=x"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("An upgraded hop that the site sends back to http is loaded as asked, not upgraded again", .timeLimit(.minutes(1)))
    func upgradeLoopStops() async {
        schemeHandler.middleware = [{ request in
            switch (request.url?.scheme, request.url?.host) {
            case ("https", "a.test"): .ok(.html("<html><body>Start<script>setTimeout(() => { location.href = 'http://b.test/page' }, 50)</script></body></html>"))
            case ("https", "b.test"): .ok(.html("<html><body>Back<script>location.href = 'http://b.test/page'</script></body></html>"))
            default: .ok(.html("<html><body>Plain http page</body></html>"))
            }
        }]
        let upgrade = LinkedPageLoad.Redirects.anyOrigin(protect: { request in
            var request = request
            request.url = request.url.flatMap { URL(string: $0.absoluteString.replacingOccurrences(of: "http://", with: "https://")) }
            return request
        })

        let result = await load("https://a.test/", redirects: upgrade, extractionDelay: 500_000_000)

        #expect(readURL(result) == "http://b.test/page")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A hop the protections refuse is blocked", .timeLimit(.minutes(1)))
    func refusedHopIsBlocked() async {
        schemeHandler.middleware = [{ request in
            request.url?.host == "a.test"
                ? .ok(.html("<html><script>location.href = 'https://b.test/'</script></html>"))
                : .ok(.html("<html>Other site</html>"))
        }]
        let result = await load("https://a.test/", extracted: "", redirects: .anyOrigin(protect: { _ in nil }), extractionDelay: 500_000_000)
        #expect(result == .failed(.redirectBlocked))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A hop loads the protected request in its place only when protecting changed it", .timeLimit(.minutes(1)))
    func hopDecision() {
        let gpcHeader = GPCRequestFactory.Constants.secGPCHeader
        let plain = URLRequest(url: URL(string: "https://b.test/a")!)
        var withGPC = plain
        withGPC.setValue("1", forHTTPHeaderField: gpcHeader)
        let upgraded = URLRequest(url: URL(string: "https://b.test/clean")!)

        #expect(LinkedPageLoad.decision(for: plain, protected: plain) == .allow)
        #expect(LinkedPageLoad.decision(for: withGPC, protected: withGPC) == .allow)
        #expect(LinkedPageLoad.decision(for: plain, protected: withGPC) == .load(withGPC))
        #expect(LinkedPageLoad.decision(for: plain, protected: upgraded) == .load(upgraded))
        #expect(LinkedPageLoad.decision(for: plain, protected: nil) == .block)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A cancelled or interrupted navigation isn't a failure", .timeLimit(.minutes(1)))
    func interruptionsAreNotFailures() {
        #expect(LinkedPageLoad.isInterruption(URLError(.cancelled)))
        #expect(LinkedPageLoad.isInterruption(NSError(domain: "WebKitErrorDomain", code: 102)))
        #expect(!LinkedPageLoad.isInterruption(URLError(.cannotConnectToHost)))
        #expect(!LinkedPageLoad.isInterruption(URLError(.serverCertificateUntrusted)))
        #expect(!LinkedPageLoad.isInterruption(NSError(domain: "WebKitErrorDomain", code: 101)))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A page that loads is read, stamped with its URL and type", .timeLimit(.minutes(1)))
    func loadedPageIsRead() async {
        schemeHandler.middleware = [{ _ in .ok(.html("<html><body>Hi</body></html>")) }]

        let result = await load("https://a.test/page")

        #expect(result == .success(AIChatPageContextData(title: "https://a.test/page", favicon: [], url: "https://a.test/page", content: "Page text",
                                                         truncated: false, fullContentLength: 9, mimeType: "text/html")))
    }

    @available(iOS 16, macOS 13, *)
    @Test("An HTTP error status is an HTTP error", .timeLimit(.minutes(1)))
    func httpErrorStatus() async {
        schemeHandler.middleware = [{ _ in .ok(code: 404, .html("<html>Not found</html>")) }]
        #expect(await load("https://a.test/missing") == .failed(.httpError))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A redirect to another origin is blocked", .timeLimit(.minutes(1)))
    func crossOriginRedirectIsBlocked() async {
        schemeHandler.middleware = [{ request in
            request.url?.host == "a.test" ? .redirect(to: "https://b.test/") : .ok(.html("<html>Other site</html>"))
        }]
        #expect(await load("https://a.test/") == .failed(.redirectBlocked))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A script navigation to another origin is blocked", .timeLimit(.minutes(1)))
    func crossOriginScriptNavigationIsBlocked() async {
        schemeHandler.middleware = [{ request in
            request.url?.host == "a.test"
                ? .ok(.html("<html><script>location.href = 'https://b.test/'</script></html>"))
                : .ok(.html("<html>Other site</html>"))
        }]
        // Extraction waits on the main frame: it never ends while the script navigates away first.
        let result = await load("https://a.test/", extracted: "")
        #expect(result == .failed(.redirectBlocked) || result == .failed(.emptyContent))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A PDF is not read", .timeLimit(.minutes(1)))
    func pdfIsPrevented() async {
        schemeHandler.middleware = [{ _ in .ok(.data(Data("%PDF-1.4".utf8), mime: "application/pdf")) }]
        #expect(await load("https://a.test/file") == .prevented("pdf"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A page with no text attaches nothing", .timeLimit(.minutes(1)))
    func emptyPage() async {
        schemeHandler.middleware = [{ _ in .ok(.html("<html></html>")) }]
        #expect(await load("https://a.test/", extracted: "") == .failed(.emptyContent))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A failed connection is a navigation failure", .timeLimit(.minutes(1)))
    func connectionFailure() async {
        schemeHandler.middleware = [{ _ in .failure(URLError(.cannotConnectToHost)) }]
        #expect(await load("https://a.test/") == .failed(.navigationFailed))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Certificate failures are reported as such", .timeLimit(.minutes(1)))
    func certificateFailureReason() {
        #expect(LinkedPageLoad.failureReason(for: URLError(.serverCertificateUntrusted)) == .certificateError)
        #expect(LinkedPageLoad.failureReason(for: URLError(.secureConnectionFailed)) == .certificateError)
        #expect(LinkedPageLoad.failureReason(for: URLError(.timedOut)) == .navigationFailed)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Only plain web links without credentials are loaded", .timeLimit(.minutes(1)))
    func supportedLinks() async {
        #expect(LinkedPageContextLoader.isSupported(URL(string: "https://example.com/a")!))
        #expect(LinkedPageContextLoader.isSupported(URL(string: "http://example.com/a")!))
        #expect(!LinkedPageContextLoader.isSupported(URL(string: "https://user@example.com/a")!))
        #expect(!LinkedPageContextLoader.isSupported(URL(string: "file:///etc/hosts")!))
        #expect(!LinkedPageContextLoader.isSupported(URL(string: "duck://newtab")!))
    }
}

// MARK: - Tab page-context slot

@MainActor
@Suite("Attaching a linked page in the tab")
struct PageContextLinkedPageTests {

    private let content = PassthroughSubject<Tab.TabContent, Never>()
    private let loader = ControlledLinkedPageLoader()
    private let pixels = PixelRecorder()
    private let pageContext: PageContextTabExtension

    init() {
        pageContext = Self.makePageContext(content: content, loader: loader, pixels: pixels)
    }

    private static func makePageContext(content: PassthroughSubject<Tab.TabContent, Never> = .init(),
                                        loader: LinkedPageContextLoading,
                                        pixels: PixelRecorder = PixelRecorder()) -> PageContextTabExtension {
        let privacyConfig = MockPrivacyConfiguration()
        // Extraction outcomes are measured once the blocklist config is present.
        privacyConfig.featureSettings = ["aiPageContextBlocklist": ["image": ["contentTypePrefixes": ["image/"]]]]
        return PageContextTabExtension(scriptsPublisher: Empty<UserScripts, Never>(),
                                       webViewPublisher: Empty<WKWebView, Never>(),
                                       contentPublisher: content,
                                       tabID: "tab",
                                       featureFlagger: MockFeatureFlagger(),
                                       privacyConfigurationManager: MockPrivacyConfigurationManager(privacyConfig: privacyConfig),
                                       extractionPixelHandler: PageContextExtractionPixelHandler(firePixel: { [pixels] in pixels.fired.append($0) }),
                                       aiChatSessionStore: MockAIChatSessionStore(),
                                       aiChatMenuConfiguration: MockAIChatConfig(),
                                       isLoadedInSidebar: false,
                                       faviconManagement: FaviconManagerMock(),
                                       linkedPageLoader: loader)
    }

    private static let page = AIChatPageContextData(title: "Linked", favicon: [], url: "https://example.com/linked",
                                                    content: "Linked text", truncated: false, fullContentLength: 11)

    @available(iOS 16, macOS 13, *)
    @Test("A read page is attached and reported as a link extraction success", .timeLimit(.minutes(1)))
    func successIsReported() async {
        let attach = pageContext.attachLinkedPage(URL(string: "https://example.com/linked")!)
        loader.complete(with: .success(Self.page))

        #expect(await attach.value == .success(Self.page))
        #expect(pixels.names == ["aichat_page_context_extraction_success"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Each failure is reported with its reason and trigger link", .timeLimit(.minutes(1)),
          arguments: [PageContextExtractionOutcome.FailureReason.httpError, .redirectBlocked, .certificateError, .timeout, .emptyContent])
    func failureIsReported(reason: PageContextExtractionOutcome.FailureReason) async {
        let attach = pageContext.attachLinkedPage(URL(string: "https://example.com/linked")!)
        loader.complete(with: .failed(reason))

        #expect(await attach.value == .failed(reason))
        #expect(pixels.parameters == [["reason": reason.rawValue, "trigger": "link", "latency": "under_1s", "context_type": "markdown"]])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A linked page the blocklist covers is prevented, not attached", .timeLimit(.minutes(1)))
    func blocklistedPageIsPrevented() async {
        let attach = pageContext.attachLinkedPage(URL(string: "https://example.com/photo")!)
        loader.complete(with: .success(AIChatPageContextData(title: "", favicon: [], url: "https://example.com/photo",
                                                             content: "x", truncated: false, fullContentLength: 1, mimeType: "image/png")))

        #expect(await attach.value == .prevented("image"))
        #expect(pixels.parameters == [["category": "image", "reason": "non_attachable", "trigger": "link"]])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Asking again cancels the first request", .timeLimit(.minutes(1)))
    func secondRequestCancelsFirst() async {
        let first = pageContext.attachLinkedPage(URL(string: "https://example.com/one")!)
        let second = pageContext.attachLinkedPage(URL(string: "https://example.com/two")!)
        loader.complete(with: .success(Self.page))

        #expect(await first.value == nil)
        #expect(await second.value == .success(Self.page))
        #expect(pixels.names == ["aichat_page_context_extraction_success"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Navigating the tab to another document drops the pending link", .timeLimit(.minutes(1)))
    func navigationCancels() async throws {
        content.send(.url(URL(string: "https://example.com/start")!, source: .link))
        try await Task.sleep(nanoseconds: 300_000_000)

        let attach = pageContext.attachLinkedPage(URL(string: "https://example.com/linked")!)
        content.send(.url(URL(string: "https://example.com/elsewhere")!, source: .link))
        try await Task.sleep(nanoseconds: 300_000_000)
        pageContext.didCommit(Self.committedNavigation)
        loader.complete(with: .success(Self.page))

        #expect(await attach.value == nil)
        #expect(pixels.fired.isEmpty)
    }

    private static var committedNavigation: Navigation {
        Navigation(identity: .init(nil), responders: .init(), state: .started, isCurrent: true, isCommitted: true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A same-document URL change keeps the pending link", .timeLimit(.minutes(1)),
          arguments: ["https://example.com/start#section", "https://example.com/start/pushed"])
    func sameDocumentChangeKeepsLink(changedURL: String) async throws {
        content.send(.url(URL(string: "https://example.com/start")!, source: .link))
        try await Task.sleep(nanoseconds: 300_000_000)

        let attach = pageContext.attachLinkedPage(URL(string: "https://example.com/linked")!)
        content.send(.url(URL(string: changedURL)!, source: .webViewUpdated))
        try await Task.sleep(nanoseconds: 300_000_000)
        loader.complete(with: .success(Self.page))

        #expect(await attach.value == .success(Self.page))
        #expect(pageContext.isLinkedPageInSlot)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Committing a navigation drops the pending link", .timeLimit(.minutes(1)))
    func commitCancels() async {
        let attach = pageContext.attachLinkedPage(URL(string: "https://example.com/linked")!)
        pageContext.didCommit(Self.committedNavigation)
        loader.complete(with: .success(Self.page))

        #expect(await attach.value == nil)
        #expect(!pageContext.isLinkedPageInSlot)
        #expect(pixels.fired.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A link that can't be read gives the slot back", .timeLimit(.minutes(1)),
          arguments: [LinkedPageContextLoadResult.failed(.httpError), .prevented("pdf")])
    func failureReleasesSlot(result: LinkedPageContextLoadResult) async {
        let attach = pageContext.attachLinkedPage(URL(string: "https://example.com/linked")!)
        loader.complete(with: result)

        #expect(await attach.value == result)
        #expect(!pageContext.isLinkedPageInSlot)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A link that can't be read leaves Duck.ai's unavailable state for the sidebar, not the tab's page", .timeLimit(.minutes(1)),
          arguments: [LinkedPageContextLoadResult.failed(.httpError), .prevented("pdf")])
    func failureDeliversUnavailableState(result: LinkedPageContextLoadResult) async {
        let attach = pageContext.attachLinkedPage(URL(string: "https://example.com/linked")!)
        loader.complete(with: result)
        _ = await attach.value

        #expect(pageContext.isLinkedPageUnavailable)
        #expect(pageContext.cachedPageContext == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A host read with the session is burnable with the tab and its window", .timeLimit(.minutes(1)))
    func sessionReadHostIsBurnable() async {
        let extensionBuilder = TestTabExtensionsBuilder(load: [PageContextTabExtension.self]) { builder in { _, _ in
            builder.override { [pageContext] in pageContext }
        }}
        let tab = Tab(content: .newtab, extensionsBuilder: extensionBuilder)
        let tabCollection = TabCollection(tabs: [tab])
        #expect(!tab.localHistoryDomains.contains("linked.example"))

        loader.sessionReadDomains = ["linked.example"]

        #expect(tab.localHistoryDomains.contains("linked.example"))
        #expect(tabCollection.localHistoryDomains.contains("linked.example"))
        _ = tabCollection.removeTab(at: 0)
        #expect(tabCollection.localHistoryDomainsOfRemovedTabs.contains("linked.example"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Once the link is attached, a same-document URL change gives the slot back", .timeLimit(.minutes(1)))
    func sameDocumentChangeAfterAttachReleasesLink() async throws {
        content.send(.url(URL(string: "https://example.com/start")!, source: .link))
        try await Task.sleep(nanoseconds: 300_000_000)
        let attach = pageContext.attachLinkedPage(URL(string: "https://example.com/linked")!)
        loader.complete(with: .success(Self.page))
        _ = await attach.value
        #expect(pageContext.isLinkedPageInSlot)

        content.send(.url(URL(string: "https://example.com/start/pushed")!, source: .webViewUpdated))
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(!pageContext.isLinkedPageInSlot)
    }

    private func makeTab(with pageContext: PageContextTabExtension) -> Tab {
        let extensionBuilder = TestTabExtensionsBuilder(load: [PageContextTabExtension.self]) { builder in { _, _ in
            builder.override { pageContext }
        }}
        return Tab(content: .url(URL(string: "https://example.com")!, source: .link), extensionsBuilder: extensionBuilder)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Hosts read with the session stay burnable after the tab is suspended or the app relaunches", .timeLimit(.minutes(1)))
    func sessionReadHostSurvivesRestoration() throws {
        loader.sessionReadDomains = ["linked.example"]
        let archived = try NSKeyedArchiver.archivedData(withRootObject: makeTab(with: pageContext).makeRestorationData(),
                                                        requiringSecureCoding: true)
        let restored = try #require(try NSKeyedUnarchiver.unarchivedObject(ofClass: TabRestorationData.self, from: archived))

        let unloaded = UnloadedTab(from: restored, isFromSessionRestore: true)
        #expect(AnyTab.unloaded(unloaded).localHistoryDomains.contains("linked.example"))

        let freshLoader = ControlledLinkedPageLoader()
        let materialized = unloaded.materialize(extensionsBuilder: TestTabExtensionsBuilder(load: [PageContextTabExtension.self]) { builder in { _, _ in
            builder.override { Self.makePageContext(loader: freshLoader) }
        }})
        #expect(materialized.localHistoryDomains.contains("linked.example"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A burn that keeps the tab open forgets the hosts read with the session", .timeLimit(.minutes(1)))
    func clearingHistoryForgetsSessionReadHosts() {
        let tab = makeTab(with: pageContext)
        loader.sessionReadDomains = ["linked.example"]

        tab.clearNavigationHistory(keepingCurrent: true)
        #expect(!tab.localHistoryDomains.contains("linked.example"))

        let unloaded = UnloadedTab(content: .url(URL(string: "https://example.com")!, source: .link), linkedPageDomains: ["linked.example"])
        unloaded.clearNavigationHistory(keepingCurrent: true)
        #expect(!AnyTab.unloaded(unloaded).localHistoryDomains.contains("linked.example"))
    }
}

@MainActor
private final class ControlledLinkedPageLoader: LinkedPageContextLoading {
    var sessionReadDomains = Set<String>()
    private var pending: [CheckedContinuation<LinkedPageContextLoadResult, Never>] = []
    private var result: LinkedPageContextLoadResult?

    func load(_ url: URL) async -> LinkedPageContextLoadResult {
        if let result { return result }
        return await withCheckedContinuation { pending.append($0) }
    }

    func complete(with result: LinkedPageContextLoadResult) {
        self.result = result
        pending.forEach { $0.resume(returning: result) }
        pending = []
    }
}

private final class PixelRecorder {
    var fired: [AIChatPixel] = []
    var names: [String] { fired.map(\.name) }
    var parameters: [[String: String]?] { fired.map(\.parameters) }
}

// MARK: - Attacher

@MainActor
@Suite("Ask About Page on a link opens the sidebar and attaches the page")
struct AIChatLinkContextAttacherTests {

    private let pixelFiring = PixelKitMock()
    private let coordinator = LinkAttachCoordinatorMock()
    private let pageContext = LinkedPageContextSpy()

    private func makeAttacher() -> AIChatLinkContextAttacher {
        AIChatLinkContextAttacher(aiChatMenuConfig: MockAIChatConfig(),
                                  aiChatCoordinator: coordinator,
                                  pixelFiring: pixelFiring,
                                  currentPageContextProvider: { [pageContext] in pageContext },
                                  aiChatConversationSourceHandler: AIChatConversationSourceHandler())
    }

    private func firedNames() -> [String] {
        pixelFiring.actualFireCalls.map(\.pixel.name)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Opens the sidebar right away and attaches the link", .timeLimit(.minutes(1)))
    func successOpensSidebarAndAttaches() async {
        pageContext.result = .success(AIChatPageContextData(title: "", favicon: [], url: "https://example.com/a", content: "x", truncated: false, fullContentLength: 1))

        makeAttacher().askAboutLink(URL(string: "https://example.com/a")!, linkType: .other, source: .contextMenu)
        await pageContext.lastTask?.value
        await Task.yield()

        #expect(pageContext.requestedURLs == [URL(string: "https://example.com/a")!])
        #expect(coordinator.revealChatCallCount == 1)
        #expect(firedNames() == ["aichat_link_ask_about_page_macos", AIChatPixel.aiChatSidebarOpened(source: .askAboutLink, shouldAutomaticallySendPageContext: nil, minutesSinceSidebarHidden: nil).name])
        #expect(pixelFiring.actualFireCalls.first?.pixel.parameters == ["link_type": "other", "source": "context_menu"])
        #expect(pixelFiring.actualFireCalls.first?.frequency == .dailyAndCount)
        #expect(pixelFiring.actualFireCalls.last?.pixel.parameters?["source"] == "ask-about-link")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A sidebar that's already open isn't reported as opened", .timeLimit(.minutes(1)))
    func alreadyOpenSidebar() async {
        coordinator.isChatPresented = true
        pageContext.result = nil

        makeAttacher().askAboutLink(URL(string: "https://duckduckgo.com/a")!, linkType: .serp, source: .serpMenu)

        #expect(firedNames() == ["aichat_link_ask_about_page_macos"])
        #expect(pixelFiring.actualFireCalls.first?.pixel.parameters == ["link_type": "serp", "source": "serp_menu"])
    }
}

@MainActor
private final class LinkedPageContextSpy: PageContextProtocol {
    var result: LinkedPageContextLoadResult?
    private(set) var requestedURLs: [URL] = []
    private(set) var lastTask: Task<LinkedPageContextLoadResult?, Never>?
    var linkedPageDomains = Set<String>()

    func appendSelectionContext(_ selection: AIChatSelectionContextData) {}
    func suppressAutoPageContextForSelectionAction() {}
    func requestPageContextAttachment() {}

    func attachLinkedPage(_ url: URL) -> Task<LinkedPageContextLoadResult?, Never> {
        requestedURLs.append(url)
        let task = Task { [result] in result }
        lastTask = task
        return task
    }
}

private final class LinkAttachCoordinatorMock: AIChatCoordinating {
    var isChatPresented = false
    var revealChatCallCount = 0

    func toggleSidebar() {}
    func collapseSidebar(withAnimation: Bool) {}
    func isSidebarOpen(for tabID: TabIdentifier) -> Bool { isChatPresented }
    func isSidebarOpenForCurrentTab() -> Bool { isChatPresented }
    func isChatPresentedForCurrentTab() -> Bool { isChatPresented }
    func sidebarHiddenAt(for tabID: TabIdentifier) -> Date? { nil }
    func sidebarHiddenAtForCurrentTab() -> Date? { nil }
    func hasHiddenChat(for tabID: TabIdentifier) -> Bool { false }
    var sidebarPresenceDidChangePublisher: AnyPublisher<AIChatPresenceChange, Never> { Empty().eraseToAnyPublisher() }
    func isChatFloating(for tabID: TabIdentifier) -> Bool { false }
    var chatFloatingStateDidChangePublisher: AnyPublisher<TabIdentifier, Never> { Empty().eraseToAnyPublisher() }
    func focusFloatingWindow(for tabID: TabIdentifier) {}
    func closeFloatingWindow(for tabID: TabIdentifier) {}
    func closeChat(for tabID: TabIdentifier, withAnimation: Bool) {}
    func revealChat(for prompt: AIChatNativePrompt) {}
    func revealChat() { revealChatCallCount += 1 }
}
