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
        XCTAssertNil(sut.encodedImages)
        XCTAssertNil(sut.encodedFiles)
    }

    func testWhenImageAttachedThenEncodedImagesReturnedAndFilesNil() {
        strip.addAttachment(.image(AIChatImageAttachment(image: makeImage(), fileName: "photo.jpg")))

        XCTAssertTrue(sut.hasAttachments)
        XCTAssertEqual(sut.encodedImages?.count, 1)
        XCTAssertNil(sut.encodedFiles)
    }

    func testWhenFileAttachedThenEncodedFilesReturnedAndImagesNil() {
        strip.addAttachment(.file(makeFileAttachment()))

        XCTAssertTrue(sut.hasAttachments)
        XCTAssertEqual(sut.encodedFiles?.count, 1)
        XCTAssertNil(sut.encodedImages)
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
        XCTAssertNil(sut.encodedFiles)
        XCTAssertNil(sut.encodedImages)
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

    private func footerCards(in view: UIView) -> [UTIFooterCardView] {
        let children = (view as? UIStackView)?.arrangedSubviews ?? view.subviews
        return children.flatMap { child -> [UTIFooterCardView] in
            if let card = child as? UTIFooterCardView { return [card] }
            return footerCards(in: child)
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
