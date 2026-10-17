//
//  UTIAttachmentControllerTests.swift
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
import Core
import UIKit
import XCTest
@testable import DuckDuckGo
@_spi(Testing) import PixelKit

/// Isolated unit tests for `UTIAttachmentController` — exercises the controller directly through
/// stub `ViewSurface` / `Environment` / `Callbacks`, without a live coordinator. Coordinator-level
/// wiring + policy construction stay covered by `UnifiedToggleInputCoordinatorAttachmentLimitsTests`.
@MainActor
final class UTIAttachmentControllerTests: XCTestCase {

    private var view: FakeAttachmentView!
    private var config: FakeEnvironmentConfig!
    private var callbackSpy: CallbackSpy!
    private var pixelKitMock: PixelKitMock!

    override func setUp() {
        super.setUp()
        pixelKitMock = PixelKitMock()
        view = FakeAttachmentView()
        config = FakeEnvironmentConfig()
        callbackSpy = CallbackSpy()
    }

    override func tearDown() {
        pixelKitMock = nil
        view = nil
        config = nil
        callbackSpy = nil
        super.tearDown()
    }

    // MARK: - Images

    func testAddImageAttachment_whenModelSupportsImages_addsImageAndPersists() {
        config.model = makeModel(supportsImageUpload: true)
        config.limits = makeLimits()
        let sut = makeController()

        sut.addImageAttachment(image: UIImage(), fileName: "a.jpg")

        XCTAssertEqual(view.attachments.count, 1)
        XCTAssertTrue(view.attachments.first?.isImage == true)
        XCTAssertEqual(callbackSpy.onDraftChangedCount, 1)
    }

    func testAddImageAttachment_whenModelDoesNotSupportImages_isNoOp() {
        config.model = makeModel(supportsImageUpload: false)
        config.limits = makeLimits()
        let sut = makeController()

        sut.addImageAttachment(image: UIImage(), fileName: "a.jpg")

        XCTAssertTrue(view.attachments.isEmpty)
        XCTAssertEqual(callbackSpy.onDraftChangedCount, 0)
    }

    // MARK: - Files

