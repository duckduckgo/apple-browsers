//
//  CreateImageModelSwitcherTests.swift
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
final class CreateImageModelSwitcherTests: XCTestCase {

    private var toolsController: UTIToolsController!
    private var modelStore: UTIModelStore!
    private var preferences: StubSwitcherPreferences!
    private var appliedModelIds: [String]!
    private var pixelFiring: MockCreateImagePixelFiring!

    override func setUp() {
        super.setUp()
        toolsController = UTIToolsController()
        preferences = StubSwitcherPreferences()
        appliedModelIds = []
        pixelFiring = MockCreateImagePixelFiring()
        modelStore = UTIModelStore(
            modelsService: StubSwitcherModelsService(),
            preferences: preferences,
            subscriptionManager: SubscriptionManagerMock(),
            isUpdatedModelPickerEnabled: false
        )
    }

    override func tearDown() {
        toolsController = nil
        modelStore = nil
        preferences = nil
        appliedModelIds = nil
        pixelFiring = nil
        super.tearDown()
    }

    // MARK: - select

    func test_select_onAModelWithoutImageSupport_switchesToTheFallbackAndSelectsTheTool() {
        seedModels(selecting: "mistral")

        let notice = select()

        XCTAssertEqual(appliedModelIds, ["image-capable"])
        XCTAssertEqual(toolsController.selectedTool, .imageGeneration)
        XCTAssertEqual(notice?.previousModelShortName, "mistral")
        XCTAssertEqual(notice?.newModelShortName, "image-capable")
    }

    func test_select_prefersTheEndorsedImageCapableModel() {
        modelStore.models = [
            makeModel(id: "mistral"),
            makeModel(id: "unlabelled-image-model", supportedTools: [.imageGeneration]),
            makeModel(id: "endorsed-image-model", supportedTools: [.imageGeneration], label: .everydayUse)
        ]
        modelStore.updateSelectedModel("mistral", isNewChatContext: true)

        select()

        XCTAssertEqual(appliedModelIds, ["endorsed-image-model"])
    }

    func test_select_onAModelThatAlreadySupportsImages_leavesTheModelAlone() {
        seedModels(selecting: "image-capable")

        let notice = select()

        XCTAssertEqual(appliedModelIds, [])
        XCTAssertNil(notice)
        XCTAssertEqual(toolsController.selectedTool, .imageGeneration)
    }

    func test_select_onAnAlreadySelectedTool_keepsItSelected() {
        seedModels(selecting: "mistral")
        select()

        select()

        XCTAssertEqual(toolsController.selectedTool, .imageGeneration)
    }

    func test_select_whenTheSurfaceCannotSwitchModels_neitherSwitchesNorSelects() {
        seedModels(selecting: "mistral")

        let notice = select(canSwitchModel: false)

        XCTAssertEqual(appliedModelIds, [])
        XCTAssertNil(notice)
        XCTAssertNil(toolsController.selectedTool)
    }

    func test_select_withoutAnImageCapableModelOnTheList_neitherSwitchesNorSelects() {
        modelStore.models = [makeModel(id: "mistral")]
        modelStore.updateSelectedModel("mistral", isNewChatContext: true)

        let notice = select()

        XCTAssertEqual(appliedModelIds, [])
        XCTAssertNil(notice)
        XCTAssertNil(toolsController.selectedTool)
    }

    func test_select_withAnInaccessibleFallbackModel_doesNotSwitch() {
        modelStore.models = [
            makeModel(id: "mistral"),
            makeModel(id: "image-capable", access: false, supportedTools: [.imageGeneration])
        ]
        modelStore.updateSelectedModel("mistral", isNewChatContext: true)

        let notice = select()

        XCTAssertEqual(appliedModelIds, [])
        XCTAssertNil(notice)
        XCTAssertNil(toolsController.selectedTool)
    }

    func test_select_withTheFeatureOff_keepsTheOldSilentNoOp() {
        seedModels(selecting: "mistral")

        let notice = select(isFeatureEnabled: false)

        XCTAssertEqual(appliedModelIds, [])
        XCTAssertNil(notice)
        XCTAssertNil(toolsController.selectedTool)
    }

