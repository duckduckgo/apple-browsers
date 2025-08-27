//
//  SuggestionContainerTests.swift
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

import Combine
import Common
import History
import InlineSnapshotTesting
import NetworkingTestingUtils
import os.log
import Suggestions
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class SuggestionContainerTests: XCTestCase {

    override class func tearDown() {
        MockURLProtocol.requestHandler = nil
    }

    @MainActor
    func testWhenGetSuggestionsIsCalled_ThenContainerAsksAndHoldsSuggestionsFromLoader() {
        let suggestionLoadingMock = SuggestionLoadingMock()
        let historyCoordinatingMock = HistoryProviderMock()
        let bookmarkProviderMock = SuggestionsBookmarkProvider(bookmarkManager: MockBookmarkManager())
        let suggestionContainer = SuggestionContainer(openTabsProvider: { [] },
                                                      suggestionLoading: suggestionLoadingMock,
                                                      historyProvider: historyCoordinatingMock,
                                                      bookmarkProvider: bookmarkProviderMock,
                                                      featureFlagger: MockFeatureFlagger(),
                                                      burnerMode: .regular,
                                                      isUrlIgnored: { _ in false })

        let e = expectation(description: "Suggestions updated")
        let cancellable = suggestionContainer.$result.sink {
            if $0 != nil {
                e.fulfill()
            }
        }

        suggestionContainer.getSuggestions(for: "test")
        let result = SuggestionResult.aSuggestionResult
        suggestionLoadingMock.completion!(result, nil)

        XCTAssert(suggestionLoadingMock.getSuggestionsCalled)
        withExtendedLifetime(cancellable) {
            waitForExpectations(timeout: 1)
        }
        XCTAssertEqual(suggestionContainer.result?.all, result.topHits + result.duckduckgoSuggestions + result.localSuggestions)
    }

    @MainActor
    func testWhenStopGettingSuggestionsIsCalled_ThenNoSuggestionsArePublished() {
        let suggestionLoadingMock = SuggestionLoadingMock()
        let historyCoordinatingMock = HistoryProviderMock()
        let bookmarkProviderMock = SuggestionsBookmarkProvider(bookmarkManager: MockBookmarkManager())
        let suggestionContainer = SuggestionContainer(openTabsProvider: { [] },
                                                      suggestionLoading: suggestionLoadingMock,
                                                      historyProvider: historyCoordinatingMock,
                                                      bookmarkProvider: bookmarkProviderMock,
                                                      featureFlagger: MockFeatureFlagger(),
                                                      burnerMode: .regular,
                                                      isUrlIgnored: { _ in false })

        suggestionContainer.getSuggestions(for: "test")
        suggestionContainer.stopGettingSuggestions()
        suggestionLoadingMock.completion?(SuggestionResult.aSuggestionResult, nil)

        XCTAssert(suggestionLoadingMock.getSuggestionsCalled)
        XCTAssertNil(suggestionContainer.result)
    }

    @MainActor
    func testSuggestionLoadingCacheClearing() {
        let suggestionLoadingMock = SuggestionLoadingMock()
        let historyCoordinatingMock = HistoryProviderMock()
        let bookmarkProviderMock = SuggestionsBookmarkProvider(bookmarkManager: MockBookmarkManager())
        let suggestionContainer = SuggestionContainer(openTabsProvider: { [] },
                                                      suggestionLoading: suggestionLoadingMock,
                                                      historyProvider: historyCoordinatingMock,
                                                      bookmarkProvider: bookmarkProviderMock,
                                                      featureFlagger: MockFeatureFlagger(),
                                                      burnerMode: .regular,
                                                      isUrlIgnored: { _ in false })

        XCTAssertNil(suggestionContainer.suggestionDataCache)
        let e = expectation(description: "Suggestions updated")
        suggestionContainer.suggestionLoading(suggestionLoadingMock, suggestionDataFromUrl: URL.duckDuckGo, withParameters: [:]) { data, error in
            XCTAssertNotNil(suggestionContainer.suggestionDataCache)
            e.fulfill()

            // Test the cache is not cleared if useCachedData is true
            XCTAssertFalse(suggestionLoadingMock.getSuggestionsCalled)
            suggestionContainer.getSuggestions(for: "test", useCachedData: true)
            XCTAssertNotNil(suggestionContainer.suggestionDataCache)
            XCTAssert(suggestionLoadingMock.getSuggestionsCalled)

            suggestionLoadingMock.getSuggestionsCalled = false

            // Test the cache is cleared if useCachedData is false
            XCTAssertFalse(suggestionLoadingMock.getSuggestionsCalled)
            suggestionContainer.getSuggestions(for: "test", useCachedData: false)
            XCTAssertNil(suggestionContainer.suggestionDataCache)
            XCTAssert(suggestionLoadingMock.getSuggestionsCalled)
        }

        waitForExpectations(timeout: 1)
    }

    @MainActor
    func testSuggestionsJsonScenarios() async throws {
        let onlyRun = "" // "bookmarks-history-open-tabs-basic"
        guard let directoryURL = Bundle(for: SuggestionContainerTests.self).url(forResource: "privacy-reference-tests/suggestions", withExtension: nil) else {
            return XCTFail("Failed to locate the suggestions directory in the bundle")
        }

        let fileURLs = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)

        // Filter for JSON files
        let jsonFiles = fileURLs.filter {
            $0.pathExtension == "json"
            && !$0.deletingPathExtension().lastPathComponent.hasSuffix("schema")
        }

        for fileURL in jsonFiles
        where onlyRun.isEmpty || onlyRun.dropping(suffix: ".json") + ".json" == fileURL.lastPathComponent {
            // Load and decode each JSON file
            let data = try Data(contentsOf: fileURL)
            let testScenario: TestScenario
            do {
                testScenario = try JSONDecoder().decode(TestScenario.self, from: data)
            } catch let error as NSError {
                throw NSError(domain: error.domain, code: error.code, userInfo: error.userInfo.merging([NSFilePathErrorKey: fileURL.lastPathComponent]) { $1 })
            }

            // Skip non-desktop scenarios - only run desktop platform tests
            guard testScenario.platform == .desktop else {
                Logger.tests.info("Skipping non-desktop test scenario: \(fileURL.lastPathComponent)")
                continue
            }

            // Run the test for each scenario
            Logger.tests.info("Running JSON test scenario: \(fileURL.lastPathComponent)")
            try await runJsonTestScenario(testScenario, named: fileURL.deletingPathExtension().lastPathComponent)
        }
    }

    @MainActor
    private func runJsonTestScenario(_ testScenario: TestScenario, named name: String) async throws {
        let input = testScenario.input

        // Find window and index containing the tab initiating the search
        var selectedWindow = 0
        var selectedTabIndex: TabIndex?

        // Search windows for tab initiating search
        for (windowIndex, window) in input.windows.enumerated() {
            if let tabIndex = window.tabs.firstIndex(where: { $0.tabId == input.tabIdInitiatingSearch }) {
                selectedWindow = windowIndex
                selectedTabIndex = .unpinned(tabIndex)
                break
            }
        }
        // Index of the tab that is currently selected.
        if selectedTabIndex == nil, let pinnedTabIndex = input.pinnedTabs.firstIndex(where: { $0.tabId == input.tabIdInitiatingSearch }) {
            selectedTabIndex = .pinned(pinnedTabIndex)
        }
        guard let selectedTabIndex else { return XCTFail("Selected Tab Id not found") }

        // Create tab collection view models for each window
        let tabCollectionViewModels = input.windows.enumerated().map { (idx, window) in
            let burnerMode = window.type == .fire ? BurnerMode(isBurner: true) : BurnerMode.regular
            return TabCollectionViewModel(
                tabCollection: tabCollection(window.tabs.map(OpenTab.init), burnerMode: burnerMode),
                selectionIndex: idx == selectedWindow ? selectedTabIndex : .unpinned(0),
                burnerMode: burnerMode
            )
        }

        // Initialize a mock WindowControllersManager with pinned tabs, tab view models, and the selected window index for testing.
        let provider = PinnedTabsManagerProvidingMock()
        let manager = pinnedTabsManager(tabs: input.pinnedTabs.map(OpenTab.init))
        provider.currentPinnedTabManagers = [manager]

        let windowControllersManagerMock = WindowControllersManagerMock(pinnedTabsManagerProvider: provider,
                                                                        tabCollectionViewModels: tabCollectionViewModels,
                                                                        selectedWindow: selectedWindow)

        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags.append(.autocompleteTabs)

        // Tested object
        let suggestionContainer = SuggestionContainer(urlSession: .mock(),
                                                      historyProvider: HistoryProviderMock(history: input.history),
                                                      bookmarkProvider: BookmarkProviderMock(bookmarks: input.bookmarks),
                                                      featureFlagger: mockFeatureFlagger,
                                                      burnerMode: tabCollectionViewModels[selectedWindow].burnerMode,
                                                      isUrlIgnored: testScenario.input.isURLIgnored,
                                                      windowControllersManager: windowControllersManagerMock)

        // Mock API Suggestions response
        MockURLProtocol.requestHandler = { request in
            let urlComponents = URLComponents(string: request.url!.absoluteString)!
            XCTAssertTrue(urlComponents.queryItems!.contains(URLQueryItem(name: "q", value: input.query)))
            switch input.apiSuggestions {
            case .suggestions(let suggestions):
                var respData: Data?
                do {
                    respData = try JSONEncoder().encode(suggestions)
                } catch {
                    XCTFail("Could not encode API suggestions from \(name) to JSON: \(error)")
                }
                return (HTTPURLResponse.ok, respData)
            case .error(let error):
                return (HTTPURLResponse(url: request.url!,
                                        statusCode: error.statusCode,
                                        httpVersion: nil,
                                        headerFields: [:])!, nil)
            }
        }

        // Get the compiled suggestions
        let resultPromise = suggestionContainer.$result.dropFirst().timeout(1).first().promise()
        suggestionContainer.getSuggestions(for: input.query)

        let actualResults = try await resultPromise.get()
        let testResults = TestExpectations(from: actualResults, query: testScenario.input.query)

        assertInlineSnapshot(of: testResults?.encoded(), as: .lines, message: name, matches: testScenario.expectations.encoded)
    }

}

