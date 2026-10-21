//
//  IPadOmnibarAttachmentControllerTests.swift
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
import FeatureFlags_iOS
@_spi(Testing) import PixelKit
import SubscriptionTestingUtilities
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class IPadOmnibarAttachmentControllerTests: XCTestCase {

    private var sut: IPadOmnibarAttachmentController!
    private var store: UTIModelStore!
    private var strip: UnifiedToggleInputAttachmentsStripView!
    private var preferences: StubAttachmentPreferences!

    override func setUp() {
        super.setUp()
        preferences = StubAttachmentPreferences()
        store = UTIModelStore(
            modelsService: StubAttachmentModelsService(),
            preferences: preferences,
            subscriptionManager: SubscriptionManagerMock(),
            isUpdatedModelPickerEnabled: false
        )
        // In production the models fetch also returns attachment limits; without them the validator
        // treats the per-turn image allowance as 0, so `canAttachImages` (and the attach menu) is
        // suppressed. Seed limits so availability tests mirror a real, limit-bearing response.
        store.attachmentLimits = makeLimits()
        strip = UnifiedToggleInputAttachmentsStripView()
        sut = IPadOmnibarAttachmentController(store: store)
        sut.attachmentsStripView = strip
    }

    override func tearDown() {
        sut = nil
        store = nil
        strip = nil
        preferences = nil
        super.tearDown()
    }

    // MARK: - Availability

    func testWhenModelSupportsImageUploadThenAvailableWithMenu() {
        store.models = [makeModel(id: "gpt-5.2", supportsImageUpload: true)]

        XCTAssertTrue(sut.isAttachButtonAvailable)
        XCTAssertTrue(sut.isAttachButtonVisible)
        XCTAssertNotNil(sut.makeMenu())
    }

    func testWhenModelSupportsFileUploadThenAvailable() {
        store.models = [makeModel(id: "gpt-5.2", supportsImageUpload: false, supportedFileTypes: ["application/pdf"])]

        XCTAssertTrue(sut.isAttachButtonAvailable)
    }

    func testWhenModelSupportsNoAttachmentsThenNotAvailableAndMenuNil() {
        store.models = [makeModel(id: "gpt-oss", supportsImageUpload: false)]

        XCTAssertFalse(sut.isAttachButtonAvailable)
        XCTAssertNil(sut.makeMenu())
    }

    func testWhenUnavailableButtonShouldRemainVisibleAndSelectedModelSupportsNoAttachmentsThenVisibleWithoutMenu() {
        store.models = [makeModel(id: "gpt-oss", supportsImageUpload: false)]
        sut = IPadOmnibarAttachmentController(store: store, keepsUnavailableAttachmentButtonVisible: true)

        XCTAssertTrue(sut.isAttachButtonVisible)
        XCTAssertNil(sut.makeMenu())
    }

    func testWhenUnavailableButtonShouldNotRemainVisibleAndSelectedModelSupportsNoAttachmentsThenHidden() {
        store.models = [makeModel(id: "gpt-oss", supportsImageUpload: false)]

        XCTAssertFalse(sut.isAttachButtonVisible)
    }

    func testWhenUnavailableButtonShouldRemainVisibleAndModelIsUnknownThenHidden() {
        sut = IPadOmnibarAttachmentController(store: store, keepsUnavailableAttachmentButtonVisible: true)

        XCTAssertFalse(sut.isAttachButtonVisible)
        XCTAssertNil(sut.makeMenu())
    }

    func testWhenNoModelsThenNotAvailableAndMenuNil() {
        XCTAssertFalse(sut.isAttachButtonAvailable)
        XCTAssertNil(sut.makeMenu())
    }

    // MARK: - Submission payloads

    func testWhenNoAttachmentsThenEncodedPayloadsNil() {
        XCTAssertFalse(sut.hasAttachments)
        XCTAssertNil(sut.encodedAttachments.images)
        XCTAssertNil(sut.encodedAttachments.files)
    }

    func testWhenImageAttachedThenEncodedImagesReturnedAndFilesNil() {
        strip.addAttachment(.image(AIChatImageAttachment(image: makeImage(), fileName: "photo.jpg")))

        XCTAssertTrue(sut.hasAttachments)
        XCTAssertEqual(sut.encodedAttachments.images?.count, 1)
        XCTAssertNil(sut.encodedAttachments.files)
    }

    func testWhenFileAttachedThenEncodedFilesReturnedAndImagesNil() {
        strip.addAttachment(.file(makeFileAttachment()))

        XCTAssertTrue(sut.hasAttachments)
        XCTAssertEqual(sut.encodedAttachments.files?.count, 1)
        XCTAssertNil(sut.encodedAttachments.images)
    }

    func testWhenInvalidFileAttachedThenNotEncoded() {
        strip.addAttachment(.invalidFile(
            UnifiedToggleInputInvalidFileAttachment(
                fileName: "bad.pdf",
                mimeType: "application/pdf",
                fileSizeBytes: 10,
                validationMessage: "nope"
            )
        ))

        XCTAssertTrue(sut.hasAttachments)
        XCTAssertNil(sut.encodedAttachments.files)
        XCTAssertNil(sut.encodedAttachments.images)
    }

    // MARK: - Reset

    func testWhenResetSelectionThenStripCleared() {
        strip.addAttachment(.image(AIChatImageAttachment(image: makeImage(), fileName: "photo.jpg")))
        strip.addAttachment(.file(makeFileAttachment()))

        sut.resetSelection()

        XCTAssertFalse(sut.hasAttachments)
        XCTAssertTrue(strip.attachments.isEmpty)
    }

    // MARK: - Model change removes unsupported attachments

    func testWhenModelChangesToOneWithoutImageSupportThenImageRemoved() {
        store.models = [makeModel(id: "vision", supportsImageUpload: true)]
        strip.addAttachment(.image(AIChatImageAttachment(image: makeImage(), fileName: "photo.jpg")))
        XCTAssertTrue(sut.hasAttachments)

        store.models = [makeModel(id: "text-only", supportsImageUpload: false)]
        sut.handleModelChanged()

        XCTAssertFalse(sut.hasAttachments)
    }

    func testWhenModelStillSupportsImageThenAttachmentKept() {
        store.models = [makeModel(id: "vision", supportsImageUpload: true)]
        strip.addAttachment(.image(AIChatImageAttachment(image: makeImage(), fileName: "photo.jpg")))

        store.models = [makeModel(id: "vision-2", supportsImageUpload: true)]
        sut.handleModelChanged()

        XCTAssertTrue(sut.hasAttachments)
    }

    func testPickerCompletionUpdatesOriginDraftWithoutChangingActiveDraft() {
        store.models = [makeModel(id: "vision", supportsImageUpload: true)]
        let origin = IPadOmnibarDraft()
        let destination = IPadOmnibarDraft()
        sut.bindDraft(origin)
        let callbacks = sut.makePickerCallbacks()
        sut.bindDraft(destination)
        strip.addAttachment(.file(makeFileAttachment()))
        sut.handleAttachmentsChanged()
        var expansionCount = 0
        sut.onExpandRequested = { expansionCount += 1 }

        callbacks.onImagePicked?(makeImage(), "origin.jpg")
        callbacks.onExpandIfNeeded?()

        XCTAssertEqual(origin.attachments.map(\.fileName), ["origin.jpg"])
        XCTAssertEqual(destination.attachments.map(\.fileName), ["doc.pdf"])
        XCTAssertEqual(strip.attachments.map(\.fileName), ["doc.pdf"])
        XCTAssertEqual(expansionCount, 0)
        sut.bindDraft(origin)
        XCTAssertEqual(strip.attachments.map(\.fileName), ["origin.jpg"])
    }

    func testPickerRejectsImageWhenActiveModelStopsSupportingImages() {
        store.models = [makeModel(id: "vision", supportsImageUpload: true)]
        let draft = IPadOmnibarDraft()
        sut.bindDraft(draft)
        let callbacks = sut.makePickerCallbacks()
        store.models = [makeModel(id: "text-only", supportsImageUpload: false)]
        sut.handleModelChanged()

        callbacks.onImagePicked?(makeImage(), "late.jpg")

        XCTAssertTrue(draft.attachments.isEmpty)
        XCTAssertTrue(strip.attachments.isEmpty)
    }

    func testRestoringInactiveDraftRemovesImagesUnsupportedByCurrentModel() {
        store.models = [makeModel(id: "vision", supportsImageUpload: true)]
        let origin = IPadOmnibarDraft()
        sut.bindDraft(origin)
        strip.addAttachment(.image(AIChatImageAttachment(image: makeImage(), fileName: "photo.jpg")))
        sut.handleAttachmentsChanged()
        sut.bindDraft(IPadOmnibarDraft())
        store.models = [makeModel(id: "text-only", supportsImageUpload: false)]
        sut.handleModelChanged()

        sut.bindDraft(origin)

        XCTAssertTrue(origin.attachments.isEmpty)
        XCTAssertTrue(strip.attachments.isEmpty)
    }

    func testClearedOrClosedDraftRejectsLatePickerCompletion() {
        store.models = [makeModel(id: "vision", supportsImageUpload: true)]
        for closesTab in [false, true] {
            let origin = IPadOmnibarDraft()
            sut.bindDraft(origin)
            let callbacks = sut.makePickerCallbacks()
            if closesTab {
                origin.invalidate()
            } else {
                origin.clear()
            }

            callbacks.onImagePicked?(makeImage(), "late.jpg")

            XCTAssertTrue(origin.attachments.isEmpty)
            XCTAssertTrue(strip.attachments.isEmpty)
        }
    }

    // MARK: - Helpers

    private func makeLimits() -> AIChatAttachmentTierLimits {
        AIChatAttachmentTierLimits(
            files: AIChatAttachmentFileLimits(maxPerConversation: 3, maxFileSizeMB: 5, maxTotalFileSizeBytes: 5_242_880, maxPagesPerFile: 8),
            images: AIChatAttachmentImageLimits(maxPerTurn: 3, maxPerConversation: 5, maxInputCharsWithAttachments: 4500)
        )
    }

    private func makeModel(id: String, supportsImageUpload: Bool, supportedFileTypes: [String] = []) -> AIChatModel {
        AIChatModel(
            id: id,
            name: id,
            shortName: id,
            provider: .openAI,
            supportsImageUpload: supportsImageUpload,
            supportedFileTypes: supportedFileTypes,
            supportedTools: [],
            entityHasAccess: true
        )
    }

    private func makeImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    private func makeFileAttachment() -> AIChatFileAttachment {
        AIChatFileAttachment(
            data: Data([0x25, 0x50, 0x44, 0x46]),
            fileName: "doc.pdf",
            mimeType: "application/pdf"
        )
    }
}

