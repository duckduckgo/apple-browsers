//
//  DuckAISubscriptionUpsellPresenterTests.swift
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

import XCTest
@testable import DuckDuckGo

final class DuckAISubscriptionUpsellPresenterTests: XCTestCase {

    private var notificationCenter: NotificationCenter!
    private var sut: DuckAISubscriptionUpsellPresenter!

    override func setUp() {
        super.setUp()
        notificationCenter = NotificationCenter()
        sut = DuckAISubscriptionUpsellPresenter(notificationCenter: notificationCenter)
    }

    override func tearDown() {
        sut = nil
        notificationCenter = nil
        super.tearDown()
    }

    func testPresentPurchaseFlowFromReasoningPickerInAddressBarPostsSubscriptionFlowWithAddressBarOrigin() {
        let expectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil, notificationCenter: notificationCenter) { notification in
            guard let deepLink = notification.object as? SettingsViewModel.SettingsDeepLinkSection,
                  case .subscriptionFlow(let components) = deepLink else {
                return false
            }
            return self.hasQueryItem(in: components, name: "featurePage", value: "duckai")
                && self.hasQueryItem(in: components, name: "origin", value: "funnel_addressbar_ios__reasoningpicker")
        }

        sut.presentPurchaseFlow(source: .reasoningPicker, isAITabState: false)

        wait(for: [expectation], timeout: 1.0)
    }

    func testPresentUpgradeFlowFromReasoningPickerInAddressBarPostsPlanChangeFlowWithAddressBarOrigin() {
        let expectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil, notificationCenter: notificationCenter) { notification in
            guard let deepLink = notification.object as? SettingsViewModel.SettingsDeepLinkSection,
                  case .subscriptionPlanChangeFlow(let components) = deepLink else {
                return false
            }
            return self.hasQueryItem(in: components, name: "origin", value: "funnel_addressbar_ios__reasoningpicker")
        }

        sut.presentUpgradeFlow(source: .reasoningPicker, isAITabState: false)

        wait(for: [expectation], timeout: 1.0)
    }

    func testPresentPurchaseFlowFromReasoningPickerInAITabUsesDuckAIOrigin() {
        let expectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil, notificationCenter: notificationCenter) { notification in
            guard let deepLink = notification.object as? SettingsViewModel.SettingsDeepLinkSection,
                  case .subscriptionFlow(let components) = deepLink else {
                return false
            }
            return self.hasQueryItem(in: components, name: "origin", value: "funnel_duckai_ios__reasoningpicker")
        }

        sut.presentPurchaseFlow(source: .reasoningPicker, isAITabState: true)

        wait(for: [expectation], timeout: 1.0)
    }

    func testPresentPurchaseFlowFromModelPickerInAddressBarUsesModelPickerOrigin() {
        let expectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil, notificationCenter: notificationCenter) { notification in
            guard let deepLink = notification.object as? SettingsViewModel.SettingsDeepLinkSection,
                  case .subscriptionFlow(let components) = deepLink else {
                return false
            }
            return self.hasQueryItem(in: components, name: "origin", value: "funnel_addressbar_ios__modelpicker")
        }

        sut.presentPurchaseFlow(source: .modelPicker, isAITabState: false)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Helpers

    private func hasQueryItem(in components: URLComponents?, name: String, value: String) -> Bool {
        components?.queryItems?.contains { $0.name == name && $0.value == value } == true
    }
}
