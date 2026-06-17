//
//  UnifiedToggleInputViewTests.swift
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
import DesignResourcesKit
import DesignResourcesKitIcons
import UIComponents
import XCTest
import UIKit
import UniformTypeIdentifiers
@testable import DuckDuckGo

final class UnifiedToggleInputViewTests: XCTestCase {

    func test_searchModeTextSubmitStaysEnabledWhenInvalidDuckAIAttachmentIsHidden() {
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        let sut = UnifiedToggleInputView(handler: handler)

        sut.applyCardLayout(.expanded(showsToggle: true, showsToolbar: true), animated: false)
        sut.addAttachment(makeInvalidFileAttachment())
        sut.text = "search query"
        sut.setInputMode(.search, animated: false)
        flushMainQueue()

        XCTAssertTrue(sut.isToolbarSubmitEnabled)
    }

    func test_searchModeAttachmentOnlySubmitStaysDisabledWhenDuckAIAttachmentIsHidden() {
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        let sut = UnifiedToggleInputView(handler: handler)

        sut.applyCardLayout(.expanded(showsToggle: true, showsToolbar: true), animated: false)
        sut.addAttachment(makeFileAttachment())
        sut.setInputMode(.search, animated: false)
        flushMainQueue()

        XCTAssertFalse(sut.isToolbarSubmitEnabled)
    }

    func test_dismissPoseFadesAttachmentsStripOutSoItAnimatesWithTheCollapse() throws {
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        let sut = UnifiedToggleInputView(handler: handler)

        sut.applyCardLayout(.expanded(showsToggle: true, showsToolbar: true), animated: false)
        sut.addAttachment(makeFileAttachment())
        flushMainQueue()

        let strip = try XCTUnwrap(firstDescendant(of: UnifiedToggleInputAttachmentsStripView.self, in: sut))
        XCTAssertEqual(strip.alpha, 1, accuracy: 0.001)

        // The top + toggle-on dismiss pose. Without fading the strip here it stays fully opaque
        // through the collapse and then blinks out when the container is hidden.
        sut.applyToggleHideChanges()

        XCTAssertEqual(strip.alpha, 0, accuracy: 0.001)
    }

    func test_attachmentStripScrollsToTrailingEdgeAfterAttachmentLayoutChange() throws {
        let sut = UnifiedToggleInputAttachmentsStripView()
        sut.frame = .zero
        sut.onAttachmentsChanged = {
            sut.frame = CGRect(
                x: 0,
                y: 0,
                width: 160,
                height: UnifiedToggleInputAttachmentsStripView.Constants.stripHeight
            )
        }

        (0..<6).forEach { index in
            sut.addAttachment(makeInvalidFileAttachment(fileName: "attachment-\(index)-long-name.pdf"))
        }
        flushMainQueue()
        sut.layoutIfNeeded()

        let scrollView = try XCTUnwrap(firstDescendant(of: UIScrollView.self, in: sut))
        let expectedOffset = max(scrollView.contentSize.width - scrollView.bounds.width, 0)

        XCTAssertGreaterThan(expectedOffset, 0)
        XCTAssertEqual(scrollView.contentOffset.x, expectedOffset, accuracy: 1)
    }

    func test_attachmentStripDoesNotAutoScrollWhenUserHasScrolledAwayFromTrailingEdge() throws {
        let sut = UnifiedToggleInputAttachmentsStripView()
        sut.frame = CGRect(
            x: 0,
            y: 0,
            width: 160,
            height: UnifiedToggleInputAttachmentsStripView.Constants.stripHeight
        )

        (0..<6).forEach { index in
            sut.addAttachment(makeInvalidFileAttachment(fileName: "attachment-\(index)-long-name.pdf"))
        }
        flushMainQueue()
        sut.layoutIfNeeded()
        let scrollView = try XCTUnwrap(firstDescendant(of: UIScrollView.self, in: sut))
        XCTAssertGreaterThan(scrollView.contentSize.width - scrollView.bounds.width, 0)

        scrollView.setContentOffset(.zero, animated: false)
        sut.addAttachment(makeInvalidFileAttachment(fileName: "attachment-new-long-name.pdf"))
        flushMainQueue()

        XCTAssertEqual(scrollView.contentOffset.x, 0, accuracy: 1)
    }