@MainActor
final class IPadOmnibarAttachmentButtonPresentationTests: XCTestCase {

    func testAttachmentPickerReturnSelectsAIChatRegardlessOfPreviousMode() throws {
        for previousMode in [TextEntryMode.search, .aiChat] {
            let controller = DefaultOmniBarViewController(dependencies: MockOmnibarDependency(), isFloatingUIEnabled: false)
            controller.loadViewIfNeeded()
            let view = try XCTUnwrap(controller.view as? DefaultOmniBarView)
            view.setLayoutMode(.expandedPad)
            controller.setSelectedTextEntryMode(previousMode)
            view.setSearchAreaExpanded(false, animated: false)

            controller.expandAIChatAfterAttachmentPicker()

            XCTAssertEqual(controller.selectedTextEntryMode, .aiChat)
            XCTAssertEqual(view.selectedModeToggleState, .aiChat)
            XCTAssertTrue(view.isSearchAreaExpanded)
        }
    }

    func testIPadControllerUsesItsFlagAndClaimsVisibleDisclosureWithAddressBarPixel() throws {
        let flags = MockFeatureFlagger()
        flags.enabledFeatureFlags = [.unifiedToggleInputAttachmentPrivacy, .duckAINativeTermsOfService]
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let displayStore = AttachmentPrivacyDisclosureStore(keyValueStore: defaults)
        let pixels = PixelKitMock()
        let disclosure = AttachmentPrivacyDisclosure(store: displayStore, webKeySource: nil, isEnabled: { true })
        let controller = DefaultOmniBarViewController(
            dependencies: MockOmnibarDependency(featureFlagger: flags),
            isFloatingUIEnabled: false,
            termsOfServiceStore: DuckAiTermsOfServiceStore(keyValueStore: defaults),
            attachmentPrivacyDisclosure: disclosure,
            attachmentPrivacyPixelFiring: pixels
        )
        controller.loadViewIfNeeded()
        controller.selectedTextEntryMode = .aiChat
        let sut = try XCTUnwrap(controller.view as? DefaultOmniBarView)
        sut.setLayoutMode(.expandedPad)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        sut.attachmentsStripView.addAttachment(.file(AIChatFileAttachment(data: Data([1]), fileName: "file.pdf", mimeType: "application/pdf")))
        sut.setSearchAreaExpanded(true, animated: false)
        sut.onSearchAreaExpandedStateChanged?(true)
        XCTAssertFalse(displayStore.hasShown)
        XCTAssertFalse(sut.visibleFooterMessages.contains { $0.id == .attachmentPrivacy })

        flags.enabledFeatureFlags.append(.aiChatAttachmentPrivacyIPad)
        UIView.performWithoutAnimation {
            sut.onSearchAreaExpandedStateChanged?(true)
            sut.layoutIfNeeded()
        }

        XCTAssertEqual(sut.visibleFooterMessages.map(\.id), [.termsConsent, .attachmentPrivacy])
        XCTAssertTrue(displayStore.hasShown)
        XCTAssertEqual(pixels.actualFireCalls.count, 1)
        XCTAssertEqual(pixels.actualFireCalls.first?.pixel.name, AttachmentPrivacyPixel(action: .shown, kind: .file, surface: .addressBar).name)
        XCTAssertEqual(pixels.actualFireCalls.first?.frequency, .dailyAndCount)
        XCTAssertEqual(pixels.actualFireCalls.first?.pixel.parameters, ["surface": UnifiedToggleInputPixelSurface.addressBar.rawValue])

        let displayedCards = footerCards(in: sut)
        sut.onFooterVisibilityChanged?([.attachmentPrivacy])
        XCTAssertEqual(footerCards(in: sut).count, displayedCards.count)
        XCTAssertTrue(zip(displayedCards, footerCards(in: sut)).allSatisfy { $0 === $1 })
        XCTAssertEqual(pixels.actualFireCalls.count, 1)

        sut.aiChatTextView.text = "Draft with attachment"
        let url = try XCTUnwrap(UTIFooterMessageMapper().attachmentPrivacyMessage().link?.url)
        sut.onFooterLinkTapped?(.attachmentPrivacy, url)
        controller.endEditing()
        controller.cancel()
        XCTAssertEqual(sut.attachmentsStripView.attachments.count, 1)
        sut.setSearchAreaExpanded(false, animated: false)
        sut.textField.text = ""
        sut.setSearchAreaExpanded(true, animated: false)
        XCTAssertEqual(sut.aiChatTextView.text, "Draft with attachment")
        XCTAssertEqual(sut.textField.alpha, 0)
        XCTAssertEqual(sut.attachmentsStripView.attachments.count, 1)
        XCTAssertEqual(pixels.actualFireCalls.last?.pixel.name, AttachmentPrivacyPixel(action: .learnMoreTapped, kind: .file, surface: .addressBar).name)

        sut.attachmentsStripView.removeAllAttachments()
        XCTAssertFalse(sut.visibleFooterMessages.contains { $0.id == .attachmentPrivacy })
        sut.attachmentsStripView.addAttachment(.file(AIChatFileAttachment(data: Data([1]), fileName: "second.pdf", mimeType: "application/pdf")))
        XCTAssertFalse(sut.visibleFooterMessages.contains { $0.id == .attachmentPrivacy })
        XCTAssertTrue(displayStore.hasShown)
        XCTAssertEqual(pixels.actualFireCalls.count, 2)
    }

