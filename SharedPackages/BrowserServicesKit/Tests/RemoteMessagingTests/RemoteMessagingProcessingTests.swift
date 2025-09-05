//
//  RemoteMessagingProcessingTests.swift
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

import BrowserServicesKit
import BrowserServicesKitTestsUtils
import RemoteMessagingTestsUtils
import XCTest
@testable import RemoteMessaging

struct TestRemoteMessagingProcessor: RemoteMessagingProcessing {
    var endpoint: URL
    var configFetcher: RemoteMessagingConfigFetching
    var configMatcherProvider: RemoteMessagingConfigMatcherProviding
    var remoteMessagingAvailabilityProvider: RemoteMessagingAvailabilityProviding
    var remoteMessagingConfigProcessor: RemoteMessagingConfigProcessing

    init(
        endpoint: URL = URL(string: "https://example.com/config.json")!,
        configFetcher: RemoteMessagingConfigFetching,
        configMatcherProvider: RemoteMessagingConfigMatcherProviding,
        remoteMessagingAvailabilityProvider: RemoteMessagingAvailabilityProviding,
        remoteMessagingConfigProcessor: RemoteMessagingConfigProcessing
    ) {
        self.endpoint = endpoint
        self.configFetcher = configFetcher
        self.configMatcherProvider = configMatcherProvider
        self.remoteMessagingAvailabilityProvider = remoteMessagingAvailabilityProvider
        self.remoteMessagingConfigProcessor = remoteMessagingConfigProcessor
    }

    func configProcessor(for configMatcher: RemoteMessagingConfigMatcher) -> RemoteMessagingConfigProcessing {
        remoteMessagingConfigProcessor
    }
}

class RemoteMessagingProcessingTests: XCTestCase {

    var availabilityProvider: MockRemoteMessagingAvailabilityProvider!
    var configFetcher: MockRemoteMessagingConfigFetcher!
    var configProcessor: MockRemoteMessagingConfigProcessor!
    var store: MockRemoteMessagingStore!

    var processor: TestRemoteMessagingProcessor!

    override func setUpWithError() throws {
        let emailManagerStorage = MockEmailManagerStorage()

        availabilityProvider = MockRemoteMessagingAvailabilityProvider()

        let matcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: MobileAppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                userAttributeMatcher: MobileUserAttributeMatcher(
                    statisticsStore: MockStatisticsStore(),
                    variantManager: MockVariantManager(),
                    emailManager: EmailManager(storage: emailManagerStorage),
                    bookmarksCount: 10,
                    favoritesCount: 0,
                    appTheme: "light",
                    isWidgetInstalled: false,
                    daysSinceNetPEnabled: -1,
                    isPrivacyProEligibleUser: false,
                    isPrivacyProSubscriber: false,
                    privacyProDaysSinceSubscribed: -1,
                    privacyProDaysUntilExpiry: -1,
                    privacyProPurchasePlatform: nil,
                    isPrivacyProSubscriptionActive: false,
                    isPrivacyProSubscriptionExpiring: false,
                    isPrivacyProSubscriptionExpired: false,
                    isDuckPlayerOnboarded: false,
                    isDuckPlayerEnabled: false,
                    dismissedMessageIds: [],
                    shownMessageIds: [],
                    enabledFeatureFlags: [],
                    isSyncEnabled: false
                ),
                percentileStore: MockRemoteMessagePercentileStore(),
                surveyActionMapper: MockRemoteMessageSurveyActionMapper(),
                dismissedMessageIds: []
        )

        configFetcher = MockRemoteMessagingConfigFetcher()
        store = MockRemoteMessagingStore()

        configProcessor = MockRemoteMessagingConfigProcessor(remoteMessagingConfigMatcher: matcher)

        processor = TestRemoteMessagingProcessor(
            configFetcher: configFetcher,
            configMatcherProvider: MockRemoteMessagingConfigMatcherProvider { _ in matcher },
            remoteMessagingAvailabilityProvider: availabilityProvider,
            remoteMessagingConfigProcessor: configProcessor
        )
    }

    func testWhenFeatureFlagIsDisabledThenProcessingIsSkipped() async throws {
        availabilityProvider.isRemoteMessagingAvailable = false

        do {
            try await processor.fetchAndProcess(using: store)
        } catch {
            XCTFail("Unexpected error thrown: \(error).")
        }
        XCTAssertEqual(store.saveProcessedResultCalls, 0)
    }

    func testWhenConfigProcessorReturnsNilThenResultIsNotSaved() async throws {
        configProcessor.processConfig = { _, _ in nil }

        do {
            try await processor.fetchAndProcess(using: store)
        } catch {
            XCTFail("Unexpected error thrown: \(error).")
        }
        XCTAssertEqual(store.saveProcessedResultCalls, 0)
    }

    func testWhenConfigProcessorReturnsMessageThenResultIsSaved() async throws {
        configProcessor.processConfig = { _, _ in .init(version: 0, message: nil) }

        do {
            try await processor.fetchAndProcess(using: store)
        } catch {
            XCTFail("Unexpected error thrown: \(error).")
        }
        XCTAssertEqual(store.saveProcessedResultCalls, 1)
    }

    func testWhenFetchingConfigFailsThenErrorIsThrown() async throws {
        struct SampleError: Error {}
        configFetcher.error = SampleError()

        do {
            try await processor.fetchAndProcess(using: store)
            XCTFail("Expected to throw error")
        } catch {
            XCTAssertTrue(error is SampleError)
        }
        XCTAssertEqual(store.saveProcessedResultCalls, 0)
    }

}
