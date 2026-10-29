//
//  TabURLInterceptorTests.swift
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

import XCTest
import BrowserServicesKit
import PrivacyConfig
import Subscription
import SubscriptionTestingUtilities
@testable import DuckDuckGo

class TabURLInterceptorDefaultTests: XCTestCase {

    private var mockInternalUserStoring = MockInternalUserStoring()
    private let performanceOptimizedPaywallPaths = SubscriptionURL.PerformanceOptimizedPaywallPaths(
        vpn: "/subscriptions/v2/vpn",
        duckai: "/subscriptions/v2/duckai",
        pir: "/subscriptions/v2/pir")

    var urlInterceptor: TabURLInterceptorDefault!
    private var performanceOptimizedPaywallsProvider: MockPerformanceOptimizedPaywallsProvider!

    override func setUp() {
        super.setUp()
        mockInternalUserStoring.isInternalUser = false
        let featureFlagger = MockFeatureFlagger(
            internalUserDecider: DefaultInternalUserDecider(store: mockInternalUserStoring))
        performanceOptimizedPaywallsProvider = MockPerformanceOptimizedPaywallsProvider(
            isEnabled: false,
            paths: performanceOptimizedPaywallPaths)
        urlInterceptor = TabURLInterceptorDefault(featureFlagger: featureFlagger,
                                                  performanceOptimizedPaywalls: performanceOptimizedPaywallsProvider,
                                                  canPurchase: { true })
    }
    
    override func tearDown() {
        urlInterceptor = nil
        super.tearDown()
    }
    
    func testAllowsNavigationForNonDuckDuckGoDomain() {
        let url = URL(string: "https://www.example.com")!
        XCTAssertTrue(urlInterceptor.allowsNavigatingTo(url: url))
    }
    
    func testAllowsNavigationForUninterceptedDuckDuckGoPath() {
        let url = URL(string: "https://duckduckgo.com/about")!
        XCTAssertTrue(urlInterceptor.allowsNavigatingTo(url: url))
    }

    func testUninterceptedDuckDuckGoPathDoesNotReadPerformanceOptimizedPaywallPaths() {
        let url = URL(string: "https://duckduckgo.com/?q=privacy")!

        XCTAssertTrue(urlInterceptor.allowsNavigatingTo(url: url))
        XCTAssertEqual(performanceOptimizedPaywallsProvider.pathsAccessCount, 0)
    }
    
    func testNotificationForInterceptedSubscriptionPath() {
        _ = self.expectation(forNotification: .urlInterceptSubscription, object: nil, handler: nil)

        let url = URL(string: "https://duckduckgo.com/subscriptions")!
        let canNavigate = urlInterceptor.allowsNavigatingTo(url: url)

        // Fail if no note is posted
        XCTAssertFalse(canNavigate)

        waitForExpectations(timeout: 1) { error in
            if let error = error {
                XCTFail("Notification expectation failed: \(error)")
            }
        }
    }

    func testNotificationForInterceptedLegacyProPath() {
        _ = self.expectation(forNotification: .urlInterceptSubscription, object: nil, handler: nil)

        let url = URL(string: "https://duckduckgo.com/pro")!
        let canNavigate = urlInterceptor.allowsNavigatingTo(url: url)

        XCTAssertFalse(canNavigate)

        waitForExpectations(timeout: 1) { error in
            if let error = error {
                XCTFail("Notification expectation failed: \(error)")
            }
        }
    }

    func testNotificationForInterceptedLegacyProPlansPath() {
        _ = self.expectation(forNotification: .urlInterceptSubscription, object: nil, handler: nil)

        let url = URL(string: "https://duckduckgo.com/pro/plans")!
        let canNavigate = urlInterceptor.allowsNavigatingTo(url: url)

        XCTAssertFalse(canNavigate)

        waitForExpectations(timeout: 1) { error in
            if let error = error {
                XCTFail("Notification expectation failed: \(error)")
            }
        }
    }