    func testRemovingAttachmentEndsDisclosureWithoutShowingAgain() throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AttachmentPrivacyDisclosureStore(keyValueStore: defaults)
        let disclosure = AttachmentPrivacyDisclosure(store: store, webKeySource: nil, isEnabled: { true })
        var kind: UTIAttachmentPrivacyKind? = .file
        let notice = IPadAttachmentPrivacyNotice(attachmentKind: { kind }, isEnabled: { true }, disclosure: disclosure)
        notice.refresh()
        XCTAssertTrue(notice.recordDisplay())
        XCTAssertTrue(notice.isPresented)

        kind = nil
        notice.refresh()
        XCTAssertFalse(notice.isPresented)

        kind = .file
        notice.refresh()
        XCTAssertFalse(notice.isPresented)
        XCTAssertFalse(notice.recordDisplay())
        XCTAssertTrue(store.hasShown)
    }

    func testPrivacyAndTermsCardsStackAndReportVisibilityOnlyInWindow() {
        let sut = DefaultOmniBarView.create(isFloatingUIEnabled: false)
        sut.frame = CGRect(x: 0, y: 0, width: 1024, height: DefaultOmniBarView.expectedHeight)
        sut.setLayoutMode(.expandedPad)
        sut.setSearchAreaExpanded(true, animated: false)
        let messages = [
            UTIFooterItem(id: .termsConsent, message: UTIFooterMessageMapper().termsOfServiceMessage()),
            UTIFooterItem(id: .attachmentPrivacy, message: UTIFooterMessageMapper().attachmentPrivacyMessage())
        ]
        var visibility: [[UTIFooterItem.ID]] = []
        sut.onFooterVisibilityChanged = { visibility.append($0) }

        sut.setFooterMessages(messages, animated: false)
        XCTAssertTrue(visibility.isEmpty)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        window.addSubview(sut)
        XCTAssertTrue(visibility.isEmpty)
        window.makeKeyAndVisible()
        sut.setNeedsLayout()
        sut.layoutIfNeeded()
        defer { window.isHidden = true }
        XCTAssertEqual(visibility, [[.termsConsent, .attachmentPrivacy]])
        XCTAssertEqual(sut.visibleFooterMessages, messages)
        let cards = footerCards(in: sut)
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(cards.map(\.isBelowAnotherCard), [false, true])

        sut.setFooterMessages([], animated: false)
        XCTAssertEqual(visibility.last, [])
        XCTAssertTrue(sut.visibleFooterMessages.isEmpty)
    }

    func testPrivacyFooterLinkKeepsItsIdentityAlongsideTerms() throws {
        let sut = DefaultOmniBarView.create(isFloatingUIEnabled: false)
        sut.setLayoutMode(.expandedPad)
        sut.setSearchAreaExpanded(true, animated: false)
        let mapper = UTIFooterMessageMapper()
        sut.setFooterMessages([
            .init(id: .termsConsent, message: mapper.termsOfServiceMessage()),
            .init(id: .attachmentPrivacy, message: UTIFooterMessageMapper().attachmentPrivacyMessage())
        ], animated: false)
        var tappedID: UTIFooterItem.ID?
        var tappedURL: URL?
        sut.onFooterLinkTapped = { tappedID = $0; tappedURL = $1 }
        let card = try XCTUnwrap(footerCards(in: sut).last)
        let url = try XCTUnwrap(UTIFooterMessageMapper().attachmentPrivacyMessage().link?.url)

        card.onLinkTap?(url)

        XCTAssertEqual(tappedID, .attachmentPrivacy)
        XCTAssertEqual(tappedURL, url)
    }

    func testWhenFooterAppearsAnimatedThenCardFadesInPlaceInsteadOfGrowingFromZero() throws {
        let (sut, window) = makeExpandedOmnibarInWindow()
        defer { window.isHidden = true }

        sut.setFooterMessages([termsItem()], animated: true)

        let card = try XCTUnwrap(footerCards(in: sut).first)
        XCTAssertNotEqual(card.frame.size, .zero)
        XCTAssertEqual(geometryAnimationKeys(in: card), [])
    }

    func testWhenFooterReappearsWithSameMessagesThenCardIsKeptAndNotAnimated() throws {
        let (sut, window) = makeExpandedOmnibarInWindow()
        defer { window.isHidden = true }
        sut.setFooterMessages([termsItem()], animated: false)
        let card = try XCTUnwrap(footerCards(in: sut).first)

        sut.setFooterMessages([termsItem()], animated: true)
        XCTAssertTrue(try XCTUnwrap(footerCards(in: sut).first) === card)
        XCTAssertEqual(geometryAnimationKeys(in: card), [])

        sut.setFooterMessages([], animated: false)
        sut.setFooterMessages([termsItem()], animated: true)
        XCTAssertTrue(try XCTUnwrap(footerCards(in: sut).first) === card)
        XCTAssertEqual(geometryAnimationKeys(in: card), [])
    }

    func testWhenFooterMessageChangesThenExistingCardIsReconfigured() throws {
        let (sut, window) = makeExpandedOmnibarInWindow()
        defer { window.isHidden = true }
        sut.setFooterMessages([termsItem()], animated: false)
        let card = try XCTUnwrap(footerCards(in: sut).first)

        let createItem = termsItem(sendButton: .create)
        sut.setFooterMessages([createItem], animated: true)

        XCTAssertTrue(try XCTUnwrap(footerCards(in: sut).first) === card)
        XCTAssertEqual(sut.visibleFooterMessages, [createItem])
        XCTAssertTrue(allLabelText(in: card).contains("Create"))
    }

    func testWhenSearchAreaExpandsAnimatedThenFooterFadesInWithTheExpansion() throws {
        let (sut, window) = makeCollapsedOmnibarInWindow()
        defer { window.isHidden = true }
        sut.onSearchAreaWillExpand = { sut.setFooterMessages([self.termsItem()], animated: false) }

        sut.setSearchAreaExpanded(true, animated: true)

        let card = try XCTUnwrap(footerCards(in: sut).first)
        let footer = try XCTUnwrap(card.superview?.superview)
        XCTAssertEqual(sut.visibleFooterMessages, [termsItem()])
        XCTAssertEqual(footer.alpha, 1)
        XCTAssertNotNil(footer.layer.animation(forKey: "opacity"))
        XCTAssertNotEqual(card.frame.size, .zero)
        XCTAssertEqual(geometryAnimationKeys(in: card), [])
    }

    func testWhenSearchAreaExpandsWithoutAnimationThenFooterIsAlreadyVisible() throws {
        let (sut, window) = makeCollapsedOmnibarInWindow()
        defer { window.isHidden = true }
        sut.onSearchAreaWillExpand = { sut.setFooterMessages([self.termsItem()], animated: false) }

        sut.setSearchAreaExpanded(true, animated: false)

        let footer = try XCTUnwrap(footerCards(in: sut).first?.superview?.superview)
        XCTAssertEqual(footer.alpha, 1)
        XCTAssertNil(footer.layer.animation(forKey: "opacity"))
    }

    func testAttachmentLandingDuringExpansionAnimationStaysVisibleWhenItFinishes() throws {
        let (sut, window) = makeCollapsedOmnibarInWindow()
        defer { window.isHidden = true }
        sut.setSearchAreaExpanded(true, animated: true)

        sut.attachmentsStripView.addAttachment(.file(AIChatFileAttachment(data: Data([1]), fileName: "late.pdf", mimeType: "application/pdf")))
        sut.updateAttachmentsLayout(animated: true)
        let expansionFinished = expectation(description: "expansion animation finished")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { expansionFinished.fulfill() }
        wait(for: [expansionFinished], timeout: 2)

        XCTAssertTrue(sut.isSearchAreaExpanded)
        XCTAssertFalse(sut.attachmentsStripView.isHidden)
        XCTAssertEqual(sut.attachmentsStripView.alpha, 1)
    }

    private func makeCollapsedOmnibarInWindow() -> (DefaultOmniBarView, UIWindow) {
        let sut = DefaultOmniBarView.create(isFloatingUIEnabled: false)
        sut.frame = CGRect(x: 0, y: 0, width: 1024, height: DefaultOmniBarView.expectedHeight)
        sut.setLayoutMode(.expandedPad)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        window.addSubview(sut)
        window.makeKeyAndVisible()
        sut.layoutIfNeeded()
        return (sut, window)
    }

    private func termsItem(sendButton: DuckAiTermsOfServiceSendButton = .ask) -> UTIFooterItem {
        UTIFooterItem(id: .termsConsent, message: UTIFooterMessageMapper().termsOfServiceMessage(sendButton: sendButton))
    }

    private func makeExpandedOmnibarInWindow() -> (DefaultOmniBarView, UIWindow) {
        let (sut, window) = makeCollapsedOmnibarInWindow()
        sut.setSearchAreaExpanded(true, animated: false)
        sut.layoutIfNeeded()
        return (sut, window)
    }

    private func geometryAnimationKeys(in view: UIView) -> [String] {
        let keys = (view.layer.animationKeys() ?? []).filter { $0.hasPrefix("position") || $0.hasPrefix("bounds") }
        return keys + view.subviews.flatMap { geometryAnimationKeys(in: $0) }
    }

    private func allLabelText(in view: UIView) -> String {
        let own = (view as? UILabel)?.text ?? (view as? UITextView)?.text ?? ""
        return ([own] + view.subviews.map { allLabelText(in: $0) }).joined(separator: " ")
    }

    private func footerCards(in view: UIView) -> [UTIFooterCardView] {
        let children = (view as? UIStackView)?.arrangedSubviews ?? view.subviews
        return children.flatMap { child -> [UTIFooterCardView] in
            if let card = child as? UTIFooterCardView { return [card] }
            return footerCards(in: child)
        }
    }

    func testOmnibarForwardsAttachmentLayoutToItsStrip() throws {
        for usesCompactLayout in [false, true] {
            let sut = DefaultOmniBarView.create(isFloatingUIEnabled: false, usesCompactAttachmentLayout: usesCompactLayout)
            let scrollView = try XCTUnwrap(sut.attachmentsStripView.subviews.compactMap { $0 as? UIScrollView }.first)
            let stack = try XCTUnwrap(scrollView.subviews.compactMap { $0 as? UIStackView }.first)
            XCTAssertEqual(stack.spacing, usesCompactLayout ? 4 : 10)
            XCTAssertEqual(scrollView.alwaysBounceHorizontal, !usesCompactLayout)
        }
    }

    func testWhenVisibleAttachmentButtonHasNoMenuThenItIsShownDisabled() {
        let sut = DefaultOmniBarView.create(isFloatingUIEnabled: false)
        sut.frame = CGRect(x: 0, y: 0, width: 1024, height: DefaultOmniBarView.expectedHeight)
        sut.setLayoutMode(.expandedPad)
        sut.isAttachButtonEnabled = true
        sut.isAIChatAttachmentButtonVisible = true
        sut.aiChatAttachmentMenu = nil

        sut.setSearchAreaExpanded(true, animated: false)

        XCTAssertFalse(sut.attachButton.isHidden)
        XCTAssertFalse(sut.attachButton.isEnabled)
        XCTAssertNil(sut.attachButton.menu)
    }

    func testWhenVisibleAttachmentButtonHasMenuThenItIsShownEnabled() {
        let sut = DefaultOmniBarView.create(isFloatingUIEnabled: false)
        sut.frame = CGRect(x: 0, y: 0, width: 1024, height: DefaultOmniBarView.expectedHeight)
        sut.setLayoutMode(.expandedPad)
        sut.isAttachButtonEnabled = true
        sut.isAIChatAttachmentButtonVisible = true
        sut.aiChatAttachmentMenu = UIMenu(children: [])

        sut.setSearchAreaExpanded(true, animated: false)

        XCTAssertFalse(sut.attachButton.isHidden)
        XCTAssertTrue(sut.attachButton.isEnabled)
        XCTAssertNotNil(sut.attachButton.menu)
    }
}

