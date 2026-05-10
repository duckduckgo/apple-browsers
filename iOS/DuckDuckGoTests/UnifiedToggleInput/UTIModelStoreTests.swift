//
//  UTIModelStoreTests.swift
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

import AIChat
import Combine
import SubscriptionTestingUtilities
import XCTest
@testable import DuckDuckGo

@MainActor
final class UTIModelStoreTests: XCTestCase {

    private var sut: UTIModelStore!
    private var preferences: StubPreferences!
    private var modelsService: StubModelsService!
    private var subscriptionManager: SubscriptionManagerMock!

    override func setUp() {
        super.setUp()
        preferences = StubPreferences()
        modelsService = StubModelsService()
        subscriptionManager = SubscriptionManagerMock()
        sut = UTIModelStore(
            modelsService: modelsService,
            preferences: preferences,
            subscriptionManager: subscriptionManager
        )
    }

    override func tearDown() {
        sut = nil
        preferences = nil
        modelsService = nil
        subscriptionManager = nil
        super.tearDown()
    }

    // MARK: - persistedModelId

    func test_persistedModelId_whenNoPreferenceAndNoModels_returnsNil() {
        XCTAssertNil(sut.persistedModelId)
    }

    func test_persistedModelId_whenPreferenceSetButNoModels_returnsPreference() {
        preferences.selectedModelId = "gpt-5"
        XCTAssertEqual(sut.persistedModelId, "gpt-5")
    }

    func test_persistedModelId_whenPreferenceMatchesAccessibleModel_returnsIt() {
        preferences.selectedModelId = "gpt-5"
        sut.models = [makeModel(id: "gpt-5", access: true)]
        XCTAssertEqual(sut.persistedModelId, "gpt-5")
    }

    func test_persistedModelId_whenPreferenceMatchesInaccessibleModel_fallsBackToFirstAccessible() {
        preferences.selectedModelId = "premium"
        sut.models = [
            makeModel(id: "premium", access: false),
            makeModel(id: "free", access: true)
        ]
        XCTAssertEqual(sut.persistedModelId, "free")
    }

    func test_persistedModelId_whenPreferenceNotInModelList_fallsBackToFirstAccessible() {
        preferences.selectedModelId = "deleted-model"
        sut.models = [
            makeModel(id: "gpt-5", access: true),
            makeModel(id: "claude", access: true)
        ]
        XCTAssertEqual(sut.persistedModelId, "gpt-5")
    }

    func test_persistedModelId_whenNoPreferenceButModelsExist_returnsFirstAccessible() {
        sut.models = [
            makeModel(id: "locked", access: false),
            makeModel(id: "free", access: true)
        ]
        XCTAssertEqual(sut.persistedModelId, "free")
    }

    func test_persistedModelId_whenAllModelsInaccessible_returnsNil() {
        sut.models = [
            makeModel(id: "locked1", access: false),
            makeModel(id: "locked2", access: false)
        ]
        XCTAssertNil(sut.persistedModelId)
    }

    // MARK: - selectedModelSupportsImageUpload

    func test_selectedModelSupportsImageUpload_whenNoModels_returnsFalse() {
        XCTAssertFalse(sut.selectedModelSupportsImageUpload)
    }

    func test_selectedModelSupportsImageUpload_whenSelectedModelSupportsIt_returnsTrue() {
        preferences.selectedModelId = "gpt-4o"
        sut.models = [makeModel(id: "gpt-4o", access: true, supportsImageUpload: true)]
        XCTAssertTrue(sut.selectedModelSupportsImageUpload)
    }

    func test_selectedModelSupportsImageUpload_whenSelectedModelDoesNot_returnsFalse() {
        preferences.selectedModelId = "gpt-5"
        sut.models = [makeModel(id: "gpt-5", access: true, supportsImageUpload: false)]
        XCTAssertFalse(sut.selectedModelSupportsImageUpload)
    }

    func test_selectedModelSupportsFileUpload_whenSelectedModelSupportsIt_returnsTrue() {
        preferences.selectedModelId = "gpt-4o"
        sut.models = [makeModel(id: "gpt-4o", access: true, supportedFileTypes: ["application/pdf"])]

        XCTAssertTrue(sut.selectedModelSupportsFileUpload)
        XCTAssertEqual(sut.selectedModelSupportedFileTypes, ["application/pdf"])
    }

    func test_selectedModelSupportsFileUpload_whenNoModelSelected_returnsFalse() {
        XCTAssertFalse(sut.selectedModelSupportsFileUpload)
        XCTAssertEqual(sut.selectedModelSupportedFileTypes, [])
    }

    // MARK: - selectedModelSupports(tool:)

