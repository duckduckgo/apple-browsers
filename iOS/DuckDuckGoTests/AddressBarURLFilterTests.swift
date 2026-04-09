//
//  AddressBarURLFilterTests.swift
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

import Common
import Foundation
import Testing

@testable import DuckDuckGo

@Suite("AddressBarURLFilter")
struct AddressBarURLFilterTests {

    // MARK: - User-initiated navigations

    @Test("User-initiated navigation always updates address bar")
    func whenUserInitiatedThenShouldAlwaysUpdate() {
        // GIVEN
        var filter = AddressBarURLFilter()
        filter.commitNavigation(for: URL(string: "https://example.com")!)
        filter.beginUserNavigation()

        // WHEN
        let differentOrigin = URL(string: "https://other.com/page")!
        let result = filter.shouldUpdate(for: differentOrigin)

        // THEN
        #expect(result == true)
    }

    @Test("User reload updates address bar without clearing committed origin")
    func whenUserReloadThenShouldUpdateAndPreserveOrigin() {
        // GIVEN
        var filter = AddressBarURLFilter()
        filter.commitNavigation(for: URL(string: "https://example.com")!)
        filter.beginUserReload()

        // WHEN
        let sameOrigin = URL(string: "https://example.com/reloaded")!
        let result = filter.shouldUpdate(for: sameOrigin)

        // THEN
        #expect(result == true)
        #expect(filter.committedSecurityOrigin != nil)
    }

    // MARK: - Cross-origin redirect filtering

    @Test("Cross-origin redirect is blocked when committed origin exists")
    func whenCrossOriginRedirectThenShouldBlock() {
        // GIVEN
        var filter = AddressBarURLFilter()
        filter.commitNavigation(for: URL(string: "https://duckduckgo.com")!)

        // WHEN
        let redirect = URL(string: "https://bing.com/redirect?target=shop.com")!
        let result = filter.shouldUpdate(for: redirect)

        // THEN
        #expect(result == false)
    }

    @Test("Same-origin URL update is allowed")
    func whenSameOriginUpdateThenShouldAllow() {
        // GIVEN
        var filter = AddressBarURLFilter()
        filter.commitNavigation(for: URL(string: "https://example.com")!)

        // WHEN
        let sameOrigin = URL(string: "https://example.com/new-page")!
        let result = filter.shouldUpdate(for: sameOrigin)

        // THEN
        #expect(result == true)
    }

    @Test("Same-origin with fragment (hash link) is allowed")
    func whenSameOriginFragmentThenShouldAllow() {
        // GIVEN
        var filter = AddressBarURLFilter()
        filter.commitNavigation(for: URL(string: "https://example.com/page")!)

        // WHEN
        let fragment = URL(string: "https://example.com/page#section")!
        let result = filter.shouldUpdate(for: fragment)

        // THEN
        #expect(result == true)
    }

    @Test("Different port is treated as different origin")
    func whenDifferentPortThenShouldBlock() {
        // GIVEN
        var filter = AddressBarURLFilter()
        filter.commitNavigation(for: URL(string: "https://example.com")!)

        // WHEN
        let differentPort = URL(string: "https://example.com:8443/page")!
        let result = filter.shouldUpdate(for: differentPort)

        // THEN
        #expect(result == false)
    }

    @Test("Different scheme is treated as different origin")
    func whenDifferentSchemeThenShouldBlock() {
        // GIVEN
        var filter = AddressBarURLFilter()
        filter.commitNavigation(for: URL(string: "https://example.com")!)

        // WHEN
        let httpURL = URL(string: "http://example.com/page")!
        let result = filter.shouldUpdate(for: httpURL)

        // THEN
        #expect(result == false)
    }

    // MARK: - Custom URL schemes

