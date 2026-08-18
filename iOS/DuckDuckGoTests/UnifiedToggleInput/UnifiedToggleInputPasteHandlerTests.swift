//
//  UnifiedToggleInputPasteHandlerTests.swift
//  DuckDuckGoTests
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
import UniformTypeIdentifiers
import XCTest
@testable import DuckDuckGo

@MainActor
final class UnifiedToggleInputPasteHandlerTests: XCTestCase {

    // MARK: - canPasteAttachments

    func testCanPasteIsFalseWhenPasteDisabled() {
        let delegate = MockPasteDelegate()
        delegate.support = .init(isEnabled: false, acceptsImages: true, fileTypes: [.pdf])
        let handler = makeHandler(delegate)
        let pasteboard = seededPasteboard(image: true)
        defer { UIPasteboard.remove(withName: pasteboard.name) }

        XCTAssertFalse(handler.canPasteAttachments(from: pasteboard))
    }

    func testCanPasteIsFalseWhenNothingAccepted() {
        let delegate = MockPasteDelegate()
        delegate.support = .init(isEnabled: true, acceptsImages: false, fileTypes: [])
        let handler = makeHandler(delegate)
        let pasteboard = seededPasteboard(image: true)
        defer { UIPasteboard.remove(withName: pasteboard.name) }

        XCTAssertFalse(handler.canPasteAttachments(from: pasteboard))
    }

    func testCanPasteIsTrueForImageWhenSupported() {
        let delegate = MockPasteDelegate()
        delegate.support = .init(isEnabled: true, acceptsImages: true, fileTypes: [])
        let handler = makeHandler(delegate)
        let pasteboard = seededPasteboard(image: true)
        defer { UIPasteboard.remove(withName: pasteboard.name) }

        XCTAssertTrue(handler.canPasteAttachments(from: pasteboard))
    }

    // MARK: - Applying loaded attachments

    func testApplyAddsFilesBeforeImages() {
        let delegate = MockPasteDelegate()
        let handler = makeHandler(delegate)

        handler.applyLoadedAttachments(makeResult(images: 1, files: 1))

        XCTAssertEqual(delegate.callLog, ["file", "image"])
        XCTAssertTrue(delegate.presentedErrors.isEmpty)
    }

    func testApplyBeyondImageLimitAddsWhatFitsAndReportsCapacity() {
        let delegate = MockPasteDelegate()
        delegate.imageHeadroom = 1
        delegate.capacityMessage = "You can only attach 3 images at a time."
        let handler = makeHandler(delegate)

        handler.applyLoadedAttachments(makeResult(images: 3))

        XCTAssertEqual(delegate.addedImages, 1)
        XCTAssertEqual(delegate.presentedErrors, ["You can only attach 3 images at a time."])
    }

    func testApplyWithinImageHeadroomShowsNoCapacityMessage() {
        let delegate = MockPasteDelegate()
        delegate.imageHeadroom = 5
        let handler = makeHandler(delegate)

        handler.applyLoadedAttachments(makeResult(images: 2))

        XCTAssertEqual(delegate.addedImages, 2)
        XCTAssertTrue(delegate.presentedErrors.isEmpty)
    }

    func testApplyDoesNothingWhenPasteDisabledDuringLoad() {
        let delegate = MockPasteDelegate()
        delegate.support = .init(isEnabled: false, acceptsImages: true, fileTypes: [.pdf])
        let handler = makeHandler(delegate)

        handler.applyLoadedAttachments(makeResult(images: 1, files: 1))

        XCTAssertTrue(delegate.callLog.isEmpty)
        XCTAssertTrue(delegate.presentedErrors.isEmpty)
    }

    func testApplyDroppedWhenTabContextChangedDuringLoad() {
        let delegate = MockPasteDelegate()
        delegate.pasteContextIdentity = "tabB"
        let handler = makeHandler(delegate)

        handler.applyLoadedAttachments(makeResult(images: 1, files: 1), expectedContext: "tabA")

        XCTAssertTrue(delegate.callLog.isEmpty)
        XCTAssertTrue(delegate.presentedErrors.isEmpty)
    }

    func testApplyReportsRejectionWithoutAddingAFile() {
        let delegate = MockPasteDelegate()
        let handler = makeHandler(delegate)
        var result = makeResult()
        result.rejection = .fileTooLarge

        handler.applyLoadedAttachments(result)

        XCTAssertEqual(delegate.addedFiles, 0)
        XCTAssertEqual(delegate.rejectionReasons, [.fileTooLarge])
    }

    func testApplyShowsCapacityMessageWhenImagesTruncated() {
        let delegate = MockPasteDelegate()
        delegate.capacityMessage = "You can only attach 3 images at a time."
        let handler = makeHandler(delegate)
        var result = makeResult(images: 1)
        result.imagesTruncated = true

        handler.applyLoadedAttachments(result)

        XCTAssertEqual(delegate.addedImages, 1)
        XCTAssertEqual(delegate.presentedErrors, ["You can only attach 3 images at a time."])
    }

