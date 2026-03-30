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

    func testEncodesAsJPEGByDefault() {
        let attachment = AIChatImageAttachment(image: makeTestImage(), fileName: "photo")
        let result = UnifiedToggleInputImageEncoder.encode([attachment])
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.format, "jpeg")
        XCTAssertFalse(result?.first?.data.isEmpty ?? true)
    }

    func testEncodesAsJPEGRegardlessOfExtension() {
        for name in ["photo.png", "sticker.webp", "image.gif", "noext"] {
            let attachment = AIChatImageAttachment(image: makeTestImage(), fileName: name)
            let result = UnifiedToggleInputImageEncoder.encode([attachment])
            XCTAssertEqual(result?.first?.format, "jpeg", "Expected jpeg for \(name)")
        }
    }

    func testMultipleAttachmentsEncoded() {
        let attachments = (0..<3).map { AIChatImageAttachment(image: makeTestImage(), fileName: "img\($0)") }
        let result = UnifiedToggleInputImageEncoder.encode(attachments)
        XCTAssertEqual(result?.count, 3)
    }

    func testOutputIsValidBase64() {
        let attachment = AIChatImageAttachment(image: makeTestImage(), fileName: "test")
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
