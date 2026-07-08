//
//  IPadOmnibarToolPickerControllerTests.swift
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
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class IPadOmnibarToolPickerControllerTests: XCTestCase {

    private var sut: IPadOmnibarToolPickerController!
    private var store: UTIModelStore!
    private var preferences: StubToolPreferences!

    override func setUp() {
        super.setUp()
        preferences = StubToolPreferences()
        store = UTIModelStore(
            modelsService: StubModelsService(),
            preferences: preferences,
            subscriptionManager: SubscriptionManagerMock()
        )
        sut = IPadOmnibarToolPickerController(store: store)
    }

    override func tearDown() {
        sut = nil
        store = nil
        preferences = nil
        super.tearDown()
    }

    // MARK: - Availability

    func testWhenModelSupportsAToolThenAvailableWithMenu() {
        store.models = [makeModel(id: "gpt-5.2", supportedTools: [.webSearch])]

        XCTAssertTrue(sut.isToolPickerAvailable)
        XCTAssertNotNil(sut.makeMenu())
    }

    func testWhenModelSupportsNoToolsThenNotAvailable() {
        store.models = [makeModel(id: "gpt-oss", supportedTools: [])]

        XCTAssertFalse(sut.isToolPickerAvailable)
        XCTAssertNil(sut.makeMenu())
    }

    func testWhenNoModelsThenNotAvailableAndMenuNil() {
        XCTAssertFalse(sut.isToolPickerAvailable)
        XCTAssertNil(sut.makeMenu())
    }

    // MARK: - Selection

    func testWhenSupportedToolSelectedThenForwardedForSubmission() {
        store.models = [makeModel(id: "gpt-5.2", supportedTools: [.webSearch])]

        sut.handleToolSelection(.webSearch)

        XCTAssertEqual(sut.selectedToolsForSubmission, [.webSearch])
        XCTAssertTrue(sut.isToolSelected)
    }

    func testWhenSelectedToolToggledOffThenCleared() {
        store.models = [makeModel(id: "gpt-5.2", supportedTools: [.webSearch])]

        sut.handleToolSelection(.webSearch)
        sut.handleToolSelection(.webSearch)

        XCTAssertNil(sut.selectedToolsForSubmission)
        XCTAssertFalse(sut.isToolSelected)
    }

    func testWhenSwitchingToolsThenOnlyLatestSelected() {
        store.models = [makeModel(id: "gpt-5.2", supportedTools: [.webSearch, .imageGeneration])]

        sut.handleToolSelection(.webSearch)
        sut.handleToolSelection(.imageGeneration)

        XCTAssertEqual(sut.selectedToolsForSubmission, [.imageGeneration])
    }

    func testWhenUnsupportedToolSelectedThenIgnored() {
        store.models = [makeModel(id: "gpt-5.2", supportedTools: [.webSearch])]

        sut.handleToolSelection(.imageGeneration)

        XCTAssertNil(sut.selectedToolsForSubmission)
        XCTAssertFalse(sut.isToolSelected)
    }

    func testSelectedToolsForSubmissionIsNilWhenNothingSelected() {
        store.models = [makeModel(id: "gpt-5.2", supportedTools: [.webSearch])]

        XCTAssertNil(sut.selectedToolsForSubmission)
    }

    // MARK: - Reasoning picker interaction

    func testWhenImageGenerationSelectedThenHidesReasoningPicker() {
        store.models = [makeModel(id: "gpt-5.2", supportedTools: [.imageGeneration])]

        sut.handleToolSelection(.imageGeneration)

        XCTAssertTrue(sut.selectedToolHidesReasoningPicker)
    }

    func testWhenWebSearchSelectedThenDoesNotHideReasoningPicker() {
        store.models = [makeModel(id: "gpt-5.2", supportedTools: [.webSearch])]

        sut.handleToolSelection(.webSearch)

        XCTAssertFalse(sut.selectedToolHidesReasoningPicker)
    }

    func testWhenNoToolSelectedThenDoesNotHideReasoningPicker() {
        store.models = [makeModel(id: "gpt-5.2", supportedTools: [.webSearch])]

        XCTAssertFalse(sut.selectedToolHidesReasoningPicker)
    }

    // MARK: - Model change clears unsupported tool

    func testWhenModelChangesToOneWithoutToolThenSelectionCleared() {
        store.models = [makeModel(id: "gpt-5.2", supportedTools: [.imageGeneration])]
        sut.handleToolSelection(.imageGeneration)
        XCTAssertEqual(sut.selectedToolsForSubmission, [.imageGeneration])

        // The newly selected model doesn't support image generation.
        store.models = [makeModel(id: "gpt-basic", supportedTools: [.webSearch])]
        sut.handleModelChanged()

        XCTAssertNil(sut.selectedToolsForSubmission)
        XCTAssertFalse(sut.isToolSelected)
    }

    func testWhenModelChangesButStillSupportsToolThenSelectionKept() {
        store.models = [makeModel(id: "gpt-5.2", supportedTools: [.webSearch])]
        sut.handleToolSelection(.webSearch)

        store.models = [makeModel(id: "gpt-5.3", supportedTools: [.webSearch, .imageGeneration])]
        sut.handleModelChanged()

        XCTAssertEqual(sut.selectedToolsForSubmission, [.webSearch])
    }

    // MARK: - Reset on submit

    func testWhenResetSelectionThenToolClearedAndReasoningRestored() {
        store.models = [makeModel(id: "gpt-5.2", supportedTools: [.imageGeneration])]
        sut.handleToolSelection(.imageGeneration)
        XCTAssertTrue(sut.selectedToolHidesReasoningPicker)

        sut.resetSelection()

        XCTAssertNil(sut.selectedToolsForSubmission)
        XCTAssertFalse(sut.isToolSelected)
        XCTAssertFalse(sut.selectedToolHidesReasoningPicker)
    }

    func testWhenResetSelectionWithSelectedToolThenOnToolsUpdatedFires() {
        store.models = [makeModel(id: "gpt-5.2", supportedTools: [.webSearch])]
        sut.handleToolSelection(.webSearch)
        var updateCount = 0
        sut.onToolsUpdated = { updateCount += 1 }

        sut.resetSelection()

        XCTAssertEqual(updateCount, 1)
    }

    func testWhenResetSelectionWithNoSelectedToolThenNoUpdate() {
        store.models = [makeModel(id: "gpt-5.2", supportedTools: [.webSearch])]
        var updateCount = 0
        sut.onToolsUpdated = { updateCount += 1 }

        sut.resetSelection()

        XCTAssertEqual(updateCount, 0)
    }

    // MARK: - Update callback

    func testWhenToolSelectedThenOnToolsUpdatedFires() {
        store.models = [makeModel(id: "gpt-5.2", supportedTools: [.webSearch])]
        var updateCount = 0
        sut.onToolsUpdated = { updateCount += 1 }

        sut.handleToolSelection(.webSearch)

        XCTAssertEqual(updateCount, 1)
    }

    // MARK: - Helpers

    private func makeModel(id: String, supportedTools: [AIChatRAGTool]) -> AIChatModel {
        AIChatModel(
            id: id,
            name: id,
            shortName: id,
            provider: .openAI,
            supportsImageUpload: false,
            supportedTools: supportedTools,
            entityHasAccess: true
        )
    }
}

private final class StubToolPreferences: AIChatPreferencesPersisting {
    var selectedReasoningEffort: String?
    var selectedModelId: String?
    var selectedModelShortName: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
}

private final class StubModelsService: AIChatModelsProviding {
    var result: Result<AIChatModelsResponse, Error> = .success(AIChatModelsResponse(models: []))

    func fetchModels() async throws -> AIChatModelsResponse { try result.get() }
}