    func test_select_appliesTheModelBeforeSelectingTheTool() {
        seedModels(selecting: "mistral")
        var toolWasStillUnselectedWhenModelApplied = false

        makeSUT().select(
            toolsController: toolsController,
            modelStore: modelStore,
            canSwitchModel: true,
            entryPoint: .toolsMenu,
            applyModel: { modelId in
                toolWasStillUnselectedWhenModelApplied = self.toolsController.selectedTool == nil
                self.applyModel(modelId)
            }
        )

        XCTAssertTrue(toolWasStillUnselectedWhenModelApplied)
        XCTAssertEqual(toolsController.selectedTool, .imageGeneration)
    }

    // MARK: - toggle

    func test_toggle_onAModelWithoutImageSupport_switchesToTheFallbackAndSelectsTheTool() {
        seedModels(selecting: "mistral")

        let notice = toggle()

        XCTAssertEqual(appliedModelIds, ["image-capable"])
        XCTAssertEqual(toolsController.selectedTool, .imageGeneration)
        XCTAssertNotNil(notice)
    }

    func test_toggle_deselecting_doesNotSwitchTheModel() {
        seedModels(selecting: "mistral")
        toggle()
        appliedModelIds = []

        let notice = toggle()

        XCTAssertNil(toolsController.selectedTool)
        XCTAssertEqual(appliedModelIds, [])
        XCTAssertNil(notice)
    }

    func test_toggle_withTheFeatureOff_keepsTheOldSilentNoOp() {
        seedModels(selecting: "mistral")

        let notice = toggle(isFeatureEnabled: false)

        XCTAssertEqual(appliedModelIds, [])
        XCTAssertNil(notice)
        XCTAssertNil(toolsController.selectedTool)
    }

    // MARK: - Pixels: model switched

    func test_pixels_whenTheModelIsSwitched_reportsBothModelsAndTheEntryPoint() {
        seedModels(selecting: "mistral")

        select(entryPoint: .chatHeaderNewImage)

        XCTAssertEqual(pixelFiring.switches.count, 1)
        XCTAssertEqual(pixelFiring.switches.first?.fromModelId, "mistral")
        XCTAssertEqual(pixelFiring.switches.first?.toModelId, "image-capable")
        XCTAssertEqual(pixelFiring.switches.first?.entryPoint, .chatHeaderNewImage)
    }

    func test_pixels_whenTheModelSwitchedFromHasExtraPrivacyProtections_reportsTheFlag() {
        modelStore.models = [
            makeModel(id: "gpt-oss-120b", provider: .oss),
            makeModel(id: "image-capable", supportedTools: [.imageGeneration])
        ]
        modelStore.updateSelectedModel("gpt-oss-120b", isNewChatContext: true)

        let notice = select()

        XCTAssertEqual(pixelFiring.switches.first?.fromModelHasExtraPrivacyProtections, true)
        XCTAssertEqual(notice?.previousModelHasExtraPrivacyProtections, true)
    }

    func test_pixels_whenTheModelSwitchedFromHasNoExtraPrivacyProtections_reportsTheFlagAsFalse() {
        seedModels(selecting: "mistral")

        select()

        XCTAssertEqual(pixelFiring.switches.first?.fromModelHasExtraPrivacyProtections, false)
    }

    func test_pixels_whenTheToggleSelectsCreateImage_reportsTheToolsMenu() {
        seedModels(selecting: "mistral")

        toggle()

        XCTAssertEqual(pixelFiring.switches.first?.entryPoint, .toolsMenu)
    }

    func test_pixels_whenTheToggleDeselectsCreateImage_reportsNothing() {
        seedModels(selecting: "mistral")
        toggle()
        pixelFiring.reset()

        toggle()

        XCTAssertTrue(pixelFiring.isEmpty)
    }

    func test_pixels_withoutAnEntryPoint_switchesTheModelButReportsNoSwitch() {
        seedModels(selecting: "mistral")

        let notice = select(entryPoint: nil)

        XCTAssertEqual(appliedModelIds, ["image-capable"])
        XCTAssertNotNil(notice)
        XCTAssertTrue(pixelFiring.switches.isEmpty)
    }

    // MARK: - Pixels: unavailable

    func test_pixels_withoutAnImageCapableModelOnTheList_reportsUnavailable() {
        modelStore.models = [makeModel(id: "mistral")]
        modelStore.updateSelectedModel("mistral", isNewChatContext: true)

        select()

        XCTAssertEqual(pixelFiring.unavailableCount, 1)
        XCTAssertTrue(pixelFiring.switches.isEmpty)
    }

