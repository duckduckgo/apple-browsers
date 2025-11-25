//
//  RemoteMessagingStoreTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import BrowserServicesKitTestsUtils
import CoreData
import Foundation
import Persistence
import RemoteMessagingTestsUtils
import PersistenceTestingUtils
import XCTest
@testable import RemoteMessaging

class RemoteMessagingStoreTests: XCTestCase {

    var store: RemoteMessagingStore!
    let notificationCenter = NotificationCenter()
    var defaults: MockKeyValueStore!
    var availabilityProvider: MockRemoteMessagingAvailabilityProvider!
    var remoteMessagingDatabase: CoreDataDatabase!
    var location: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundle = RemoteMessaging.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "RemoteMessaging") else {
            XCTFail("Failed to load model")
            return
        }
        remoteMessagingDatabase = CoreDataDatabase(name: type(of: self).description(), containerLocation: location, model: model)
        remoteMessagingDatabase.loadStore()

        availabilityProvider = MockRemoteMessagingAvailabilityProvider()

        store = RemoteMessagingStore(
            database: remoteMessagingDatabase,
            notificationCenter: notificationCenter,
            errorEvents: nil,
            remoteMessagingAvailabilityProvider: availabilityProvider
        )

        defaults = MockKeyValueStore()
    }

    override func tearDownWithError() throws {
        store = nil

        try? remoteMessagingDatabase.tearDown(deleteStores: true)
        remoteMessagingDatabase = nil
        try? FileManager.default.removeItem(at: location)

        try super.tearDownWithError()
    }

    // Tests:
    // 1. saveProcessedResult()
    // 2. fetch RemoteMessagingConfig and RemoteMessage successfully returned from save in step 1
    // 3. NSNotification RemoteMessagesDidChange is posted
    func testWhenSaveProcessedResultThenFetchRemoteConfigAndMessageExistsAndNotificationSent() async throws {
        let expectation = XCTNSNotificationExpectation(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange,
                                                       object: nil, notificationCenter: notificationCenter)

        _ = try await saveProcessedResultFetchRemoteMessage()

        // 3. NSNotification RemoteMessagesDidChange is posted
        await fulfillment(of: [expectation], timeout: 10)
    }

    func saveProcessedResultFetchRemoteMessage(for configJSON: String? = nil) async throws -> RemoteMessageModel {
        let processorResult = try processorResult(for: configJSON)
        // 1. saveProcessedResult()
        await store.saveProcessedResult(processorResult)

        // 2. fetch RemoteMessagingConfig and RemoteMessage successfully returned from save in step 1
        let config = store.fetchRemoteMessagingConfig()
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.version, processorResult.version)
        guard let remoteMessage = store.fetchScheduledRemoteMessage(surfaces: .allCases) else {
            XCTFail("No remote message found")
            return RemoteMessageModel(id: "", surfaces: .newTabPage, content: nil, matchingRules: [], exclusionRules: [], isMetricsEnabled: true)
        }

        XCTAssertNotNil(remoteMessage)
        XCTAssertEqual(remoteMessage, processorResult.message)
        return remoteMessage
    }

    func testWhenHasNotShownMessageThenReturnFalse() async throws {
        let remoteMessage = try await saveProcessedResultFetchRemoteMessage()
        XCTAssertFalse(store.hasShownRemoteMessage(withID: remoteMessage.id))
    }

    func testWhenUpdateRemoteMessageAsShownMessageThenHasShownIsTrue() async throws {
        let remoteMessage = try await saveProcessedResultFetchRemoteMessage()
        await store.updateRemoteMessage(withID: remoteMessage.id, asShown: true)
        XCTAssertTrue(store.hasShownRemoteMessage(withID: remoteMessage.id))
    }

    func testWhenUpdateRemoteMessageAsShownFalseThenHasShownIsFalse() async throws {
        let remoteMessage = try await saveProcessedResultFetchRemoteMessage()
        await store.updateRemoteMessage(withID: remoteMessage.id, asShown: false)
        XCTAssertFalse(store.hasShownRemoteMessage(withID: remoteMessage.id))
    }

    func testFetchShownRemoteMessageIds() async throws {
        let remoteMessage = try await saveProcessedResultFetchRemoteMessage()
        XCTAssertEqual(store.fetchShownRemoteMessageIDs(), [])

        await store.updateRemoteMessage(withID: remoteMessage.id, asShown: true)
        XCTAssertEqual(store.fetchShownRemoteMessageIDs(), [remoteMessage.id])
    }

    func testFetchDismissedRemoteMessageIds() async throws {
        let remoteMessage = try await saveProcessedResultFetchRemoteMessage()

        await store.dismissRemoteMessage(withID: remoteMessage.id)

        let dismissedRemoteMessageIds = store.fetchDismissedRemoteMessageIDs()
        XCTAssertEqual(dismissedRemoteMessageIds.count, 1)
        XCTAssertEqual(dismissedRemoteMessageIds.first, remoteMessage.id)
    }

    func testConfigUpdateWhenMessageWasShownAndNotInteractedWithThenItIsNotRemovedFromDatabase() async throws {
        let remoteMessage = try await saveProcessedResultFetchRemoteMessage(for: minimalConfig(version: 1, messageID: 1))
        await store.updateRemoteMessage(withID: remoteMessage.id, asShown: true)

        let context = remoteMessagingDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            let messages = RemoteMessageUtils.fetchAllRemoteMessages(in: context)
            XCTAssertEqual(messages.count, 1)
            let firstMessage = messages.first!
            XCTAssertTrue(firstMessage.shown)
            XCTAssertEqual(firstMessage.status?.int16Value, RemoteMessagingStore.RemoteMessageStatus.scheduled.rawValue)
        }

        _ = try await saveProcessedResultFetchRemoteMessage(for: minimalConfig(version: 2, messageID: 2))

        context.performAndWait {
            context.refreshAllObjects()
            let messages = RemoteMessageUtils.fetchAllRemoteMessages(in: context)
            XCTAssertEqual(messages.count, 2)

            let firstMessage = messages.first(where: { $0.id == "1" })!
            XCTAssertTrue(firstMessage.shown)
            XCTAssertEqual(firstMessage.status?.int16Value, RemoteMessagingStore.RemoteMessageStatus.done.rawValue)

            let secondMessage = messages.first(where: { $0.id == "2" })!
            XCTAssertFalse(secondMessage.shown)
            XCTAssertEqual(secondMessage.status?.int16Value, RemoteMessagingStore.RemoteMessageStatus.scheduled.rawValue)
        }
    }

    func testConfigUpdateWhenMessageWasInteractedWithThenItIsNotRemovedFromDatabase() async throws {
        let remoteMessage = try await saveProcessedResultFetchRemoteMessage(for: minimalConfig(version: 1, messageID: 1))
        await store.updateRemoteMessage(withID: remoteMessage.id, asShown: true)
        await store.dismissRemoteMessage(withID: remoteMessage.id)

        let context = remoteMessagingDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            let messages = RemoteMessageUtils.fetchAllRemoteMessages(in: context)
            XCTAssertEqual(messages.count, 1)

            let firstMessage = messages.first!
            XCTAssertTrue(firstMessage.shown)
            XCTAssertEqual(firstMessage.status?.int16Value, RemoteMessagingStore.RemoteMessageStatus.dismissed.rawValue)
        }

        _ = try await saveProcessedResultFetchRemoteMessage(for: minimalConfig(version: 2, messageID: 2))

        context.performAndWait {
            context.refreshAllObjects()
            let messages = RemoteMessageUtils.fetchAllRemoteMessages(in: context)
            XCTAssertEqual(messages.count, 2)

            let firstMessage = messages.first(where: { $0.id == "1" })!
            XCTAssertTrue(firstMessage.shown)
            XCTAssertEqual(firstMessage.status?.int16Value, RemoteMessagingStore.RemoteMessageStatus.dismissed.rawValue)

            let secondMessage = messages.first(where: { $0.id == "2" })!
            XCTAssertFalse(secondMessage.shown)
            XCTAssertEqual(secondMessage.status?.int16Value, RemoteMessagingStore.RemoteMessageStatus.scheduled.rawValue)
        }
    }

    func testConfigUpdateWhenMessageWasNotShownThenItIsRemovedFromDatabase() async throws {
        _ = try await saveProcessedResultFetchRemoteMessage(for: minimalConfig(version: 1, messageID: 1))

        let context = remoteMessagingDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            let messages = RemoteMessageUtils.fetchAllRemoteMessages(in: context)
            XCTAssertEqual(messages.count, 1)

            let firstMessage = messages.first!
            XCTAssertFalse(firstMessage.shown)
            XCTAssertEqual(firstMessage.status?.int16Value, RemoteMessagingStore.RemoteMessageStatus.scheduled.rawValue)
        }

        _ = try await saveProcessedResultFetchRemoteMessage(for: minimalConfig(version: 2, messageID: 2))

        context.performAndWait {
            context.refreshAllObjects()
            let messages = RemoteMessageUtils.fetchAllRemoteMessages(in: context)
            XCTAssertEqual(messages.count, 1)

            let secondMessage = messages.first!
            XCTAssertEqual(secondMessage.id, "2")
            XCTAssertFalse(secondMessage.shown)
            XCTAssertEqual(secondMessage.status?.int16Value, RemoteMessagingStore.RemoteMessageStatus.scheduled.rawValue)
        }
    }

    func testConfigUpdateWhenShownAndNotInteractedWithMessageIsReintroducedInNewConfigThenItIsMarkedAsScheduled() async throws {
        let remoteMessage = try await saveProcessedResultFetchRemoteMessage(for: minimalConfig(version: 1, messageID: 1))
        await store.updateRemoteMessage(withID: remoteMessage.id, asShown: true)

        let context = remoteMessagingDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            let messages = RemoteMessageUtils.fetchAllRemoteMessages(in: context)
            XCTAssertEqual(messages.count, 1)

            let firstMessage = messages.first!
            XCTAssertTrue(firstMessage.shown)
            XCTAssertEqual(firstMessage.status?.int16Value, RemoteMessagingStore.RemoteMessageStatus.scheduled.rawValue)
        }

        _ = try await saveProcessedResultFetchRemoteMessage(for: minimalConfig(version: 2, messageID: 2))
        _ = try await saveProcessedResultFetchRemoteMessage(for: minimalConfig(version: 3, messageID: 1))

        context.performAndWait {
            context.refreshAllObjects()
            let messages = RemoteMessageUtils.fetchAllRemoteMessages(in: context)
            XCTAssertEqual(messages.count, 1)

            let firstMessage = messages.first!
            XCTAssertEqual(firstMessage.id, "1")
            XCTAssertTrue(firstMessage.shown) // shown status is preserved
            XCTAssertEqual(firstMessage.status?.int16Value, RemoteMessagingStore.RemoteMessageStatus.scheduled.rawValue)
        }
    }

    // MARK: - Feature Flag

    func testWhenFeatureFlagIsDisabledThenScheduledRemoteMessagesAreDeleted() async throws {
        _ = try await saveProcessedResultFetchRemoteMessage()
        XCTAssertNotNil(store.fetchScheduledRemoteMessage(surfaces: .allCases))

        let expectation = XCTNSNotificationExpectation(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange,
                                                       object: nil, notificationCenter: notificationCenter)

        try await setFeatureFlagEnabled(false)
        XCTAssertNil(store.fetchScheduledRemoteMessage(surfaces: .allCases))

        await fulfillment(of: [expectation], timeout: 1)

        // Re-enabling remote messaging doesn't trigger a refetch on a Store level so no new scheduled messages should appear
        try await setFeatureFlagEnabled(true)
        XCTAssertNil(store.fetchScheduledRemoteMessage(surfaces: .allCases))
    }

    func testWhenFeatureFlagIsDisabledAndThereWereNoMessagesThenNotificationIsNotSent() async throws {
        XCTAssertNil(store.fetchScheduledRemoteMessage(surfaces: .allCases))

        let expectation = XCTNSNotificationExpectation(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange,
                                                       object: nil, notificationCenter: notificationCenter)
        expectation.isInverted = true

        try await setFeatureFlagEnabled(false)
        XCTAssertNil(store.fetchScheduledRemoteMessage(surfaces: .allCases))

        await fulfillment(of: [expectation], timeout: 1)
    }

    func testWhenFeatureFlagIsDisabledAndThereWereNoScheduledMessagesThenNotificationIsNotSent() async throws {
        _ = try await saveProcessedResultFetchRemoteMessage()

        // Dismiss all available messages
        while let remoteMessage = store.fetchScheduledRemoteMessage(surfaces: .allCases) {
            await store.dismissRemoteMessage(withID: remoteMessage.id)
        }

        let expectation = XCTNSNotificationExpectation(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange,
                                                       object: nil, notificationCenter: notificationCenter)
        expectation.isInverted = true

        try await setFeatureFlagEnabled(false)
        XCTAssertNil(store.fetchScheduledRemoteMessage(surfaces: .allCases))

        await fulfillment(of: [expectation], timeout: 1)
    }

    func testWhenFeatureFlagIsDisabledThenProcessedResultIsNotSaved() async throws {
        try await setFeatureFlagEnabled(false)

        let expectation = XCTNSNotificationExpectation(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange,
                                                       object: nil, notificationCenter: notificationCenter)
        expectation.isInverted = true

        let processorResult = try processorResult()
        await store.saveProcessedResult(processorResult)

        await fulfillment(of: [expectation], timeout: 1)
    }

    func testWhenFeatureFlagIsDisabledThenFetchScheduledRemoteMessageReturnsNil() async throws {
        _ = try await saveProcessedResultFetchRemoteMessage()
        try await setFeatureFlagEnabled(false)

        XCTAssertNil(store.fetchScheduledRemoteMessage(surfaces: .allCases))
    }

    func testWhenFeatureFlagIsDisabledThenFetchRemoteMessagingConfigReturnsNil() async throws {
        _ = try await saveProcessedResultFetchRemoteMessage()
        try await setFeatureFlagEnabled(false)

        XCTAssertNil(store.fetchRemoteMessagingConfig())
    }

    func testWhenFeatureFlagIsDisabledThenUpdateShownFlagHasNoEffect() async throws {
        let remoteMessage = try await saveProcessedResultFetchRemoteMessage()
        try await setFeatureFlagEnabled(false)

        await store.updateRemoteMessage(withID: remoteMessage.id, asShown: true)

        XCTAssertFalse(store.hasShownRemoteMessage(withID: remoteMessage.id))
    }

    func testWhenFeatureFlagIsDisabledThenHasShownMessageReturnFalse() async throws {
        let remoteMessage = try await saveProcessedResultFetchRemoteMessage()
        await store.updateRemoteMessage(withID: remoteMessage.id, asShown: true)
        try await setFeatureFlagEnabled(false)

        XCTAssertFalse(store.hasShownRemoteMessage(withID: remoteMessage.id))
    }

    func testWhenFeatureFlagIsDisabledThenDismissingRemoteMessageHasNoEffect() async throws {
        let remoteMessage = try await saveProcessedResultFetchRemoteMessage()

        try await setFeatureFlagEnabled(false)
        await store.dismissRemoteMessage(withID: remoteMessage.id)

        XCTAssertEqual(store.fetchDismissedRemoteMessageIDs(), [])
    }

    // MARK: - Surface

    func testWhenFetchScheduledRemoteMessageAndScheduledMessageSurfaceDoesNotMatchThenReturnNil() async throws {
        // GIVEN
        XCTAssertNil(store.fetchScheduledRemoteMessage(surfaces: .allCases))
        let message = RemoteMessageModel(id: "1", surfaces: .newTabPage, content: .small(titleText: "", descriptionText: ""), matchingRules: [], exclusionRules: [], isMetricsEnabled: false)
        let processorResult = RemoteMessagingConfigProcessor.ProcessorResult(version: 1, message: message)
        await store.saveProcessedResult(processorResult)

        // WHEN
        let result = store.fetchScheduledRemoteMessage(surfaces: [.modal, .dedicatedTab])

        // THEN
        XCTAssertNil(result)
    }

    func testWhenFetchScheduledRemoteMessageAndSurfaceIsNewTabAndScheduledMessageSurfaceMatchesThenReturnMessage() async throws {
        // GIVEN
        XCTAssertNil(store.fetchScheduledRemoteMessage(surfaces: .allCases))
        let message = RemoteMessageModel(id: "1", surfaces: .newTabPage, content: .small(titleText: "", descriptionText: ""), matchingRules: [], exclusionRules: [], isMetricsEnabled: false)
        let processorResult = RemoteMessagingConfigProcessor.ProcessorResult(version: 1, message: message)
        await store.saveProcessedResult(processorResult)

        // WHEN
        let result = store.fetchScheduledRemoteMessage(surfaces: .newTabPage)

        // THEN
        XCTAssertEqual(result, message)
    }

    func testWhenFetchScheduledRemoteMessageAndSurfaceIsModalAndScheduledMessageSurfaceMatchesThenReturnMessage() async throws {
        // GIVEN
        XCTAssertNil(store.fetchScheduledRemoteMessage(surfaces: .allCases))
        let message = RemoteMessageModel(id: "1", surfaces: .modal, content: .small(titleText: "", descriptionText: ""), matchingRules: [], exclusionRules: [], isMetricsEnabled: false)
        let processorResult = RemoteMessagingConfigProcessor.ProcessorResult(version: 1, message: message)
        await store.saveProcessedResult(processorResult)

        // WHEN
        let result = store.fetchScheduledRemoteMessage(surfaces: .modal)

        // THEN
        XCTAssertEqual(result, message)
    }

    func testWhenFetchScheduledRemoteMessageAndSurfaceIsDedicatedTabAndScheduledMessageSurfaceMatchesThenReturnMessage() async throws {
        // GIVEN
        XCTAssertNil(store.fetchScheduledRemoteMessage(surfaces: .allCases))
        let message = RemoteMessageModel(id: "1", surfaces: .dedicatedTab, content: .small(titleText: "", descriptionText: ""), matchingRules: [], exclusionRules: [], isMetricsEnabled: false)
        let processorResult = RemoteMessagingConfigProcessor.ProcessorResult(version: 1, message: message)
        await store.saveProcessedResult(processorResult)

        // WHEN
        let result = store.fetchScheduledRemoteMessage(surfaces: .dedicatedTab)

        // THEN
        XCTAssertEqual(result, message)
    }

    func testWhenFetchScheduledRemoteMessageAndSurfaceIsAllCasesAndScheduledMessageSurfaceIsNewTabThenReturnMessage() async throws {
        // GIVEN
        XCTAssertNil(store.fetchScheduledRemoteMessage(surfaces: .allCases))
        let message = RemoteMessageModel(id: "1", surfaces: .newTabPage, content: .small(titleText: "", descriptionText: ""), matchingRules: [], exclusionRules: [], isMetricsEnabled: false)
        let processorResult = RemoteMessagingConfigProcessor.ProcessorResult(version: 1, message: message)
        await store.saveProcessedResult(processorResult)

        // WHEN
        let result = store.fetchScheduledRemoteMessage(surfaces: .allCases)

        // THEN
        XCTAssertEqual(result, message)
    }

    func testWhenFetchScheduledRemoteMessageAndSurfaceIsAllCasesAndScheduledMessageSurfaceIsModalThenReturnMessage() async throws {
        // GIVEN
        XCTAssertNil(store.fetchScheduledRemoteMessage(surfaces: .allCases))
        let message = RemoteMessageModel(id: "1", surfaces: .modal, content: .small(titleText: "", descriptionText: ""), matchingRules: [], exclusionRules: [], isMetricsEnabled: false)
        let processorResult = RemoteMessagingConfigProcessor.ProcessorResult(version: 1, message: message)
        await store.saveProcessedResult(processorResult)

        // WHEN
        let result = store.fetchScheduledRemoteMessage(surfaces: .allCases)

        // THEN
        XCTAssertEqual(result, message)
    }

    func testWhenFetchScheduledRemoteMessageAndSurfaceIsAllCasesAndScheduledMessageSurfaceIsDedicatedTabThenReturnMessage() async throws {
        // GIVEN
        XCTAssertNil(store.fetchScheduledRemoteMessage(surfaces: .allCases))
        let message = RemoteMessageModel(id: "1", surfaces: .dedicatedTab, content: .small(titleText: "", descriptionText: ""), matchingRules: [], exclusionRules: [], isMetricsEnabled: false)
        let processorResult = RemoteMessagingConfigProcessor.ProcessorResult(version: 1, message: message)
        await store.saveProcessedResult(processorResult)

        // WHEN
        let result = store.fetchScheduledRemoteMessage(surfaces: .allCases)

        // THEN
        XCTAssertEqual(result, message)
    }

    func testWhenFetchScheduledRemoteMessageAndSurfaceMatchesOneOfTheOptionsThenReturnMessage() async throws {
        // GIVEN
        XCTAssertNil(store.fetchScheduledRemoteMessage(surfaces: .allCases))
        let message = RemoteMessageModel(id: "1", surfaces: [.newTabPage, .modal], content: .small(titleText: "", descriptionText: ""), matchingRules: [], exclusionRules: [], isMetricsEnabled: false)
        let processorResult = RemoteMessagingConfigProcessor.ProcessorResult(version: 1, message: message)
        await store.saveProcessedResult(processorResult)

        // WHEN
        let result = store.fetchScheduledRemoteMessage(surfaces: .newTabPage)

        // THEN
        XCTAssertEqual(result, message)
    }

    func testWhenFetchScheduledRemoteMessageAndMesssageDoesNotHaveAnySurfaceAndSurfaceIsNewTabThenDefaultToNewTabPageSurface() async throws {
        // GIVEN
        let context = store.context
        XCTAssertNil(store.fetchScheduledRemoteMessage(surfaces: .allCases))
        try context.performAndWait {
            let message = RemoteMessageManagedObject(context: context)
            message.id = "1"
            message.status = NSNumber(value: 0) // Scheduled
            message.shown = false
            message.message = """
              {"isMetricsEnabled":false,"content":{"small":{"titleText":"","descriptionText":""}},"id":"1","exclusionRules":[],"matchingRules":[]}
              """
            context.insert(message)
            try context.save()
        }

        // WHEN
        let result = store.fetchScheduledRemoteMessage(surfaces: .newTabPage)

        // THEN
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.surfaces, .newTabPage)
    }

    func testWhenFetchScheduledRemoteMessageAndMesssageDoesNotHaveAnySurfaceAndSurfaceHasNewTabThenDefaultToNewTabPageSurface() async throws {
        // GIVEN
        let context = store.context
        XCTAssertNil(store.fetchScheduledRemoteMessage(surfaces: .allCases))
        try context.performAndWait {
            let message = RemoteMessageManagedObject(context: context)
            message.id = "1"
            message.status = NSNumber(value: 0) // Scheduled
            message.shown = false
            message.message = """
              {"isMetricsEnabled":false,"content":{"small":{"titleText":"","descriptionText":""}},"id":"1","exclusionRules":[],"matchingRules":[]}
              """
            context.insert(message)
            try context.save()
        }

        // WHEN
        let result = store.fetchScheduledRemoteMessage(surfaces: [.newTabPage, .modal])

        // THEN
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.surfaces, .newTabPage)
    }

    func testWhenFetchScheduledRemoteMessageAndMesssageDoesNotHaveAnySurfaceAndSurfaceHasNotNewTabThenDoNotReturnMessage() async throws {
        // GIVEN
        let context = store.context
        XCTAssertNil(store.fetchScheduledRemoteMessage(surfaces: .allCases))
        try context.performAndWait {
            let message = RemoteMessageManagedObject(context: context)
            message.id = "1"
            message.status = NSNumber(value: 0) // Scheduled
            message.shown = false
            message.message = """
              {"isMetricsEnabled":false,"content":{"small":{"titleText":"","descriptionText":""}},"id":"1","exclusionRules":[],"matchingRules":[]}
              """
            context.insert(message)
            try context.save()
        }

        // WHEN
        let result = store.fetchScheduledRemoteMessage(surfaces: .modal)

        // THEN
        XCTAssertNil(result)
    }

}

