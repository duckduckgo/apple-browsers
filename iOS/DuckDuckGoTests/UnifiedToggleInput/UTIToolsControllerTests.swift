//
//  UTIToolsControllerTests.swift
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

/// The tools menu's presentation rules. `.legacy` is the pre-`updatedCreateImage` behaviour and is
/// also what the iPad address bar gets, since it never passes a policy — so the `.legacy` cases here
/// double as regression cover for that surface.
@MainActor
final class UTIToolsControllerTests: XCTestCase {

    private var sut: UTIToolsController!
    private var modelStore: UTIModelStore!
    private var preferences: StubToolsPreferences!

    override func setUp() {
        super.setUp()
        sut = UTIToolsController()
        preferences = StubToolsPreferences()
        modelStore = UTIModelStore(
            modelsService: StubToolsModelsService(),
            preferences: preferences,
            subscriptionManager: SubscriptionManagerMock(),
            isUpdatedModelPickerEnabled: false
        )
    }

    override func tearDown() {
        sut = nil
        modelStore = nil
        preferences = nil
        super.tearDown()
    }

    // MARK: - Create Image enablement

    func test_legacy_createImageIsEnabledOnlyWhenTheSelectedModelSupportsIt() {
        selectModel(supportedTools: [.imageGeneration])
        XCTAssertTrue(isCreateImageEnabled(policy: .legacy))

        selectModel(supportedTools: [])
        XCTAssertFalse(isCreateImageEnabled(policy: .legacy))
    }

    func test_updated_createImageIsEnabledOnAnUnsupportedModelWhenTheModelCanBeSwitched() {
        selectModel(supportedTools: [])

        XCTAssertTrue(isCreateImageEnabled(policy: .updated(canSwitchModel: true)))
    }

    func test_updated_createImageStaysDisabledOnAnUnsupportedModelWhenTheModelCannotBeSwitched() {
        selectModel(supportedTools: [])

        XCTAssertFalse(isCreateImageEnabled(policy: .updated(canSwitchModel: false)))
    }

    func test_updated_createImageIsEnabledOnASupportedModelRegardlessOfSwitching() {
        selectModel(supportedTools: [.imageGeneration])

        XCTAssertTrue(isCreateImageEnabled(policy: .updated(canSwitchModel: false)))
    }

    // MARK: - Create Image subtitle

    func test_updated_disabledCreateImageExplainsWhyInsteadOfDescribingItself() {
        selectModel(supportedTools: [])

        XCTAssertEqual(createImageSubtitle(policy: .updated(canSwitchModel: false)),
                       UserText.aiChatToolbarImageGenerationToolUnavailableSubtitle)
    }

    func test_updated_enabledCreateImageKeepsItsGenericSubtitle() {
        selectModel(supportedTools: [])

        XCTAssertEqual(createImageSubtitle(policy: .updated(canSwitchModel: true)),
                       UserText.aiChatToolbarImageGenerationToolSubtitle)
    }

    // MARK: - Tools button visibility

    func test_legacy_toolsButtonHidesWhenNoToolIsSupportedAndThereIsNoCustomizeResponses() {
        selectModel(supportedTools: [])

        let presentation = sut.presentation(isActive: true,
                                            modelStore: modelStore,
                                            canShowCustomizeResponses: false,
                                            createImagePolicy: .legacy)

        XCTAssertTrue(presentation.isToolsButtonHidden)
        XCTAssertNil(presentation.toolsMenu)
    }

    func test_updated_toolsButtonStaysVisibleForAnUnsupportedModelWhenCreateImageCanSwitchTheModel() {
        selectModel(supportedTools: [])

        let presentation = sut.presentation(isActive: true,
                                            modelStore: modelStore,
                                            canShowCustomizeResponses: false,
                                            createImagePolicy: .updated(canSwitchModel: true))

        XCTAssertFalse(presentation.isToolsButtonHidden)
        XCTAssertEqual(presentation.toolsMenu?.items.first { $0.identifier == .imageGeneration }?.isEnabled, true)
    }

    func test_updated_toolsButtonHidesWhenNothingIsActionableAtAll() {
        selectModel(supportedTools: [])

        let presentation = sut.presentation(isActive: true,
                                            modelStore: modelStore,
                                            canShowCustomizeResponses: false,
                                            createImagePolicy: .updated(canSwitchModel: false))

        XCTAssertTrue(presentation.isToolsButtonHidden)
    }

    func test_customizeResponsesAloneKeepsTheToolsButtonVisible() {
        selectModel(supportedTools: [])

        let presentation = sut.presentation(isActive: true,
                                            modelStore: modelStore,
                                            canShowCustomizeResponses: true,
                                            createImagePolicy: .legacy)

        XCTAssertFalse(presentation.isToolsButtonHidden)
    }

    func test_toolsButtonHidesWhileInactiveNoMatterThePolicy() {
        selectModel(supportedTools: [.imageGeneration])

        let presentation = sut.presentation(isActive: false,
                                            modelStore: modelStore,
                                            canShowCustomizeResponses: true,
                                            createImagePolicy: .updated(canSwitchModel: true))

        XCTAssertTrue(presentation.isToolsButtonHidden)
    }

    // MARK: - Web Search is untouched by the policy

    func test_webSearchEnablementIgnoresTheCreateImagePolicy() {
        selectModel(supportedTools: [])

        let legacy = webSearchItem(policy: .legacy)
        let updated = webSearchItem(policy: .updated(canSwitchModel: true))

        XCTAssertEqual(legacy?.isEnabled, false)
        XCTAssertEqual(updated?.isEnabled, false)
    }

    // MARK: - Helpers

    private func selectModel(supportedTools: [AIChatRAGTool]) {
        let model = AIChatModel(
            id: "model-under-test",
            name: "Model Under Test",
            provider: .unknown,
            supportsImageUpload: false,
            supportedTools: supportedTools,
            entityHasAccess: true
        )
        modelStore.models = [model]
        modelStore.updateSelectedModel(model.id, isNewChatContext: true)
    }

    private func menu(policy: CreateImageMenuPolicy) -> UTIToolsMenu? {
        sut.presentation(isActive: true,
                         modelStore: modelStore,
                         canShowCustomizeResponses: true,
                         createImagePolicy: policy).toolsMenu
    }

    private func createImageItem(policy: CreateImageMenuPolicy) -> UTIToolsMenu.Item? {
        menu(policy: policy)?.items.first { $0.identifier == .imageGeneration }
    }

    private func webSearchItem(policy: CreateImageMenuPolicy) -> UTIToolsMenu.Item? {
        menu(policy: policy)?.items.first { $0.identifier == .webSearch }
    }

    private func isCreateImageEnabled(policy: CreateImageMenuPolicy) -> Bool {
        createImageItem(policy: policy)?.isEnabled ?? false
    }

    private func createImageSubtitle(policy: CreateImageMenuPolicy) -> String? {
        guard case let .imageGeneration(_, _, subtitle) = createImageItem(policy: policy) else { return nil }
        return subtitle
    }
}

// MARK: - Test doubles

private final class StubToolsPreferences: AIChatPreferencesPersisting {
    var selectedReasoningEffort: String?
    var selectedModelId: String?
    var selectedModelShortName: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
}

@MainActor
private final class StubToolsModelsService: AIChatModelsProviding {
    func fetchModels() async throws -> AIChatModelsResponse { AIChatModelsResponse(models: []) }
}