extension SuggestionContainerTests {

    fileprivate struct TestScenario: Decodable {
        enum Platform: String, Decodable {
            case mobile
            case desktop
        }

        let platform: Platform
        let description: String
        let input: TestInput
        let expectations: TestExpectations
    }

    struct TestInput: Decodable {
        let query: String
        let tabIdInitiatingSearch: UUID
        let bookmarks: [Bookmark]
        let history: [HistoryEntry]
        let pinnedTabs: [TabMock]
        let windows: [Window]
        let apiSuggestions: ApiSuggestions
        let ignoredUris: Set<String>?

        enum ApiSuggestions: Decodable {
            case suggestions([Suggestions.APIResult.SuggestionResult])
            case error(HTTPError)

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let result = try? container.decode(Suggestions.APIResult.self) {
                    self = .suggestions(result.items)
                } else {
                    self = try .error(.init(from: decoder))
                }
            }
        }

        struct HTTPError: Swift.Error, Decodable {
            let statusCode: Int
        }

        func isURLIgnored(_ url: URL) -> Bool {
            ignoredUris?.contains(url.nakedString ?? "") ?? false
        }
    }

    struct Bookmark: Decodable, Suggestions.Bookmark {
        enum CodingKeys: String, CodingKey {
            case title
            case url="uri"
            case isFavorite
        }
        let title: String
        var url: String
        let isFavorite: Bool
    }

    struct HistoryEntry: Decodable, Hashable, Suggestions.HistorySuggestion {
        enum CodingKeys: String, CodingKey {
            case title
            case url = "uri"
            case numberOfVisits = "visitCount"
            case _lastVisit = "lastVisit"
            case _failedToLoad = "failedToLoad"
        }
        let title: String?
        let url: URL
        let numberOfVisits: Int
        let _lastVisit: Date?
        var lastVisit: Date { _lastVisit ?? .distantPast }
        let _failedToLoad: Bool?
        var failedToLoad: Bool { _failedToLoad ?? false }

        var identifier: UUID { Self.uuidFromHash(self.hashValue) }

        private static func uuidFromHash(_ hash: Int) -> UUID {
            // Convert the integer hash to a string
            let hashString = String(abs(hash))

            // Create a UUID from the hash string by padding/truncating to fit UUID format
            let paddedHashString = hashString.padding(toLength: 32, withPad: "0", startingAt: 0)

            // Format the string to match UUID format (8-4-4-4-12)
            let uuidString = "\(paddedHashString.prefix(8))-\(paddedHashString.dropFirst(8).prefix(4))-\(paddedHashString.dropFirst(12).prefix(4))-\(paddedHashString.dropFirst(16).prefix(4))-\(paddedHashString.dropFirst(20).prefix(12))"

            // Create and return a UUID from the formatted string
            return UUID(uuidString: uuidString)!
        }

    }

    struct Window: Decodable {
        // Window types from schema
        enum WindowType: String, Decodable {
            case regular = "fullyFeatured"
            case fire = "fireWindow"
            case popup
        }

        // Only fields defined in schema
        let type: WindowType
        let tabs: [TabMock]
    }

    // Update TabMock to match schema
    struct TabMock: Equatable, Decodable {
        let tabId: UUID
        let title: String
        let url: URL

        private enum CodingKeys: String, CodingKey {
            case tabId, title, uri
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.tabId = try container.decode(UUID.self, forKey: .tabId)
            self.title = try container.decode(String.self, forKey: .title)
            self.url = try container.decode(URL.self, forKey: .uri)
        }
    }

    struct APISuggestion: Decodable {
        let phrase: String
        let isNav: Bool?
    }

    class WindowControllersManagerMock: WindowControllersManagerProtocol {
        var stateChanged: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher()

        var mainWindowControllers: [DuckDuckGo_Privacy_Browser.MainWindowController] = []

        var lastKeyMainWindowController: DuckDuckGo_Privacy_Browser.MainWindowController?

        var pinnedTabsManagerProvider: any DuckDuckGo_Privacy_Browser.PinnedTabsManagerProviding

        var didRegisterWindowController = PassthroughSubject<(DuckDuckGo_Privacy_Browser.MainWindowController), Never>()

        var didUnregisterWindowController = PassthroughSubject<(DuckDuckGo_Privacy_Browser.MainWindowController), Never>()

        func register(_ windowController: DuckDuckGo_Privacy_Browser.MainWindowController) {
        }

        func unregister(_ windowController: DuckDuckGo_Privacy_Browser.MainWindowController) {
        }

        func show(url: URL?, tabId: String?, source: DuckDuckGo_Privacy_Browser.Tab.TabContent.URLSource, newTab: Bool, selected: Bool?) {
        }

        func showBookmarksTab() {
        }

        func showTab(with content: DuckDuckGo_Privacy_Browser.Tab.TabContent) {
        }

        func open(_ url: URL, source: DuckDuckGo_Privacy_Browser.Tab.TabContent.URLSource, target window: NSWindow?, event: NSEvent?) {
        }

        var allTabCollectionViewModels: [TabCollectionViewModel] = []
        var selectedWindowIndex: Int
        var selectedTab: Tab? {
            allTabCollectionViewModels[selectedWindowIndex].selectedTab
        }

        func openNewWindow(with tabCollectionViewModel: DuckDuckGo_Privacy_Browser.TabCollectionViewModel?, burnerMode: DuckDuckGo_Privacy_Browser.BurnerMode, droppingPoint: NSPoint?, contentSize: NSSize?, showWindow: Bool, popUp: Bool, lazyLoadTabs: Bool, isMiniaturized: Bool, isMaximized: Bool, isFullscreen: Bool) -> NSWindow? {
            nil
        }

        func openAIChat(_ url: URL, with linkOpenBehavior: LinkOpenBehavior) {}
        func openAIChat(_ url: URL, with linkOpenBehavior: LinkOpenBehavior, hasPrompt: Bool) {}

        init(pinnedTabsManagerProvider: PinnedTabsManagerProviding, tabCollectionViewModels: [TabCollectionViewModel] = [], selectedWindow: Int = 0) {
            self.pinnedTabsManagerProvider = pinnedTabsManagerProvider
            self.allTabCollectionViewModels = tabCollectionViewModels
            self.selectedWindowIndex = selectedWindow
        }
    }

    @MainActor
    private func tabCollection(_ openTabs: [OpenTab], burnerMode: BurnerMode = .regular) -> TabCollection {
        let contentBlockingMock = ContentBlockingMock()
        let privacyFeaturesMock = AppPrivacyFeatures(contentBlocking: contentBlockingMock, httpsUpgradeStore: HTTPSUpgradeStoreMock())
        // disable waiting for CBR compilation on navigation
        (contentBlockingMock.privacyConfigurationManager.privacyConfig as! MockPrivacyConfiguration).isFeatureKeyEnabled = { _, _ in
            return false
        }
        let tabs = openTabs.map {
            Tab(id: $0.tabId, content: TabContent.contentFromURL($0.url, source: .link), webViewConfiguration: WKWebViewConfiguration(), privacyFeatures: privacyFeaturesMock, title: $0.title, burnerMode: burnerMode)
        }
        return TabCollection(tabs: tabs)
    }

    @MainActor
    private func pinnedTabsManager(tabs: [OpenTab]) -> PinnedTabsManager {
        PinnedTabsManager(tabCollection: tabCollection(tabs))
    }

}
private extension OpenTab {
    init(_ tab: SuggestionContainerTests.TabMock) {
        self.init(tabId: tab.tabId.uuidString, title: tab.title, url: tab.url)
    }
}
class HistoryProviderMock: SuggestionContainer.HistoryProvider {
    let history: [SuggestionContainerTests.HistoryEntry]

