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
import XCTest
@testable import DuckDuckGo

@MainActor
final class UTIModelStoreTests: XCTestCase {

    private var sut: UTIModelStore!
    private var preferences: StubPreferences!

    override func setUp() {
        super.setUp()
        preferences = StubPreferences()
        sut = UTIModelStore(
            modelsService: StubModelsService(),
            preferences: preferences,
            subscriptionManager: AppDependencyProvider.shared.subscriptionManager
        )
    }

    override func tearDown() {
        sut = nil
        preferences = nil
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

    // MARK: - Helpers

    private func makeModel(
        id: String,
        access: Bool,
        supportsImageUpload: Bool = false,
        supportedTools: [AIChatRAGTool] = [],
        supportedReasoningEffort: [AIChatReasoningEffort] = []
    ) -> AIChatModel {
        AIChatModel(
            id: id,
            name: id,
            provider: .unknown,
            supportsImageUpload: supportsImageUpload,
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
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
}

private final class StubModelsService: AIChatModelsProviding {
    func fetchModels() async throws -> [AIChatRemoteModel] { [] }
}
