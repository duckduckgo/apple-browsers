//
//  UnifiedToggleInputAttachmentEncoderTests.swift
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
import XCTest
@testable import DuckDuckGo

final class UnifiedToggleInputAttachmentEncoderTests: XCTestCase {

    func testNothingAttachedEncodesNoKinds() {
        XCTAssertEqual(encode([]), .none)
    }

    func testUnsupportedKindsAreNilEvenWhenAttached() {
        let attachments: [UnifiedToggleInputAttachment] = [.image(makeImageAttachment()), .file(makeFileAttachment())]

        let result = UnifiedToggleInputAttachmentEncoder.encode(attachments, imagesSupported: false, filesSupported: false)

        XCTAssertEqual(result, .none)
    }

    func testSupportedKindWithNothingOfThatKindIsNil() {
        let result = encode([.file(makeFileAttachment())])

        XCTAssertNil(result.images)
        XCTAssertEqual(result.files?.count, 1)
    }

    func testFileIsEncodedAsBase64WithNameAndMimeType() {
        let file = makeFileAttachment()

        let result = encode([.file(file)])

        XCTAssertEqual(result.files, [AIChatNativePrompt.NativePromptFile(data: file.data.base64EncodedString(),
                                                                          fileName: "a.pdf",
                                                                          mimeType: "application/pdf")])
    }

    func testEncodesAsJPEGByDefault() {
        let result = encode([.image(makeImageAttachment())]).images
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.format, "jpeg")
        XCTAssertFalse(result?.first?.data.isEmpty ?? true)
    }

    func testEncodesAsJPEGRegardlessOfExtension() {
        for name in ["photo.png", "sticker.webp", "image.gif", "noext"] {
            let result = encode([.image(makeImageAttachment(fileName: name))]).images
            XCTAssertEqual(result?.first?.format, "jpeg", "Expected jpeg for \(name)")
        }
    }

    func testKeepsOriginalDataAndFormatWhenPresent() {
        let original = Data([1, 2, 3])
        let attachment = AIChatImageAttachment(image: makeTestImage(), fileName: "a.png", originalEncodedData: original, originalFormat: "png")

        let result = encode([.image(attachment)]).images

        XCTAssertEqual(result, [AIChatNativePrompt.NativePromptImage(data: original.base64EncodedString(), format: "png")])
    }

    func testMultipleAttachmentsEncoded() {
        let attachments = (0..<3).map { UnifiedToggleInputAttachment.image(makeImageAttachment(fileName: "img\($0)")) }
        XCTAssertEqual(encode(attachments).images?.count, 3)
    }

    func testOutputIsValidBase64() {
        let result = encode([.image(makeImageAttachment())]).images
        XCTAssertNotNil(result?.first.flatMap { Data(base64Encoded: $0.data) })
    }

    func testEditSendsEmptyArrayForSupportedKindWithNothingAttached() {
        let result = UnifiedToggleInputAttachmentEncoder.encodeForEdit([], imagesSupported: true, filesSupported: true)

        XCTAssertEqual(result, AIChatPromptAttachments(images: [], files: []))
    }

    func testEditSendsNilForUnsupportedKind() {
        let result = UnifiedToggleInputAttachmentEncoder.encodeForEdit([.image(makeImageAttachment())],
                                                                       imagesSupported: false,
                                                                       filesSupported: true)

        XCTAssertNil(result.images)
        XCTAssertEqual(result.files, [])
    }

    private func encode(_ attachments: [UnifiedToggleInputAttachment]) -> AIChatPromptAttachments {
        UnifiedToggleInputAttachmentEncoder.encode(attachments, imagesSupported: true, filesSupported: true)
    }

    private func makeImageAttachment(fileName: String = "photo") -> AIChatImageAttachment {
        AIChatImageAttachment(image: makeTestImage(), fileName: fileName)
    }

    private func makeFileAttachment() -> AIChatFileAttachment {
        let data = Data("file".utf8)
        return AIChatFileAttachment(data: data, fileName: "a.pdf", mimeType: "application/pdf", fileSizeBytes: data.count, pageCount: 1)
    }

    private func makeTestImage(size: CGSize = CGSize(width: 100, height: 100)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
