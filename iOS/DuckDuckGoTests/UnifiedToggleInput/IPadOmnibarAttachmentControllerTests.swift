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
            subscriptionManager: SubscriptionManagerMock()
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
