//
//  SearchURLBuilderTests.swift
//  DuckDuckGo
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

import CustomDump
import Foundation
import Testing
@testable import AppRouting

@Suite("Search URL Builder")
struct SearchURLBuilderTests {

    @Test("The default and overridden search bases match Core's environment behavior")
    func whenSearchBaseIsResolvedThenTheEnvironmentOverrideOrDefaultIsUsed() {
        expectNoDifference(SearchURLDefaults.searchBaseURL(environment: [:]).absoluteString, "https://duckduckgo.com")
        expectNoDifference(
            SearchURLDefaults.searchBaseURL(environment: ["BASE_URL": "http://127.0.0.1:8080"]).absoluteString,
            "http://127.0.0.1:8080"
        )
    }

    @Test("Queries preserve byte-sensitive encoding and parameter order")
    func whenSearchURLIsBuiltThenTheQueryIsEncodedExactly() throws {
        let baseURL = try #require(URL(string: "https://duckduckgo.com"))
        let builder = SearchURLBuilder(searchBaseURL: baseURL, isPad: false)

        let url = builder.makeSearchURL(query: "a+b / c&d", forceSearchQuery: true)

        expectNoDifference(url?.absoluteString, "https://duckduckgo.com/?q=a%2Bb+%2F+c%26d&t=ddg_ios")
    }

