//
//  UnifiedToggleInputToolbarViewTests.swift
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

import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class UnifiedToggleInputToolbarViewTests: XCTestCase {

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    func test_emptyInput_whenAIVoiceChatBecomesInactive_showsDisabledSubmitButton() {
        let sut = UnifiedToggleInputToolbarView()
        sut.isSubmitEnabled = false
        sut.isAIVoiceChatActive = true

        guard let submitButton = findButton(accessibilityLabel: UserText.aiChatToolbarSubmitButtonAccessibilityLabel, in: sut) else {
            XCTFail("Expected to find submit button")
            return
        }
        XCTAssertTrue(submitButton.isEnabled)

        sut.isAIVoiceChatActive = false

        XCTAssertFalse(submitButton.isEnabled)
    }

    func test_compactWidthWithLongModelName_keepsSubmitButtonVisible() {
        let sut = UnifiedToggleInputToolbarView()
        sut.translatesAutoresizingMaskIntoConstraints = false
        sut.modelName = "Claude Haiku 4.5 with a long label"

        let container = UIView(frame: CGRect(x: 0, y: 0, width: 280, height: 56))
        container.addSubview(sut)
        NSLayoutConstraint.activate([
            sut.topAnchor.constraint(equalTo: container.topAnchor),
            sut.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sut.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sut.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        container.layoutIfNeeded()

        guard let submitButton = findButton(accessibilityLabel: UserText.aiChatToolbarSubmitButtonAccessibilityLabel, in: sut) else {
            XCTFail("Expected to find submit button")
            return
        }

        let submitFrame = submitButton.convert(submitButton.bounds, to: sut)
        XCTAssertGreaterThanOrEqual(submitFrame.minX, sut.bounds.minX)
        XCTAssertLessThanOrEqual(submitFrame.maxX, sut.bounds.maxX)
    }

    func test_stopGeneratingButtonMatchesSubmitLayoutAndUsesMinimumHitTarget() {
        let sut = UnifiedToggleInputToolbarView()
        sut.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView(frame: CGRect(x: 0, y: 0, width: 280, height: 56))
        container.addSubview(sut)
        NSLayoutConstraint.activate([
            sut.topAnchor.constraint(equalTo: container.topAnchor),
            sut.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sut.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sut.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        container.layoutIfNeeded()

        guard let submitButton = findButton(accessibilityLabel: UserText.aiChatToolbarSubmitButtonAccessibilityLabel, in: sut) else {
            XCTFail("Expected to find submit button")
            return
        }

        let submitFrame = submitButton.convert(submitButton.bounds, to: sut)
        sut.isGenerating = true
        container.layoutIfNeeded()

        guard let stopButton = findButton(accessibilityIdentifier: "AIChat.Toolbar.Button.StopGenerating", in: sut) else {
            XCTFail("Expected to find stop generating button")
            return
        }

        let stopFrame = stopButton.convert(stopButton.bounds, to: sut)
        XCTAssertEqual(stopFrame.width, submitFrame.width, accuracy: 0.5)
        XCTAssertEqual(stopFrame.height, submitFrame.height, accuracy: 0.5)
        XCTAssertEqual(stopButton.image(for: .normal)?.size, CGSize(width: 24, height: 24))
        XCTAssertTrue(stopButton.hitTest(CGPoint(x: -1, y: stopButton.bounds.midY), with: nil) === stopButton)
    }

    func test_isGenerating_disablesToolbarConfigurationButtons() {
        let sut = UnifiedToggleInputToolbarView()
        sut.isImageButtonEnabled = true
        sut.selectedTool = .webSearch

        let attachmentButton = findButton(accessibilityLabel: UserText.aiChatToolbarAttachButtonAccessibilityLabel, in: sut)
        let toolsButton = findButton(accessibilityLabel: UserText.aiChatToolbarToolsButtonAccessibilityLabel, in: sut)
        let reasoningButton = findButton(accessibilityIdentifier: "AIChat.Toolbar.Button.Reasoning", in: sut)
        let modelChipButton = findButton(accessibilityIdentifier: "AIChat.Toolbar.Button.ModelChip", in: sut)
        let selectedToolClearButton = findButton(accessibilityLabel: UserText.aiChatToolbarClearSelectedToolAccessibilityLabel, in: sut)

        sut.isGenerating = true

        XCTAssertFalse(attachmentButton?.isEnabled ?? true)
        XCTAssertFalse(toolsButton?.isEnabled ?? true)
        XCTAssertFalse(reasoningButton?.isEnabled ?? true)
        XCTAssertFalse(modelChipButton?.isEnabled ?? true)
        XCTAssertFalse(selectedToolClearButton?.isEnabled ?? true)

        sut.isGenerating = false

        XCTAssertTrue(attachmentButton?.isEnabled ?? false)
        XCTAssertTrue(toolsButton?.isEnabled ?? false)
        XCTAssertTrue(reasoningButton?.isEnabled ?? false)
        XCTAssertTrue(modelChipButton?.isEnabled ?? false)
        XCTAssertTrue(selectedToolClearButton?.isEnabled ?? false)
    }

    /// A spent allowance leaves the card's own CTA as the only live control.
    func test_isInputBlockedByUsageLimit_disablesToolbarConfigurationButtons() {
        let sut = UnifiedToggleInputToolbarView()
        sut.isImageButtonEnabled = true
        sut.selectedTool = .webSearch

        let attachmentButton = findButton(accessibilityLabel: UserText.aiChatToolbarAttachButtonAccessibilityLabel, in: sut)
        let toolsButton = findButton(accessibilityLabel: UserText.aiChatToolbarToolsButtonAccessibilityLabel, in: sut)
        let reasoningButton = findButton(accessibilityIdentifier: "AIChat.Toolbar.Button.Reasoning", in: sut)
        let modelChipButton = findButton(accessibilityIdentifier: "AIChat.Toolbar.Button.ModelChip", in: sut)

        sut.isInputBlockedByUsageLimit = true

        XCTAssertFalse(attachmentButton?.isEnabled ?? true)
        XCTAssertFalse(toolsButton?.isEnabled ?? true)
        XCTAssertFalse(reasoningButton?.isEnabled ?? true)
        XCTAssertFalse(modelChipButton?.isEnabled ?? true)

        sut.isInputBlockedByUsageLimit = false

        XCTAssertTrue(attachmentButton?.isEnabled ?? false)
        XCTAssertTrue(toolsButton?.isEnabled ?? false)
        XCTAssertTrue(reasoningButton?.isEnabled ?? false)
        XCTAssertTrue(modelChipButton?.isEnabled ?? false)
    }

    func test_isInputBlockedByUsageLimit_disablesTheSubmitButton() {
        let sut = UnifiedToggleInputToolbarView()
        sut.isSubmitEnabled = true

        let submitButton = findButton(accessibilityLabel: UserText.aiChatToolbarSubmitButtonAccessibilityLabel, in: sut)
        XCTAssertTrue(submitButton?.isEnabled ?? false)

        sut.isInputBlockedByUsageLimit = true

        XCTAssertFalse(submitButton?.isEnabled ?? true)
    }

    /// Voice is a way into a chat the allowance can't pay for either, so it greys out with submit.
    func test_isInputBlockedByUsageLimit_disablesTheVoiceButton() {
        let sut = UnifiedToggleInputToolbarView()
        sut.isAIVoiceChatActive = true

        let submitButton = findButton(accessibilityLabel: UserText.aiChatToolbarSubmitButtonAccessibilityLabel, in: sut)
        XCTAssertTrue(submitButton?.isEnabled ?? false, "Voice is live on an empty input")

        sut.isInputBlockedByUsageLimit = true

        XCTAssertFalse(submitButton?.isEnabled ?? true)
    }

    // MARK: - Terms of Service submit button

    func test_termsOfServiceSendButton_showsTheAskTitleInsteadOfTheArrow() throws {
        let sut = UnifiedToggleInputToolbarView()
        sut.isSubmitEnabled = true

        sut.termsOfServiceSendButton = .ask

        let submitButton = try XCTUnwrap(findButton(accessibilityIdentifier: Self.submitButtonIdentifier, in: sut))
        XCTAssertEqual(submitButton.title(for: .normal), UserText.duckAIAskButtonTitle)
        XCTAssertNil(submitButton.image(for: .normal))
        XCTAssertEqual(submitButton.accessibilityLabel, UserText.duckAIAskButtonTitle)
        XCTAssertTrue(submitButton.isEnabled)
    }

    func test_termsOfServiceSendButton_whenCreate_showsTheCreateTitle() throws {
        let sut = UnifiedToggleInputToolbarView()
        sut.isSubmitEnabled = true
        sut.termsOfServiceSendButton = .ask

        sut.termsOfServiceSendButton = .create

        let submitButton = try XCTUnwrap(findButton(accessibilityIdentifier: Self.submitButtonIdentifier, in: sut))
        XCTAssertEqual(submitButton.title(for: .normal), UserText.duckAICreateButtonTitle)
        XCTAssertNil(submitButton.image(for: .normal))
        XCTAssertEqual(submitButton.accessibilityLabel, UserText.duckAICreateButtonTitle)
    }

    func test_termsOfServiceSendButton_dismissalKeepsTheLabelTheUserTapped() throws {
        let sut = UnifiedToggleInputToolbarView()
        sut.isSubmitEnabled = true
        sut.termsOfServiceSendButton = .create
        let submitButton = try XCTUnwrap(findButton(accessibilityIdentifier: Self.submitButtonIdentifier, in: sut))

        sut.prepareForToolbarVisibilityChange(showToolbar: false)
        // The submit clears Create Image and accepts the terms while the toolbar is still leaving.
        sut.termsOfServiceSendButton = .ask
        sut.termsOfServiceSendButton = nil
        XCTAssertEqual(submitButton.title(for: .normal), UserText.duckAICreateButtonTitle)

        sut.finalizeToolbarShown()
        XCTAssertNil(submitButton.title(for: .normal))
    }

    func test_termsOfServiceSendButton_keepsTheVoiceButtonOnAnEmptyInput() throws {
        let sut = UnifiedToggleInputToolbarView()
        sut.isSubmitEnabled = false
        sut.isAIVoiceChatActive = true

        sut.termsOfServiceSendButton = .ask

        let submitButton = try XCTUnwrap(findButton(accessibilityIdentifier: Self.submitButtonIdentifier, in: sut))
        XCTAssertNil(submitButton.title(for: .normal))
        XCTAssertNotNil(submitButton.image(for: .normal))
        XCTAssertEqual(submitButton.accessibilityLabel, UserText.aiChatToolbarSubmitButtonAccessibilityLabel)
    }

    func test_termsOfServiceSendButton_widensTheButtonToFitTheTitleAndKeepsItTappable() throws {
        let sut = UnifiedToggleInputToolbarView()
        sut.isSubmitEnabled = true
        let container = makeContainer(for: sut)

        sut.termsOfServiceSendButton = .ask
        container.layoutIfNeeded()

        let submitButton = try XCTUnwrap(findButton(accessibilityIdentifier: Self.submitButtonIdentifier, in: sut))
        let titleWidth = try XCTUnwrap(submitButton.titleLabel).intrinsicContentSize.width
        XCTAssertGreaterThan(submitButton.bounds.width, titleWidth)
        XCTAssertEqual(submitButton.bounds.height, 40)
        let trailingEdge = CGPoint(x: submitButton.bounds.maxX - 1, y: submitButton.bounds.midY)
        XCTAssertTrue(submitButton.hitTest(trailingEdge, with: nil) === submitButton)
    }

    func test_termsOfServiceSendButton_whenTurnedOff_restoresTheCircularArrow() throws {
        let sut = UnifiedToggleInputToolbarView()
        sut.isSubmitEnabled = true
        let container = makeContainer(for: sut)
        sut.termsOfServiceSendButton = .ask
        container.layoutIfNeeded()

        sut.termsOfServiceSendButton = nil
        container.layoutIfNeeded()

        let submitButton = try XCTUnwrap(findButton(accessibilityIdentifier: Self.submitButtonIdentifier, in: sut))
        XCTAssertNil(submitButton.title(for: .normal))
        XCTAssertNotNil(submitButton.image(for: .normal))
        XCTAssertEqual(submitButton.accessibilityLabel, UserText.aiChatToolbarSubmitButtonAccessibilityLabel)
        XCTAssertEqual(submitButton.bounds.size, CGSize(width: 40, height: 40))
    }

    func test_isGenerating_doesNotReenableUnavailableAttachmentButton() {
        let sut = UnifiedToggleInputToolbarView()
        sut.isImageButtonEnabled = false

        let attachmentButton = findButton(accessibilityLabel: UserText.aiChatToolbarAttachButtonAccessibilityLabel, in: sut)
        let toolsButton = findButton(accessibilityLabel: UserText.aiChatToolbarToolsButtonAccessibilityLabel, in: sut)

        sut.isGenerating = true
        sut.isGenerating = false

        XCTAssertFalse(attachmentButton?.isEnabled ?? true)
        XCTAssertTrue(toolsButton?.isEnabled ?? false)
    }

    func test_reasoningButton_hasAccessibilityIdentifier() {
        let sut = UnifiedToggleInputToolbarView()

        let reasoningButton = findButton(accessibilityIdentifier: "AIChat.Toolbar.Button.Reasoning", in: sut)

        XCTAssertEqual(reasoningButton?.accessibilityLabel, UserText.aiChatToolbarReasoningButtonAccessibilityLabel)
        if #available(iOS 16.0, *) {
            XCTAssertEqual(reasoningButton?.preferredMenuElementOrder, .fixed)
        }
    }

    func test_modelChipButton_usesFixedMenuElementOrder() {
        let sut = UnifiedToggleInputToolbarView()

        let modelChipButton = findButton(accessibilityIdentifier: "AIChat.Toolbar.Button.ModelChip", in: sut)

        XCTAssertNotNil(modelChipButton)
        if #available(iOS 16.0, *) {
            XCTAssertEqual(modelChipButton?.preferredMenuElementOrder, .fixed)
        }
    }

    func testWhenModelPickerMenuIsSetThenModelChipUsesMenuAsPrimaryAction() {
        let sut = UnifiedToggleInputToolbarView()
        sut.modelPickerMenu = UIMenu(children: [UIAction(title: "Model") { _ in }])

        let modelChipButton = findButton(accessibilityIdentifier: "AIChat.Toolbar.Button.ModelChip", in: sut)

        XCTAssertTrue(modelChipButton?.showsMenuAsPrimaryAction ?? false)
    }

    func testWhenModelChipReceivesTouchDownThenRoutesToShownCallback() {
        let sut = UnifiedToggleInputToolbarView()
        sut.modelPickerMenu = UIMenu(children: [UIAction(title: "Model") { _ in }])
        var modelPickerShownCallbackCount = 0
        sut.onModelPickerShown = { modelPickerShownCallbackCount += 1 }

        let modelChipButton = findButton(accessibilityIdentifier: "AIChat.Toolbar.Button.ModelChip", in: sut)
        modelChipButton?.sendActions(for: .touchDown)

        XCTAssertEqual(modelPickerShownCallbackCount, 1)
    }

    func test_attachmentButton_usesFixedMenuElementOrder() {
        let sut = UnifiedToggleInputToolbarView()

        let attachmentButton = findButton(accessibilityLabel: UserText.aiChatToolbarAttachButtonAccessibilityLabel, in: sut)

        XCTAssertNotNil(attachmentButton)
        if #available(iOS 16.0, *) {
            XCTAssertEqual(attachmentButton?.preferredMenuElementOrder, .fixed)
        }
    }

    // MARK: - Fitting the row

    func testWhenEveryControlFitsThenTheRowStaysFull() {
        let fit = UnifiedToggleInputToolbarView.RowFit(modelChipWidth: 120)

        XCTAssertEqual(fit.level(forToolbarWidth: fit.minimumToolbarWidth(at: .full)), .full)
        XCTAssertEqual(fit.level(forToolbarWidth: 1000), .full)
    }

    func testWhenTheRowOverflowsThenThePillCollapsesBeforeTheToolsMerge() {
        let fit = UnifiedToggleInputToolbarView.RowFit(showsModeChip: true, modelChipWidth: 120, submitButtonWidth: 80)

        XCTAssertGreaterThan(fit.minimumToolbarWidth(at: .full), fit.minimumToolbarWidth(at: .modelIcon))
        XCTAssertGreaterThan(fit.minimumToolbarWidth(at: .modelIcon), fit.minimumToolbarWidth(at: .mergedTools))
        XCTAssertEqual(fit.level(forToolbarWidth: fit.minimumToolbarWidth(at: .full) - 1), .modelIcon)
        XCTAssertEqual(fit.level(forToolbarWidth: fit.minimumToolbarWidth(at: .modelIcon) - 1), .mergedTools)
    }

    func testWhenNothingFitsThenTheRowStopsAtMergedTools() {
        let fit = UnifiedToggleInputToolbarView.RowFit(showsModeChip: true, modelChipWidth: 120, showsReturnKey: true, submitButtonWidth: 120)

        XCTAssertEqual(fit.level(forToolbarWidth: 100), .mergedTools)
    }

    func testWhenControlsAreHiddenThenTheyTakeNoRoom() {
        let everything = UnifiedToggleInputToolbarView.RowFit(showsModeChip: true, modelChipWidth: 120)
        let noModeChip = UnifiedToggleInputToolbarView.RowFit(modelChipWidth: 120)
        let noPickers = UnifiedToggleInputToolbarView.RowFit(showsReasoningButton: false, modelChipWidth: nil)

        XCTAssertEqual(everything.minimumToolbarWidth(at: .full) - noModeChip.minimumToolbarWidth(at: .full),
                       UnifiedToggleInputToolbarView.RowFit.toolChipWidth + 4)
        XCTAssertLessThan(noPickers.minimumToolbarWidth(at: .full), noModeChip.minimumToolbarWidth(at: .full))
        XCTAssertEqual(noPickers.level(forToolbarWidth: noPickers.minimumToolbarWidth(at: .full)), .full)
    }

    func testWhenTheSubmitLabelNarrowsThenTheLevelRelaxes() {
        let arrow = UnifiedToggleInputToolbarView.RowFit(modelChipWidth: 120, submitButtonWidth: 40)
        let label = UnifiedToggleInputToolbarView.RowFit(modelChipWidth: 120, submitButtonWidth: 100)
        let width = arrow.minimumToolbarWidth(at: .full)

        XCTAssertEqual(arrow.level(forToolbarWidth: width), .full)
        XCTAssertGreaterThan(label.level(forToolbarWidth: width), .full)
    }

    func testWhenTheRowFitsThenThePillAndToolsLookAsBefore() throws {
        let sut = makeFittingToolbar()
        sut.selectedTool = .webSearch
        layOut(sut, width: sut.rowFit.minimumToolbarWidth(at: .full))

        XCTAssertEqual(sut.compactLevel, .full)
        let modelChip = try XCTUnwrap(findButton(accessibilityIdentifier: Self.modelChipIdentifier, in: sut))
        XCTAssertEqual(modelChip.configuration?.title, "5.4 mini")
        XCTAssertNil(modelChip.accessibilityLabel)
        XCTAssertGreaterThan(modelChip.bounds.width, 40)
        XCTAssertFalse(try XCTUnwrap(findButton(accessibilityLabel: UserText.aiChatToolbarToolsButtonAccessibilityLabel, in: sut)).isHidden)
        XCTAssertFalse(try XCTUnwrap(findButton(accessibilityLabel: UserText.aiChatToolbarClearSelectedToolAccessibilityLabel, in: sut)).isHidden)
        XCTAssertTrue(try XCTUnwrap(findButton(accessibilityIdentifier: Self.selectedToolMenuIdentifier, in: sut)).isHidden)
        assertNoControlsOverlap(in: sut)
    }

    func testWhenThePillShowsItsNameThenItTakesTheWidthTheRowCounted() throws {
        let sut = makeFittingToolbar()
        sut.modelName = "Sonnet 4.6"
        layOut(sut, width: 1000)

        let modelChip = try XCTUnwrap(findButton(accessibilityIdentifier: Self.modelChipIdentifier, in: sut))
        XCTAssertEqual(modelChip.bounds.width, try XCTUnwrap(sut.rowFit.modelChipWidth), accuracy: 1)
    }

    func testWhenThePillCollapsesThenItShowsTheProviderIconInASquareThatOpensTheSameMenu() throws {
        let sut = makeFittingToolbar()
        let icon = try XCTUnwrap(UIImage(systemName: "star"))
        sut.modelIcon = icon
        sut.modelPickerMenu = UIMenu(children: [UIAction(title: "Model") { _ in }])
        layOut(sut, width: sut.rowFit.minimumToolbarWidth(at: .full) - 1)

        XCTAssertEqual(sut.compactLevel, .modelIcon)
        let modelChip = try XCTUnwrap(findButton(accessibilityIdentifier: Self.modelChipIdentifier, in: sut))
        XCTAssertNil(modelChip.configuration?.title)
        XCTAssertEqual(modelChip.configuration?.image, icon)
        XCTAssertEqual(modelChip.bounds.size, CGSize(width: 40, height: 40))
        XCTAssertTrue(modelChip.showsMenuAsPrimaryAction)
        XCTAssertEqual(modelChip.accessibilityLabel, "5.4 mini")
    }

    func testWhenAModeTurnsOnWithoutRoomForItsChipThenThePillCollapses() {
        let sut = makeFittingToolbar()
        var withModeChip = sut.rowFit
        withModeChip.showsModeChip = true
        let container = layOut(sut, width: withModeChip.minimumToolbarWidth(at: .modelIcon))
        XCTAssertEqual(sut.compactLevel, .full)

        sut.selectedTool = .webSearch
        container.layoutIfNeeded()
        XCTAssertEqual(sut.compactLevel, .modelIcon)
        assertNoControlsOverlap(in: sut)

        sut.selectedTool = nil
        container.layoutIfNeeded()
        XCTAssertEqual(sut.compactLevel, .full)
    }

    func testWhenALongerModelNameNoLongerFitsThenThePillCollapses() {
        let sut = makeFittingToolbar()
        let container = layOut(sut, width: sut.rowFit.minimumToolbarWidth(at: .full))
        XCTAssertEqual(sut.compactLevel, .full)

        sut.modelName = "Sonnet 4.6 with a long name"
        container.layoutIfNeeded()

        XCTAssertEqual(sut.compactLevel, .modelIcon)
        assertNoControlsOverlap(in: sut)
    }

    func testWhenTheToolsMergeThenTheModeChipOpensTheToolsMenuWithoutItsClearButton() throws {
        let sut = makeFittingToolbar()
        sut.toolsMenu = UIMenu(children: [UIAction(title: "Web search") { _ in }])
        sut.selectedTool = .webSearch
        layOut(sut, width: sut.rowFit.minimumToolbarWidth(at: .modelIcon) - 1)

        XCTAssertEqual(sut.compactLevel, .mergedTools)
        XCTAssertTrue(try XCTUnwrap(findButton(accessibilityLabel: UserText.aiChatToolbarToolsButtonAccessibilityLabel, in: sut)).isHidden)
        XCTAssertTrue(try XCTUnwrap(findButton(accessibilityLabel: UserText.aiChatToolbarClearSelectedToolAccessibilityLabel, in: sut)).isHidden)
        let chipMenuButton = try XCTUnwrap(findButton(accessibilityIdentifier: Self.selectedToolMenuIdentifier, in: sut))
        XCTAssertFalse(chipMenuButton.isHidden)
        XCTAssertEqual(chipMenuButton.menu?.children.map(\.title), ["Web search"])
        XCTAssertTrue(chipMenuButton.showsMenuAsPrimaryAction)
        XCTAssertEqual(chipMenuButton.accessibilityValue, UserText.aiChatToolbarWebSearchToolTitle)
        XCTAssertGreaterThan(chipMenuButton.bounds.width, 0)
        assertNoControlsOverlap(in: sut)
    }

    func testWhenTheToolbarWidensThenTheModelNameComesBack() throws {
        let sut = makeFittingToolbar()
        sut.selectedTool = .webSearch
        let container = layOut(sut, width: sut.rowFit.minimumToolbarWidth(at: .modelIcon) - 1)
        XCTAssertEqual(sut.compactLevel, .mergedTools)

        container.frame.size.width = sut.rowFit.minimumToolbarWidth(at: .full)
        container.layoutIfNeeded()

        XCTAssertEqual(sut.compactLevel, .full)
        XCTAssertEqual(try XCTUnwrap(findButton(accessibilityIdentifier: Self.modelChipIdentifier, in: sut)).configuration?.title, "5.4 mini")
        XCTAssertFalse(try XCTUnwrap(findButton(accessibilityLabel: UserText.aiChatToolbarToolsButtonAccessibilityLabel, in: sut)).isHidden)
    }

    func testWhenTextIsTypedWithTheTermsUnacceptedThenTheLevelIsTheSame() {
        let sut = makeFittingToolbar()
        sut.reservesTermsOfServiceSendButton = true
        sut.isAIVoiceChatActive = true
        sut.isSubmitEnabled = false
        let container = layOut(sut, width: sut.rowFit.minimumToolbarWidth(at: .full))
        XCTAssertEqual(sut.compactLevel, .full, "The empty input already counts the Ask label")

        sut.isSubmitEnabled = true
        sut.termsOfServiceSendButton = .ask
        container.layoutIfNeeded()

        XCTAssertEqual(sut.compactLevel, .full)
        assertNoControlsOverlap(in: sut)
    }

    func testWhenTheTermsAreAcceptedThenTheFreedWidthGoesBackToThePill() {
        let sut = makeFittingToolbar()
        let widthWithArrow = sut.rowFit.minimumToolbarWidth(at: .full)
        sut.reservesTermsOfServiceSendButton = true
        sut.isSubmitEnabled = true
        sut.termsOfServiceSendButton = .ask
        let container = layOut(sut, width: widthWithArrow)
        XCTAssertGreaterThan(sut.compactLevel, .full)

        sut.termsOfServiceSendButton = nil
        sut.reservesTermsOfServiceSendButton = false
        container.layoutIfNeeded()

        XCTAssertEqual(sut.compactLevel, .full)
    }

    func testWhenTheRowIsAtItsNarrowestThenTheSubmitLabelIsWholeAndNothingOverlaps() throws {
        let sut = makeFittingToolbar()
        sut.selectedTool = .imageGeneration
        sut.reservesTermsOfServiceSendButton = true
        sut.isSubmitEnabled = true
        sut.termsOfServiceSendButton = .create
        layOut(sut, width: sut.rowFit.minimumToolbarWidth(at: .mergedTools))

        XCTAssertEqual(sut.compactLevel, .mergedTools)
        let submitButton = try XCTUnwrap(findButton(accessibilityIdentifier: Self.submitButtonIdentifier, in: sut))
        let titleWidth = try XCTUnwrap(submitButton.titleLabel).intrinsicContentSize.width
        XCTAssertGreaterThan(submitButton.bounds.width, titleWidth)
        assertNoControlsOverlap(in: sut)
    }

    func testWhenEditingThenTheRowStaysFull() {
        let sut = makeFittingToolbar()
        sut.isEditing = true
        layOut(sut, width: 200)

        XCTAssertEqual(sut.compactLevel, .full)
    }

    private static let submitButtonIdentifier = "AIChat.Toolbar.Button.Submit"
    private static let modelChipIdentifier = "AIChat.Toolbar.Button.ModelChip"
    private static let selectedToolMenuIdentifier = "AIChat.Toolbar.Button.SelectedToolMenu"

    /// Attach, tools, reasoning and the "5.4 mini" pill on, with no mode selected.
    private func makeFittingToolbar() -> UnifiedToggleInputToolbarView {
        let sut = UnifiedToggleInputToolbarView()
        sut.modelName = "5.4 mini"
        sut.isReasoningButtonHidden = false
        return sut
    }

    /// Stack views lay out a re-shown control only inside a window, so the row is hosted in one.
    private var window: UIWindow?

    @discardableResult
    private func layOut(_ sut: UnifiedToggleInputToolbarView, width: CGFloat) -> UIView {
        sut.translatesAutoresizingMaskIntoConstraints = false
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 56))
        window.isHidden = false
        self.window = window
        let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 56))
        window.addSubview(container)
        container.addSubview(sut)
        NSLayoutConstraint.activate([
            sut.topAnchor.constraint(equalTo: container.topAnchor),
            sut.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sut.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sut.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.layoutIfNeeded()
        return container
    }

    private func assertNoControlsOverlap(in sut: UIView, file: StaticString = #filePath, line: UInt = #line) {
        let frames = visibleButtons(in: sut).map { $0.convert($0.bounds, to: sut) }
        XCTAssertFalse(frames.isEmpty, file: file, line: line)
        for (index, frame) in frames.enumerated() {
            XCTAssertGreaterThanOrEqual(frame.minX, sut.bounds.minX, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, sut.bounds.maxX, file: file, line: line)
            for other in frames[(index + 1)...] {
                XCTAssertFalse(frame.insetBy(dx: 0.5, dy: 0.5).intersects(other), "\(frame) overlaps \(other)", file: file, line: line)
            }
        }
    }

    private func visibleButtons(in view: UIView) -> [UIButton] {
        view.subviews.filter { !$0.isHidden }.flatMap { subview -> [UIButton] in
            if let button = subview as? UIButton { return [button] }
            return visibleButtons(in: subview)
        }
    }

    private func makeContainer(for sut: UnifiedToggleInputToolbarView) -> UIView {
        sut.translatesAutoresizingMaskIntoConstraints = false
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 56))
        container.addSubview(sut)
        NSLayoutConstraint.activate([
            sut.topAnchor.constraint(equalTo: container.topAnchor),
            sut.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sut.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sut.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.layoutIfNeeded()
        return container
    }

    private func findButton(accessibilityLabel: String, in view: UIView) -> UIButton? {
        for subview in view.subviews {
            if let button = subview as? UIButton, button.accessibilityLabel == accessibilityLabel {
                return button
            }
            if let button = findButton(accessibilityLabel: accessibilityLabel, in: subview) {
                return button
            }
        }
        return nil
    }

    private func findButton(accessibilityIdentifier: String, in view: UIView) -> UIButton? {
        for subview in view.subviews {
            if let button = subview as? UIButton, button.accessibilityIdentifier == accessibilityIdentifier {
                return button
            }
            if let button = findButton(accessibilityIdentifier: accessibilityIdentifier, in: subview) {
                return button
            }
        }
        return nil
    }
}