    func test_selectedModelSupportsTool_whenSelectedModelSupportsWebSearch_returnsTrue() {
        preferences.selectedModelId = "gpt-5"
        sut.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.webSearch])]

        XCTAssertTrue(sut.selectedModelSupports(tool: .webSearch))
    }

    func test_selectedModelSupportsTool_whenSelectedModelDoesNotSupportWebSearch_returnsFalse() {
        preferences.selectedModelId = "gpt-5"
        sut.models = [makeModel(id: "gpt-5", access: true)]

        XCTAssertFalse(sut.selectedModelSupports(tool: .webSearch))
    }

    // MARK: - clearStaleModelSelectionIfNeeded

    func test_clearStale_whenSelectedModelNoLongerInList_clearsPreferences() {
        preferences.selectedModelId = "removed-model"
        preferences.selectedModelShortName = "Removed"
        sut.models = [makeModel(id: "gpt-5", access: true)]

        sut.clearStaleModelSelectionIfNeeded()

        XCTAssertNil(preferences.selectedModelId)
        XCTAssertNil(preferences.selectedModelShortName)
    }

    func test_clearStale_whenSelectedModelIsInaccessible_clearsPreferences() {
        preferences.selectedModelId = "premium"
        preferences.selectedModelShortName = "Premium"
        sut.models = [makeModel(id: "premium", access: false)]

        sut.clearStaleModelSelectionIfNeeded()

        XCTAssertNil(preferences.selectedModelId)
        XCTAssertNil(preferences.selectedModelShortName)
    }

    func test_clearStale_whenSelectedModelIsValid_preservesPreferences() {
        preferences.selectedModelId = "gpt-5"
        preferences.selectedModelShortName = "GPT-5"
        sut.models = [makeModel(id: "gpt-5", access: true)]

        sut.clearStaleModelSelectionIfNeeded()

        XCTAssertEqual(preferences.selectedModelId, "gpt-5")
        XCTAssertEqual(preferences.selectedModelShortName, "GPT-5")
    }

    func test_clearStale_whenNoModels_doesNotClear() {
        preferences.selectedModelId = "gpt-5"
        sut.models = []

        sut.clearStaleModelSelectionIfNeeded()

        XCTAssertEqual(preferences.selectedModelId, "gpt-5")
    }

    func test_clearStale_whenNoSelection_doesNothing() {
        sut.models = [makeModel(id: "gpt-5", access: true)]

        sut.clearStaleModelSelectionIfNeeded()

        XCTAssertNil(preferences.selectedModelId)
    }

    // MARK: - updateSelectedModel

    func test_updateSelectedModel_writesPreferences() {
        sut.models = [
            AIChatModel(id: "gpt-5", name: "GPT-5", shortName: "G5", provider: .openAI, supportsImageUpload: false, entityHasAccess: true)
        ]

        sut.updateSelectedModel("gpt-5")

        XCTAssertEqual(preferences.selectedModelId, "gpt-5")
        XCTAssertEqual(preferences.selectedModelShortName, "G5")
    }

    func test_updateSelectedModel_whenReasoningModeIsUnsupported_clearsSelection() {
        preferences.selectedReasoningMode = .extendedReasoning
        sut.models = [
            makeModel(id: "gpt-5", access: true, supportedReasoningEffort: [.none, .low])
        ]

        sut.updateSelectedModel("gpt-5")

        XCTAssertNil(preferences.selectedReasoningMode)
    }

    func test_updateSelectedModel_whenReasoningModeIsSupported_preservesSelection() {
        preferences.selectedReasoningMode = .extendedReasoning
        sut.models = [
            makeModel(id: "gpt-5", access: true, supportedReasoningEffort: [.none, .low, .medium])
        ]

        sut.updateSelectedModel("gpt-5")

        XCTAssertEqual(preferences.selectedReasoningMode, .extendedReasoning)
    }

    func test_updateSelectedReasoningMode_whenModeIsUnsupported_doesNotWritePreference() {
        preferences.selectedReasoningMode = .fast
        preferences.selectedModelId = "gpt-5"
        sut.models = [
            makeModel(id: "gpt-5", access: true, supportedReasoningEffort: [.none, .low])
        ]

        sut.updateSelectedReasoningMode(.extendedReasoning)

        XCTAssertEqual(preferences.selectedReasoningMode, .fast)
    }

    func test_fetchModels_whenModelFetchFails_clearsAttachmentLimitsAndNotifies() async {
        let didUpdate = expectation(description: "models updated")
        modelsService.result = .failure(StubModelsService.StubError.fetchFailed)
        sut.attachmentLimits = makeLimits()
        sut.onModelsUpdated = {
            didUpdate.fulfill()
        }

        sut.fetchModels()

        await fulfillment(of: [didUpdate], timeout: 1)
        XCTAssertNil(sut.attachmentLimits)
        XCTAssertEqual(sut.subscriptionState.userTier, .free)
    }

    // MARK: - Helpers

    private func makeLimits() -> AIChatAttachmentTierLimits {
        AIChatAttachmentTierLimits(
            files: AIChatAttachmentFileLimits(maxPerConversation: 3, maxFileSizeMB: 5, maxTotalFileSizeBytes: 5_242_880, maxPagesPerFile: 8),
            images: AIChatAttachmentImageLimits(maxPerTurn: 3, maxPerConversation: 5, maxInputCharsWithAttachments: 4500)
        )
    }

    private func makeModel(
        id: String,
        access: Bool,
        supportsImageUpload: Bool = false,
        supportedFileTypes: [String] = [],
        supportedTools: [AIChatRAGTool] = [],
        supportedReasoningEffort: [AIChatReasoningEffort] = []
    ) -> AIChatModel {
        AIChatModel(
            id: id,
            name: id,
            provider: .unknown,
            supportsImageUpload: supportsImageUpload,
            supportedFileTypes: supportedFileTypes,
            supportedTools: supportedTools,
            entityHasAccess: access,
            supportedReasoningEffort: supportedReasoningEffort
        )
    }
}

private final class StubPreferences: AIChatPreferencesPersisting {
    var selectedReasoningEffort: String?
    var selectedModelId: String?
    var selectedModelShortName: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
}

private final class StubModelsService: AIChatModelsProviding {
    enum StubError: Error {
        case fetchFailed
    }

    var result: Result<AIChatModelsResponse, Error> = .success(AIChatModelsResponse(models: []))

    func fetchModels() async throws -> AIChatModelsResponse { try result.get() }
}
