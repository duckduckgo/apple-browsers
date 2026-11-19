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
@_spi(Testing) import Persistence
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

    func testFindFlagsAreDefaultDisabledAndRemotelyConfigurable() {
        for flag in [FeatureFlag.legacyFindInPage, .legacyFindInPageUIWithSystemFindEngine] {
            guard case .disabled = flag.defaultValue else {
                XCTFail("Expected disabled default for \(flag.rawValue)")
                continue
            }
            guard case let .remoteReleasable(subfeature) = flag.source else {
                XCTFail("Expected remote source for \(flag.rawValue)")
                continue
            }
            XCTAssertEqual(subfeature.parent, .iOSBrowserConfig)
            XCTAssertEqual(subfeature.rawValue, flag.rawValue)
        }
    }

    func testClassicLayoutAppliesAndRestoresExperimentalFindInsets() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Experiment targets iOS 27") }
        let tab = try await makeTabWithUserScripts(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []),
                                                 implementation: .delegateSessionExperiment)
        defer { tab.prepareForDataClearing() }
        let chrome = DuckPlayerBrowserChromeDelegateMock()
        tab.chromeDelegate = chrome
        let scrollView = tab.webView.scrollView
        let originalAdjustment = scrollView.contentInsetAdjustmentBehavior
        let originalIndicatorAdjustment = scrollView.automaticallyAdjustsScrollIndicatorInsets
        tab.requestFindInPage()

        for bottom in [CGFloat(390), 120, 440] {
            let insets = UIEdgeInsets(top: 0, left: 0, bottom: bottom, right: 0)
            chrome.findInPageInsets = insets
            tab.updateWebViewLayoutForKeyboard()
            XCTAssertEqual(tab.webView.obscuredContentInsets, insets)
            XCTAssertEqual(scrollView.contentInset, insets)
            XCTAssertEqual(scrollView.verticalScrollIndicatorInsets, insets)
            XCTAssertEqual(scrollView.contentInsetAdjustmentBehavior, .never)
        }

        tab.endCustomFindInPage()
        chrome.findInPageInsets = nil
        tab.updateWebViewLayoutForKeyboard()
        XCTAssertEqual(tab.webView.obscuredContentInsets, .zero)
        XCTAssertEqual(scrollView.contentInset, .zero)
        XCTAssertEqual(scrollView.contentInsetAdjustmentBehavior, originalAdjustment)
        XCTAssertEqual(scrollView.automaticallyAdjustsScrollIndicatorInsets, originalIndicatorAdjustment)
    }

    func testSystemEngineRequiresBothFlags() {
        for flags in findFlagStates {
            let flagger = MockFeatureFlagger(enabledFeatureFlags: flags)
            let expected: FindInPageImplementation
            if #available(iOS 27.0, *), flags.count == 2 {
                expected = .delegateSessionExperiment
            } else {
                expected = flags.contains(.legacyFindInPage) ? .legacy : .system
            }
            XCTAssertEqual(FindInPageImplementation(featureFlagger: flagger), expected, "Flags: \(flags)")
        }
    }

    func testDelegateExperimentPreservesEachTabsQueryIncludingExplicitlyEmptyAcrossSessions() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Experiment targets iOS 27") }
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [])
        let first = try await makeTabWithUserScripts(featureFlagger: flagger, implementation: .delegateSessionExperiment)
        let second = try await makeTabWithUserScripts(featureFlagger: flagger, implementation: .delegateSessionExperiment)
        defer { first.prepareForDataClearing(); second.prepareForDataClearing() }
        let originalWebView = first.webView
        XCTAssertNil(first.userScripts?.findInPageScript)
        first.requestFindInPage()
        let originalSession = try XCTUnwrap(first.customFindInPage)
        XCTAssertTrue(originalSession is DelegateSessionFindInPage)
        XCTAssertTrue(first.webView === originalWebView)
        XCTAssertNil(first.findInPage)
        XCTAssertFalse(first.webView.findInteraction?.isFindNavigatorVisible ?? true)
        _ = originalSession.search(forText: "first query")
        second.requestFindInPage()
        _ = second.customFindInPage?.search(forText: "second query")

        first.endCustomFindInPage()
        (first.webView as? WebView)?.lastFindInPageQuery = "native-only query"
        first.requestFindInPage()
        XCTAssertFalse(first.customFindInPage === originalSession)
        XCTAssertEqual(first.customFindInPage?.searchTerm, "first query")
        XCTAssertEqual(second.customFindInPage?.searchTerm, "second query")
        _ = first.customFindInPage?.search(forText: "")
        first.endCustomFindInPage()
        first.requestFindInPage()
        XCTAssertEqual(first.customFindInPage?.searchTerm, "")
        XCTAssertEqual(first.delegateSessionFindInPageQuery, "")
        XCTAssertEqual(second.delegateSessionFindInPageQuery, "second query")
    }

    func testFindFlagChangesKeepLaunchImplementationAndScripts() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Experiment targets iOS 27") }
        for initialFlags in findFlagStates {
            for updatedFlags in findFlagStates {
                let flagger = MockFeatureFlagger(enabledFeatureFlags: initialFlags)
                let implementation = FindInPageImplementation(featureFlagger: flagger)
                let content = PassthroughSubject<ContentBlockingUpdating.NewContent, Never>()
                let tab = try await makeTabWithUserScripts(featureFlagger: flagger, content: content)
                defer { tab.prepareForDataClearing() }
                let controller = try XCTUnwrap(tab.webView.configuration.userContentController as? UserContentController)
                let updated = expectation(description: "Scripts updated after Find flags change")
                let subscription = controller.$contentBlockingAssets.dropFirst().compactMap { $0 }.first().sink { _ in updated.fulfill() }
                defer { subscription.cancel() }

                flagger.enabledFeatureFlags = updatedFlags
                flagger.triggerUpdate()
                content.send(makeContent())
                await fulfillment(of: [updated], timeout: 10)

                XCTAssertEqual(tab.findInPageImplementation, implementation)
                XCTAssertEqual(tab.userScripts?.findInPageScript != nil, implementation == .legacy)
                tab.requestFindInPage()
                XCTAssertEqual(tab.customFindInPage is DelegateSessionFindInPage, implementation == .delegateSessionExperiment)
                XCTAssertEqual(tab.findInPage != nil, implementation == .legacy)
                XCTAssertEqual(tab.webView.isFindInteractionEnabled, implementation != .legacy)
            }
        }
    }

    func testDelegateExperimentEndsOnReloadAndTabDetachAndCanRestart() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Experiment targets iOS 27") }
        let tab = try await makeTabWithUserScripts(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []),
                                                 implementation: .delegateSessionExperiment)
        defer { tab.prepareForDataClearing() }
        tab.requestFindInPage()
        _ = tab.customFindInPage?.search(forText: "retained")
        tab.reload()
        XCTAssertNil(tab.customFindInPage)
        tab.requestFindInPage()
        XCTAssertEqual(tab.customFindInPage?.searchTerm, "retained")
        tab.dismiss()
        XCTAssertNil(tab.customFindInPage)
        XCTAssertEqual(tab.delegateSessionFindInPageQuery, "retained")
        tab.requestFindInPage()
        tab.prepareForDataClearing()
        XCTAssertNil(tab.customFindInPage)
    }

    func testDelegateExperimentEndsBeforeReplacingWebViewAndRetainsTheModelQuery() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Experiment targets iOS 27") }
        let tab = try await makeTabWithUserScripts(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []),
                                                 implementation: .delegateSessionExperiment)
        defer { tab.prepareForDataClearing() }
        let oldWebView = try XCTUnwrap(tab.webView)
        tab.requestFindInPage()
        _ = tab.customFindInPage?.search(forText: "retained")

        tab.attachWebView(configuration: WKWebViewConfiguration(), andLoadRequest: nil, consumeCookies: false)

        XCTAssertFalse(tab.webView === oldWebView)
        XCTAssertNil(tab.customFindInPage)
        XCTAssertFalse(oldWebView.isFindInteractionEnabled)
        XCTAssertEqual(tab.tabModel.delegateSessionFindInPageQuery, "retained")
        tab.requestFindInPage()
        XCTAssertEqual(tab.customFindInPage?.searchTerm, "retained")
        XCTAssertFalse(tab.webView.findInteraction?.isFindNavigatorVisible ?? true)
        let replacementSession = tab.customFindInPage
        let delegate = MockTabDelegate()
        tab.delegate = delegate
        tab.webViewWebContentProcessDidTerminate(oldWebView)
        XCTAssertTrue(tab.customFindInPage === replacementSession)
        XCTAssertEqual(delegate.contentProcessTerminationCount, 0)
        tab.webViewWebContentProcessDidTerminate(tab.webView)
        XCTAssertNil(tab.customFindInPage)
        XCTAssertEqual(delegate.contentProcessTerminationCount, 1)
        XCTAssertEqual(tab.delegateSessionFindInPageQuery, "retained")
    }

    private var findFlagStates: [[FeatureFlag]] {
        [[], [.legacyFindInPage], [.legacyFindInPageUIWithSystemFindEngine], [.legacyFindInPage, .legacyFindInPageUIWithSystemFindEngine]]
    }

    private func makeTabWithUserScripts(
        featureFlagger: MockFeatureFlagger,
        content: PassthroughSubject<ContentBlockingUpdating.NewContent, Never> = .init(),
        pixelFiring: any PixelKitFiring = PixelKitMock(),
        implementation: FindInPageImplementation? = nil
    ) async throws -> TabViewController {
        let tab = TabViewController.fake(featureFlagger: featureFlagger,
                                        findInPageImplementation: implementation ?? FindInPageImplementation(featureFlagger: featureFlagger),
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
              duckAiNativeStorageHandler: nil,
              sponsorBlockPreferences: SponsorBlockPreferences(store: InMemoryKeyValueStore()))
    }
}