    func testAddValidFileAttachment_addsFileAndFiresAttachedPixel() {
        config.model = makeModel(supportsImageUpload: false, supportedFileTypes: ["application/pdf"])
        config.limits = makeLimits()
        let sut = makeController()

        sut.addFileAttachment(makeFileAttachment())

        XCTAssertEqual(view.attachments.count, 1)
        XCTAssertFalse(view.attachments.first?.isInvalid == true)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.unifiedToggleInputFileAttached.name)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters?["source"], "file_picker")
    }

    func testAddInvalidFileAttachment_addsInvalidChipShowsErrorAndFiresValidationPixel() {
        config.model = makeModel(supportsImageUpload: false, supportedFileTypes: ["application/pdf"])
        config.limits = makeLimits()
        let sut = makeController()

        sut.addFileAttachment(makeFileAttachment(pageCount: 9)) // exceeds maxPagesPerFile (8)

        XCTAssertEqual(view.attachments.count, 1)
        XCTAssertTrue(view.attachments.first?.isInvalid == true)
        XCTAssertNotNil(view.validationMessage)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.unifiedToggleInputFileValidationFailed.name)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters?["source"], "file_picker")
    }

    // MARK: - Remove / clear

    func testRemoveAttachment_removesFromViewAndPersists() {
        config.model = makeModel(supportsImageUpload: true)
        config.limits = makeLimits()
        let sut = makeController()
        sut.addImageAttachment(image: UIImage(), fileName: "a.jpg")
        let id = view.attachments.first!.id
        callbackSpy.onDraftChangedCount = 0

        sut.removeAttachment(id: id)

        XCTAssertTrue(view.attachments.isEmpty)
        XCTAssertEqual(callbackSpy.onDraftChangedCount, 1)
    }

    func testClearAttachments_removesAllAndClearsValidation() {
        config.model = makeModel(supportsImageUpload: true)
        config.limits = makeLimits()
        let sut = makeController()
        sut.addImageAttachment(image: UIImage(), fileName: "a.jpg")
        sut.addImageAttachment(image: UIImage(), fileName: "b.jpg")
        view.validationMessage = "stale error"

        sut.clearAttachments()

        XCTAssertTrue(view.attachments.isEmpty)
        XCTAssertNil(view.validationMessage)
    }

    // MARK: - Paste rejection banner

    func testReportRejectedPaste_showsTransientBannerAndFiresValidationPixelWithPasteSource() {
        config.model = makeModel(supportsImageUpload: false, supportedFileTypes: ["application/pdf"])
        config.limits = makeLimits()
        let sut = makeController()

        sut.reportRejectedPastedFiles(reason: .fileTooLarge)

        XCTAssertEqual(view.validationMessage, UserText.aiChatAttachmentFileTooLarge(maxFileSizeMB: 5))
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.pixel.name, Pixel.Event.unifiedToggleInputFileValidationFailed.name)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters?["reason"], "size_exceeded")
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.additionalParameters?["source"], "paste")
    }

    func testTransientBanner_survivesValidationResyncWithNoInvalidAttachments() {
        config.model = makeModel(supportsImageUpload: false, supportedFileTypes: ["application/pdf"])
        config.limits = makeLimits()
        config.inputMode = .aiChat
        let sut = makeController()

        sut.reportRejectedPastedFiles(reason: .fileTooLarge)
        XCTAssertNotNil(view.validationMessage)

        // A re-sync with no attachment-derived error must fall back to the transient banner, not clear it.
        sut.syncValidationErrorForCurrentMode()

        XCTAssertNotNil(view.validationMessage)
    }

    // MARK: - Attach button presentation

    func testUpdateAttachButtonPresentation_hidesButtonWhenNoAttachmentSupport() {
        config.model = makeModel(supportsImageUpload: false, supportedFileTypes: [])
        config.limits = makeLimits()
        let sut = makeController()

        sut.updateAttachButtonPresentation()

        XCTAssertTrue(view.imageButtonHidden)
    }

    func testUpdateAttachButtonPresentation_whenUnavailableButtonShouldRemainVisible_showsDisabledButtonWithoutMenu() {
        config.model = makeModel(supportsImageUpload: false, supportedFileTypes: [])
        config.limits = makeLimits()
        config.keepsUnavailableAttachmentButtonVisible = true
        let sut = makeController()

        sut.updateAttachButtonPresentation()

        XCTAssertFalse(view.imageButtonHidden)
        XCTAssertFalse(view.imageButtonEnabled)
        XCTAssertNil(view.attachmentMenu)
    }

    func testUpdateAttachButtonPresentation_whenModelIsUnknown_hidesUnavailableButton() {
        config.model = nil
        config.limits = makeLimits()
        config.keepsUnavailableAttachmentButtonVisible = true
        let sut = makeController()

        sut.updateAttachButtonPresentation()

        XCTAssertTrue(view.imageButtonHidden)
        XCTAssertFalse(view.imageButtonEnabled)
        XCTAssertNil(view.attachmentMenu)
    }

    func testUpdateAttachButtonPresentation_disablesButtonWhileGenerating() {
        config.model = makeModel(supportsImageUpload: true)
        config.limits = makeLimits()
        view.isGenerating = true
        let sut = makeController()

        sut.updateAttachButtonPresentation()

        XCTAssertFalse(view.imageButtonHidden)
        XCTAssertFalse(view.imageButtonEnabled)
    }

    // MARK: - Unsupported-attachment pruning

    func testRemoveUnsupportedAttachmentsForSelectedModel_removesImageWhenModelLosesImageSupport() {
        config.model = makeModel(supportsImageUpload: true)
        config.limits = makeLimits()
        let sut = makeController()
        sut.addImageAttachment(image: UIImage(), fileName: "a.jpg")
        XCTAssertEqual(view.attachments.count, 1)

        config.model = makeModel(supportsImageUpload: false)
        sut.removeUnsupportedAttachmentsForSelectedModel()

        XCTAssertTrue(view.attachments.isEmpty)
    }

    // MARK: - Submission validation

    func testSubmissionValidationMessage_inSearchMode_returnsNil() {
        config.model = makeModel(supportsImageUpload: true)
        config.limits = makeLimits()
        let sut = makeController()

        XCTAssertNil(sut.submissionValidationMessage(for: "hello", mode: .search))
    }

    // MARK: - Tab attachments

    func testWhenDraftChangesWhilePickerIsOpenThenUnchangedConfirmationReportsCancellationOnce() {
        enableTabAttachments()
        let controller = makeController()
        let first = candidate(id: "first")

        for isAttached in [true, false] {
            let initialTabIds: Set<TabUID> = isAttached ? [] : [first.tabId]
            let selectedTabIds: Set<TabUID> = isAttached ? [first.tabId] : []
            let session = makePickerPixelSession()
            session.show()

            XCTAssertEqual(controller.setTabAttachment(first, isAttached: isAttached, attachmentSource: .mention), .changed)
            let fireCount = pixelKitMock.actualFireCalls.count
            let draftChangeCount = callbackSpy.onDraftChangedCount

            UnifiedToggleInputAttachmentPresenter.confirmTabSelection(
                selectedTabIds, initialTabIds: initialTabIds, candidates: [first], pixelSession: session,
                tabActionHandler: controller.setTabAttachment)
            session.finish()

            let calls = Array(pixelKitMock.actualFireCalls.dropFirst(fireCount))
            XCTAssertEqual(calls.map(\.pixel.name), ["aichat_unified_input_tab_picker_canceled"])
            XCTAssertEqual(calls.first?.pixel.parameters, ["surface": "contextual_chat", "source": "tab_picker"])
            XCTAssertEqual(calls.first?.frequency, .dailyAndCount)
            XCTAssertEqual(Set(view.attachments.compactMap { $0.tabAttachment?.tabId }), selectedTabIds)
            XCTAssertEqual(callbackSpy.onDraftChangedCount, draftChangeCount)
        }
    }

    func testWhenPickerAddsOrRemovesTabThenReportsMutationWithoutCancellation() {
        enableTabAttachments()
        let controller = makeController()
        let first = candidate(id: "first")

        for isAttached in [true, false] {
            let initialTabIds: Set<TabUID> = isAttached ? [] : [first.tabId]
            let selectedTabIds: Set<TabUID> = isAttached ? [first.tabId] : []
            let session = makePickerPixelSession()
            session.show()
            let fireCount = pixelKitMock.actualFireCalls.count

            UnifiedToggleInputAttachmentPresenter.confirmTabSelection(
                selectedTabIds, initialTabIds: initialTabIds, candidates: [first], pixelSession: session,
                tabActionHandler: controller.setTabAttachment)
            session.finish()

            let calls = Array(pixelKitMock.actualFireCalls.dropFirst(fireCount))
            XCTAssertEqual(calls.map(\.pixel.name), [isAttached ? "aichat_unified_input_tab_attached" : "aichat_unified_input_tab_removed"])
            XCTAssertEqual(calls.first?.pixel.parameters?["source"], "tab_picker")
            XCTAssertEqual(Set(view.attachments.compactMap { $0.tabAttachment?.tabId }), selectedTabIds)
        }
    }

    func testWhenPickerConfirmsOriginalSelectionThenReportsCancellationOnce() {
        enableTabAttachments()
        let controller = makeController()
        let session = makePickerPixelSession()
        session.show()
        let fireCount = pixelKitMock.actualFireCalls.count

        UnifiedToggleInputAttachmentPresenter.confirmTabSelection(
            [], initialTabIds: [], candidates: [candidate(id: "first")], pixelSession: session,
            tabActionHandler: controller.setTabAttachment)
        session.finish()

        XCTAssertEqual(pixelKitMock.actualFireCalls.dropFirst(fireCount).map(\.pixel.name), ["aichat_unified_input_tab_picker_canceled"])
        XCTAssertTrue(view.attachments.isEmpty)
        XCTAssertEqual(callbackSpy.onDraftChangedCount, 0)
    }

    func testWhenPickerSelectionIsRejectedThenReportsCancellationOnce() {
        enableTabAttachments(limit: 1)
        let controller = makeController()
        let first = candidate(id: "first")
        let second = candidate(id: "second")
        let session = makePickerPixelSession()
        session.show()
        XCTAssertEqual(controller.setTabAttachment(first, isAttached: true, attachmentSource: .mention), .changed)
        let fireCount = pixelKitMock.actualFireCalls.count

        UnifiedToggleInputAttachmentPresenter.confirmTabSelection(
            [second.tabId], initialTabIds: [], candidates: [first, second], pixelSession: session,
            tabActionHandler: controller.setTabAttachment)
        session.finish()

        XCTAssertEqual(pixelKitMock.actualFireCalls.dropFirst(fireCount).map(\.pixel.name), ["aichat_unified_input_tab_picker_canceled"])
        XCTAssertEqual(view.attachments.compactMap { $0.tabAttachment?.tabId }, [first.tabId])
        XCTAssertEqual(callbackSpy.onDraftChangedCount, 1)
    }

    func testWhenPickerConfirmationHasMixedResultsThenActualChangePreventsCancellation() {
        enableTabAttachments(limit: 2)
        let controller = makeController()
        let first = candidate(id: "first")
        let second = candidate(id: "second")
        let third = candidate(id: "third")
        XCTAssertEqual(controller.setTabAttachment(first, isAttached: true, attachmentSource: .recentTabs), .changed)
        let session = makePickerPixelSession()
        session.show()
        XCTAssertEqual(controller.setTabAttachment(first, isAttached: false, attachmentSource: .recentTabs), .changed)
        config.tabFeatureState = .available(maximumTabAttachmentCount: 1)
        let fireCount = pixelKitMock.actualFireCalls.count

        UnifiedToggleInputAttachmentPresenter.confirmTabSelection(
            [second.tabId, third.tabId], initialTabIds: [first.tabId], candidates: [first, second, third], pixelSession: session,
            tabActionHandler: controller.setTabAttachment)
        session.finish()

        XCTAssertEqual(pixelKitMock.actualFireCalls.dropFirst(fireCount).map(\.pixel.name), ["aichat_unified_input_tab_attached"])
        XCTAssertEqual(view.attachments.compactMap { $0.tabAttachment?.tabId }, [second.tabId])
        XCTAssertEqual(callbackSpy.onDraftChangedCount, 3)
    }

    func testWhenTabSelectionChangesThenReportsOnceAndPreservesOriginalSourceOnRemoval() {
        enableTabAttachments(limit: 1)
        let controller = makeController()
        let first = candidate(id: "first")

        XCTAssertEqual(controller.setTabAttachment(first, isAttached: true, attachmentSource: .mention), .changed)
        XCTAssertEqual(controller.setTabAttachment(first, isAttached: true, attachmentSource: .tabPicker), .unchanged)
        XCTAssertEqual(controller.setTabAttachment(candidate(id: "second"), isAttached: true, attachmentSource: .recentTabs), .rejected)
        XCTAssertEqual(controller.setTabAttachment(first, isAttached: false, attachmentSource: .tabPicker), .changed)
        XCTAssertEqual(controller.setTabAttachment(first, isAttached: false, attachmentSource: .recentTabs), .unchanged)

        XCTAssertEqual(pixelKitMock.actualFireCalls.map(\.pixel.name), [
            "aichat_unified_input_tab_attached", "aichat_unified_input_tab_removed"
        ])
        for call in pixelKitMock.actualFireCalls {
            XCTAssertEqual(call.pixel.parameters?["source"], "mention")
            XCTAssertEqual(call.frequency, .dailyAndCount)
        }
    }

    func testWhenCurrentPageOrDisabledFeatureIsSelectedThenNoAdditionalTabPixel() {
        enableTabAttachments()
        config.pageContextAttachHandler = { }
        let controller = makeController()
        XCTAssertEqual(controller.setTabAttachment(candidate(id: "current"), isAttached: true, attachmentSource: .recentTabs), .changed)
        config.tabFeatureState = .unavailable
        XCTAssertEqual(controller.setTabAttachment(candidate(id: "first"), isAttached: true, attachmentSource: .recentTabs), .rejected)
        XCTAssertTrue(pixelKitMock.actualFireCalls.isEmpty)
    }

    func testFirstUseCallbackRequiresSuccessfulAdditionalTabAttachment() {
        enableTabAttachments(limit: 1)
        let controller = makeController()
        let first = candidate(id: "first")
        XCTAssertEqual(controller.setTabAttachment(first, isAttached: true, attachmentSource: .recentTabs), .changed)
        XCTAssertEqual(callbackSpy.onTabAttachedCount, 1)
        XCTAssertEqual(controller.setTabAttachment(first, isAttached: true, attachmentSource: .recentTabs), .unchanged)
        XCTAssertEqual(controller.setTabAttachment(candidate(id: "second"), isAttached: true, attachmentSource: .recentTabs), .rejected)
        XCTAssertEqual(controller.setTabAttachment(first, isAttached: false, attachmentSource: .recentTabs), .changed)
        XCTAssertEqual(callbackSpy.onTabAttachedCount, 1)
        XCTAssertTrue(controller.toggleTabAttachment(candidate(id: "second"), attachmentSource: .recentTabs))
        XCTAssertEqual(callbackSpy.onTabAttachedCount, 2)
    }

    func testCurrentPageAndOpeningMenuDoNotReportAdditionalTabUse() {
        enableTabAttachments()
        let config = self.config!
        config.pageContextAttachHandler = { config.isCurrentPageAttached = true }
        let controller = makeController()
        controller.updateAttachButtonPresentation()
        XCTAssertEqual(callbackSpy.onTabAttachedCount, 0)
        XCTAssertEqual(controller.setTabAttachment(candidate(id: "current"), isAttached: true, attachmentSource: .recentTabs), .changed)
        XCTAssertEqual(callbackSpy.onTabAttachedCount, 0)
    }

    func test_tabSelection_togglesByIdentityAndKeepsSameAddressTabsDistinct() {
        enableTabAttachments()
        let controller = makeController()
        let first = candidate(id: "first")
        let second = candidate(id: "second")

        XCTAssertTrue(controller.toggleTabAttachment(first, attachmentSource: .recentTabs))
        XCTAssertTrue(controller.toggleTabAttachment(second, attachmentSource: .recentTabs))
        XCTAssertEqual(view.attachments.compactMap { $0.tabAttachment?.tabId }, ["first", "second"])
        XCTAssertTrue(controller.toggleTabAttachment(first, attachmentSource: .recentTabs))
        XCTAssertEqual(view.attachments.compactMap { $0.tabAttachment?.tabId }, ["second"])
    }

    func test_tabSelection_currentPageReservesOneSlotAndCanBeRemovedAtCapacity() {
        enableTabAttachments()
        config.isCurrentPageAttached = true
        let config = self.config!
        config.pageContextRemoveHandler = { [unowned config] in config.isCurrentPageAttached = false }
        let controller = makeController()

        XCTAssertTrue(controller.toggleTabAttachment(candidate(id: "first"), attachmentSource: .recentTabs))
        XCTAssertTrue(controller.toggleTabAttachment(candidate(id: "second"), attachmentSource: .recentTabs))
        XCTAssertFalse(controller.toggleTabAttachment(candidate(id: "third"), attachmentSource: .recentTabs))
        XCTAssertTrue(controller.toggleTabAttachment(candidate(id: "current"), attachmentSource: .recentTabs))
        XCTAssertFalse(config.isCurrentPageAttached)
        XCTAssertTrue(controller.toggleTabAttachment(candidate(id: "third"), attachmentSource: .recentTabs))
        XCTAssertEqual(view.attachments.count, 3)
    }

    func test_tabSelection_currentPageUsesExistingHandlerWithoutCreatingTabChip() {
        enableTabAttachments(limit: 1)
        var attachCount = 0
        let config = self.config!
        config.pageContextAttachHandler = { [unowned config] in
            attachCount += 1
            config.isCurrentPageAttached = true
        }
        let controller = makeController()

        XCTAssertTrue(controller.toggleTabAttachment(candidate(id: "current"), attachmentSource: .recentTabs))
        XCTAssertEqual(attachCount, 1)
        XCTAssertTrue(view.attachments.isEmpty)
        XCTAssertFalse(controller.toggleTabAttachment(candidate(id: "first"), attachmentSource: .recentTabs))
        XCTAssertEqual(controller.setTabAttachment(candidate(id: "current"), isAttached: true, attachmentSource: .recentTabs), .unchanged)
        XCTAssertEqual(attachCount, 1)
    }

    func test_tabSelection_disabledFeatureDoesNotReadCandidatesOrMutateDraft() {
        enableTabAttachments()
        config.tabFeatureState = .unavailable
        let controller = makeController()

        _ = controller.makeAttachmentMenu()
        XCTAssertFalse(controller.toggleTabAttachment(candidate(id: "first"), attachmentSource: .recentTabs))
        XCTAssertEqual(config.candidateReadCount, 0)
        XCTAssertTrue(view.attachments.isEmpty)
        XCTAssertEqual(callbackSpy.onDraftChangedCount, 0)
    }

    func test_tabSelection_disabledAfterMenuCreationRejectsSelection() {
        enableTabAttachments()
        let controller = makeController()
        _ = controller.makeAttachmentMenu()
        config.tabFeatureState = .unavailable

        XCTAssertFalse(controller.toggleTabAttachment(candidate(id: "first"), attachmentSource: .recentTabs))
        XCTAssertTrue(view.attachments.isEmpty)
    }

    func test_tabSelection_ignoresNonContextualSurfacesAndGeneratingState() {
        enableTabAttachments()
        let controller = makeController()
        config.isContextualChatState = false
        XCTAssertFalse(controller.toggleTabAttachment(candidate(id: "first"), attachmentSource: .recentTabs))
        config.isContextualChatState = true
        view.isGenerating = true
        XCTAssertFalse(controller.toggleTabAttachment(candidate(id: "first"), attachmentSource: .recentTabs))
        XCTAssertTrue(view.attachments.isEmpty)
    }

    func test_tabSelection_rejectsOtherModeAndClosedCandidates() {
        enableTabAttachments()
        config.tabs.append(Tab(uid: "fire", link: Link(title: "Fire", url: candidate(id: "fire").url), fireTab: true))
        let controller = makeController()
        _ = controller.makeAttachmentMenu()
        config.tabs.removeAll { $0.uid == "first" }

        XCTAssertFalse(controller.toggleTabAttachment(candidate(id: "fire"), attachmentSource: .recentTabs))
        XCTAssertFalse(controller.toggleTabAttachment(candidate(id: "first"), attachmentSource: .recentTabs))
        XCTAssertTrue(view.attachments.isEmpty)
    }

    func test_tabSelection_fireSourceRejectsStandardTab() {
        enableTabAttachments(mode: .fire)
        config.tabs.append(Tab(uid: "standard", link: Link(title: "Standard", url: candidate(id: "standard").url), fireTab: false))
        let controller = makeController()

        XCTAssertFalse(controller.toggleTabAttachment(candidate(id: "standard"), attachmentSource: .recentTabs))
        XCTAssertTrue(controller.toggleTabAttachment(candidate(id: "first"), attachmentSource: .recentTabs))
    }

    func test_tabSelection_usesFreshMetadataWhenCandidateNavigated() {
        enableTabAttachments()
        let controller = makeController()
        let oldCandidate = candidate(id: "first")
        let newURL = URL(string: "https://example.org/new")!
        config.tabs.first { $0.uid == "first" }?.link = Link(title: "New page", url: newURL)

        XCTAssertTrue(controller.toggleTabAttachment(oldCandidate, attachmentSource: .recentTabs))
        XCTAssertEqual(view.attachments.first?.tabAttachment?.url, newURL)
        XCTAssertEqual(view.attachments.first?.tabAttachment?.title, "New page")
    }

    func test_tabSelection_rejectsIneligibleCurrentPage() {
        enableTabAttachments()
        config.isCurrentPageAttachable = false
        var didRequestPage = false
        config.pageContextAttachHandler = { didRequestPage = true }
        let controller = makeController()

        XCTAssertFalse(controller.toggleTabAttachment(candidate(id: "current"), attachmentSource: .recentTabs))
        XCTAssertFalse(didRequestPage)
    }

    func test_tabSelection_explicitStateDoesNotInvertExistingAttachment() {
        enableTabAttachments()
        let controller = makeController()
        XCTAssertEqual(controller.setTabAttachment(candidate(id: "first"), isAttached: true, attachmentSource: .recentTabs), .changed)
        XCTAssertEqual(controller.setTabAttachment(candidate(id: "first"), isAttached: true, attachmentSource: .recentTabs), .unchanged)
        XCTAssertEqual(view.attachments.count, 1)
        XCTAssertEqual(callbackSpy.onDraftChangedCount, 1)
        XCTAssertEqual(controller.setTabAttachment(candidate(id: "first"), isAttached: false, attachmentSource: .recentTabs), .changed)
        XCTAssertEqual(controller.setTabAttachment(candidate(id: "first"), isAttached: false, attachmentSource: .recentTabs), .unchanged)
        XCTAssertTrue(view.attachments.isEmpty)
    }

    func test_tabChipRemovalReleasesCapacity() throws {
        enableTabAttachments(limit: 1)
        let controller = makeController()
        XCTAssertTrue(controller.toggleTabAttachment(candidate(id: "first"), attachmentSource: .recentTabs))
        controller.removeAttachment(id: try XCTUnwrap(view.attachments.first?.id))

        XCTAssertTrue(controller.toggleTabAttachment(candidate(id: "second"), attachmentSource: .recentTabs))
        XCTAssertEqual(view.attachments.compactMap { $0.tabAttachment?.tabId }, ["second"])
    }

    func test_tabMenuReflectsSharedLimitAndKeepsSelectedRowsEnabled() throws {
        enableTabAttachments(limit: 2)
        config.isCurrentPageAttached = true
        config.pageContextAttachHandler = {}
        let controller = makeController()
        XCTAssertTrue(controller.toggleTabAttachment(candidate(id: "first"), attachmentSource: .recentTabs))
        let menu = try XCTUnwrap(controller.makeAttachmentMenu())
        let recent = try XCTUnwrap(menu.children.first as? UIMenu)
        let actions = recent.children.compactMap { $0 as? UIAction }

        XCTAssertEqual(actions.count, 3)
        XCTAssertEqual(actions.map(\.state), [.on, .on, .off])
        XCTAssertFalse(actions[0].attributes.contains(.disabled))
        XCTAssertFalse(actions[1].attributes.contains(.disabled))
        XCTAssertTrue(actions[2].attributes.contains(.disabled))
        let askPage = try XCTUnwrap(menu.children.compactMap { $0 as? UIAction }
            .first { $0.title == UserText.aiChatAttachmentOptionAskAboutPage })
        XCTAssertFalse(askPage.attributes.contains(.disabled))
    }

    // MARK: - Helpers

    private func makePickerPixelSession() -> MultiTabPickerPixelSession {
        let reporter = UTIPixelReporter(
            firing: UTIPixelFiring(pixelKit: { [unowned self] in pixelKitMock }),
            context: { UTIPixelContext(surface: .contextualChat, isDuckAISurfaceForAttribution: true,
                                      inputMode: .aiChat, isToggleVisible: false, pageType: .unknown, duckAIEntrySource: nil) })
        return MultiTabPickerPixelSession(surfaceProvider: { .contextualChat }) {
            reporter.reportTabAttachment($0, source: .tabPicker, surface: $1)
        }
    }

    private func enableTabAttachments(limit: Int = 3, mode: BrowsingMode = .normal) {
        let config = self.config!
        config.isContextualChatState = true
        config.tabFeatureState = .available(maximumTabAttachmentCount: limit)
        config.tabs = ["current", "first", "second", "third"].map { id in
            Tab(uid: id, link: Link(title: id, url: candidate(id: id).url), fireTab: mode == .fire)
        }
        config.tabSource = MultiTabAttachmentSource(currentTabID: "current", mode: mode, tabsProvider: { [weak config] in
            config?.candidateReadCount += 1
            return config?.tabs ?? []
        })
    }

    private func candidate(id: String) -> MultiTabAttachmentCandidate {
        MultiTabAttachmentCandidate(tabId: id, title: id, url: URL(string: "https://example.com/page")!)
    }

    private func makeController() -> UTIAttachmentController {
        let view = self.view!
        let config = self.config!
        return UTIAttachmentController(
            pixelReporter: UTIPixelReporter(
                firing: UTIPixelFiring(pixelKit: { [unowned self] in pixelKitMock }),
                context: { UTIPixelContext(surface: .addressBar, isDuckAISurfaceForAttribution: false, inputMode: .aiChat, isToggleVisible: false, pageType: .unknown, duckAIEntrySource: nil) }
            ),
            view: view.surface,
            environment: .init(
                policy: {
                    UTIAttachmentPolicy(
                        attachmentLimits: config.limits,
                        attachmentUsage: config.usage,
                        pendingAttachments: view.attachments,
                        model: config.model,
                        maximumTabAttachmentCount: config.maximumTabAttachmentCount,
                        currentPageTabID: config.tabSource?.currentTabID,
                        isCurrentPageAttached: config.isCurrentPageAttached
                    )
                },
                inputMode: { config.inputMode },
                pixelSurface: { .addressBar },
                isContextualChatState: { config.isContextualChatState },
                supportsImageUpload: { config.model?.supportsImageUpload ?? false },
                supportedFileTypes: { config.model?.supportedFileTypes ?? [] },
                hasSelectedModel: { config.model != nil },
                keepsUnavailableAttachmentButtonVisible: { config.keepsUnavailableAttachmentButtonVisible },
                attachmentLimits: { config.limits },
                currentTabUID: { "tab-1" },
                isPageContextAttachable: { config.isCurrentPageAttachable },
                pageContextAttachHandler: { config.pageContextAttachHandler },
                presenterViewController: { nil },
                tabAttachmentSource: { config.tabSource },
                tabAttachmentFeatureState: { config.tabFeatureState },
                pageContextRemoveHandler: { config.pageContextRemoveHandler }
            ),
            callbacks: callbackSpy.callbacks
        )
    }

    private func makeModel(supportsImageUpload: Bool, supportedFileTypes: [String] = []) -> AIChatModel {
        AIChatModel(id: "m", name: "m", provider: .unknown, supportsImageUpload: supportsImageUpload, supportedFileTypes: supportedFileTypes, entityHasAccess: true)
    }

    private func makeLimits() -> AIChatAttachmentTierLimits {
        AIChatAttachmentTierLimits(
            files: AIChatAttachmentFileLimits(maxPerConversation: 3, maxFileSizeMB: 5, maxTotalFileSizeBytes: 5_242_880, maxPagesPerFile: 8),
            images: AIChatAttachmentImageLimits(maxPerTurn: 3, maxPerConversation: 5, maxInputCharsWithAttachments: 4500)
        )
    }

    private func makeFileAttachment(fileName: String = "test.pdf", pageCount: Int? = 1) -> AIChatFileAttachment {
        let data = Data(repeating: 0, count: 1_000)
        return AIChatFileAttachment(data: data, fileName: fileName, mimeType: "application/pdf", fileSizeBytes: data.count, pageCount: pageCount)
    }
}