    @Test("Search bases with and without a trailing slash produce the same URL")
    func whenSearchBaseTrailingSlashVariesThenOutputIsStable() throws {
        let baseURLs = try ["http://127.0.0.1:8080", "http://127.0.0.1:8080/"]
            .map { try #require(URL(string: $0)) }
        let urls = baseURLs.map {
            SearchURLBuilder(searchBaseURL: $0, isPad: false)
                .makeSearchURL(query: "query", forceSearchQuery: true)?
                .absoluteString
        }

        expectNoDifference(
            urls,
            ["http://127.0.0.1:8080/?q=query&t=ddg_ios", "http://127.0.0.1:8080/?q=query&t=ddg_ios"].map(Optional.some)
        )
    }

    @Test("Phone and tablet searches use their established source values")
    func whenFormFactorChangesThenTheSourceParameterChanges() throws {
        let baseURL = try #require(URL(string: "https://duckduckgo.com"))
        let phoneURL = SearchURLBuilder(searchBaseURL: baseURL, isPad: false)
            .makeSearchURL(query: "query", forceSearchQuery: true)
        let tabletURL = SearchURLBuilder(searchBaseURL: baseURL, isPad: true)
            .makeSearchURL(query: "query", forceSearchQuery: true)

        expectNoDifference(phoneURL?.absoluteString, "https://duckduckgo.com/?q=query&t=ddg_ios")
        expectNoDifference(tabletURL?.absoluteString, "https://duckduckgo.com/?q=query&t=ddg_ios_tablet")
    }

    @Test("Attribution is optional and evaluated for every search")
    func whenAttributionChangesThenEachSearchUsesTheLatestValue() throws {
        let baseURL = try #require(URL(string: "https://duckduckgo.com"))
        var attribution: String?
        let builder = SearchURLBuilder(searchBaseURL: baseURL, isPad: false) { attribution }

        let urlWithoutAttribution = builder.makeSearchURL(query: "query", forceSearchQuery: true)
        attribution = "v123-4ru"
        let urlWithAttribution = builder.makeSearchURL(query: "query", forceSearchQuery: true)

        expectNoDifference(urlWithoutAttribution?.absoluteString, "https://duckduckgo.com/?q=query&t=ddg_ios")
        expectNoDifference(urlWithAttribution?.absoluteString, "https://duckduckgo.com/?q=query&t=ddg_ios&atb=v123-4ru")
    }

    @Test("Direct navigation bypasses attribution and force-search overrides classification")
    func whenDomainLikeInputIsUsedThenForceSearchControlsTheResult() throws {
        let baseURL = try #require(URL(string: "https://duckduckgo.com"))
        var attributionRequests = 0
        let builder = SearchURLBuilder(searchBaseURL: baseURL, isPad: false) {
            attributionRequests += 1
            return "v123-4ru"
        }

        let navigationURL = builder.makeSearchURL(query: "example.com")
        expectNoDifference(navigationURL?.absoluteString, "http://example.com")
        expectNoDifference(attributionRequests, 0)

        let searchURL = builder.makeSearchURL(query: "example.com", forceSearchQuery: true)
        expectNoDifference(searchURL?.absoluteString, "https://duckduckgo.com/?q=example.com&t=ddg_ios&atb=v123-4ru")
        expectNoDifference(attributionRequests, 1)
    }

    @Test("Abbreviated IPv4 is searched while four-octet IPv4 navigates")
    func whenIPv4OctetCountVariesThenClassificationIsPreserved() throws {
        let baseURL = try #require(URL(string: "https://duckduckgo.com"))
        let builder = SearchURLBuilder(searchBaseURL: baseURL, isPad: false)

        let abbreviatedIPv4 = builder.makeSearchURL(query: "1.4")
        let abbreviatedIPv4WithPath = builder.makeSearchURL(query: "1.4/3.4")
        let singleNumberWithPath = builder.makeSearchURL(query: "4/3.4")
        let fourOctetIPv4 = builder.makeSearchURL(query: "1.0.0.4/3.4")

        expectNoDifference(abbreviatedIPv4?.absoluteString, "https://duckduckgo.com/?q=1.4&t=ddg_ios")
        expectNoDifference(abbreviatedIPv4WithPath?.absoluteString, "https://duckduckgo.com/?q=1.4%2F3.4&t=ddg_ios")
        expectNoDifference(singleNumberWithPath?.absoluteString, "https://duckduckgo.com/?q=4%2F3.4&t=ddg_ios")
        expectNoDifference(fourOctetIPv4?.absoluteString, "http://1.0.0.4/3.4")
    }

    @Test("Major vertical contexts are rewritten")
    func whenContextUsesAMajorVerticalThenItIsAppliedToTheNewSearch() throws {
        let baseURL = try #require(URL(string: "https://duckduckgo.com"))
        let builder = SearchURLBuilder(searchBaseURL: baseURL, isPad: false)
        let contexts = try ["images", "videos", "news"].map {
            try #require(URL(string: "https://duckduckgo.com/?q=old&ia=\($0)"))
        }
        let urls = contexts.map {
            builder.makeSearchURL(query: "query", forceSearchQuery: true, queryContext: $0)?.absoluteString
        }
        let expected = ["images", "videos", "news"].map {
            Optional("https://duckduckgo.com/?q=query&iar=\($0)&t=ddg_ios")
        }

        expectNoDifference(urls, expected)
    }

    @Test("Maps, unsupported verticals, and non-search contexts are not rewritten")
    func whenContextIsNotEligibleThenNoVerticalIsApplied() throws {
        let baseURL = try #require(URL(string: "https://duckduckgo.com"))
        let builder = SearchURLBuilder(searchBaseURL: baseURL, isPad: false)
        let contexts = try [
            "https://duckduckgo.com/?q=old&ia=images&iaxm=maps",
            "https://duckduckgo.com/?q=old&ia=maps",
            "https://duckduckgo.com/?ia=images",
            "https://example.com/?q=old&ia=images"
        ].map { try #require(URL(string: $0)) }
        let urls = contexts.map {
            builder.makeSearchURL(query: "query", forceSearchQuery: true, queryContext: $0)?.absoluteString
        }

        expectNoDifference(urls, Array(repeating: Optional("https://duckduckgo.com/?q=query&t=ddg_ios"), count: contexts.count))
    }

    @Test("An injected base controls vertical-context recognition")
    func whenSearchBaseIsInjectedThenItsDomainDefinesSearchContexts() throws {
        let baseURL = try #require(URL(string: "https://search.example"))
        let context = try #require(URL(string: "https://www.search.example/?q=old&ia=news"))
        let builder = SearchURLBuilder(searchBaseURL: baseURL, isPad: false)

        let url = builder.makeSearchURL(query: "query", forceSearchQuery: true, queryContext: context)

        expectNoDifference(url?.absoluteString, "https://search.example/?q=query&iar=news&t=ddg_ios")
    }

    @Test("Existing source and attribution parameters are replaced")
    func whenParametersAlreadyExistThenTheyAreReplacedInOrder() throws {
        let baseURL = try #require(URL(string: "https://duckduckgo.com"))
        let input = try #require(URL(string: "https://duckduckgo.com/?q=query&t=wrong&atb=old&other=1"))
        let builder = SearchURLBuilder(searchBaseURL: baseURL, isPad: true) { "v123-4ru" }

        let url = builder.applyingSourceAndAttributionParameters(to: input)

        expectNoDifference(url.absoluteString, "https://duckduckgo.com/?q=query&other=1&t=ddg_ios_tablet&atb=v123-4ru")
        #expect(builder.hasExpectedSourceAndAttributionParameters(in: url))
    }

    @Test("Existing attribution is removed when no attribution is available")
    func whenAttributionBecomesUnavailableThenTheExistingValueIsRemoved() throws {
        let baseURL = try #require(URL(string: "https://duckduckgo.com"))
        let input = try #require(URL(string: "https://duckduckgo.com/?q=query&t=wrong&atb=old&other=1"))
        let builder = SearchURLBuilder(searchBaseURL: baseURL, isPad: false)

        let url = builder.applyingSourceAndAttributionParameters(to: input)

        expectNoDifference(url.absoluteString, "https://duckduckgo.com/?q=query&other=1&t=ddg_ios")
        #expect(url.getParameter(named: "atb") == nil)
        #expect(builder.hasExpectedSourceAndAttributionParameters(in: url))
    }
}