// MARK: - Helpers

private extension RemoteMessagingStoreTests {

    func setFeatureFlagEnabled(_ isRemoteMessagingAvailable: Bool) async throws {
        availabilityProvider.isRemoteMessagingAvailable = isRemoteMessagingAvailable
        try await Task.sleep(interval: 0.1)
    }

    func decodeJson(fileName: String) throws -> RemoteMessageResponse.JsonRemoteMessagingConfig {
        let resourceURL = Bundle.module.resourceURL!.appendingPathComponent(fileName, conformingTo: .json)

        let validJson = try Data(contentsOf: resourceURL)
        let remoteMessagingConfig = try JSONDecoder().decode(RemoteMessageResponse.JsonRemoteMessagingConfig.self, from: validJson)
        XCTAssertNotNil(remoteMessagingConfig)

        return remoteMessagingConfig
    }

    func decodeJson(from jsonString: String) throws -> RemoteMessageResponse.JsonRemoteMessagingConfig {
        let validJson = jsonString.data(using: .utf8)!
        let remoteMessagingConfig = try JSONDecoder().decode(RemoteMessageResponse.JsonRemoteMessagingConfig.self, from: validJson)
        XCTAssertNotNil(remoteMessagingConfig)

        return remoteMessagingConfig
    }

    func processorResult(for configJSON: String? = nil) throws -> RemoteMessagingConfigProcessor.ProcessorResult {
        let jsonRemoteMessagingConfig = try {
            guard let configJSON else {
                return try decodeJson(fileName: "remote-messaging-config-example.json")
            }
            return try decodeJson(from: configJSON)
        }()
        return try processorResult(for: jsonRemoteMessagingConfig)
    }