@MainActor
private final class FakeAttachmentView {
    var attachments: [UnifiedToggleInputAttachment] = []
    var isGenerating = false
    var validationMessage: String?
    var imageButtonHidden = false
    var imageButtonEnabled = true
    var attachmentMenu: UIMenu?

    var surface: UTIAttachmentController.ViewSurface {
        .init(
            currentAttachments: { self.attachments },
            isGenerating: { self.isGenerating },
            addAttachment: { self.attachments.append($0) },
            removeAttachment: { id in self.attachments.removeAll { $0.id == id } },
            removeAllAttachments: { self.attachments.removeAll() },
            replaceAttachment: { id, attachment in
                guard let index = self.attachments.firstIndex(where: { $0.id == id }) else { return }
                self.attachments[index] = attachment
            },
            showValidationError: { self.validationMessage = $0 },
            clearValidationError: { self.validationMessage = nil },
            setImageButtonHidden: { self.imageButtonHidden = $0 },
            setImageButtonEnabled: { self.imageButtonEnabled = $0 },
            setAttachmentMenu: { self.attachmentMenu = $0 }
        )
    }
}

@MainActor
private final class FakeEnvironmentConfig {
    var model: AIChatModel?
    var limits: AIChatAttachmentTierLimits?
    var usage: AIChatAttachmentUsage?
    var inputMode: TextEntryMode = .aiChat
    var isContextualChatState = false
    var keepsUnavailableAttachmentButtonVisible = false
    var tabSource: MultiTabAttachmentSource?
    var tabs: [Tab] = []
    var candidateReadCount = 0
    var tabFeatureState: AIChatContextualAttachMoreTabsState = .unavailable
    var isCurrentPageAttached = false
    var isCurrentPageAttachable: Bool?
    var pageContextAttachHandler: (() -> Void)?
    var pageContextRemoveHandler: (() -> Void)?

    var maximumTabAttachmentCount: Int? {
        guard case .available(let count) = tabFeatureState else { return nil }
        return count
    }
}

@MainActor
private final class CallbackSpy {
    var onDraftChangedCount = 0
    var onExpandIfNeededCount = 0
    var updateFloatingReturnKeyCount = 0
    var onTabAttachedCount = 0

    var callbacks: UTIAttachmentController.Callbacks {
        .init(
            onDraftChanged: { self.onDraftChangedCount += 1 },
            onExpandIfNeeded: { self.onExpandIfNeededCount += 1 },
            updateFloatingReturnKey: { self.updateFloatingReturnKeyCount += 1 },
            onTabAttached: { self.onTabAttachedCount += 1 }
        )
    }
}