    func testPasteDoesNothingWhenDisabled() {
        let delegate = MockPasteDelegate()
        delegate.support = .init(isEnabled: false, acceptsImages: true, fileTypes: [.pdf])
        let handler = makeHandler(delegate)
        let pasteboard = seededPasteboard(image: true, pdf: true)
        defer { UIPasteboard.remove(withName: pasteboard.name) }

        handler.pasteAttachments(from: pasteboard)

        XCTAssertTrue(delegate.callLog.isEmpty)
        XCTAssertTrue(delegate.presentedErrors.isEmpty)
    }

    // MARK: - Text control paste override

    func testTextViewAdvertisesPasteWhenHandlerAccepts() {
        let handler = MockAttachmentPasteHandler()
        handler.canPasteResult = true
        let textView = SwitchBarTextView()
        textView.attachmentPasteHandler = handler

        XCTAssertTrue(textView.canPerformAction(#selector(UIResponder.paste(_:)), withSender: nil))
    }

    func testTextViewRoutesPasteToHandler() {
        let handler = MockAttachmentPasteHandler()
        handler.canPasteResult = true
        let textView = SwitchBarTextView()
        textView.attachmentPasteHandler = handler

        textView.paste(nil)

        XCTAssertEqual(handler.pasteCallCount, 1)
    }

    func testTextViewDefersToDefaultWhenHandlerDeclines() {
        let handler = MockAttachmentPasteHandler()
        handler.canPasteResult = false
        let textView = SwitchBarTextView()
        textView.attachmentPasteHandler = handler

        textView.paste(nil)

        XCTAssertEqual(handler.pasteCallCount, 0)
    }

    // MARK: - Helpers

    private func makeHandler(_ delegate: MockPasteDelegate) -> UnifiedToggleInputPasteHandler {
        let handler = UnifiedToggleInputPasteHandler()
        handler.delegate = delegate
        return handler
    }

    private func makeResult(images: Int = 0, files: Int = 0) -> PasteboardAttachmentReader.Result {
        var result = PasteboardAttachmentReader.Result()
        result.images = (0..<images).map { (makeTestImage(), "image\($0)") }
        result.files = (0..<files).map {
            AIChatFileAttachment(data: Data("%PDF-1.4".utf8), fileName: "doc\($0).pdf", mimeType: "application/pdf")
        }
        return result
    }

    /// Seeds concrete type identifiers for the metadata-only `canPasteAttachments` probe (the round-trip doesn't need to vend loadable data for that check).
    private func seededPasteboard(image: Bool = false, pdf: Bool = false) -> UIPasteboard {
        let pasteboard = UIPasteboard.withUniqueName()
        var items: [[String: Any]] = []
        if image, let png = makeTestImage().pngData() {
            items.append([UTType.png.identifier: png])
        }
        if pdf {
            items.append([UTType.pdf.identifier: Data("%PDF-1.4".utf8)])
        }
        pasteboard.setItems(items)
        return pasteboard
    }

    private func makeTestImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
    }
}

// MARK: - Mocks

@MainActor
private final class MockPasteDelegate: UnifiedToggleInputPasteDelegate {

    var support = UnifiedToggleInputPasteSupport(isEnabled: true, acceptsImages: true, fileTypes: [.pdf])
    var pasteContextIdentity: String?
    var imageHeadroom = Int.max
    var capacityMessage: String?

    private(set) var callLog: [String] = []
    private(set) var addedImages = 0
    private(set) var addedFiles = 0
    private(set) var rejectionReasons: [PasteRejectionReason] = []
    private(set) var presentedErrors: [String] = []

    var pasteAttachmentSupport: UnifiedToggleInputPasteSupport { support }

    func imageCapacityMessage() -> String? { capacityMessage }

    func pasteWillBeginExpandingIfNeeded() {}

    func addPastedImage(_ image: UIImage, fileName: String) -> Bool {
        guard imageHeadroom > 0 else { return false }
        imageHeadroom -= 1
        addedImages += 1
        callLog.append("image")
        return true
    }

    func addPastedFile(_ file: AIChatFileAttachment) {
        addedFiles += 1
        callLog.append("file")
    }

    func reportRejectedPaste(reason: PasteRejectionReason) {
        rejectionReasons.append(reason)
        callLog.append("rejected")
    }

    func presentPasteError(_ message: String) {
        presentedErrors.append(message)
    }
}

@MainActor
private final class MockAttachmentPasteHandler: AttachmentPasteHandling {
    var canPasteResult = false
    private(set) var pasteCallCount = 0

    func canPasteAttachments(from pasteboard: UIPasteboard) -> Bool { canPasteResult }
    func pasteAttachments(from pasteboard: UIPasteboard) { pasteCallCount += 1 }
}
