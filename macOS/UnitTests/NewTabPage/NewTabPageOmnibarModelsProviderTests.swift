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

@MainActor
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
        XCTAssertTrue(item?.isAvailable == true)
        XCTAssertTrue(item?.supportsImageUpload == true)
        XCTAssertEqual(item?.supportedTools, ["WebSearch", "NewsSearch"])
        XCTAssertNil(item?.accessTier)
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

        XCTAssertTrue(freeItem?.isAvailable == true)
        XCTAssertTrue(premiumItem?.isAvailable == false)
    }

    func testWhenSubscribedUserThenAllAccessibleModelsAreEnabled() async {
        mockSubscriptionManager.resultSubscription = .success(makeSubscription(tier: .plus))
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "free-model", accessTier: ["free", "plus"]),
            makeRemoteModel(id: "plus-model", accessTier: ["plus", "pro"]),
        ]

        let sections = await provider.fetchAIModelSections()
        let allItems = sections.flatMap(\.items)

        XCTAssertTrue(allItems.allSatisfy(\.isAvailable))
    }

    /// A Pro-only model must still show (disabled, with an upsell) to a Plus subscriber, not be dropped.
    func testWhenSubscribedPlusUserThenProOnlyModelIsShownDisabledWithUpgradeUpsell() async {
        mockSubscriptionManager.resultSubscription = .success(makeSubscription(tier: .plus))
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "plus-model", accessTier: ["plus", "pro"]),
            makeRemoteModel(id: "pro-only", accessTier: ["pro"]),
            makeRemoteModel(id: "free-model", accessTier: ["free", "plus"]),
        ]

        let sections = await provider.fetchAIModelSections()
        let allItems = sections.flatMap(\.items)
        let proOnlyItem = allItems.first(where: { $0.id == "pro-only" })

        XCTAssertTrue(allItems.contains(where: { $0.id == "plus-model" }))
        XCTAssertTrue(allItems.contains(where: { $0.id == "free-model" }))
        XCTAssertEqual(proOnlyItem?.isAvailable, false)
        XCTAssertEqual(proOnlyItem?.accessTier, "pro")
        XCTAssertEqual(proOnlyItem?.upsell, "upgrade")
    }

    // MARK: - Attachment Limits Tests

    func testWhenResponseHasNoAttachmentLimitsThenProviderLimitsAreNil() async {
        mockModelsService.modelsToReturn = [makeRemoteModel(id: "free-model", accessTier: ["free"])]
        mockModelsService.attachmentLimitsToReturn = nil

        _ = await provider.fetchAIModelSections()

        XCTAssertNil(provider.attachmentLimits)
    }

    func testWhenResponseHasAttachmentLimitsThenTheyAreMappedForFreeTier() async {
        mockModelsService.modelsToReturn = [makeRemoteModel(id: "free-model", accessTier: ["free"])]
        mockModelsService.attachmentLimitsToReturn = makeAttachmentLimits()

        _ = await provider.fetchAIModelSections()

        XCTAssertEqual(provider.attachmentLimits, expectedAttachmentLimits(base: freeBase))
    }

    func testWhenPlusUserThenPlusAttachmentLimitsAreMapped() async {
        mockSubscriptionManager.resultSubscription = .success(makeSubscription(tier: .plus))
        mockModelsService.modelsToReturn = [makeRemoteModel(id: "plus-model", accessTier: ["plus"])]
        mockModelsService.attachmentLimitsToReturn = makeAttachmentLimits()

        _ = await provider.fetchAIModelSections()

        XCTAssertEqual(provider.attachmentLimits, expectedAttachmentLimits(base: plusBase))
    }

    func testWhenProUserThenProAttachmentLimitsAreMapped() async {
        mockSubscriptionManager.resultSubscription = .success(makeSubscription(tier: .pro))
        mockModelsService.modelsToReturn = [makeRemoteModel(id: "pro-model", accessTier: ["pro"])]
        mockModelsService.attachmentLimitsToReturn = makeAttachmentLimits()

        _ = await provider.fetchAIModelSections()

        XCTAssertEqual(provider.attachmentLimits, expectedAttachmentLimits(base: proBase))
    }

    func testWhenFetchFailsThenAttachmentLimitsRemainNil() async {
        mockModelsService.errorToThrow = NSError(domain: "test", code: -1)

        _ = await provider.fetchAIModelSections()

        XCTAssertNil(provider.attachmentLimits)
    }

    // MARK: - Reasoning Effort Tests

    /// One entry per conceptual mode, not per raw effort — `id` is the mode's representative effort.
    func testWhenModelHasSupportedReasoningEffortThenItIsMappedToItem() async {
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "reasoning-model", supportedReasoningEffort: [.none, .low, .medium], accessTier: ["free"])
        ]

        let sections = await provider.fetchAIModelSections()
        let item = sections.flatMap(\.items).first(where: { $0.id == "reasoning-model" })

        XCTAssertEqual(item?.reasoningEfforts.map(\.id), ["none", "low", "medium"])
        XCTAssertEqual(item?.reasoningEfforts.map(\.isAvailable), [true, true, true])
        XCTAssertEqual(item?.reasoningEfforts.map(\.upsell), [nil, nil, nil])
        XCTAssertEqual(item?.reasoningEfforts.first?.name, UserText.aiChatReasoningEffortFastTitle)
        XCTAssertEqual(item?.reasoningEfforts.first?.description, UserText.aiChatReasoningEffortFastSubtitle)
    }

    func testWhenModelHasNoReasoningSupportThenMappedItemHasEmptyArray() async {
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "plain-model", accessTier: ["free"])
        ]

        let sections = await provider.fetchAIModelSections()
        let item = sections.flatMap(\.items).first(where: { $0.id == "plain-model" })

        XCTAssertEqual(item?.reasoningEfforts, [])
    }

    /// A reasoning effort gated behind a higher tier than the user's must be mapped `unavailable`
    /// with the right `upsell` flow, while effort ids/order stay stable regardless of gating.
    func testWhenReasoningEffortIsGatedForPlusUserThenItIsMappedUnavailableWithUpgradeUpsell() async {
        mockSubscriptionManager.resultSubscription = .success(makeSubscription(tier: .plus))
        mockModelsService.modelsToReturn = [
            makeRemoteModel(
                id: "reasoning-model",
                supportedReasoningEffort: [.none, .low, .medium],
                accessTier: ["free", "plus", "pro"],
                reasoningEffortAccess: [
                    AIChatReasoningEffortAccess(effort: .none, accessTier: ["free", "plus", "pro"], entityHasAccess: true),
                    AIChatReasoningEffortAccess(effort: .low, accessTier: ["free", "plus", "pro"], entityHasAccess: true),
                    AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro"], entityHasAccess: false)
                ]
            )
        ]

        let sections = await provider.fetchAIModelSections()
        let efforts = sections.flatMap(\.items).first(where: { $0.id == "reasoning-model" })?.reasoningEfforts

        XCTAssertEqual(efforts?.map(\.id), ["none", "low", "medium"])
        XCTAssertEqual(efforts?.map(\.isAvailable), [true, true, false])
        XCTAssertEqual(efforts?.last?.upsell, "upgrade")
        XCTAssertEqual(efforts?.last?.name, UserText.aiChatReasoningEffortMediumTitle)
    }

    /// The same gated effort routes to "subscribe" rather than "upgrade" for a free user.
    func testWhenReasoningEffortIsGatedForFreeUserThenItIsMappedUnavailableWithSubscribeUpsell() async {
        mockModelsService.modelsToReturn = [
            makeRemoteModel(
                id: "reasoning-model",
                supportedReasoningEffort: [.none, .low],
                accessTier: ["free"],
                reasoningEffortAccess: [
                    AIChatReasoningEffortAccess(effort: .none, accessTier: ["free"], entityHasAccess: true),
                    AIChatReasoningEffortAccess(effort: .low, accessTier: ["plus", "pro"], entityHasAccess: false)
                ]
            )
        ]

        let sections = await provider.fetchAIModelSections()
        let efforts = sections.flatMap(\.items).first(where: { $0.id == "reasoning-model" })?.reasoningEfforts

        XCTAssertEqual(efforts?.last?.isAvailable, false)
        XCTAssertEqual(efforts?.last?.upsell, "subscribe")
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

    func testWhenSubscribedUserHasGatedModelThenTwoSectionsReturned() async {
        mockSubscriptionManager.resultSubscription = .success(makeSubscription(tier: .plus))
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "plus-model", accessTier: ["plus"]),
            makeRemoteModel(id: "pro-only", accessTier: ["pro"]),
        ]

        let sections = await provider.fetchAIModelSections()

        XCTAssertEqual(sections.count, 2)
        XCTAssertNil(sections[0].header)
        XCTAssertNotNil(sections[1].header)
    }

    /// A subscribed user with nothing gated gets one flat section — this is what regressed to two
    /// sections under the old Basic/Advanced split (Asana comment 1216793923923610).
    func testWhenSubscribedUserHasNothingGatedThenSingleSectionReturned() async {
        mockSubscriptionManager.resultSubscription = .success(makeSubscription(tier: .plus))
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "plus-model", accessTier: ["plus"]),
            makeRemoteModel(id: "free-model", accessTier: ["free", "plus"]),
        ]

        let sections = await provider.fetchAIModelSections()

        XCTAssertEqual(sections.count, 1)
        XCTAssertNil(sections[0].header)
    }

    /// Mirrors the address bar's model picker: a subscriber's accessible models — whether "basic"
    /// or "advanced" tier — render as one flat, ordered section, not split by tier. The old split
    /// produced a stray unheaded section for a Pro user (who has both kinds accessible), causing a
    /// UI inconsistency reported in Asana comment 1216793923923610.
    func testWhenProUserHasBothBasicAndAdvancedModelsThenSingleFlatSectionReturned() async {
        mockSubscriptionManager.resultSubscription = .success(makeSubscription(tier: .pro))
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "basic-model", accessTier: ["free", "plus", "pro"]),
            makeRemoteModel(id: "advanced-model", accessTier: ["plus", "pro"]),
        ]

        let sections = await provider.fetchAIModelSections()

        XCTAssertEqual(sections.count, 1)
        XCTAssertNil(sections[0].header)
        XCTAssertEqual(Set(sections[0].items.map(\.id)), ["basic-model", "advanced-model"])
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

    /// A transient failure after a prior success must not mix a fresh-empty model list with the
    /// stale `isEligibleForFreeTrial`/`attachmentLimits` left over from that success — either both
    /// describe the last good fetch, or neither does.
    func testWhenFetchFailsAfterPriorSuccessThenLastKnownGoodSectionsAreReturned() async {
        mockSubscriptionManager.isEligibleForFreeTrialResult = true
        mockModelsService.modelsToReturn = [makeRemoteModel(id: "free-model", accessTier: ["free"])]
        let goodSections = await provider.fetchAIModelSections()
        XCTAssertFalse(goodSections.isEmpty)

        mockModelsService.errorToThrow = NSError(domain: "test", code: -1)
        let sectionsAfterFailure = await provider.fetchAIModelSections()

        XCTAssertEqual(sectionsAfterFailure.flatMap(\.items).map(\.id), goodSections.flatMap(\.items).map(\.id))
        XCTAssertTrue(provider.isEligibleForFreeTrial)
    }

    func testWhenSubscriptionFailsThenDefaultsToFreeUser() async {
        mockSubscriptionManager.resultSubscription = .failure(NSError(domain: "test", code: -1))
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "free-model", accessTier: ["free"]),
            makeRemoteModel(id: "premium-model", accessTier: ["plus"]),
        ]

        let sections = await provider.fetchAIModelSections()
        let premiumItem = sections.flatMap(\.items).first(where: { $0.id == "premium-model" })

        XCTAssertTrue(premiumItem?.isAvailable == false)
    }

    // MARK: - Free Trial Eligibility

    func testWhenFreeUserEligibleForFreeTrialThenProviderReflectsIt() async {
        mockSubscriptionManager.isEligibleForFreeTrialResult = true
        mockModelsService.modelsToReturn = [makeRemoteModel(id: "free-model", accessTier: ["free"])]

        _ = await provider.fetchAIModelSections()

        XCTAssertTrue(provider.isEligibleForFreeTrial)
    }

    func testWhenFreeUserNotEligibleForFreeTrialThenProviderReflectsIt() async {
        mockSubscriptionManager.isEligibleForFreeTrialResult = false
        mockModelsService.modelsToReturn = [makeRemoteModel(id: "free-model", accessTier: ["free"])]

        _ = await provider.fetchAIModelSections()

        XCTAssertFalse(provider.isEligibleForFreeTrial)
    }

    /// StoreKit trial eligibility is independent of subscription tier — an existing subscriber can
    /// still read as eligible. The tier check has to win, or a subscriber would see "Try for Free".
    func testWhenSubscribedUserThenNotEligibleForFreeTrialRegardlessOfStoreKit() async {
        mockSubscriptionManager.resultSubscription = .success(makeSubscription(tier: .plus))
        mockSubscriptionManager.isEligibleForFreeTrialResult = true
        mockModelsService.modelsToReturn = [makeRemoteModel(id: "plus-model", accessTier: ["plus"])]

        _ = await provider.fetchAIModelSections()

        XCTAssertFalse(provider.isEligibleForFreeTrial)
    }

    // MARK: - Concurrency

    /// Overlapping callers (`NewTabPageOmnibarClient.getConfig` and `refreshModelsAndNotify`) must
    /// not corrupt the cached sections. `@MainActor` isolation serializes these accesses on the main
    /// actor; before isolation the provider was non-isolated, so concurrent writes to
    /// `lastFetchedSections` raced on the array's ARC refcount and double-freed its backing storage
    /// (EXC_BAD_ACCESS in `swift_arrayDestroy`, Sentry APPLE-MACOS-C4H/C6Q/C72). Hammering the
    /// provider from many overlapping tasks must complete with a well-formed cache; most effective
    /// under the Thread Sanitizer.
    func testWhenFetchedConcurrentlyThenCachedSectionsAreNotCorrupted() async {
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "free-model", accessTier: ["free"]),
            makeRemoteModel(id: "premium-model", accessTier: ["plus", "pro"]),
        ]
        let provider = self.provider!

        // Child tasks only return values; assertions run in this `@MainActor` parent so XCTest
        // failure recording is never invoked concurrently from background executors.
        let fetchedIDs = await withTaskGroup(of: [String]?.self) { group -> [[String]] in
            for _ in 0..<500 {
                group.addTask {
                    await provider.fetchAIModelSections().flatMap(\.items).map(\.id)
                }
                // Interleave concurrent reads of the cached property with the in-flight writes.
                group.addTask {
                    _ = await provider.lastFetchedSections
                    return nil
                }
            }
            return await group.reduce(into: [[String]]()) { result, ids in
                if let ids { result.append(ids) }
            }
        }

        for ids in fetchedIDs {
            XCTAssertEqual(Set(ids), ["free-model", "premium-model"])
        }
        XCTAssertEqual(Set(provider.lastFetchedSections?.flatMap(\.items).map(\.id) ?? []),
                       ["free-model", "premium-model"])
    }

    // MARK: - Helpers

    private func makeRemoteModel(
        id: String,
        name: String = "Model",
        shortName: String? = nil,
        supportsImageUpload: Bool = false,
        supportedTools: [String] = [],
        supportedReasoningEffort: [AIChatReasoningEffort] = [],
        accessTier: [String],
        reasoningEffortAccess: [AIChatReasoningEffortAccess]? = nil
    ) -> AIChatRemoteModel {
        AIChatRemoteModel(
            id: id,
            name: name,
            modelShortName: shortName ?? id,
            provider: "openai",
            entityHasAccess: true,
            supportsImageUpload: supportsImageUpload,
            supportedTools: supportedTools,
            accessTier: accessTier,
            supportedReasoningEffort: supportedReasoningEffort,
            reasoningEffortAccess: reasoningEffortAccess
        )
    }

    // Distinct base values per tier so tier-specific mapping is verifiable.
    private let freeBase = 10
    private let plusBase = 100
    private let proBase = 1000

    private func makeAttachmentLimits() -> AIChatAttachmentLimits {
        AIChatAttachmentLimits(
            free: makeTierLimits(base: freeBase),
            plus: makeTierLimits(base: plusBase),
            pro: makeTierLimits(base: proBase)
        )
    }

    private func makeTierLimits(base: Int) -> AIChatAttachmentTierLimits {
        AIChatAttachmentTierLimits(
            files: AIChatAttachmentFileLimits(
                maxPerConversation: base + 1,
                maxFileSizeMB: base + 2,
                maxTotalFileSizeBytes: base + 3,
                maxPagesPerFile: base + 4
            ),
            images: AIChatAttachmentImageLimits(
                maxPerTurn: base + 5,
                maxPerConversation: base + 6,
                maxInputCharsWithAttachments: base + 7
            )
        )
    }

    private func expectedAttachmentLimits(base: Int) -> NewTabPageDataModel.AttachmentLimits {
        NewTabPageDataModel.AttachmentLimits(
            files: .init(
                maxPerConversation: base + 1,
                maxFileSizeMB: base + 2,
                maxTotalFileSizeBytes: base + 3,
                maxPagesPerFile: base + 4
            ),
            images: .init(
                maxPerTurn: base + 5,
                maxPerConversation: base + 6,
                maxInputCharsWithAttachments: base + 7
            )
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

@MainActor
private final class MockModelsService: AIChatModelsProviding {
    var modelsToReturn: [AIChatRemoteModel] = []
    var attachmentLimitsToReturn: AIChatAttachmentLimits?
    var errorToThrow: Error?

    func fetchModels() async throws -> AIChatModelsResponse {
        if let error = errorToThrow { throw error }
        return AIChatModelsResponse(models: modelsToReturn, attachmentLimits: attachmentLimitsToReturn)
    }
}