    func history(for suggestionLoading: any Suggestions.SuggestionLoading) -> [any Suggestions.HistorySuggestion] {
        history
    }

    init(history: [SuggestionContainerTests.HistoryEntry] = []) {
        self.history = history
    }
}

private class BookmarkProviderMock: SuggestionContainer.BookmarkProvider {
    let bookmarks: [SuggestionContainerTests.Bookmark]

    func bookmarks(for suggestionLoading: any Suggestions.SuggestionLoading) -> [any Suggestions.Bookmark] {
        bookmarks
    }

    init(bookmarks: [SuggestionContainerTests.Bookmark]) {
        self.bookmarks = bookmarks
    }
}

extension SuggestionContainerTests {
    fileprivate struct TestExpectations: Codable {
        struct ExpectedSuggestion: Codable {
            enum SuggestionType: String, Codable {
                case phrase
                case website
                case bookmark
                case favorite
                case historyEntry
                case openTab
                case internalPage
            }
            enum CodingKeys: String, CodingKey {
                case type
                case title
                case subtitle
                case uri
                case tabId
                case score
            }

            let type: SuggestionType
            let title: String
            let subtitle: String
            let uri: String?
            let tabId: UUID?
            let score: Int

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.type = try container.decode(SuggestionType.self, forKey: .type)
                self.title = try container.decode(String.self, forKey: .title)
                self.subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
                self.uri = try container.decodeIfPresent(String.self, forKey: .uri).flatMap { urlString in
                    // Convert percent-encoded sequences to upper case to match macOS `String.addingPercentEncoding` implementation
                    guard let qStartIdx = urlString.firstIndex(of: "?") else { return urlString }
                    let qEndIdx = urlString[qStartIdx...].firstIndex(of: "#") ?? urlString.endIndex
                    var urlString = urlString
                    let percentEncoursedSequencesRegex = regex(#"(%[0-9a-f]{2})"#)
                    let matches = percentEncoursedSequencesRegex.matches(in: urlString, options: [], range: NSRange(qStartIdx..<qEndIdx, in: urlString))
                    for match in matches {
                        urlString.replaceSubrange(match.range(in: urlString)!, with: urlString[match.range(in: urlString)!].uppercased())
                    }
                    return urlString
                }
                let tabId = try container.decodeIfPresent(UUID.self, forKey: .tabId)
                self.tabId = (tabId == UUID(uuidString: "00000000-0000-0000-0000-000000000000")) ? nil : (type == .openTab ? tabId : nil)
                self.score = try container.decode(Int.self, forKey: .score)
            }

            init(type: SuggestionType, title: String, subtitle: String?, uri: String?, tabId: UUID?, score: Int = 1) {
                self.type = type
                self.title = title
                self.subtitle = subtitle ?? ""
                self.uri = uri
                self.tabId = (tabId == UUID(uuidString: "00000000-0000-0000-0000-000000000000")) ? nil : (type == .openTab ? tabId : nil)
                self.score = score
            }
        }

        let topHits: [ExpectedSuggestion]
        let searchSuggestions: [ExpectedSuggestion]
        let localSuggestions: [ExpectedSuggestion]

        init?(from result: SuggestionResult?, query: String) {
            guard let result else { return nil }
            self.topHits = result.topHits.compactMap { $0.expectedSuggestion(query: query) }
            self.searchSuggestions = result.duckduckgoSuggestions.compactMap { $0.expectedSuggestion(query: query) }
            self.localSuggestions = result.localSuggestions.compactMap { $0.expectedSuggestion(query: query) }
        }

        func encoded() -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                return try encoder.encode(self).utf8String() ?? "<nil>"
            } catch {
                return error.localizedDescription
            }
        }
    }
}
private extension URLSession {
    static func mock() -> URLSession {
        let testConfiguration = URLSessionConfiguration.default
        testConfiguration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: testConfiguration)
    }
}
private extension Suggestion {