    @Test("Custom URL schemes always update address bar")
    func whenCustomURLSchemeThenShouldAlwaysUpdate() {
        // GIVEN
        var filter = AddressBarURLFilter()
        filter.commitNavigation(for: URL(string: "https://example.com")!)

        // WHEN/THEN
        #expect(filter.shouldUpdate(for: URL(string: "about:blank")!) == true)
        #expect(filter.shouldUpdate(for: URL(string: "duck://settings")!) == true)
        #expect(filter.shouldUpdate(for: URL(string: "file:///path/to/file")!) == true)
    }

    // MARK: - No committed origin

    @Test("Blocks update when no committed origin exists")
    func whenNoCommittedOriginThenShouldBlock() {
        // GIVEN
        let filter = AddressBarURLFilter()

        // WHEN/THEN
        let anyURL = URL(string: "https://example.com/page")!
        #expect(filter.shouldUpdate(for: anyURL) == false)
        #expect(filter.shouldUpdate(for: anyURL) == false)
    }

    // MARK: - Lifecycle

    @Test("commitNavigation sets origin and resets user-initiated flag")
    func whenCommitNavigationThenSetsOriginAndResetsFlag() {
        // GIVEN
        var filter = AddressBarURLFilter()
        filter.beginUserNavigation()

        // WHEN
        filter.commitNavigation(for: URL(string: "https://example.com")!)

        // THEN
        #expect(filter.isUserInitiatedNavigation == false)
        #expect(filter.committedSecurityOrigin == URL(string: "https://example.com")!.securityOrigin)
    }

    @Test("beginUserNavigation sets flag and clears origin")
    func whenBeginUserNavigationThenSetsFlagAndClearsOrigin() {
        // GIVEN
        var filter = AddressBarURLFilter()
        filter.commitNavigation(for: URL(string: "https://example.com")!)

        // WHEN
        filter.beginUserNavigation()

        // THEN
        #expect(filter.isUserInitiatedNavigation == true)
        #expect(filter.committedSecurityOrigin == nil)
    }

    // MARK: - Multi-hop redirect chain

    @Test("Multi-hop redirect chain blocks all intermediate URLs")
    func whenMultiHopRedirectThenBlocksAllIntermediateURLs() {
        // GIVEN
        var filter = AddressBarURLFilter()
        filter.commitNavigation(for: URL(string: "https://duckduckgo.com")!)

        // WHEN/THEN
        let hop1 = URL(string: "https://search-company.site/y.js?u=something")!
        #expect(filter.shouldUpdate(for: hop1) == false)

        let hop2 = URL(string: "https://ad-company.site/aclick?ID=1")!
        #expect(filter.shouldUpdate(for: hop2) == false)

        let hop3 = URL(string: "https://bing.com/redirect?target=shop.com")!
        #expect(filter.shouldUpdate(for: hop3) == false)

        // Final destination commits
        filter.commitNavigation(for: URL(string: "https://shop.com/product")!)
        let finalURL = URL(string: "https://shop.com/product")!
        #expect(filter.shouldUpdate(for: finalURL) == true)
    }

    // MARK: - Local network domains

    @Test("Local network domain works correctly with security origin filtering")
    func whenLocalNetworkDomainThenFilterWorksCorrectly() {
        // GIVEN
        var filter = AddressBarURLFilter()
        filter.commitNavigation(for: URL(string: "http://somehost.local")!)

        // WHEN/THEN
        let sameDomain = URL(string: "http://somehost.local/page")!
        #expect(filter.shouldUpdate(for: sameDomain) == true)

        let differentDomain = URL(string: "http://otherhost.local/page")!
        #expect(filter.shouldUpdate(for: differentDomain) == false)
    }

    @Test("Local network domain with non-standard port")
    func whenLocalNetworkDomainWithPortThenFilterWorksCorrectly() {
        // GIVEN
        var filter = AddressBarURLFilter()
        filter.commitNavigation(for: URL(string: "http://somehost.local:8080")!)

        // WHEN/THEN
        let samePort = URL(string: "http://somehost.local:8080/api")!
        #expect(filter.shouldUpdate(for: samePort) == true)

        let differentPort = URL(string: "http://somehost.local:9090/api")!
        #expect(filter.shouldUpdate(for: differentPort) == false)
    }
}
