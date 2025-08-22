//
//  SuggestionJsonScenarioTests.swift
//  DuckDuckGo
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

import Bookmarks
import BrowserServicesKit
import Common
import Core
import CoreData
import InlineSnapshotTesting
import History
import os.log
import Persistence
import Suggestions
import XCTest

@testable import DuckDuckGo

// swiftlint:disable force_try identifier_name

final class SuggestionJsonScenarioTests: XCTestCase {

    override class func setUp() {
        StatisticsUserDefaults().atb = nil
    }

    // MARK: - Test Scenarios

    @MainActor
    func testSuggestionsJsonScenarios() async throws {
        let onlyRun = "" // "bookmarks-history-open-tabs-basic"
        guard let directoryURL = Bundle(for: SuggestionJsonScenarioTests.self).url(forResource: "privacy-reference-tests/suggestions", withExtension: nil) else {
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

            // Skip non-mobile scenarios - only run mobile platform tests
            guard testScenario.platform == .mobile else {
                os_log("Skipping non-mobile test scenario: %{public}@", log: .default, type: .info, fileURL.lastPathComponent)
                continue
            }

            // Run the test for each scenario
            os_log("Running JSON test scenario: %{public}@", log: .default, type: .info, fileURL.lastPathComponent)
            try await runJsonTestScenario(testScenario, named: fileURL.deletingPathExtension().lastPathComponent)
        }
    }

    @MainActor
    private func runJsonTestScenario(_ testScenario: TestScenario, named name: String) async throws {
        let input = testScenario.input

        // Set up mocked dependencies for the data source
        let mockHistoryCoordinator = MockHistoryCoordinator()
        mockHistoryCoordinator.testHistoryEntries = input.history
        
        let historyManager = MockHistoryManager(
            historyCoordinator: mockHistoryCoordinator,
            isEnabledByUser: true,
            historyFeatureEnabled: true
        )
        
        // Set up the bookmarks database
        let model = CoreDataDatabase.loadModel(from: Bookmarks.bundle, named: "BookmarksModel")!
        let bookmarksDB = CoreDataDatabase(name: "Test", containerLocation: tempDBDir(), model: model)
        bookmarksDB.loadStore()
        
        // Populate bookmarks database with test data
        try populateBookmarks(database: bookmarksDB, bookmarks: input.bookmarks)
        
        // Set up tabs model with test data
        let tabsModel = TabsModel(desktop: false)
        assert(input.windows.count == 1, "iOS only supports 1 window")
        for tab in input.windows[0].tabs {
            tabsModel.add(tab: Tab(uid: tab.tabId.uuidString, link: Link(title: tab.title, url: tab.url)))
        }
        
        // Set up feature flagger
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags.append(.autocompleteTabs)
        
        // Create the real data source with test dependencies
        let dataSource = AutocompleteSuggestionsDataSource(
            historyManager: historyManager,
            bookmarksDatabase: bookmarksDB,
            featureFlagger: featureFlagger,
            tabsModel: tabsModel
        ) { _, completion in
            // Mock API response
            switch input.apiSuggestions {
            case .suggestions(let suggestions):
                do {
                    let data = try JSONEncoder().encode(suggestions)
                    completion(data, nil)
                } catch {
                    completion(nil, error)
                }
            case .error(let error):
                completion(nil, error)
            }
        }

        // Wrap the data source to ensure sorted bookmarks for stable test results
        let sortedDataSource = SortingDataSourceWrapper(wrapping: dataSource)

        // Create a suggestion loader
        let suggestionLoader = SuggestionLoader(urlFactory: { _ in return nil }, isUrlIgnored: testScenario.input.isURLIgnored)
        var actualResults: SuggestionResult?
        var loadingError: Error?

        // Create an expectation for the async completion
        let expectation = expectation(description: "Suggestion loading completion")

        // Request suggestions
        suggestionLoader.getSuggestions(query: input.query, usingDataSource: sortedDataSource) { results, error in
            actualResults = results
            loadingError = error
            expectation.fulfill()
        }

        // Wait for the expectation to be fulfilled with a timeout
        await fulfillment(of: [expectation], timeout: 1.0)

        // Check for errors
        if let loadingError = loadingError {
            throw loadingError
        }

        // Convert the results to test expectations format
        var expectations = testScenario.expectations
        let testResults = TestExpectations(from: actualResults, query: input.query)
        // append "&t=ddg_ios" to duckduckgo queries for iOS
        for idx in expectations.searchSuggestions.indices {
            let searchSuggestion = expectations.searchSuggestions[idx]
            if case .phrase = searchSuggestion.type {
                expectations.searchSuggestions[idx].uri = (searchSuggestion.uri ?? "") + "&t=ddg_ios"
            }
        }

        // Assert the results match expectations
        assertInlineSnapshot(of: testResults?.encoded(), as: .lines, message: name, matches: expectations.encoded)
    }

}

// MARK: - Model Types

extension SuggestionJsonScenarioTests {
    
