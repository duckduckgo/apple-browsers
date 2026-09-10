//
//  WindowControllersManagerBrowsingBeforeCompletionTests.swift
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

import FeatureFlags_macOS
import Navigation
@_spi(Testing) import PixelKit
import SharedTestUtilities
import XCTest

@testable import PrivacyConfig
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class WindowControllersManagerBrowsingBeforeCompletionTests: XCTestCase {

    private var firedEvents: [String] = []
    private var pixelDefaults: UserDefaults!
    private var featureFlagger: MockFeatureFlagger!
    private var originalFeatures: [String: Bool] = [:]
    private var originalOnboardingFinished = false
    private var onboardingTab: Tab!
    private var sut: WindowControllersManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        featureFlagger = try XCTUnwrap(Application.appDelegate.featureFlagger as? MockFeatureFlagger)
        originalFeatures = featureFlagger.featuresStub
        originalOnboardingFinished = OnboardingActionsManager.isOnboardingFinished
        featureFlagger.enabledFeatureFlags = [.onboardingAsync]
        OnboardingActionsManager.isOnboardingFinished = false
        sut = Application.appDelegate.windowControllersManager
        onboardingTab = Tab(content: .onboarding)
        sut.setOnboardingTab(onboardingTab)
        sut.setOnboardingHandlers(onClose: { _ in }, onSkipInPlace: {})

        pixelDefaults = UserDefaults(suiteName: UUID().uuidString)!
        PixelKit.setUp(dryRun: false, appVersion: "1.0.0", session: "test", defaultHeaders: [:], defaults: pixelDefaults) { [weak self] name, _, parameters, _, _, completion in
            if name == "m_mac_onboarding_browsing-before-completion_u" {
                XCTAssertNil(parameters["cohort"])
                XCTAssertNil(parameters["enrollmentDate"])
                self?.firedEvents.append(name)
            }
            completion(true, nil)
        }
    }

    override func tearDown() {
        sut?.setOnboardingTab(nil)
        featureFlagger?.featuresStub = originalFeatures
        OnboardingActionsManager.isOnboardingFinished = originalOnboardingFinished
        PixelKit.tearDown()
        pixelDefaults = nil
        onboardingTab = nil
        sut = nil
        featureFlagger = nil
        firedEvents = []
        super.tearDown()
    }

    func testWebNavigationStartsCountWithoutWindowRegistrationOrCompletion() {
        let tab = Tab(content: .newtab)
        startNavigation(in: tab, to: URL(string: "https://example.com")!)
        startNavigation(in: tab, to: URL(string: "http://example.com/next")!)

        XCTAssertEqual(firedEvents, ["m_mac_onboarding_browsing-before-completion_u"])
    }

    func testInternalAndErrorPageLoadsDoNotCount() {
        let tab = Tab(content: .newtab)
        for url in [URL(string: "about:blank")!, URL(string: "duck://onboarding")!, URL(fileURLWithPath: "/tmp/page.html")] {
            startNavigation(in: tab, to: url)
        }
        startNavigation(in: tab, to: URL(string: "https://example.com")!, isErrorPage: true)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func testDoesNotCountAfterNavigatingAwayFromOnboarding() {
        onboardingTab.setContent(.newtab)
        startNavigation(in: onboardingTab, to: URL(string: "https://example.com")!)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func testDoesNotCountAfterOnboardingTabCloses() {
        onboardingTab.onClose?()
        startNavigation(in: Tab(content: .newtab), to: URL(string: "https://example.com")!)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func testDoesNotCountAfterCompletion() {
        OnboardingActionsManager.isOnboardingFinished = true
        startNavigation(in: Tab(content: .newtab), to: URL(string: "https://example.com")!)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func testDoesNotCountAfterQuitCleanupOrBeforeHandlersAreInstalled() {
        sut.setOnboardingTab(nil)
        startNavigation(in: Tab(content: .newtab), to: URL(string: "https://example.com")!)
        sut.setOnboardingTab(onboardingTab)
        startNavigation(in: Tab(content: .newtab), to: URL(string: "https://example.com")!)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    private func startNavigation(in tab: Tab, to url: URL, isErrorPage: Bool = false) {
        let action = NavigationAction(request: URLRequest(url: url),
                                      navigationType: isErrorPage ? .alternateHtmlLoad : .reload,
                                      currentHistoryItemIdentity: nil,
                                      redirectHistory: [],
                                      isUserInitiated: true,
                                      sourceFrame: FrameInfo(frame: .mock()),
                                      targetFrame: nil,
                                      shouldDownload: false,
                                      mainFrameNavigation: nil)
        let navigation = Navigation(identity: NavigationIdentity(nil),
                                    responders: ResponderChain(responderRefs: []),
                                    state: .started,
                                    redirectHistory: [action],
                                    isCurrent: true,
                                    isCommitted: false)
        tab.didStart(navigation)
    }
}