@MainActor
final class IPadOmnibarDraftTests: XCTestCase {

    func testSwitchingTabsRestoresEachDraftTextAndAttachments() throws {
        let (controller, view, window) = try makeController()
        defer { window.isHidden = true }
        let first = Tab()
        let second = Tab()
        controller.bindIPadDraft(to: first)
        expand(controller, view)
        enter("First draft", in: controller, view)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { $0.fill(CGRect(x: 0, y: 0, width: 2, height: 2)) }
        view.attachmentsStripView.addAttachment(.image(AIChatImageAttachment(image: image, fileName: "first.jpg")))

        controller.endEditing()
        controller.cancel()
        expand(controller, view)
        XCTAssertEqual(view.aiChatTextView.text, "First draft")
        XCTAssertEqual(view.attachmentsStripView.attachments.map(\.fileName), ["first.jpg"])
        let url = try XCTUnwrap(UTIFooterMessageMapper().attachmentPrivacyMessage().link?.url)
        view.onFooterLinkTapped?(.attachmentPrivacy, url)
        controller.endEditing()
        controller.cancel()

        controller.bindIPadDraft(to: second)
        expand(controller, view)
        XCTAssertEqual(view.aiChatTextView.text, "")
        XCTAssertTrue(view.attachmentsStripView.attachments.isEmpty)
        enter("Second draft", in: controller, view)
        view.attachmentsStripView.addAttachment(file(named: "second.pdf"))

        controller.bindIPadDraft(to: first)
        expand(controller, view)
        XCTAssertEqual(view.aiChatTextView.text, "First draft")
        XCTAssertEqual(view.attachmentsStripView.attachments.map(\.fileName), ["first.jpg"])
        XCTAssertEqual(view.textField.alpha, 0)
        controller.bindIPadDraft(to: second)
        expand(controller, view)
        XCTAssertEqual(view.aiChatTextView.text, "Second draft")
        XCTAssertEqual(view.attachmentsStripView.attachments.map(\.fileName), ["second.pdf"])
    }

