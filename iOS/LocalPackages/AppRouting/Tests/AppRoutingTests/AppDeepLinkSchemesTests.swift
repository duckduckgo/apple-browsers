//
//  AppDeepLinkSchemesTests.swift
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

@Suite("App Deep Link Schemes")
struct AppDeepLinkSchemesTests {

    @Test("All schemes preserve their raw values and URL round trips")
    func whenAllSchemesAreUsedThenTheirRawValuesAndURLsRoundTrip() {
        let expectedRawValues = [
            "ddgNewSearch",
            "ddgVoiceSearch",
            "ddgFireButton",
            "ddgFavorites",
            "ddgNewEmail",
            "ddgQuickLink",
            "ddgAddFavorite",
            "ddgOpenVPN",
            "ddgOpenPasswords",
            "ddgOpenAIChat",
            "ddgOpenAIVoiceChat",
            "ddgOpenBookmarks",
            "ddgCPP"
        ]

        expectNoDifference(AppDeepLinkSchemes.allCases.map(\.rawValue), expectedRawValues)
        expectNoDifference(
            AppDeepLinkSchemes.allCases.map(\.url.absoluteString),
            expectedRawValues.map { $0 + "://" }
        )
        expectNoDifference(
            AppDeepLinkSchemes.allCases.map { AppDeepLinkSchemes.fromURL($0.url) },
            AppDeepLinkSchemes.allCases.map(Optional.some)
        )
    }

    @Test("Scheme matching is case insensitive")
    func whenSchemeCasingVariesThenTheQuickLinkIsDetected() throws {
        let urls = try ["ddgquicklink://foo.bar", "DDGQUICKLINK://foo.bar", "ddgQuickLink://foo.bar"]
            .map { try #require(URL(string: $0)) }

        expectNoDifference(urls.map { AppDeepLinkSchemes.fromURL($0) }, [.quickLink, .quickLink, .quickLink])
    }

    @Test("Unknown schemes are rejected")
    func whenSchemeIsUnknownThenItIsNotDetected() throws {
        let url = try #require(URL(string: "someOtherType://foo.bar"))
        #expect(AppDeepLinkSchemes.fromURL(url) == nil)
    }

    @Test("Quick-link queries preserve their complete payload")
    func whenQuickLinkQueriesAreExtractedThenTheirPayloadIsPreserved() throws {
        let inputs = [
            "ddgquicklink://foo.bar",
            "DDGQUICKLINK://foo.bar/baz/123?A=b&c=D",
            "ddgQuickLink://foo.bar/baz/123#hello-world?A=b&c=D",
            "ddgquicklink://https://foo.bar",
            "ddgquicklink://https//foo.bar"
        ]
        let urls = try inputs.map { try #require(URL(string: $0)) }
        let expected = [
            "foo.bar",
            "foo.bar/baz/123?A=b&c=D",
            "foo.bar/baz/123#hello-world?A=b&c=D",
            "https://foo.bar",
            "https://foo.bar"
        ]

        expectNoDifference(urls.map { AppDeepLinkSchemes.query(fromQuickLink: $0) }, expected)
    }

    @Test("Non-quick-link queries remain unchanged")
    func whenURLIsNotAQuickLinkThenItsQueryIsUnchanged() throws {
        let url = try #require(URL(string: "someOtherType://foo.bar"))
        expectNoDifference(AppDeepLinkSchemes.query(fromQuickLink: url), "someOtherType://foo.bar")
    }

    @Test("Appending a payload preserves the deep-link scheme")
    func whenPayloadIsAppendedThenTheSchemeIsPreserved() {
        expectNoDifference(AppDeepLinkSchemes.quickLink.appending("https://foo.bar"), "ddgQuickLink://https://foo.bar")
    }
}