    func processorResult(for jsonRemoteMessagingConfig: RemoteMessageResponse.JsonRemoteMessagingConfig) throws -> RemoteMessagingConfigProcessor.ProcessorResult {
        let remoteMessagingConfigMatcher = RemoteMessagingConfigMatcher(
                appAttributeMatcher: MobileAppAttributeMatcher(statisticsStore: MockStatisticsStore(), variantManager: MockVariantManager()),
                userAttributeMatcher: MobileUserAttributeMatcher(
                    statisticsStore: MockStatisticsStore(),
                    featureDiscovery: MockFeatureDiscovery(),
                    variantManager: MockVariantManager(),
                    bookmarksCount: 0,
                    favoritesCount: 0,
                    appTheme: "light",
                    isWidgetInstalled: false,
                    daysSinceNetPEnabled: -1,
                    isSubscriptionEligibleUser: false,
                    isDuckDuckGoSubscriber: false,
                    subscriptionDaysSinceSubscribed: -1,
                    subscriptionDaysUntilExpiry: -1,
                    subscriptionPurchasePlatform: nil,
                    isSubscriptionActive: false,
                    isSubscriptionExpiring: false,
                    isSubscriptionExpired: false,
                    subscriptionFreeTrialActive: false,
                    isDuckPlayerOnboarded: false,
                    isDuckPlayerEnabled: false,
                    dismissedMessageIds: [],
                    shownMessageIds: [],
                    enabledFeatureFlags: [],
                    isSyncEnabled: false,
                    shouldShowWinBackOfferUrgencyMessage: false
                ),
                percentileStore: RemoteMessagingPercentileUserDefaultsStore(keyValueStore: self.defaults),
                surveyActionMapper: MockRemoteMessagingSurveyActionMapper(),
                dismissedMessageIds: []
        )

        let processor = RemoteMessagingConfigProcessor(remoteMessagingConfigMatcher: remoteMessagingConfigMatcher)
        let config: RemoteMessagingConfig = RemoteMessagingConfig(version: jsonRemoteMessagingConfig.version - 1,
                                                                  invalidate: false,
                                                                  evaluationTimestamp: Date())

        if let processorResult = processor.process(jsonRemoteMessagingConfig: jsonRemoteMessagingConfig, currentConfig: config, supportedSurfacesForMessage: { _ in .newTabPage }) {
            return processorResult
        } else {
            XCTFail("Processor result message is nil")
            return RemoteMessagingConfigProcessor.ProcessorResult(version: 0, message: nil)
        }
    }

    func minimalConfig(version: Int, messageID: Int) -> String {
        """
        {
          "version": \(version),
          "messages": [
            {
              "id": "\(messageID)",
              "content": { "messageType": "small", "titleText": "title", "descriptionText": "description" },
              "matchingRules": [], "exclusionRules": []
            }
          ],
          "rules": []
        }
        """
    }

}

private final class MockRemoteMessagingSurveyActionMapper: RemoteMessagingSurveyActionMapping {

    func add(parameters: [RemoteMessagingSurveyActionParameter], to url: URL) -> URL {
        return url
    }

}