    func testClearThenReopenDoesNotRestoreOldText() throws {
        for mode in [TextEntryMode.search, .aiChat] {
            let (controller, view, window) = try makeController()
            defer { window.isHidden = true }
            controller.bindIPadDraft(to: Tab())
            expand(controller, view)
            enter("Clear me", in: controller, view)
            if mode == .search {
                controller.endEditing()
                controller.setSelectedTextEntryMode(mode)
            }

            view.onClearButtonPressed?()
            controller.endEditing()
            controller.cancel()
            expand(controller, view)

            XCTAssertEqual(view.aiChatTextView.text, "", "Mode: \(mode)")
            XCTAssertEqual(view.textField.alpha, 1, "Mode: \(mode)")
        }
    }

    func testNewSearchTextTransfersToAIInsteadOfRestoringOldDraft() throws {
        let (controller, view, window) = try makeController()
        defer { window.isHidden = true }
        controller.bindIPadDraft(to: Tab())
        expand(controller, view)
        enter("Old AI draft", in: controller, view)
        controller.setSelectedTextEntryMode(.search)
        expectation(for: NSPredicate { _, _ in
            view.textField.isFirstResponder && view.onCollapseAnimationCompleted == nil
        }, evaluatedWith: nil)
        waitForExpectations(timeout: 2)
        XCTAssertEqual(controller.selectedTextEntryMode, .search)
        _ = controller.textField(view.textField, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "New search text")
        controller.updateQuery("New search text")
        XCTAssertEqual(view.textField.text, "New search text")

        controller.setSelectedTextEntryMode(.aiChat)
        expectation(for: NSPredicate { _, _ in
            view.aiChatTextView.isFirstResponder && view.isSearchAreaExpanded
        }, evaluatedWith: nil)
        waitForExpectations(timeout: 2)

        XCTAssertEqual(view.aiChatTextView.text, "New search text")
    }

    func testTabSwitchCancelsPendingSearchModeTransfer() throws {
        let (controller, view, window) = try makeController()
        defer { window.isHidden = true }
        let origin = Tab()
        controller.bindIPadDraft(to: origin)
        expand(controller, view)
        enter("Origin draft", in: controller, view)
        controller.setSelectedTextEntryMode(.search)
        XCTAssertNotNil(view.onCollapseAnimationCompleted)

        controller.bindIPadDraft(to: Tab())
        controller.updateQuery("Destination search")
        view.onCollapseAnimationCompleted?()

        XCTAssertEqual(view.textField.text, "Destination search")
        XCTAssertFalse(view.textField.isFirstResponder)
        controller.bindIPadDraft(to: origin)
        expand(controller, view)
        XCTAssertEqual(view.aiChatTextView.text, "Origin draft")
    }

    func testSynchronousTabSwitchDuringSubmissionPreservesDestinationAndSubmittedPayload() throws {
        for usesLegacyTextField in [false, true] {
            let (controller, view, window) = try makeController()
            defer { window.isHidden = true }
            let origin = Tab()
            let destination = Tab()
            let delegate = MockOmniBarDelegate()
            controller.omniDelegate = delegate
            controller.bindIPadDraft(to: destination)
            expand(controller, view)
            enter("Destination draft", in: controller, view)
            view.attachmentsStripView.addAttachment(file(named: "destination.pdf"))
            controller.bindIPadDraft(to: origin)
            expand(controller, view)
            enter("Submitted prompt", in: controller, view)
            view.attachmentsStripView.addAttachment(file(named: "origin.pdf"))
            delegate.onPromptSubmittedAction = {
                controller.bindIPadDraft(to: destination)
                self.expand(controller, view)
            }

            if usesLegacyTextField {
                controller.endEditing()
                view.setSearchAreaExpanded(false, animated: false)
                view.textField.text = "Submitted prompt"
                controller.onQuerySubmitted()
            } else {
                view.aiChatSendButton.sendActions(for: .primaryActionTriggered)
            }

            XCTAssertEqual(delegate.promptQuery, "Submitted prompt", "Legacy: \(usesLegacyTextField)")
            XCTAssertEqual(delegate.promptControlValues?.selectedAttachments.files?.map(\.fileName), ["origin.pdf"], "Legacy: \(usesLegacyTextField)")
            XCTAssertEqual(view.aiChatTextView.text, "Destination draft", "Legacy: \(usesLegacyTextField)")
            XCTAssertEqual(view.attachmentsStripView.attachments.map(\.fileName), ["destination.pdf"], "Legacy: \(usesLegacyTextField)")
            controller.bindIPadDraft(to: origin)
            expand(controller, view)
            XCTAssertEqual(view.aiChatTextView.text, "", "Legacy: \(usesLegacyTextField)")
            XCTAssertTrue(view.attachmentsStripView.attachments.isEmpty, "Legacy: \(usesLegacyTextField)")
        }
    }