    fileprivate struct TestScenario: Decodable {
        enum Platform: String, Decodable {
            case mobile
            case desktop
        }
        
        let platform: Platform
        let description: String
        let input: TestInput
        var expectations: TestExpectations
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
            case url = "uri"
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
}

// MARK: - Test Helper Functions

extension SuggestionJsonScenarioTests {
    
    private func tempDBDir() -> URL {
        let directoryName = "test_db_\(UUID().uuidString)"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(directoryName)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    
    private func populateBookmarks(database: CoreDataDatabase, bookmarks: [Bookmark]) throws {
        let context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        
        // Properly prepare the folder structure
        BookmarkUtils.prepareFoldersStructure(in: context)
        
        // Fetch the root folder and favorites folders
        guard let rootFolder = BookmarkUtils.fetchRootFolder(context) else {
            throw NSError(domain: "SuggestionJsonScenarioTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get root folder"])
        }
        
        let favoritesFolders = BookmarkUtils.fetchFavoritesFolders(for: .displayNative(.mobile), in: context)
        guard !favoritesFolders.isEmpty else {
            throw NSError(domain: "SuggestionJsonScenarioTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to get favorites folders"])
        }
        
        // Add each bookmark from the test data
        for bookmark in bookmarks {
            let entity = BookmarkEntity(context: context)
            entity.title = bookmark.title
            entity.url = bookmark.url
            entity.uuid = UUID().uuidString
            entity.isFolder = false
            entity.parent = rootFolder
            
            // If it's a favorite, add it to all favorites folders
            if bookmark.isFavorite {
                entity.addToFavorites(folders: favoritesFolders)
            }
        }
        
        // Save the context
        try context.save()
    }
    
    class MockHistoryCoordinator: HistoryCoordinating {

        // Store test history entries
        var testHistoryEntries: [SuggestionJsonScenarioTests.HistoryEntry]? {
            didSet {
                // Convert test entries to History.HistoryEntry when assigned
                if let entries = testHistoryEntries {
                    history = entries.map { testEntry in
                        // Initialize HistoryEntry with all required parameters based on how it's done in HistoryStoreTests
                        return History.HistoryEntry(
                            identifier: testEntry.identifier,
                            url: testEntry.url,
                            title: testEntry.title,
                            failedToLoad: testEntry.failedToLoad,
                            numberOfTotalVisits: testEntry.numberOfVisits,
                            lastVisit: testEntry.lastVisit,
                            visits: Set<History.Visit>(),
                            numberOfTrackersBlocked: 0,
                            blockedTrackingEntities: Set<String>(),
                            trackersFound: false
                        )
                    }
                    
                    // Update history dictionary
                    historyDictionary = Dictionary(uniqueKeysWithValues: (history ?? []).map { ($0.url, $0) })
                }
            }
        }
        
        var history: [History.HistoryEntry]?
        var allHistoryVisits: [History.Visit]?

        @Published var historyDictionary: [URL: History.HistoryEntry]?
        var historyDictionaryPublisher: Published<[URL: History.HistoryEntry]?>.Publisher {
            $historyDictionary
        }

        func loadHistory(onCleanFinished: @escaping () -> Void) {
            onCleanFinished()
        }
        
        func addVisit(of url: URL) -> History.Visit? {
            return nil
        }
        
        func addVisit(of url: URL, at date: Date) -> History.Visit? {
            return nil
        }
        
        func addBlockedTracker(entityName: String, on url: URL) {
        }
        
        func trackerFound(on: URL) {
        }
        
        func updateTitleIfNeeded(title: String, url: URL) {
        }
        
        func markFailedToLoadUrl(_ url: URL) {
        }
        
        func commitChanges(url: URL) {
        }
        
        func title(for url: URL) -> String? {
            return nil
        }
        
        func burnAll(completion: @escaping () -> Void) {
            completion()
        }
        
        func burnDomains(_ baseDomains: Set<String>, tld: Common.TLD, completion: @escaping (Set<URL>) -> Void) {
            completion([])
        }
        
        func burnVisits(_ visits: [History.Visit], completion: @escaping () -> Void) {
            completion()
        }
        
        func removeUrlEntry(_ url: URL, completion: (((any Error)?) -> Void)?) {
            completion?(nil)
        }
    }
    
    class MockHistoryManager: HistoryManaging {
        let historyCoordinator: HistoryCoordinating
        var isEnabledByUser: Bool
        var historyFeatureEnabled: Bool
        
        init(historyCoordinator: HistoryCoordinating, isEnabledByUser: Bool, historyFeatureEnabled: Bool) {
            self.historyCoordinator = historyCoordinator
            self.historyFeatureEnabled = historyFeatureEnabled
            self.isEnabledByUser = isEnabledByUser
        }
        
        func isHistoryFeatureEnabled() -> Bool {
            return historyFeatureEnabled
        }
        
        func removeAllHistory() async {
        }
        
        func deleteHistoryForURL(_ url: URL) async {
        }
    }
}

