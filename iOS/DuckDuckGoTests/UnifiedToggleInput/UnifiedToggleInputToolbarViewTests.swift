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

    func test_attachmentButton_usesFixedMenuElementOrder() {
        let sut = UnifiedToggleInputToolbarView()

        let attachmentButton = findButton(accessibilityLabel: UserText.aiChatToolbarAttachButtonAccessibilityLabel, in: sut)

        XCTAssertNotNil(attachmentButton)
        if #available(iOS 16.0, *) {
            XCTAssertEqual(attachmentButton?.preferredMenuElementOrder, .fixed)
        }
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