    private func makeController() throws -> (DefaultOmniBarViewController, DefaultOmniBarView, UIWindow) {
        let controller = DefaultOmniBarViewController(
            dependencies: MockOmnibarDependency(
                aiChatSettings: MockAIChatSettingsProvider(isAIChatSearchInputUserSettingsEnabled: true),
                userInterfaceIdiomProvider: DraftIPadIdiomProvider()
            ),
            isFloatingUIEnabled: false
        )
        controller.loadViewIfNeeded()
        controller.enterPadState()
        let view = try XCTUnwrap(controller.view as? DefaultOmniBarView)
        view.setLayoutMode(.expandedPad)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        return (controller, view, window)
    }

    private func expand(_ controller: DefaultOmniBarViewController, _ view: DefaultOmniBarView) {
        controller.setSelectedTextEntryMode(.aiChat)
        view.setSearchAreaExpanded(true, animated: false)
    }

    private func enter(_ text: String, in controller: DefaultOmniBarViewController, _ view: DefaultOmniBarView) {
        view.aiChatTextView.text = text
        controller.textViewDidChange(view.aiChatTextView)
    }

    private func file(named name: String) -> UnifiedToggleInputAttachment {
        .file(AIChatFileAttachment(data: Data([1]), fileName: name, mimeType: "application/pdf"))
    }
}

@MainActor
final class IPadOmnibarPastedTextTests: XCTestCase {

