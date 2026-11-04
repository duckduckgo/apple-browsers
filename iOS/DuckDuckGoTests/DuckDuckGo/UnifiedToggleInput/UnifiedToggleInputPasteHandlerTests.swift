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
        XCTAssertEqual(delegate.imageRejectionReasons, [.capacityReached])
        XCTAssertEqual(delegate.presentedErrors, ["You can only attach 3 images at a time."])
    }

    /// The gap this closes: no banner to show, but the drop must still be visible in metrics.
    func testApplyRecordsImageRejectionEvenWithoutACapacityMessage() {
        let delegate = MockPasteDelegate()
        delegate.imageHeadroom = 0
        delegate.capacityMessage = nil
        let handler = makeHandler(delegate)

        handler.applyLoadedAttachments(makeResult(images: 2))

        XCTAssertEqual(delegate.addedImages, 0)
        XCTAssertEqual(delegate.imageRejectionReasons, [.capacityReached])
        XCTAssertTrue(delegate.presentedErrors.isEmpty)
    }

    /// A full conversation truncates at a zero allowance before any decode, so no add is refused — it must still read as capacity, not truncation.
    func testApplyReportsCapacityWhenNoImageCouldBeLoadedAtAll() {
        let delegate = MockPasteDelegate()
        let handler = makeHandler(delegate)
        var result = makeResult()
        result.imagesTruncated = true

        handler.applyLoadedAttachments(result)

        XCTAssertEqual(delegate.imageRejectionReasons, [.capacityReached])
    }

    /// Some images fit and the rest were dropped — that is genuine truncation.
    func testApplyReportsTruncationWhenSomeImagesWereLoaded() {
        let delegate = MockPasteDelegate()
        let handler = makeHandler(delegate)
        var result = makeResult(images: 2)
        result.imagesTruncated = true

        handler.applyLoadedAttachments(result)

        XCTAssertEqual(delegate.addedImages, 2)
        XCTAssertEqual(delegate.imageRejectionReasons, [.allowanceTruncated])
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
        XCTAssertEqual(delegate.imageRejectionReasons, [.allowanceTruncated])
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

    // MARK: - Probe memoisation

    func testProbeReadsPasteboardOnceWhileClipboardUnchanged() {
        let pasteboard = seededPasteboard(image: true)
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        let spy = ProbeSpy(answer: true)
        let probe = PasteboardAttachmentProbe(read: spy.read)

        let answers = (0..<5).map { _ in probe.hasSupportedAttachments(in: pasteboard, allowsImages: true, allowedFileTypes: [.pdf]) }

        XCTAssertEqual(answers, Array(repeating: true, count: 5))
        XCTAssertEqual(spy.readCount, 1)
    }

    func testProbeRereadsAfterClipboardChanges() {
        let pasteboard = seededPasteboard(image: true)
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        let spy = ProbeSpy(answer: true)
        let probe = PasteboardAttachmentProbe(read: spy.read)

        _ = probe.hasSupportedAttachments(in: pasteboard, allowsImages: true, allowedFileTypes: [.pdf])
        pasteboard.string = "duckduckgo.com"
        spy.answer = false

        XCTAssertFalse(probe.hasSupportedAttachments(in: pasteboard, allowsImages: true, allowedFileTypes: [.pdf]))
        XCTAssertEqual(spy.readCount, 2)
    }

    /// A model change alters what the input accepts, so the cached answer must not survive it even on an unchanged clipboard.
    func testProbeRereadsWhenAcceptedAttachmentTypesChange() {
        let pasteboard = seededPasteboard(image: true)
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        let spy = ProbeSpy(answer: true)
        let probe = PasteboardAttachmentProbe(read: spy.read)

        _ = probe.hasSupportedAttachments(in: pasteboard, allowsImages: true, allowedFileTypes: [.pdf])
        _ = probe.hasSupportedAttachments(in: pasteboard, allowsImages: true, allowedFileTypes: [.plainText])
        XCTAssertEqual(spy.readCount, 2)

        _ = probe.hasSupportedAttachments(in: pasteboard, allowsImages: false, allowedFileTypes: [.plainText])
        XCTAssertEqual(spy.readCount, 3)
    }

    func testProbeRereadsForADifferentPasteboard() {
        let first = seededPasteboard(image: true)
        let second = seededPasteboard(image: true)
        defer {
            UIPasteboard.remove(withName: first.name)
            UIPasteboard.remove(withName: second.name)
        }
        let spy = ProbeSpy(answer: true)
        let probe = PasteboardAttachmentProbe(read: spy.read)

        _ = probe.hasSupportedAttachments(in: first, allowsImages: true, allowedFileTypes: [.pdf])
        _ = probe.hasSupportedAttachments(in: second, allowsImages: true, allowedFileTypes: [.pdf])

        XCTAssertEqual(spy.readCount, 2)
    }

    func testCanPasteReadsPasteboardOnceForRepeatedMenuBuilds() {
        let delegate = MockPasteDelegate()
        let spy = ProbeSpy(answer: true)
        let handler = makeHandler(delegate, probe: PasteboardAttachmentProbe(read: spy.read))
        let pasteboard = seededPasteboard(image: true)
        defer { UIPasteboard.remove(withName: pasteboard.name) }

        for _ in 0..<5 {
            XCTAssertTrue(handler.canPasteAttachments(from: pasteboard))
        }

        XCTAssertEqual(spy.readCount, 1)
    }

    private func longText(_ count: Int = 4_000) -> String { String(repeating: "a", count: count) }

    func testInsertedTextAtTheThresholdBecomesPastedTextAndBelowStaysInline() {
        let delegate = MockPasteDelegate()
        delegate.support = .init(isEnabled: true, acceptsImages: false, fileTypes: [], acceptsPastedText: true)
        let handler = makeHandler(delegate)

        XCTAssertFalse(handler.attachInsertedTextIfLong(longText(3_999)))
        XCTAssertTrue(handler.attachInsertedTextIfLong(longText(4_000)))
        XCTAssertEqual(delegate.pastedTexts, [longText(4_000)])
    }

    func testBlankInsertedTextStaysInline() {
        let delegate = MockPasteDelegate()
        delegate.support = .init(isEnabled: true, acceptsImages: false, fileTypes: [], acceptsPastedText: true)
        let handler = makeHandler(delegate)

        XCTAssertFalse(handler.attachInsertedTextIfLong(String(repeating: " ", count: 5_000)))
        XCTAssertTrue(delegate.pastedTexts.isEmpty)
    }

    func testLongInsertedTextStaysInlineWhenPasteIsDisabled() {
        let delegate = MockPasteDelegate()
        delegate.support = .init(isEnabled: false, acceptsImages: true, fileTypes: [.pdf], acceptsPastedText: true)
        let handler = makeHandler(delegate)

        XCTAssertFalse(handler.attachInsertedTextIfLong(longText()))
        XCTAssertTrue(delegate.pastedTexts.isEmpty)
    }

    func testLongInsertedTextStaysInlineWhenPastedTextIsNotAccepted() {
        let delegate = MockPasteDelegate()
        delegate.support = .init(isEnabled: true, acceptsImages: true, fileTypes: [.pdf], acceptsPastedText: false)
        let handler = makeHandler(delegate)

        XCTAssertFalse(handler.attachInsertedTextIfLong(longText()))
        XCTAssertTrue(delegate.pastedTexts.isEmpty)
    }

    func testTextEntryRefusesTheInsertionTheHandlerTakes() throws {
        let handler = MockAttachmentPasteHandler()
        handler.takesInsertedText = true
        let sut = SwitchBarTextEntryView(handler: UnifiedToggleInputHandler(isVoiceSearchEnabled: false))
        sut.attachmentPasteHandler = handler
        let textView = try XCTUnwrap(firstDescendant(of: SwitchBarTextView.self, in: sut))

        XCTAssertFalse(sut.textView(textView, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementText: longText()))
        XCTAssertEqual(handler.offeredTexts, [longText()])
    }

    func testTextEntryInsertsTextTheHandlerDeclines() throws {
        let handler = MockAttachmentPasteHandler()
        let sut = SwitchBarTextEntryView(handler: UnifiedToggleInputHandler(isVoiceSearchEnabled: false))
        sut.attachmentPasteHandler = handler
        let textView = try XCTUnwrap(firstDescendant(of: SwitchBarTextView.self, in: sut))

        XCTAssertTrue(sut.textView(textView, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementText: "hello"))
        XCTAssertEqual(handler.offeredTexts, ["hello"])
    }

    func testTextEntryRemovesTheSelectionALongPasteReplacesAndRestoresTheCaret() throws {
        let handler = MockAttachmentPasteHandler()
        handler.takesInsertedText = true
        let inputHandler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        let sut = SwitchBarTextEntryView(handler: inputHandler)
        sut.attachmentPasteHandler = handler
        sut.setQueryText("keep this, drop that")
        let textView = try XCTUnwrap(firstDescendant(of: SwitchBarTextView.self, in: sut))
        let selection = NSRange(location: 10, length: 10)

        XCTAssertFalse(sut.textView(textView, shouldChangeTextIn: selection, replacementText: longText()))

        XCTAssertEqual(textView.text, "keep this,")
        XCTAssertEqual(inputHandler.currentText, "keep this,", "The text model follows the removal")
    }

    func testRemovingTheReplacedSelectionPutsTheCaretBackOnTheScheduledTurn() {
        let textView = SwitchBarTextView()
        textView.text = "keep this, drop that"
        var scheduled: [() -> Void] = []

        PastedTextInsertion.removeReplacedSelection(in: textView, range: NSRange(location: 10, length: 10), schedule: { scheduled.append($0) })
        textView.selectedRange = NSRange(location: 3, length: 0)
        XCTAssertEqual(scheduled.count, 1)
        scheduled.forEach { $0() }

        XCTAssertEqual(textView.text, "keep this,")
        XCTAssertEqual(textView.selectedRange, NSRange(location: 10, length: 0))
    }

    func testPasteAndGoThatConvertsSubmitsAnAttachmentOnlyPromptWithItsOwnTrigger() throws {
        let handler = MockAttachmentPasteHandler()
        handler.takesInsertedText = true
        let inputHandler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        let sut = SwitchBarTextEntryView(handler: inputHandler)
        sut.attachmentPasteHandler = handler
        sut.setQueryText("typed draft")
        let textView = try XCTUnwrap(firstDescendant(of: SwitchBarTextView.self, in: sut))
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        pasteboard.string = longText()
        textView.pasteboard = { pasteboard }
        var submissions: [(text: String, trigger: TextSubmissionTrigger)] = []
        let cancellable = inputHandler.textSubmissionPublisher.sink { submissions.append((text: $0.text, trigger: $0.trigger)) }
        defer { cancellable.cancel() }

        sut.pasteURLAndGo()

        XCTAssertEqual(handler.offeredTexts, [longText()])
        XCTAssertEqual(inputHandler.currentText, "", "Paste & Go replaces the draft")
        XCTAssertEqual(submissions.map(\.text), [""])
        XCTAssertEqual(submissions.map(\.trigger), [.pasteAndGo])
    }

    func testPasteAndGoThatDoesNotConvertSubmitsTheTextAsToday() throws {
        let handler = MockAttachmentPasteHandler()
        let inputHandler = UnifiedToggleInputHandler(isVoiceSearchEnabled: false)
        let sut = SwitchBarTextEntryView(handler: inputHandler)
        sut.attachmentPasteHandler = handler
        let textView = try XCTUnwrap(firstDescendant(of: SwitchBarTextView.self, in: sut))
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        pasteboard.string = "duckduckgo.com"
        textView.pasteboard = { pasteboard }
        var submissions: [(text: String, trigger: TextSubmissionTrigger)] = []
        let cancellable = inputHandler.textSubmissionPublisher.sink { submissions.append((text: $0.text, trigger: $0.trigger)) }
        defer { cancellable.cancel() }

        sut.pasteURLAndGo()

        XCTAssertEqual(submissions.map(\.text), ["duckduckgo.com"])
        XCTAssertEqual(submissions.map(\.trigger), [.pasteAndGo])
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
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        textView.pasteboard = { pasteboard }

        textView.paste(nil)

        XCTAssertEqual(handler.pasteCallCount, 1)
        XCTAssertTrue(handler.pasteboards.allSatisfy { $0 === pasteboard })
    }

    func testTextViewDefersToDefaultWhenHandlerDeclines() {
        let handler = MockAttachmentPasteHandler()
        handler.canPasteResult = false
        let textView = SwitchBarTextView()
        textView.attachmentPasteHandler = handler
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        textView.pasteboard = { pasteboard }

        textView.paste(nil)

        XCTAssertEqual(handler.pasteCallCount, 0)
    }

    private func firstDescendant<T: UIView>(of type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { self.firstDescendant(of: type, in: $0) }.first
    }

    // MARK: - Helpers

    private func makeHandler(_ delegate: MockPasteDelegate, probe: PasteboardAttachmentProbe = PasteboardAttachmentProbe()) -> UnifiedToggleInputPasteHandler {
        let handler = UnifiedToggleInputPasteHandler(attachmentProbe: probe)
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
    private(set) var rejectionReasons: [PasteFileRejectionReason] = []
    private(set) var imageRejectionReasons: [PasteImageRejectionReason] = []
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

    func reportRejectedPastedFiles(reason: PasteFileRejectionReason) {
        rejectionReasons.append(reason)
        callLog.append("rejected")
    }

    func reportRejectedPastedImages(reason: PasteImageRejectionReason) {
        imageRejectionReasons.append(reason)
    }

    func presentPasteError(_ message: String) {
        presentedErrors.append(message)
    }

    private(set) var pastedTexts: [String] = []

    func addPastedText(_ text: String) {
        pastedTexts.append(text)
    }
}

@MainActor
private final class MockAttachmentPasteHandler: AttachmentPasteHandling {
    var canPasteResult = false
    var takesInsertedText = false
    private(set) var pasteCallCount = 0
    private(set) var pasteboards: [UIPasteboard] = []
    private(set) var offeredTexts: [String] = []

    func canPasteAttachments(from pasteboard: UIPasteboard) -> Bool {
        pasteboards.append(pasteboard)
        return canPasteResult
    }
    func pasteAttachments(from pasteboard: UIPasteboard) {
        pasteboards.append(pasteboard)
        pasteCallCount += 1
    }
    func attachInsertedTextIfLong(_ text: String) -> Bool {
        offeredTexts.append(text)
        return takesInsertedText
    }
}

@MainActor
private final class ProbeSpy {
    var answer: Bool
    private(set) var readCount = 0

    init(answer: Bool) {
        self.answer = answer
    }

    func read(_ pasteboard: UIPasteboard, _ allowsImages: Bool, _ allowedFileTypes: [UTType]) -> Bool {
        readCount += 1
        return answer
    }
}