    @MainActor
    func test_documentPickerFailureIncludesFallbackMetadataForInvalidChip() async {
        let sut = UnifiedToggleInputAttachmentPresenter()
        let expectation = expectation(description: "file validation failed")
        let missingURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("missing-unreadable.pdf")

        sut.onFileValidationFailed = { message, metadata in
            XCTAssertEqual(message, UserText.aiChatAttachmentFileUnreadable)
            XCTAssertEqual(metadata.fileName, "missing-unreadable.pdf")
            XCTAssertEqual(metadata.mimeType, "application/pdf")
            XCTAssertNil(metadata.fileSizeBytes)
            expectation.fulfill()
        }

        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf])
        sut.documentPicker(controller, didPickDocumentsAt: [missingURL])

        await fulfillment(of: [expectation], timeout: 1)
    }

    func test_floatingReturnKeyDoesNotInsertReturnForEmptyState() throws {
        let sut = UnifiedToggleInputFloatingReturnKeyViewController()
        let delegate = SpyFloatingReturnKeyDelegate()
        sut.delegate = delegate
        sut.loadViewIfNeeded()

        sut.updateState(UnifiedToggleInputFloatingReturnKeyState(
            hasText: false
        ))

        let button = try XCTUnwrap(firstDescendant(of: UIButton.self, in: sut.view))
        XCTAssertFalse(button.isEnabled)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(delegate.returnKeyTapCount, 0)
    }

    func test_floatingReturnKeyInsertsReturnForNewAIChatTextState() throws {
        let sut = UnifiedToggleInputFloatingReturnKeyViewController()
        let delegate = SpyFloatingReturnKeyDelegate()
        sut.delegate = delegate
        sut.loadViewIfNeeded()

        let state = UnifiedToggleInputFloatingReturnKeyState(
            hasText: true,
            mode: .aiChat,
            usesFloatingReturnKey: true
        )
        XCTAssertTrue(state.canInsertReturn)
        sut.updateState(state)

        let button = try XCTUnwrap(firstDescendant(of: UIButton.self, in: sut.view))
        XCTAssertTrue(button.isEnabled)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(delegate.returnKeyTapCount, 1)
    }

    func test_floatingReturnKeyDoesNotInsertReturnForFollowUpAIChatTextState() throws {
        let sut = UnifiedToggleInputFloatingReturnKeyViewController()
        let delegate = SpyFloatingReturnKeyDelegate()
        sut.delegate = delegate
        sut.loadViewIfNeeded()

        sut.updateState(UnifiedToggleInputFloatingReturnKeyState(
            hasText: true,
            mode: .aiChat
        ))

        let button = try XCTUnwrap(firstDescendant(of: UIButton.self, in: sut.view))
        XCTAssertFalse(button.isEnabled)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(delegate.returnKeyTapCount, 0)
    }

    func test_floatingReturnKeyDoesNotInsertReturnForSearchTextState() throws {
        let sut = UnifiedToggleInputFloatingReturnKeyViewController()
        let delegate = SpyFloatingReturnKeyDelegate()
        sut.delegate = delegate
        sut.loadViewIfNeeded()

        sut.updateState(UnifiedToggleInputFloatingReturnKeyState(
            hasText: true,
            mode: .search
        ))

        let button = try XCTUnwrap(firstDescendant(of: UIButton.self, in: sut.view))
        XCTAssertFalse(button.isEnabled)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(delegate.returnKeyTapCount, 0)
    }

    func test_toolbarDismissalPreservesNewPromptSubmitStyleUntilShownAgain() throws {
        let sut = UnifiedToggleInputToolbarView()
        sut.usesNewPromptSubmitStyle = true
        sut.isSubmitEnabled = true

        let submitButton = try XCTUnwrap(findButton(accessibilityLabel: UserText.aiChatToolbarSubmitButtonAccessibilityLabel, in: sut))
        XCTAssertEqual(submitButton.currentImage, DesignSystemImages.Glyphs.Size24.arrowRight)

        sut.prepareForToolbarVisibilityChange(showToolbar: false)
        sut.usesNewPromptSubmitStyle = false
        XCTAssertEqual(submitButton.currentImage, DesignSystemImages.Glyphs.Size24.arrowRight)

        sut.finalizeToolbarShown()
        XCTAssertEqual(submitButton.currentImage, DesignSystemImages.Glyphs.Size24.arrowUp)
    }

    // MARK: - Recovery-Card Submit Block

    func test_recoveryCardBlock_disablesSubmit_whenContentPresent() throws {
        let sut = UnifiedToggleInputToolbarView()
        sut.isSubmitEnabled = true
        sut.isSubmitBlockedByRecoveryCard = true

        let submitButton = try XCTUnwrap(findButton(accessibilityLabel: UserText.aiChatToolbarSubmitButtonAccessibilityLabel, in: sut))
        XCTAssertFalse(submitButton.isEnabled,
                       "Recovery card must block submit while there is submittable content")
    }

    func test_recoveryCardBlock_leavesVoiceButtonUntouched_whenNoContent() throws {
        let sut = UnifiedToggleInputToolbarView()
        sut.isAIVoiceChatActive = true
        sut.isSubmitEnabled = false
        sut.isSubmitBlockedByRecoveryCard = true

        let submitButton = try XCTUnwrap(findButton(accessibilityLabel: UserText.aiChatToolbarSubmitButtonAccessibilityLabel, in: sut))
        XCTAssertTrue(submitButton.isEnabled,
                      "With no text the Voice affordance must stay active — the block only suppresses submit")
        XCTAssertEqual(submitButton.currentImage, DesignSystemImages.Glyphs.Size24.voice)
    }

    func test_clearingRecoveryCardBlock_reenablesSubmit_whenContentPresent() throws {
        let sut = UnifiedToggleInputToolbarView()
        sut.isSubmitEnabled = true
        sut.isSubmitBlockedByRecoveryCard = true
        let submitButton = try XCTUnwrap(findButton(accessibilityLabel: UserText.aiChatToolbarSubmitButtonAccessibilityLabel, in: sut))
        XCTAssertFalse(submitButton.isEnabled)

        sut.isSubmitBlockedByRecoveryCard = false

        XCTAssertTrue(submitButton.isEnabled,
                      "Clearing the recovery block re-enables submit when content is present")
    }

    func test_clearingRecoveryCardBlock_doesNotForceEnableSubmit_whenNoContent() throws {
        let sut = UnifiedToggleInputToolbarView()
        sut.isSubmitEnabled = false
        sut.isSubmitBlockedByRecoveryCard = true

        sut.isSubmitBlockedByRecoveryCard = false

        let submitButton = try XCTUnwrap(findButton(accessibilityLabel: UserText.aiChatToolbarSubmitButtonAccessibilityLabel, in: sut))
        XCTAssertFalse(submitButton.isEnabled,
                       "enableChatInput must not force-enable submit when another reason (no content) still blocks it")
    }

    func test_insertNewlineAtCursor_whenTextIsEmpty() {
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        let sut = SwitchBarTextEntryView(handler: handler)

        sut.insertNewlineAtCursor()

        XCTAssertEqual(handler.currentText, "\n")
    }

    func test_insertNewlineAtCursor_whenCursorIsAtEnd() throws {
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        let sut = SwitchBarTextEntryView(handler: handler)
        sut.setQueryText("hello")
        let textView = try XCTUnwrap(firstDescendant(of: UITextView.self, in: sut))
        let end = textView.endOfDocument
        textView.selectedTextRange = textView.textRange(from: end, to: end)

        sut.insertNewlineAtCursor()

        XCTAssertEqual(handler.currentText, "hello\n")
    }

    func test_insertNewlineAtCursor_whenCursorIsMidText() throws {
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        let sut = SwitchBarTextEntryView(handler: handler)
        sut.setQueryText("hello")
        let textView = try XCTUnwrap(firstDescendant(of: UITextView.self, in: sut))
        let cursor = try XCTUnwrap(textView.position(from: textView.beginningOfDocument, offset: 2))
        textView.selectedTextRange = textView.textRange(from: cursor, to: cursor)

        sut.insertNewlineAtCursor()

        XCTAssertEqual(handler.currentText, "he\nllo")
    }

    func test_topAIChatTextEntryDoesNotGrowOnFirstFloatingReturnNewline() {
        let expectedTopAIChatMinimumHeight: CGFloat = 68
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        handler.updateBarPosition(isTop: true)
        let sut = SwitchBarTextEntryView(handler: handler)
        sut.isExpandable = true
        prepareForFitting(sut)
        sut.setQueryText("hello")
        let initialHeight = applyFittingHeight(to: sut)

        sut.insertNewlineAtCursor()
        let heightAfterFirstNewline = applyFittingHeight(to: sut)

        XCTAssertEqual(initialHeight, expectedTopAIChatMinimumHeight, accuracy: 1)
        XCTAssertEqual(heightAfterFirstNewline, initialHeight, accuracy: 1)
    }

    func test_topAIChatPlaceholderAlignsWithTextContainerTopInset() throws {
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        handler.updateBarPosition(isTop: true)
        let sut = SwitchBarTextEntryView(handler: handler)
        sut.isExpandable = true
        prepareForFitting(sut)
        applyFittingHeight(to: sut)

        let textView = try XCTUnwrap(firstDescendant(of: UITextView.self, in: sut))
        let placeholderLabel = try XCTUnwrap(firstDescendant(of: UILabel.self, in: sut))
        let expectedPlaceholderMinY = textView.convert(CGPoint(x: 0, y: textView.textContainerInset.top), to: sut).y

        XCTAssertFalse(placeholderLabel.isHidden)
        XCTAssertEqual(placeholderLabel.frame.minY, expectedPlaceholderMinY, accuracy: 1)
    }

    func test_collapsedAIChatPlaceholderStaysVerticallyCenteredInPill() throws {
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        let sut = SwitchBarTextEntryView(handler: handler)
        prepareForFitting(sut, height: 48)
        applyFittingHeight(to: sut, height: 48)

        let textView = try XCTUnwrap(firstDescendant(of: UITextView.self, in: sut))
        let placeholderLabel = try XCTUnwrap(firstDescendant(of: UILabel.self, in: sut))

        XCTAssertFalse(placeholderLabel.isHidden)
        XCTAssertEqual(placeholderLabel.center.y, textView.center.y, accuracy: 1)
    }

    func test_expandedSearchPlaceholderStaysVerticallyCenteredInPill() throws {
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        handler.setToggleState(.search)
        let sut = SwitchBarTextEntryView(handler: handler)
        sut.isExpandable = true
        prepareForFitting(sut, height: 48)
        applyFittingHeight(to: sut, height: 48)

        let textView = try XCTUnwrap(firstDescendant(of: UITextView.self, in: sut))
        let placeholderLabel = try XCTUnwrap(firstDescendant(of: UILabel.self, in: sut))

        XCTAssertFalse(placeholderLabel.isHidden)
        XCTAssertEqual(placeholderLabel.center.y, textView.center.y, accuracy: 1)
    }

    func test_bottomAIChatPlaceholderStaysVerticallyCenteredInPill() throws {
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        handler.updateBarPosition(isTop: false)
        let sut = SwitchBarTextEntryView(handler: handler)
        sut.isExpandable = true
        prepareForFitting(sut, height: 48)
        applyFittingHeight(to: sut, height: 48)

        let textView = try XCTUnwrap(firstDescendant(of: UITextView.self, in: sut))
        let placeholderLabel = try XCTUnwrap(firstDescendant(of: UILabel.self, in: sut))

        XCTAssertFalse(placeholderLabel.isHidden)
        XCTAssertEqual(placeholderLabel.center.y, textView.center.y, accuracy: 1)
    }

    func test_legacyNonFadeOutTopAIChatTextEntryStaysCompactWhenExpandable() throws {
        let handler = LegacyTextEntryMockHandler(
            currentToggleState: .aiChat,
            isTopBarPosition: true,
            isUsingFadeOutAnimation: false
        )
        let sut = SwitchBarTextEntryView(handler: handler)
        sut.isExpandable = true
        prepareForFitting(sut, height: 44)
        let height = applyFittingHeight(to: sut, height: 44)

        let textView = try XCTUnwrap(firstDescendant(of: UITextView.self, in: sut))
        let placeholderLabel = try XCTUnwrap(firstDescendant(of: UILabel.self, in: sut))

        XCTAssertEqual(height, 44, accuracy: 1)
        XCTAssertFalse(placeholderLabel.isHidden)
        XCTAssertEqual(placeholderLabel.center.y, textView.center.y, accuracy: 1)
    }

    func test_legacyExpandedAIChatLayoutTopPlaceholderAlignsWithTextContainerTopInset() throws {
        let handler = LegacyTextEntryMockHandler(
            currentToggleState: .aiChat,
            isTopBarPosition: true,
            isUsingFadeOutAnimation: true,
            usesExpandedAIChatTextEntryLayout: true
        )
        let sut = SwitchBarTextEntryView(handler: handler)
        sut.isExpandable = true
        prepareForFitting(sut)
        let height = applyFittingHeight(to: sut)

        let textView = try XCTUnwrap(firstDescendant(of: UITextView.self, in: sut))
        let placeholderLabel = try XCTUnwrap(firstDescendant(of: UILabel.self, in: sut))
        let expectedPlaceholderMinY = textView.convert(CGPoint(x: 0, y: textView.textContainerInset.top), to: sut).y

        XCTAssertEqual(height, 68, accuracy: 1)
        XCTAssertFalse(placeholderLabel.isHidden)
        XCTAssertEqual(placeholderLabel.frame.minY, expectedPlaceholderMinY, accuracy: 1)
    }

    func test_barPositionChangeRefreshesExpandedAIChatPose() {
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        handler.updateBarPosition(isTop: false)
        let sut = SwitchBarTextEntryView(handler: handler)
        sut.isExpandable = true
        prepareForFitting(sut, height: 44)

        XCTAssertEqual(applyFittingHeight(to: sut, height: 44), 44, accuracy: 1)

        handler.updateBarPosition(isTop: true)
        sut.updatePoseForCurrentState()

        XCTAssertEqual(applyFittingHeight(to: sut), 68, accuracy: 1)
    }

    func test_expandedPlaceholderAlignmentUpdatesWhenToggleSwitchesMode() throws {
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        handler.updateBarPosition(isTop: true)
        let sut = SwitchBarTextEntryView(handler: handler)
        sut.isExpandable = true
        prepareForFitting(sut)
        applyFittingHeight(to: sut)

        let textView = try XCTUnwrap(firstDescendant(of: UITextView.self, in: sut))
        let placeholderLabel = try XCTUnwrap(firstDescendant(of: UILabel.self, in: sut))
        let expectedPlaceholderMinY = textView.convert(CGPoint(x: 0, y: textView.textContainerInset.top), to: sut).y

        XCTAssertEqual(placeholderLabel.frame.minY, expectedPlaceholderMinY, accuracy: 1)

        handler.setToggleState(.search)
        flushMainQueue()
        applyFittingHeight(to: sut)

        XCTAssertEqual(placeholderLabel.center.y, textView.center.y, accuracy: 1)

        handler.setToggleState(.aiChat)
        flushMainQueue()
        applyFittingHeight(to: sut)

        XCTAssertEqual(placeholderLabel.frame.minY, expectedPlaceholderMinY, accuracy: 1)
    }

    func test_clearButtonStaysPinnedToTopLineWhenTextEntryExpands() throws {
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        handler.updateBarPosition(isTop: true)
        let sut = SwitchBarTextEntryView(handler: handler)
        sut.isExpandable = true
        prepareForFitting(sut)
        sut.setQueryText("hello")
        let initialHeight = applyFittingHeight(to: sut)
        let clearButton = try XCTUnwrap(findButton(accessibilityLabel: "Clear text", in: sut))
        let initialClearButtonMinY = clearButton.convert(clearButton.bounds, to: sut).minY

        sut.insertNewlineAtCursor()
        sut.insertNewlineAtCursor()
        let expandedHeight = applyFittingHeight(to: sut)
        let expandedClearButtonMinY = clearButton.convert(clearButton.bounds, to: sut).minY

        XCTAssertGreaterThan(expandedHeight, initialHeight)
        XCTAssertEqual(expandedClearButtonMinY, initialClearButtonMinY, accuracy: 1)
    }

    func test_topAIChatToggleDoesNotCompressWhenFloatingReturnExpandsTextEntry() throws {
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        let sut = UnifiedToggleInputView(handler: handler)
        sut.handlerIsTopBarPosition = true
        sut.applyCardLayout(.expanded(showsToggle: true, showsToolbar: true), animated: false)
        prepareForFitting(sut, width: 402, height: 192)
        applyFittingHeight(to: sut, width: 402)
        sut.onNeedsHierarchyLayout = { [weak sut] in
            guard let sut else { return }
            self.applyFittingHeight(to: sut, width: 402)
        }
        sut.text = "hello"
        applyFittingHeight(to: sut, width: 402)
        let duckAIButton = try XCTUnwrap(findButton(accessibilityIdentifier: "AddressBar.Button.DuckAI", in: sut))

        sut.insertNewlineAtCursor()
        sut.insertNewlineAtCursor()
        sut.layoutIfNeeded()

        XCTAssertEqual(duckAIButton.frame.height, 36, accuracy: 1)
    }

    func test_topAIChatHierarchyLayoutCallbackFiresSynchronouslyWhenNewlineExpandsTextEntry() {
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        let sut = UnifiedToggleInputView(handler: handler)
        sut.handlerIsTopBarPosition = true
        sut.applyCardLayout(.expanded(showsToggle: true, showsToolbar: true), animated: false)
        prepareForFitting(sut, width: 402, height: 192)
        applyFittingHeight(to: sut, width: 402)
        sut.text = "hello"
        applyFittingHeight(to: sut, width: 402)

        var callbacks = 0
        sut.onNeedsHierarchyLayout = { callbacks += 1 }
        sut.insertNewlineAtCursor()
        sut.insertNewlineAtCursor()

        XCTAssertGreaterThan(callbacks, 0)
    }

    func test_flankedAIChatShadowUsesTransparentBlackTokenInDarkMode() throws {
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        let sut = UnifiedToggleInputView(handler: handler)
        sut.overrideUserInterfaceStyle = .dark
        sut.applyCardLayout(.flanked, animated: false)
        prepareForFitting(sut, width: 402, height: 80)

        let shadowView = try XCTUnwrap(firstDescendant(of: CompositeShadowView.self, in: sut))
        let rimShadowLayer = try XCTUnwrap(shadowView.subviews.first { $0.layer.name == "rim" }?.layer)
        let expectedShadowColor = UIColor(designSystemColor: .shadowSecondary).resolvedColor(with: sut.traitCollection)

        XCTAssertFalse(shadowView.isHidden)
        assertColor(rimShadowLayer.shadowColor, equals: expectedShadowColor)
    }

    private let longURL = "https://www.cinemark.com/theatres/ca-playa-vista/cinemark-playa-vista-and-xd?showDate=2026-06-12"

    func test_urlDoesNotExpandHeightInSearchModeAfterUserTap() {
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        handler.setToggleState(.search)
        let sut = SwitchBarTextEntryView(handler: handler)
        sut.isExpandable = true
        prepareForFitting(sut)
        sut.setQueryText(longURL)
        let singleLineHeight = applyFittingHeight(to: sut)

        sut.hasBeenInteractedWith = true
        sut.updatePoseForCurrentState()
        let heightAfterTap = applyFittingHeight(to: sut)

        XCTAssertEqual(heightAfterTap, singleLineHeight, accuracy: 1)
    }

    func test_urlCanExpandInAIChatModeAfterUserTap() {
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        handler.setToggleState(.aiChat)
        let sut = SwitchBarTextEntryView(handler: handler)
        sut.isExpandable = true
        prepareForFitting(sut)
        sut.setQueryText(longURL)
        let singleLineHeight = applyFittingHeight(to: sut)

        sut.hasBeenInteractedWith = true
        sut.updatePoseForCurrentState()
        let heightAfterTap = applyFittingHeight(to: sut)

        XCTAssertGreaterThan(heightAfterTap, singleLineHeight)
    }

    func test_urlCollapsesToSingleLineWhenModeSwitchesFromAIChatToSearch() {
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        handler.setToggleState(.aiChat)
        let sut = SwitchBarTextEntryView(handler: handler)
        sut.isExpandable = true
        prepareForFitting(sut)
        sut.setQueryText(longURL)
        sut.hasBeenInteractedWith = true
        sut.updatePoseForCurrentState()
        let expandedHeight = applyFittingHeight(to: sut)

        handler.setToggleState(.search)
        sut.updatePoseForCurrentState()
        let heightAfterSwitch = applyFittingHeight(to: sut)

        XCTAssertGreaterThan(expandedHeight, heightAfterSwitch)
    }

    // Search-only: UTI shown without a toggle (AI chat unavailable). Even though the handler's
    // toggle state may still be its `.aiChat` default, a tapped URL must stay single-line.
    func test_urlDoesNotExpandHeightInSearchOnlyModeWithoutToggle() {
        let handler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false, isToggleEnabled: false)
        let sut = SwitchBarTextEntryView(handler: handler)
        sut.isExpandable = true
        prepareForFitting(sut)
        sut.setQueryText(longURL)
        let singleLineHeight = applyFittingHeight(to: sut)

        sut.hasBeenInteractedWith = true
        sut.updatePoseForCurrentState()
        let heightAfterTap = applyFittingHeight(to: sut)

        XCTAssertEqual(heightAfterTap, singleLineHeight, accuracy: 1)
    }

    private func flushMainQueue() {
        let expectation = expectation(description: "main queue flushed")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    private func prepareForFitting(_ view: UIView, width: CGFloat = 320, height: CGFloat = 68) {
        view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    @discardableResult
    private func applyFittingHeight(to view: UIView, width: CGFloat = 320, height proposedHeight: CGFloat = UIView.layoutFittingCompressedSize.height) -> CGFloat {
        let height = view.systemLayoutSizeFitting(
            CGSize(width: width, height: proposedHeight),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        return height
    }

    private func makeInvalidFileAttachment(
        fileName: String = "invalid.pdf",
        validationMessage: String = UserText.aiChatAttachmentFileTooManyPages(maxPagesPerFile: 15)
    ) -> UnifiedToggleInputAttachment {
        .invalidFile(
            UnifiedToggleInputInvalidFileAttachment(
                fileName: fileName,
                mimeType: "application/pdf",
                fileSizeBytes: 1_000,
                validationMessage: validationMessage
            )
        )
    }

    private func makeFileAttachment(fileName: String = "valid.pdf") -> UnifiedToggleInputAttachment {
        .file(
            AIChatFileAttachment(
                data: Data(repeating: 0, count: 1_000),
                fileName: fileName,
                mimeType: "application/pdf",
                fileSizeBytes: 1_000,
                pageCount: 1
            )
        )
    }

    private func firstDescendant<T: UIView>(of type: T.Type, in view: UIView) -> T? {
        if let match = view as? T {
            return match
        }

        for subview in view.subviews {
            if let match = firstDescendant(of: type, in: subview) {
                return match
            }
        }

        return nil
    }

    private func findButton(accessibilityLabel: String, in view: UIView) -> UIButton? {
        findButton(in: view) { $0.accessibilityLabel == accessibilityLabel }
    }

    private func findButton(accessibilityIdentifier: String, in view: UIView) -> UIButton? {
        findButton(in: view) { $0.accessibilityIdentifier == accessibilityIdentifier }
    }

    private func findButton(in view: UIView, where matches: (UIButton) -> Bool) -> UIButton? {
        if let button = view as? UIButton, matches(button) {
            return button
        }

        for subview in view.subviews {
            if let button = findButton(in: subview, where: matches) {
                return button
            }
        }

        return nil
    }

    private func assertColor(_ actualColor: CGColor?, equals expectedColor: UIColor, file: StaticString = #filePath, line: UInt = #line) {
        guard let actualColor else {
            XCTFail("Expected color", file: file, line: line)
            return
        }

        let actualComponents = rgbaComponents(of: UIColor(cgColor: actualColor))
        let expectedComponents = rgbaComponents(of: expectedColor)

        XCTAssertEqual(actualComponents.red, expectedComponents.red, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualComponents.green, expectedComponents.green, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualComponents.blue, expectedComponents.blue, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualComponents.alpha, expectedComponents.alpha, accuracy: 0.001, file: file, line: line)
    }

    private func rgbaComponents(of color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
    }
}

private final class SpyFloatingReturnKeyDelegate: UnifiedToggleInputFloatingReturnKeyDelegate {
    var returnKeyTapCount = 0

    func floatingReturnKeyDidTap() {
        returnKeyTapCount += 1
    }
}

private final class LegacyTextEntryMockHandler: SwitchBarHandling {
    var currentText: String = ""
    var currentToggleState: TextEntryMode
    var isVoiceSearchEnabled: Bool = false
    var isAIVoiceChatEnabled: Bool = false
    var hasUserInteractedWithText: Bool = false
    var isCurrentTextValidURL: Bool = false
    var buttonState: SwitchBarButtonState = .noButtons
    var isTopBarPosition: Bool
    var isToggleEnabled: Bool = true
    var isFireTab: Bool = false
    var isUsingExpandedBottomBarHeight: Bool = false
    var isUsingFadeOutAnimation: Bool
    var usesExpandedAIChatTextEntryLayout: Bool
    var shouldDisableAutocorrectOnEmpty: Bool = false
    var hidesVoiceButton: Bool = false
    var hasSubmittedPrompt: Bool = false
    var modeParameters: [String: String] = [:]

    var hasSubmittedPromptPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
    var currentTextPublisher: AnyPublisher<String, Never> { Empty().eraseToAnyPublisher() }
    var toggleStatePublisher: AnyPublisher<TextEntryMode, Never> { Empty().eraseToAnyPublisher() }
    var textSubmissionPublisher: AnyPublisher<(text: String, mode: TextEntryMode), Never> { Empty().eraseToAnyPublisher() }
    var microphoneButtonTappedPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var clearButtonTappedPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var hasUserInteractedWithTextPublisher: AnyPublisher<Bool, Never> { Empty().eraseToAnyPublisher() }
    var isCurrentTextValidURLPublisher: AnyPublisher<Bool, Never> { Empty().eraseToAnyPublisher() }
    var currentButtonStatePublisher: AnyPublisher<SwitchBarButtonState, Never> { Empty().eraseToAnyPublisher() }

    init(currentToggleState: TextEntryMode,
         isTopBarPosition: Bool,
         isUsingFadeOutAnimation: Bool,
         usesExpandedAIChatTextEntryLayout: Bool = false) {
        self.currentToggleState = currentToggleState
        self.isTopBarPosition = isTopBarPosition
        self.isUsingFadeOutAnimation = isUsingFadeOutAnimation
        self.usesExpandedAIChatTextEntryLayout = usesExpandedAIChatTextEntryLayout
    }

    func updateCurrentText(_ text: String) {
        currentText = text
    }

    func submitText(_ text: String) {}

    func setToggleState(_ state: TextEntryMode) {
        currentToggleState = state
    }

    func clearText() {}

    func microphoneButtonTapped() {}

    func markUserInteraction() {}

    func clearButtonTapped() {}

    func updateBarPosition(isTop: Bool) {
        isTopBarPosition = isTop
    }
}
