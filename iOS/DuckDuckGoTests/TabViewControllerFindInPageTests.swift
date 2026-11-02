//
//  TabViewControllerFindInPageTests.swift
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

import BrowserServicesKit
import Combine
import FeatureFlags_iOS
import WebKit
import XCTest
@_spi(Testing) import PixelKit

@testable import DuckDuckGo

@available(iOS 16.0, *)
@MainActor
final class TabViewControllerFindInPageTests: XCTestCase {

    func testWhenFindInPageIsRequestedThenFiresDailyUsagePixelWithoutSearchData() async throws {
        for legacyEnabled in [false, true] {
            let pixelFiring = PixelKitMock()
            let flagger = MockFeatureFlagger(enabledFeatureFlags: legacyEnabled ? [.legacyFindInPage] : [])
            let tab = try await makeTabWithUserScripts(featureFlagger: flagger, pixelFiring: pixelFiring)
            defer { tab.prepareForDataClearing() }
            if legacyEnabled {
                tab.findInPage = FindInPage(webView: tab.webView)
                tab.findInPage?.searchTerm = "private search"
            } else {
                (tab.webView as? WebView)?.lastFindInPageQuery = "private search"
            }

            tab.requestFindInPage()

            let calls = pixelFiring.actualFireCalls.filter { $0.pixel is FindInPagePixel }
            XCTAssertEqual(calls, [ExpectedFireCall(pixel: FindInPagePixel.opened, frequency: .daily)])
            XCTAssertNil(calls.first?.pixel.parameters)
            XCTAssertNil(calls.first?.pixel.standardParameters)
            XCTAssertNil(calls.first?.additionalParameters)
        }
    }

    func testWhenLegacyFlagIsDisabledThenUsesSystemSearchAndRestoresTheTabQuery() async throws {
        let tab = try await makeTabWithUserScripts(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []))
        defer { tab.prepareForDataClearing() }
        let scripts = try XCTUnwrap(tab.userScripts)
        XCTAssertNil(scripts.findInPageScript)
        XCTAssertFalse(scripts.userScripts.contains { $0 is FindInPageUserScript })
        (tab.webView as? WebView)?.lastFindInPageQuery = "previous search"

        tab.requestFindInPage()

        XCTAssertTrue(tab.webView.isFindInteractionEnabled)
        XCTAssertEqual(tab.webView.findInteraction?.searchText, "previous search")
        XCTAssertNil(tab.findInPage)
    }

    func testWhenLegacyFlagIsEnabledThenUsesCustomSearchAndPreservesAnActiveSearch() async throws {
        let tab = try await makeTabWithUserScripts(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.legacyFindInPage]))
        defer { tab.prepareForDataClearing() }
        let scripts = try XCTUnwrap(tab.userScripts)
        let script = try XCTUnwrap(scripts.findInPageScript)
        XCTAssertTrue(scripts.userScripts.contains { $0 === script })

        tab.requestFindInPage()

        let findInPage = try XCTUnwrap(tab.findInPage)
        XCTAssertTrue(findInPage.webView === tab.webView)
        XCTAssertFalse(tab.webView.isFindInteractionEnabled)
        findInPage.searchTerm = "in-progress search"

        tab.requestFindInPage()

        XCTAssertTrue(tab.findInPage === findInPage)
        XCTAssertEqual(tab.findInPage?.searchTerm, "in-progress search")
    }

    func testWhenFlagChangesDuringTheSessionThenTabsAndUpdatedScriptsKeepTheLaunchImplementation() async throws {
        for legacyEnabledAtLaunch in [false, true] {
            let flagger = MockFeatureFlagger(enabledFeatureFlags: legacyEnabledAtLaunch ? [.legacyFindInPage] : [])
            let content = PassthroughSubject<ContentBlockingUpdating.NewContent, Never>()
            let tab = try await makeTabWithUserScripts(featureFlagger: flagger, content: content)
            defer { tab.prepareForDataClearing() }
            let controller = try XCTUnwrap(tab.webView.configuration.userContentController as? UserContentController)
            let updated = expectation(description: "Scripts updated after flag change")
            let subscription = controller.$contentBlockingAssets.dropFirst().compactMap { $0 }.first().sink { _ in updated.fulfill() }
            defer { subscription.cancel() }

            flagger.enabledFeatureFlags = legacyEnabledAtLaunch ? [] : [.legacyFindInPage]
            flagger.triggerUpdate()
            content.send(makeContent())
            await fulfillment(of: [updated], timeout: 10)

            let scripts = try XCTUnwrap(tab.userScripts)
            XCTAssertEqual(scripts.findInPageScript != nil, legacyEnabledAtLaunch)
            XCTAssertEqual(tab.findInPageImplementation, legacyEnabledAtLaunch ? .legacy : .system)
            tab.requestFindInPage()
            XCTAssertEqual(tab.webView.isFindInteractionEnabled, !legacyEnabledAtLaunch)
            XCTAssertEqual(tab.findInPage != nil, legacyEnabledAtLaunch)
            XCTAssertEqual(FindInPageImplementation(featureFlagger: flagger), legacyEnabledAtLaunch ? .system : .legacy)
        }
    }

    private func makeTabWithUserScripts(
        featureFlagger: MockFeatureFlagger,
        content: PassthroughSubject<ContentBlockingUpdating.NewContent, Never> = .init(),
        pixelFiring: any PixelKitFiring = PixelKitMock()
    ) async throws -> TabViewController {
        let tab = TabViewController.fake(featureFlagger: featureFlagger,
                                        findInPageImplementation: FindInPageImplementation(featureFlagger: featureFlagger),
                                        contentBlockingAssetsPublisher: content.eraseToAnyPublisher(), pixelFiring: pixelFiring)
        let controller = try XCTUnwrap(tab.webView.configuration.userContentController as? UserContentController)
        let installed = expectation(description: "User scripts installed")
        let subscription = controller.$contentBlockingAssets.compactMap { $0 }.first().sink { _ in installed.fulfill() }
        defer { subscription.cancel() }

        content.send(makeContent())
        await fulfillment(of: [installed], timeout: 10)
        return tab
    }

    private func makeContent() -> ContentBlockingUpdating.NewContent {
        .init(rulesUpdate: .init(rules: [], changes: [:], completionTokens: []),
              sourceProvider: DefaultScriptSourceProvider(dependencies: .makeMock()),
              duckAiNativeStorageHandler: nil)
    }
}