    func testWhenURLIsSubscriptionAndHasOriginQueryParameterThenNotificationUserInfoHasOriginSet() throws {
        // GIVEN
        var capturedNotification: Notification?
        _ = self.expectation(forNotification: .urlInterceptSubscription, object: nil, handler: { notification in
            capturedNotification = notification
            return true
        })
        let url = try XCTUnwrap(URL(string: "https://duckduckgo.com/subscriptions?origin=test_origin"))
        
        // WHEN
        _ = urlInterceptor.allowsNavigatingTo(url: url)

        // THEN
        waitForExpectations(timeout: 1)
        let interceptedURLComponents = try XCTUnwrap(capturedNotification?.userInfo?[TabURLInterceptorParameter.interceptedURLComponents] as? URLComponents)
        let originQueryItem = try XCTUnwrap(interceptedURLComponents.queryItems?.first { $0.name == AttributionParameter.origin })
        XCTAssertEqual(originQueryItem.value, "test_origin")
    }

    func testWhenURLIsSubscriptionAndDoesNotHaveOriginQueryParameterThenNotificationUserInfoDoesNotHaveOriginSet() throws {
        // GIVEN
        var capturedNotification: Notification?
        _ = self.expectation(forNotification: .urlInterceptSubscription, object: nil, handler: { notification in
            capturedNotification = notification
            return true
        })
        let url = try XCTUnwrap(URL(string: "https://duckduckgo.com/subscriptions"))

        // WHEN
        _ = urlInterceptor.allowsNavigatingTo(url: url)

        // THEN
        waitForExpectations(timeout: 1)
        let interceptedURLComponents = try XCTUnwrap(capturedNotification?.userInfo?[TabURLInterceptorParameter.interceptedURLComponents] as? URLComponents)
        let originQueryItem = interceptedURLComponents.queryItems?.first { $0.name == AttributionParameter.origin }
        XCTAssertNil(originQueryItem)
    }

    func testWhenURLBelongsToTestDomainAndInternalModeIsDisabledThenNavigationIsNotIntercepted() async throws {
        let notificationExpectation = expectation(forNotification: .urlInterceptSubscription, object: nil, handler: nil)
        notificationExpectation.isInverted = true

        // GIVEN
        let url = URL(string: "https://duck.co/subscriptions")!
        mockInternalUserStoring.isInternalUser = false

        // WHEN
        let canNavigate = urlInterceptor.allowsNavigatingTo(url: url)

        // THEN
        XCTAssertTrue(canNavigate)
        await fulfillment(of: [notificationExpectation], timeout: 0.5)
    }

    func testWhenURLBelongsToTestDomainAndInternalModeIsEnabledThenRedirectTriggers() async throws {
        let notificationExpectation = expectation(forNotification: .urlInterceptSubscription, object: nil, handler: nil)

        // GIVEN
        let url = URL(string: "https://duck.co/subscriptions")!
        mockInternalUserStoring.isInternalUser = true

        // WHEN
        let canNavigate = urlInterceptor.allowsNavigatingTo(url: url)

        // THEN
        XCTAssertFalse(canNavigate)
        await fulfillment(of: [notificationExpectation], timeout: 0.5)
    }

    func testNotificationForInterceptedSubscriptionPlansPath() async {
        let notificationExpectation = expectation(forNotification: .urlInterceptSubscription, object: nil, handler: nil)

        // GIVEN
        let url = URL(string: "https://duck.co/subscriptions/plans")!
        mockInternalUserStoring.isInternalUser = true

        // WHEN
        let canNavigate = urlInterceptor.allowsNavigatingTo(url: url)

        // THEN
        XCTAssertFalse(canNavigate)
        await fulfillment(of: [notificationExpectation], timeout: 0.5)
    }

    func testNotificationForInterceptedSubscriptionUpgradePath() async {
        let notificationExpectation = expectation(forNotification: .urlInterceptSubscription, object: nil, handler: nil)

        // GIVEN
        let url = URL(string: "https://duckduckgo.com/subscriptions/plans?tier=pro")!
        mockInternalUserStoring.isInternalUser = true

        // WHEN
        let canNavigate = urlInterceptor.allowsNavigatingTo(url: url)

        // THEN
        XCTAssertFalse(canNavigate)
        await fulfillment(of: [notificationExpectation], timeout: 0.5)
    }

