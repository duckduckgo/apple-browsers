//
//  NewTabPageOmnibarModelsProviderTests.swift
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
import AIChat
import NewTabPage
@testable import Subscription
import SubscriptionTestingUtilities
@testable import DuckDuckGo_Privacy_Browser

final class NewTabPageOmnibarModelsProviderTests: XCTestCase {

    private var mockModelsService: MockModelsService!
    private var mockSubscriptionManager: SubscriptionManagerMock!
    private var provider: NewTabPageOmnibarModelsProvider!

    override func setUp() {
        super.setUp()
        mockModelsService = MockModelsService()
        mockSubscriptionManager = SubscriptionManagerMock()
        provider = NewTabPageOmnibarModelsProvider(
            modelsService: mockModelsService,
            subscriptionManager: mockSubscriptionManager
        )
    }

    override func tearDown() {
        provider = nil
        mockModelsService = nil
        mockSubscriptionManager = nil
        super.tearDown()
    }

    // MARK: - Mapping Tests

    func testWhenFetchingModelsThenFieldsAreMappedCorrectly() async {
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "gpt-4o-mini", name: "GPT-4o mini", shortName: "4o-mini",
                            supportsImageUpload: true, supportedTools: ["WebSearch", "NewsSearch"], accessTier: ["free"])
        ]

        let sections = await provider.fetchAIModelSections()
        let item = sections.first?.items.first

        XCTAssertEqual(item?.id, "gpt-4o-mini")
        XCTAssertEqual(item?.name, "GPT-4o mini")
        XCTAssertEqual(item?.shortName, "4o-mini")
        XCTAssertTrue(item?.isEnabled == true)
        XCTAssertTrue(item?.supportsImageUpload == true)
        XCTAssertEqual(item?.supportedTools, ["WebSearch", "NewsSearch"])
    }

    func testWhenFreeUserThenPremiumModelsAreDisabled() async {
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "free-model", accessTier: ["free"]),
            makeRemoteModel(id: "premium-model", accessTier: ["plus", "pro"]),
        ]

        let sections = await provider.fetchAIModelSections()
        let allItems = sections.flatMap(\.items)

        let freeItem = allItems.first(where: { $0.id == "free-model" })
        let premiumItem = allItems.first(where: { $0.id == "premium-model" })

        XCTAssertTrue(freeItem?.isEnabled == true)
        XCTAssertTrue(premiumItem?.isEnabled == false)
    }

    func testWhenSubscribedUserThenAllAccessibleModelsAreEnabled() async {
        mockSubscriptionManager.resultSubscription = .success(makeSubscription(tier: .plus))
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "free-model", accessTier: ["free", "plus"]),
            makeRemoteModel(id: "plus-model", accessTier: ["plus", "pro"]),
        ]

        let sections = await provider.fetchAIModelSections()
        let allItems = sections.flatMap(\.items)

        XCTAssertTrue(allItems.allSatisfy(\.isEnabled))
    }

    func testWhenSubscribedPlusUserThenProOnlyModelsAreHidden() async {
        mockSubscriptionManager.resultSubscription = .success(makeSubscription(tier: .plus))
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "plus-model", accessTier: ["plus", "pro"]),
            makeRemoteModel(id: "pro-only", accessTier: ["pro"]),
            makeRemoteModel(id: "free-model", accessTier: ["free", "plus"]),
        ]

        let sections = await provider.fetchAIModelSections()
        let allIds = sections.flatMap(\.items).map(\.id)

        XCTAssertTrue(allIds.contains("plus-model"))
        XCTAssertTrue(allIds.contains("free-model"))
        XCTAssertFalse(allIds.contains("pro-only"))
    }

    // MARK: - Section Structure Tests

    func testWhenFreeUserThenTwoSectionsReturned() async {
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "free-model", accessTier: ["free"]),
            makeRemoteModel(id: "premium-model", accessTier: ["plus"]),
        ]

        let sections = await provider.fetchAIModelSections()

        XCTAssertEqual(sections.count, 2)
        XCTAssertNil(sections[0].header)
        XCTAssertNotNil(sections[1].header)
    }

    func testWhenSubscribedUserThenTwoSectionsReturned() async {
        mockSubscriptionManager.resultSubscription = .success(makeSubscription(tier: .plus))
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "plus-model", accessTier: ["plus"]),
            makeRemoteModel(id: "free-model", accessTier: ["free", "plus"]),
        ]

        let sections = await provider.fetchAIModelSections()

        XCTAssertEqual(sections.count, 2)
        XCTAssertNil(sections[0].header)
        XCTAssertNotNil(sections[1].header)
    }

    // MARK: - Caching

    func testWhenFetchSucceedsThenLastFetchedSectionsIsCached() async {
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "free-model", accessTier: ["free"]),
        ]

        XCTAssertNil(provider.lastFetchedSections)

        _ = await provider.fetchAIModelSections()

        XCTAssertEqual(provider.lastFetchedSections?.flatMap(\.items).map(\.id), ["free-model"])
    }

    func testWhenFetchFailsThenLastFetchedSectionsRemainsNil() async {
        mockModelsService.errorToThrow = NSError(domain: "test", code: -1)

        _ = await provider.fetchAIModelSections()

        XCTAssertNil(provider.lastFetchedSections)
    }

    // MARK: - Error Handling

    func testWhenFetchFailsThenEmptySectionsReturned() async {
        mockModelsService.errorToThrow = NSError(domain: "test", code: -1)

        let sections = await provider.fetchAIModelSections()

        XCTAssertTrue(sections.isEmpty)
    }

    func testWhenSubscriptionFailsThenDefaultsToFreeUser() async {
        mockSubscriptionManager.resultSubscription = .failure(NSError(domain: "test", code: -1))
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "free-model", accessTier: ["free"]),
            makeRemoteModel(id: "premium-model", accessTier: ["plus"]),
        ]

        let sections = await provider.fetchAIModelSections()
        let premiumItem = sections.flatMap(\.items).first(where: { $0.id == "premium-model" })

        XCTAssertTrue(premiumItem?.isEnabled == false)
    }

    // MARK: - Helpers

    private func makeRemoteModel(
        id: String,
        name: String = "Model",
        shortName: String? = nil,
        supportsImageUpload: Bool = false,
        supportedTools: [String] = [],
        accessTier: [String]
    ) -> AIChatRemoteModel {
        AIChatRemoteModel(
            id: id,
            name: name,
            modelShortName: shortName ?? id,
            provider: "openai",
            entityHasAccess: true,
            supportsImageUpload: supportsImageUpload,
            supportedTools: supportedTools,
            accessTier: accessTier
        )
    }

    private func makeSubscription(tier: TierName) -> DuckDuckGoSubscription {
        DuckDuckGoSubscription(
            productId: "test",
            name: "test",
            billingPeriod: .yearly,
            startedAt: Date(),
            expiresOrRenewsAt: Date().addingTimeInterval(86400 * 30),
            platform: .stripe,
            status: .autoRenewable,
            activeOffers: [],
            tier: tier,
            availableChanges: nil,
            pendingPlans: nil
        )
    }
}

// MARK: - Mocks

private final class MockModelsService: AIChatModelsProviding {
    var modelsToReturn: [AIChatRemoteModel] = []
    var errorToThrow: Error?

    func fetchModels() async throws -> [AIChatRemoteModel] {
        if let error = errorToThrow { throw error }
        return modelsToReturn
    }
}
