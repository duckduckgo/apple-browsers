//
//  UnifiedToggleInputImageEncoderTests.swift
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

final class UnifiedToggleInputImageEncoderTests: XCTestCase {

    func testEmptyAttachmentsReturnsNil() {
        let result = UnifiedToggleInputImageEncoder.encode([])
        XCTAssertNil(result)
    }

    func testJPEGFileNameProducesJPEGFormat() {
        let attachment = AIChatImageAttachment(image: makeTestImage(), fileName: "photo.jpg")
        let result = UnifiedToggleInputImageEncoder.encode([attachment])
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.format, "jpeg")
        XCTAssertFalse(result?.first?.data.isEmpty ?? true)
    }

    func testJPEFileNameProducesJPEGFormat() {
        let attachment = AIChatImageAttachment(image: makeTestImage(), fileName: "photo.jpeg")
        let result = UnifiedToggleInputImageEncoder.encode([attachment])
        XCTAssertEqual(result?.first?.format, "jpeg")
    }

    func testPNGFileNameProducesPNGFormat() {
        let attachment = AIChatImageAttachment(image: makeTestImage(), fileName: "screenshot.png")
        let result = UnifiedToggleInputImageEncoder.encode([attachment])
        XCTAssertEqual(result?.first?.format, "png")
    }

    func testWebPFileNameFallsToPNG() {
        let attachment = AIChatImageAttachment(image: makeTestImage(), fileName: "sticker.webp")
        let result = UnifiedToggleInputImageEncoder.encode([attachment])
        XCTAssertEqual(result?.first?.format, "png")
    }

    func testNoExtensionFallsToPNG() {
        let attachment = AIChatImageAttachment(image: makeTestImage(), fileName: "image")
        let result = UnifiedToggleInputImageEncoder.encode([attachment])
        XCTAssertEqual(result?.first?.format, "png")
    }

    func testMultipleAttachmentsEncoded() {
        let attachments = (0..<3).map { AIChatImageAttachment(image: makeTestImage(), fileName: "img\($0).png") }
        let result = UnifiedToggleInputImageEncoder.encode(attachments)
        XCTAssertEqual(result?.count, 3)
    }

    func testOutputIsValidBase64() {
        let attachment = AIChatImageAttachment(image: makeTestImage(), fileName: "test.png")
        let result = UnifiedToggleInputImageEncoder.encode([attachment])
        XCTAssertNotNil(result?.first.flatMap { Data(base64Encoded: $0.data) })
    }

    private func makeTestImage(size: CGSize = CGSize(width: 100, height: 100)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