    private var window: UIWindow?
    private let termsSuiteName = "IPadOmnibarPastedTextTests.terms"

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: termsSuiteName)?.removePersistentDomain(forName: termsSuiteName)
    }

    override func tearDown() {
        window?.isHidden = true
        window = nil
        UserDefaults(suiteName: termsSuiteName)?.removePersistentDomain(forName: termsSuiteName)
        super.tearDown()
    }

    // MARK: - Interception

    func testPasteBelowThresholdStaysInline() throws {
        let (controller, view) = try makeController()
        expand(controller, view)

        XCTAssertTrue(paste(text(length: 3_999), into: controller, view))
        XCTAssertTrue(view.attachmentsStripView.attachments.isEmpty)
    }

    func testPasteAtThresholdBecomesChipAndIsNotInserted() throws {
        let (controller, view) = try makeController()
        expand(controller, view)
        let pasted = text(length: 4_000)

        XCTAssertFalse(paste(pasted, into: controller, view))
        XCTAssertEqual(view.attachmentsStripView.attachments.compactMap(\.pastedText).map(\.content), [pasted])
        XCTAssertEqual(view.aiChatTextView.text, "")
    }

    func testPasteInSearchModeStaysInline() throws {
        let (controller, view) = try makeController()
        expand(controller, view)
        controller.setSelectedTextEntryMode(.search)

        XCTAssertTrue(paste(text(length: 4_100), into: controller, view))
        XCTAssertTrue(view.attachmentsStripView.attachments.isEmpty)
    }

    func testPasteWithFeatureOffStaysInline() throws {
        let (controller, view) = try makeController(flags: [])
        expand(controller, view)

        XCTAssertTrue(paste(text(length: 4_100), into: controller, view))
        XCTAssertTrue(view.attachmentsStripView.attachments.isEmpty)
    }

    // MARK: - Over the limit

    func testOverLimitShowsErrorAloneOverTermsBlocksSendAndKeepsReturnAsNewLine() throws {
        let (controller, view) = try makeController(flags: [.unifiedToggleInputPastedText, .duckAINativeTermsOfService])
        let delegate = MockOmniBarDelegate()
        controller.omniDelegate = delegate
        expand(controller, view)
        XCTAssertEqual(view.visibleFooterMessages.map(\.id), [.termsConsent])

        XCTAssertFalse(paste(text(length: 16_100), into: controller, view))
        let chipID = try XCTUnwrap(view.attachmentsStripView.attachments.first?.id)

        XCTAssertEqual(view.visibleFooterMessages.map(\.id), [.promptTooLong])
        XCTAssertEqual(view.visibleFooterMessages.first?.message.subtitle, "16100/16000")
        XCTAssertFalse(view.aiChatSendButton.isEnabled)
        XCTAssertTrue(view.attachmentsStripView.showsPromptLengthError)
        XCTAssertEqual(view.aiChatSendButton.title(for: .normal), UserText.duckAIAskButtonTitle, "Ask stays while the error hides the disclaimer")
        XCTAssertEqual(view.aiChatTextView.keyboardType, .default, "Return keeps adding a new line while the error hides the disclaimer")
        XCTAssertTrue(pressReturn(controller, view))
        view.aiChatSendButton.sendActions(for: .primaryActionTriggered)
        XCTAssertFalse(delegate.wasOnPromptSubmittedCalled)

        view.attachmentsStripView.removeAttachment(id: chipID, isUserInitiated: true)

        XCTAssertEqual(view.visibleFooterMessages.map(\.id), [.termsConsent])
        XCTAssertFalse(view.attachmentsStripView.showsPromptLengthError)
        XCTAssertEqual(view.aiChatSendButton.title(for: .normal), UserText.duckAIAskButtonTitle)
    }

    func testOverLimitWithTermsAcceptedBlocksReturnAndSend() throws {
        let (controller, view) = try makeController()
        let delegate = MockOmniBarDelegate()
        controller.omniDelegate = delegate
        expand(controller, view)
        XCTAssertFalse(paste(text(length: 16_100), into: controller, view))

        XCTAssertFalse(pressReturn(controller, view), "Return is consumed, not inserted")
        view.aiChatSendButton.sendActions(for: .primaryActionTriggered)

        XCTAssertFalse(delegate.wasOnPromptSubmittedCalled)
        XCTAssertFalse(delegate.wasOnOmniQuerySubmittedCalled)
        XCTAssertEqual(view.visibleFooterMessages.map(\.id), [.promptTooLong])
        XCTAssertEqual(view.attachmentsStripView.attachments.count, 1, "The draft stays for the user to fix")
    }

    func testTypingOverTheLimitAfterAChipShowsTheErrorAndTypingBackClearsIt() throws {
        let (controller, view) = try makeController()
        expand(controller, view)
        XCTAssertFalse(paste(text(length: 15_900), into: controller, view))
        XCTAssertTrue(view.visibleFooterMessages.isEmpty)

        enter(String(repeating: "a", count: 101), in: controller, view)
        XCTAssertEqual(view.visibleFooterMessages.first?.message.subtitle, "16001/16000")
        XCTAssertFalse(view.aiChatSendButton.isEnabled)

        enter(String(repeating: "a", count: 100), in: controller, view)
        XCTAssertTrue(view.visibleFooterMessages.isEmpty)
        XCTAssertTrue(view.aiChatSendButton.isEnabled)
    }

    // MARK: - Submission

    func testSubmitMeasuresTheSentTextNotTheLastTypedDraft() throws {
        let (controller, view) = try makeController()
        let delegate = MockOmniBarDelegate()
        controller.omniDelegate = delegate
        expand(controller, view)

        controller.submitAIChatQuery(text(length: 16_001))
        XCTAssertFalse(delegate.wasOnPromptSubmittedCalled, "Set without typing, so only the submit measures it")

        controller.submitAIChatQuery(text(length: 100))
        XCTAssertTrue(delegate.wasOnPromptSubmittedCalled)
    }

    func testURLShapedPromptWithoutAttachmentsNavigates() throws {
        let (controller, view) = try makeController()
        let delegate = MockOmniBarDelegate()
        controller.omniDelegate = delegate
        expand(controller, view)
        enter("https://example.com/path", in: controller, view)

        XCTAssertFalse(pressReturn(controller, view))

        XCTAssertTrue(delegate.wasOnOmniQuerySubmittedCalled)
        XCTAssertFalse(delegate.wasOnPromptSubmittedCalled)
    }

    func testURLShapedPromptNavigatesAgainAfterLastChipRemoved() throws {
        let (controller, view) = try makeController()
        let delegate = MockOmniBarDelegate()
        controller.omniDelegate = delegate
        expand(controller, view)
        XCTAssertFalse(paste(text(length: 4_100), into: controller, view))
        let chipID = try XCTUnwrap(view.attachmentsStripView.attachments.first?.id)
        view.attachmentsStripView.removeAttachment(id: chipID, isUserInitiated: true)
        enter("https://example.com/path", in: controller, view)

        XCTAssertFalse(pressReturn(controller, view))

        XCTAssertTrue(delegate.wasOnOmniQuerySubmittedCalled)
        XCTAssertFalse(delegate.wasOnPromptSubmittedCalled)
    }

    func testURLShapedPromptWithChipSubmitsToDuckAIWithPastedText() throws {
        let (controller, view) = try makeController()
        let delegate = MockOmniBarDelegate()
        controller.omniDelegate = delegate
        expand(controller, view)
        let pasted = text(length: 4_100)
        XCTAssertFalse(paste(pasted, into: controller, view))
        enter("https://example.com/path", in: controller, view)

        XCTAssertFalse(pressReturn(controller, view))

        XCTAssertTrue(delegate.wasOnPromptSubmittedCalled)
        XCTAssertFalse(delegate.wasOnOmniQuerySubmittedCalled)
        XCTAssertEqual(delegate.promptQuery, "https://example.com/path")
        XCTAssertEqual(delegate.promptControlValues?.selectedAttachments.textPasted?.map(\.content), [pasted])
        let controlValues = try XCTUnwrap(delegate.promptControlValues)
        XCTAssertFalse(DuckAIPromptFlowStart(controlValues: controlValues, tools: nil).attachmentsSelected, "A paste is prompt text")
    }

    func testURLShapedPromptWithImageSubmitsToDuckAIWithImage() throws {
        let (controller, view) = try makeController(flags: [])
        let delegate = MockOmniBarDelegate()
        controller.omniDelegate = delegate
        expand(controller, view)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { $0.fill(CGRect(x: 0, y: 0, width: 2, height: 2)) }
        view.attachmentsStripView.addAttachment(.image(AIChatImageAttachment(image: image, fileName: "photo.jpg")))
        enter("https://example.com/path", in: controller, view)

        XCTAssertFalse(pressReturn(controller, view))

        XCTAssertTrue(delegate.wasOnPromptSubmittedCalled)
        XCTAssertFalse(delegate.wasOnOmniQuerySubmittedCalled)
        XCTAssertEqual(delegate.promptControlValues?.selectedAttachments.images?.count, 1)
        let controlValues = try XCTUnwrap(delegate.promptControlValues)
        XCTAssertTrue(DuckAIPromptFlowStart(controlValues: controlValues, tools: nil).attachmentsSelected)
    }

    // MARK: - Sheet

    func testSavingInTheSheetReplacesTheChipAndRestoresTheInput() throws {
        let (controller, view) = try makeController()
        expand(controller, view)
        XCTAssertFalse(paste(text(length: 4_100), into: controller, view))
        let chipID = try XCTUnwrap(view.attachmentsStripView.attachments.first?.id)

        view.attachmentsStripView.onAttachmentTapped?(chipID)
        let sheet = try XCTUnwrap(controller.presentedViewController as? PastedTextSheetHostingController)
        controller.setSelectedTextEntryMode(.search)
        view.setSearchAreaExpanded(false, animated: false)
        let edited = text(length: 4_200)
        sheet.finish(.saved(AIChatPastedText(content: edited)))

        XCTAssertEqual(view.attachmentsStripView.attachments.compactMap(\.pastedText).map(\.content), [edited])
        XCTAssertNotEqual(view.attachmentsStripView.attachments.first?.id, chipID, "A saved edit is a new value")
        XCTAssertEqual(controller.selectedTextEntryMode, .aiChat)
        XCTAssertTrue(view.isSearchAreaExpanded)
    }

    func testCancellingTheSheetKeepsTheChipAndRestoresTheInput() throws {
        let (controller, view) = try makeController()
        expand(controller, view)
        let pasted = text(length: 4_100)
        XCTAssertFalse(paste(pasted, into: controller, view))
        let chipID = try XCTUnwrap(view.attachmentsStripView.attachments.first?.id)

        view.attachmentsStripView.onAttachmentTapped?(chipID)
        let sheet = try XCTUnwrap(controller.presentedViewController as? PastedTextSheetHostingController)
        controller.setSelectedTextEntryMode(.search)
        view.setSearchAreaExpanded(false, animated: false)
        sheet.finish(.unchanged)

        XCTAssertEqual(view.attachmentsStripView.attachments.map(\.id), [chipID])
        XCTAssertEqual(view.attachmentsStripView.attachments.first?.pastedText?.content, pasted)
        XCTAssertEqual(controller.selectedTextEntryMode, .aiChat)
        XCTAssertTrue(view.isSearchAreaExpanded)
    }

    // MARK: - Helpers

    private func makeController(flags: [FeatureFlag] = [.unifiedToggleInputPastedText]) throws -> (DefaultOmniBarViewController, DefaultOmniBarView) {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = flags
        let controller = DefaultOmniBarViewController(
            dependencies: MockOmnibarDependency(
                featureFlagger: featureFlagger,
                aiChatSettings: MockAIChatSettingsProvider(isAIChatSearchInputUserSettingsEnabled: true),
                userInterfaceIdiomProvider: DraftIPadIdiomProvider()
            ),
            isFloatingUIEnabled: false,
            termsOfServiceStore: DuckAiTermsOfServiceStore(keyValueStore: try XCTUnwrap(UserDefaults(suiteName: termsSuiteName)))
        )
        controller.loadViewIfNeeded()
        controller.enterPadState()
        let view = try XCTUnwrap(controller.view as? DefaultOmniBarView)
        view.setLayoutMode(.expandedPad)
        // The sheet is presented from the key window of the bar's scene, so the window needs one.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return (controller, view)
    }

    private func expand(_ controller: DefaultOmniBarViewController, _ view: DefaultOmniBarView) {
        controller.setSelectedTextEntryMode(.aiChat)
        view.setSearchAreaExpanded(true, animated: false)
    }

    private func enter(_ text: String, in controller: DefaultOmniBarViewController, _ view: DefaultOmniBarView) {
        view.aiChatTextView.text = text
        controller.textViewDidChange(view.aiChatTextView)
    }

    /// What UIKit asks before inserting a paste; `true` means the text goes in as typed text.
    private func paste(_ text: String, into controller: DefaultOmniBarViewController, _ view: DefaultOmniBarView) -> Bool {
        let end = (view.aiChatTextView.text as NSString).length
        return controller.textView(view.aiChatTextView, shouldChangeTextIn: NSRange(location: end, length: 0), replacementText: text)
    }

    private func pressReturn(_ controller: DefaultOmniBarViewController, _ view: DefaultOmniBarView) -> Bool {
        let end = (view.aiChatTextView.text as NSString).length
        return controller.textView(view.aiChatTextView, shouldChangeTextIn: NSRange(location: end, length: 0), replacementText: "\n")
    }

    private func text(length: Int) -> String {
        String(repeating: "x", count: length)
    }
}