    func test_pixels_withAnInaccessibleFallbackModel_reportsUnavailable() {
        modelStore.models = [
            makeModel(id: "mistral"),
            makeModel(id: "image-capable", access: false, supportedTools: [.imageGeneration])
        ]
        modelStore.updateSelectedModel("mistral", isNewChatContext: true)

        select()

        XCTAssertEqual(pixelFiring.unavailableCount, 1)
    }

    func test_pixels_withoutAnImageCapableModelAndWithoutAnEntryPoint_stillReportsUnavailable() {
        modelStore.models = [makeModel(id: "mistral")]
        modelStore.updateSelectedModel("mistral", isNewChatContext: true)

        select(entryPoint: nil)

        XCTAssertEqual(pixelFiring.unavailableCount, 1)
    }

    func test_pixels_withoutAnImageCapableModelMidConversation_reportsUnavailable() {
        modelStore.models = [makeModel(id: "mistral")]
        modelStore.updateSelectedModel("mistral", isNewChatContext: true)

        select(canSwitchModel: false)

        XCTAssertEqual(pixelFiring.unavailableCount, 1)
    }

    // MARK: - Pixels: silence

    func test_pixels_withTheFeatureOff_reportsNothing() {
        modelStore.models = [makeModel(id: "mistral")]
        modelStore.updateSelectedModel("mistral", isNewChatContext: true)

        select(isFeatureEnabled: false)

        XCTAssertTrue(pixelFiring.isEmpty)
    }

    func test_pixels_onAModelThatAlreadySupportsImages_reportsNothing() {
        seedModels(selecting: "image-capable")

        select()

        XCTAssertTrue(pixelFiring.isEmpty)
    }

    func test_pixels_midConversationWithAFallbackAvailable_reportsNothing() {
        seedModels(selecting: "mistral")

        select(canSwitchModel: false)

        XCTAssertTrue(pixelFiring.isEmpty)
    }

    // MARK: - Helpers

    private func makeSUT(isFeatureEnabled: Bool = true) -> CreateImageModelSwitcher {
        CreateImageModelSwitcher(isFeatureEnabled: isFeatureEnabled, pixelFiring: pixelFiring)
    }

    @discardableResult
    private func select(isFeatureEnabled: Bool = true,
                        canSwitchModel: Bool = true,
                        entryPoint: CreateImageEntryPoint? = .toolsMenu) -> CreateImageModelSwitchNotice? {
        makeSUT(isFeatureEnabled: isFeatureEnabled).select(
            toolsController: toolsController,
            modelStore: modelStore,
            canSwitchModel: canSwitchModel,
            entryPoint: entryPoint,
            applyModel: { self.applyModel($0) }
        )
    }

    @discardableResult
    private func toggle(isFeatureEnabled: Bool = true,
                        canSwitchModel: Bool = true,
                        entryPoint: CreateImageEntryPoint? = .toolsMenu) -> CreateImageModelSwitchNotice? {
        makeSUT(isFeatureEnabled: isFeatureEnabled).toggle(
            toolsController: toolsController,
            modelStore: modelStore,
            canSwitchModel: canSwitchModel,
            entryPoint: entryPoint,
            applyModel: { self.applyModel($0) }
        )
    }

    private func applyModel(_ modelId: String) {
        appliedModelIds.append(modelId)
        modelStore.updateSelectedModel(modelId, isNewChatContext: true)
    }

    private func seedModels(selecting id: String) {
        modelStore.models = [
            makeModel(id: "mistral"),
            makeModel(id: "image-capable", supportedTools: [.imageGeneration]),
            makeModel(id: "second-image-capable", supportedTools: [.imageGeneration])
        ]
        modelStore.updateSelectedModel(id, isNewChatContext: true)
    }

    private func makeModel(id: String,
                           access: Bool = true,
                           supportedTools: [AIChatRAGTool] = [],
                           label: AIChatModelLabel? = nil,
                           provider: AIChatModel.ModelProvider = .unknown) -> AIChatModel {
        AIChatModel(id: id,
                    name: id,
                    provider: provider,
                    supportsImageUpload: false,
                    supportedTools: supportedTools,
                    entityHasAccess: access,
                    label: label)
    }
}

// MARK: - Test doubles

private final class StubSwitcherPreferences: AIChatPreferencesPersisting {
    var selectedReasoningEffort: String?
    var selectedModelId: String?
    var selectedModelShortName: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
}

@MainActor
private final class StubSwitcherModelsService: AIChatModelsProviding {
    func fetchModels() async throws -> AIChatModelsResponse { AIChatModelsResponse(models: []) }
}
