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

    func test_floatingSubmitEnablesAndSubmitsAttachmentOnlyState() throws {
        let sut = UnifiedToggleInputFloatingSubmitViewController()
        let delegate = SpyFloatingSubmitDelegate()
        sut.delegate = delegate
        sut.loadViewIfNeeded()

        sut.updateState(UnifiedToggleInputFloatingSubmitState(
            hasText: false,
            hasValidAttachment: true,
            hasInvalidAttachment: false
        ))

        XCTAssertTrue(sut.isSubmitButtonEnabled)
        try XCTUnwrap(firstDescendant(of: UIButton.self, in: sut.view)).sendActions(for: .touchUpInside)
        XCTAssertEqual(delegate.submitTapCount, 1)
        XCTAssertEqual(delegate.voiceTapCount, 0)
    }

    func test_floatingSubmitDisablesWhenInvalidAttachmentIsPresent() {
        let sut = UnifiedToggleInputFloatingSubmitViewController()
        sut.isAIVoiceChatEnabled = true
        sut.loadViewIfNeeded()

        sut.updateState(UnifiedToggleInputFloatingSubmitState(
            hasText: true,
            hasValidAttachment: false,
            hasInvalidAttachment: true
        ))

        XCTAssertFalse(sut.isSubmitButtonEnabled)
    }

    private func flushMainQueue() {
        let expectation = expectation(description: "main queue flushed")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
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
}

private final class SpyFloatingSubmitDelegate: UnifiedToggleInputFloatingSubmitDelegate {
    var submitTapCount = 0
    var voiceTapCount = 0

    func floatingSubmitDidTapSubmit() {
        submitTapCount += 1
    }

    func floatingSubmitDidTapVoice() {
        voiceTapCount += 1
    }
}