@MainActor
final class IPadOmnibarAttachmentControllerPastedTextTests: XCTestCase {

    private var sut: IPadOmnibarAttachmentController!
    private var strip: UnifiedToggleInputAttachmentsStripView!
    private var pixels: PixelKitMock!
    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        let store = UTIModelStore(
            modelsService: StubAttachmentModelsService(),
            preferences: StubAttachmentPreferences(),
            subscriptionManager: SubscriptionManagerMock(),
            isUpdatedModelPickerEnabled: false
        )
        strip = UnifiedToggleInputAttachmentsStripView()
        pixels = PixelKitMock()
        sut = IPadOmnibarAttachmentController(store: store, pixelFiring: pixels)
        sut.attachmentsStripView = strip
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        sut.presenterProvider = { [window] in window?.rootViewController }
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        sut = nil
        strip = nil
        pixels = nil
        super.tearDown()
    }

    func testAddingPastedTextFiresAttachedPixelForTheAddressBar() {
        var expandRequests = 0
        sut.onExpandRequested = { expandRequests += 1 }

        sut.addPastedText("pasted")

        XCTAssertEqual(strip.attachments.compactMap(\.pastedText).map(\.content), ["pasted"])
        XCTAssertEqual(sut.encodedAttachments.textPasted?.map(\.content), ["pasted"])
        XCTAssertEqual(expandRequests, 1)
        XCTAssertEqual(firedPixels.map(\.name), ["aichat_unified_input_pasted_text_attached"])
        XCTAssertEqual(firedPixels.map(\.surface), ["address_bar"])
    }

    func testRemovingAChipByTheUserFiresRemovedPixelOnlyForTheAddressBar() throws {
        sut.addPastedText("pasted")
        let id = try XCTUnwrap(strip.attachments.first?.id)

        strip.removeAttachment(id: id)
        XCTAssertEqual(firedPixels.count, 1, "A programmatic removal is not reported")

        sut.addPastedText("again")
        let secondID = try XCTUnwrap(strip.attachments.first?.id)
        strip.removeAttachment(id: secondID, isUserInitiated: true)

        XCTAssertEqual(firedPixels.last?.name, "aichat_unified_input_pasted_text_removed")
        XCTAssertEqual(firedPixels.last?.surface, "address_bar")
    }

    func testOpeningAndSavingTheSheetReportsOpenedThenEditedAndCallsDismissed() throws {
        sut.addPastedText("pasted")
        let id = try XCTUnwrap(strip.attachments.first?.id)
        var limitRequests: [String] = []
        sut.pastedTextSheetLimit = { limitRequests.append($0.content); return 12 }
        var dismissals = 0
        sut.onPastedTextSheetDismissed = { dismissals += 1 }

        sut.presentPastedTextSheet(id: id)
        let sheet = try XCTUnwrap(window.rootViewController?.presentedViewController as? PastedTextSheetHostingController)
        XCTAssertEqual(limitRequests, ["pasted"])
        sheet.finish(.saved(AIChatPastedText(content: "edited")))

        XCTAssertEqual(strip.attachments.compactMap(\.pastedText).map(\.content), ["edited"])
        XCTAssertEqual(sut.encodedAttachments.textPasted?.map(\.content), ["edited"])
        XCTAssertEqual(firedPixels.map(\.name), [
            "aichat_unified_input_pasted_text_attached",
            "aichat_unified_input_pasted_text_sheet_opened",
            "aichat_unified_input_pasted_text_edited"
        ])
        XCTAssertEqual(dismissals, 1)
    }

    func testClosingTheSheetUnchangedKeepsTheChipAndReportsNoEdit() throws {
        sut.addPastedText("pasted")
        let id = try XCTUnwrap(strip.attachments.first?.id)
        var dismissals = 0
        sut.onPastedTextSheetDismissed = { dismissals += 1 }

        sut.presentPastedTextSheet(id: id)
        let sheet = try XCTUnwrap(window.rootViewController?.presentedViewController as? PastedTextSheetHostingController)
        sheet.finish(.unchanged)

        XCTAssertEqual(strip.attachments.map(\.id), [id])
        XCTAssertEqual(firedPixels.map(\.name), ["aichat_unified_input_pasted_text_attached", "aichat_unified_input_pasted_text_sheet_opened"])
        XCTAssertEqual(dismissals, 1)
    }

    func testSavingAfterTheChipIsGoneReportsNoEdit() throws {
        sut.addPastedText("pasted")
        let id = try XCTUnwrap(strip.attachments.first?.id)
        var dismissals = 0
        sut.onPastedTextSheetDismissed = { dismissals += 1 }

        sut.presentPastedTextSheet(id: id)
        let sheet = try XCTUnwrap(window.rootViewController?.presentedViewController as? PastedTextSheetHostingController)
        sut.resetSelection()
        sheet.finish(.saved(AIChatPastedText(content: "edited")))

        XCTAssertTrue(strip.attachments.isEmpty)
        XCTAssertEqual(firedPixels.map(\.name), ["aichat_unified_input_pasted_text_attached", "aichat_unified_input_pasted_text_sheet_opened"])
        XCTAssertEqual(dismissals, 1)
    }

    func testTappingANonPastedChipOpensNothing() {
        strip.addAttachment(.file(AIChatFileAttachment(data: Data([1]), fileName: "doc.pdf", mimeType: "application/pdf")))

        strip.onAttachmentTapped?(strip.attachments[0].id)

        XCTAssertNil(window.rootViewController?.presentedViewController)
        XCTAssertTrue(firedPixels.isEmpty)
    }

    private var firedPixels: [(name: String, surface: String?)] {
        pixels.actualFireCalls.map { ($0.pixel.name, $0.pixel.parameters?["surface"]) }
    }
}

private struct DraftIPadIdiomProvider: UserInterfaceIdiomProviding {
    let userInterfaceIdiom: UIUserInterfaceIdiom = .pad
}

private final class StubAttachmentPreferences: AIChatPreferencesPersisting {
    var selectedReasoningEffort: String?
    var selectedModelId: String?
    var selectedModelShortName: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
}

private final class StubAttachmentModelsService: AIChatModelsProviding {
    var result: Result<AIChatModelsResponse, Error> = .success(AIChatModelsResponse(models: []))

    func fetchModels() async throws -> AIChatModelsResponse { try result.get() }
}