// MARK: - Results Test Expectations

extension SuggestionJsonScenarioTests {
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
            var uri: String?
            let tabId: UUID?
            let score: Int
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.type = try container.decode(SuggestionType.self, forKey: .type)
                self.title = try container.decode(String.self, forKey: .title)
                self.subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
                self.uri = try container.decodeIfPresent(String.self, forKey: .uri).flatMap { urlString in
                    // Convert percent-encoded sequences to upper case to match iOS URL encoding
                    guard let qStartIdx = urlString.firstIndex(of: "?") else { return urlString }
                    let qEndIdx = urlString[qStartIdx...].firstIndex(of: "#") ?? urlString.endIndex
                    var urlString = urlString
                    let percentEncoursedSequencesRegex = try! NSRegularExpression(pattern: "(%[0-9a-f]{2})", options: [])
                    let range = NSRange(qStartIdx..<qEndIdx, in: urlString)
                    let matches = percentEncoursedSequencesRegex.matches(in: urlString, options: [], range: range)
                    for match in matches {
                        if let matchRange = Range(match.range(at: 1), in: urlString) {
                            urlString.replaceSubrange(matchRange, with: urlString[matchRange].uppercased())
                        }
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
        var searchSuggestions: [ExpectedSuggestion]
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

// MARK: - Helper Extensions

extension OpenTab {
    init(_ tab: SuggestionJsonScenarioTests.TabMock) {
        self.init(tabId: tab.tabId.uuidString, title: tab.title, url: tab.url)
    }
}

private extension Suggestion {

    func expectedSuggestion(query: String) -> SuggestionJsonScenarioTests.TestExpectations.ExpectedSuggestion? {
        let subtitle = ""
        switch self {
        case .phrase(phrase: let phrase):
            return .init(type: .phrase, title: phrase, subtitle: subtitle, uri: URL.makeSearchURL(query: phrase, forceSearchQuery: true)?.absoluteString, tabId: nil, score: 0)

        case .website(url: let url):
            return .init(type: .website, title: url.absoluteString.dropping(prefix: (url.scheme ?? "") + "://"), subtitle: subtitle, uri: url.absoluteString, tabId: nil, score: 0)

        case .bookmark(title: let title, url: let url, isFavorite: let isFavorite, score: let score):
            return .init(type: isFavorite ? .favorite : .bookmark, title: title, subtitle: "", uri: url.absoluteString, tabId: nil, score: score)

        case .historyEntry(title: let title, url: let url, score: let score):
            return .init(type: .historyEntry, title: title ?? "", subtitle: subtitle, uri: url.absoluteString, tabId: nil, score: score)

        case .openTab(title: let title, url: let url, tabId: let tabId, score: let score):
            return .init(type: .openTab, title: title, subtitle: subtitle, uri: url.absoluteString, tabId: tabId.flatMap(UUID.init(uuidString:)), score: score)
        case .internalPage(title: let title, url: let url, score: let score):
            return .init(type: .internalPage, title: title, subtitle: subtitle, uri: url.absoluteString, tabId: nil, score: score)
        case .unknown, .askAIChat:
            return nil
        }
    }
}

// MARK: - SortingDataSourceWrapper

class SortingDataSourceWrapper: SuggestionLoadingDataSource {
    private let wrappedDataSource: SuggestionLoadingDataSource
    
    init(wrapping dataSource: SuggestionLoadingDataSource) {
        self.wrappedDataSource = dataSource
    }
    
    var platform: Platform {
        return wrappedDataSource.platform
    }
    
    func bookmarks(for suggestionLoading: SuggestionLoading) -> [Suggestions.Bookmark] {
        // Get bookmarks from the wrapped data source and sort them for consistent results
        let originalBookmarks = wrappedDataSource.bookmarks(for: suggestionLoading)
        
        // Sort by URL then by title for deterministic results
        return originalBookmarks.sorted { first, second in
            if first.url == second.url {
                return first.title < second.title
            }
            return first.url < second.url
        }
    }
    
    func history(for suggestionLoading: SuggestionLoading) -> [HistorySuggestion] {
        return wrappedDataSource.history(for: suggestionLoading)
    }
    
    func internalPages(for suggestionLoading: SuggestionLoading) -> [InternalPage] {
        return wrappedDataSource.internalPages(for: suggestionLoading)
    }
    
    func openTabs(for suggestionLoading: SuggestionLoading) -> [BrowserTab] {
        return wrappedDataSource.openTabs(for: suggestionLoading)
    }
    
    func suggestionLoading(_ suggestionLoading: SuggestionLoading,
                           suggestionDataFromUrl url: URL,
                           withParameters parameters: [String: String],
                           completion: @escaping (Data?, Error?) -> Void) {
        wrappedDataSource.suggestionLoading(suggestionLoading,
                                            suggestionDataFromUrl: url,
                                            withParameters: parameters,
                                            completion: completion)
    }
}

// swiftlint:enable force_try identifier_name