    func expectedSuggestion(query: String) -> SuggestionContainerTests.TestExpectations.ExpectedSuggestion? {
        let viewModel = SuggestionViewModel(isHomePage: false, suggestion: self, userStringValue: query, visualStyle: VisualStyle.current)
        switch self {
        case .phrase(phrase: let phrase):
            return .init(type: .phrase, title: phrase, subtitle: viewModel.suffix ?? "", uri: URL.makeSearchUrl(from: phrase)?.absoluteString, tabId: nil, score: 0)

        case .website(url: let url):
            return .init(type: .website, title: url.absoluteString.dropping(prefix: url.navigationalScheme?.separated() ?? ""), subtitle: viewModel.suffix ?? "", uri: url.absoluteString, tabId: nil, score: 0)

        case .bookmark(title: let title, url: let url, isFavorite: let isFavorite, score: let score):
            return .init(type: isFavorite ? .favorite : .bookmark, title: title, subtitle: viewModel.suffix ?? "", uri: url.absoluteString, tabId: nil, score: score)

        case .historyEntry(title: let title, url: let url, score: let score):
            return .init(type: .historyEntry, title: title ?? "", subtitle: viewModel.suffix ?? "", uri: url.absoluteString, tabId: nil, score: score)

        case .openTab(title: let title, url: let url, tabId: let tabId, score: let score):
            return .init(type: .openTab, title: title, subtitle: viewModel.suffix ?? "", uri: url.absoluteString, tabId: tabId.flatMap(UUID.init(uuidString:)), score: score)
        case .internalPage(title: let title, url: let url, score: let score):
            return .init(type: .internalPage, title: title, subtitle: viewModel.suffix ?? "", uri: url.absoluteString, tabId: nil, score: score)
        case .unknown, .askAIChat:
            return nil
        }
    }
}