    func testConfiguredPerformanceOptimizedPaywallPathsAreInterceptedWhenFeatureIsDisabled() throws {
        let testCases: [(path: String, entryPoint: SubscriptionURL.PerformanceOptimizedPaywallEntryPoint)] = [
            (performanceOptimizedPaywallPaths.vpn, .vpn),
            (performanceOptimizedPaywallPaths.duckai, .duckai),
            (performanceOptimizedPaywallPaths.pir, .pir)
        ]

        for testCase in testCases {
            let url = try XCTUnwrap(URL(
                string: "https://duckduckgo.com\(testCase.path)"
                + "?origin=test_origin"
                + "&experiment_mobileannualtrials2_ios=treatment"
                + "&featurePage=stale"))

            let redirectComponents = try interceptedRedirectComponents(for: url)

            XCTAssertEqual(redirectComponents.path, SubscriptionPurchaseFlowPath.purchase.rawValue)
            XCTAssertEqual(redirectComponents.queryItems?.first { $0.name == AttributionParameter.origin }?.value, "test_origin")
            XCTAssertEqual(redirectComponents.queryItems?.first { $0.name == "experiment_mobileannualtrials2_ios" }?.value, "treatment")
            let featurePages = (redirectComponents.queryItems ?? [])
                .filter { $0.name == "featurePage" }
                .compactMap(\.value)
            XCTAssertEqual(featurePages, [testCase.entryPoint.rawValue])
        }
    }

    func testDefaultPerformanceOptimizedPaywallPathIsInterceptedWhenConfiguredPathIsDifferent() throws {
        let url = try XCTUnwrap(URL(string: "https://duckduckgo.com/subscriptions/new/mobile/vpn"))

        let redirectComponents = try interceptedRedirectComponents(for: url)

        XCTAssertEqual(redirectComponents.path, SubscriptionPurchaseFlowPath.purchase.rawValue)
        XCTAssertEqual(redirectComponents.queryItems?.count, 1)
        XCTAssertEqual(redirectComponents.queryItems?.first?.name, "featurePage")
        XCTAssertEqual(redirectComponents.queryItems?.first?.value, "vpn")
    }

    func testUnknownPerformanceOptimizedPaywallPathIsNotIntercepted() throws {
        let notificationExpectation = expectation(forNotification: .urlInterceptSubscription, object: nil, handler: nil)
        notificationExpectation.isInverted = true
        let url = try XCTUnwrap(URL(string: "https://duckduckgo.com/subscriptions/v2/unknown"))

        XCTAssertTrue(urlInterceptor.allowsNavigatingTo(url: url))
        wait(for: [notificationExpectation], timeout: 0.5)
    }

    private func interceptedRedirectComponents(for url: URL) throws -> URLComponents {
        var capturedNotification: Notification?
        let notificationExpectation = expectation(forNotification: .urlInterceptSubscription, object: nil) { notification in
            capturedNotification = notification
            return true
        }

        XCTAssertFalse(urlInterceptor.allowsNavigatingTo(url: url))
        wait(for: [notificationExpectation], timeout: 1)

        return try XCTUnwrap(capturedNotification?.userInfo?[TabURLInterceptorParameter.interceptedURLComponents] as? URLComponents)
    }
}

private final class MockPerformanceOptimizedPaywallsProvider: PerformanceOptimizedPaywallsProviding {
    let isEnabled: Bool
    private let configuredPaths: SubscriptionURL.PerformanceOptimizedPaywallPaths
    private(set) var pathsAccessCount = 0

    var paths: SubscriptionURL.PerformanceOptimizedPaywallPaths {
        pathsAccessCount += 1
        return configuredPaths
    }

    init(isEnabled: Bool, paths: SubscriptionURL.PerformanceOptimizedPaywallPaths) {
        self.isEnabled = isEnabled
        self.configuredPaths = paths
    }
}
