//
//  AIChatPDFInspectorTests.swift
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

import CoreGraphics
import Foundation
import XCTest
@testable import AIChat

final class AIChatPDFInspectorTests: XCTestCase {

    func testWhenMimeTypeIsNotPDF_ThenResultIsNotPDF() {
        let result = AIChatPDFInspector.inspect(data: Data([0x25, 0x50]), mimeType: "image/png")
        XCTAssertEqual(result, .notPDF)
        XCTAssertNil(result.pageCount)
        XCTAssertFalse(result.isEncrypted)
    }

    func testWhenBytesAreNotAValidPDF_ThenResultIsUnreadable() {
        let result = AIChatPDFInspector.inspect(data: Data("not a pdf".utf8), mimeType: "application/pdf")
        XCTAssertEqual(result, .unreadable)
    }

    func testWhenPDFIsValid_ThenResultIsReadableWithPageCount() throws {
        let data = try makePDFData(pageCount: 3)
        let result = AIChatPDFInspector.inspect(data: data, mimeType: "application/pdf")
        XCTAssertEqual(result, .readable(pageCount: 3))
        XCTAssertEqual(result.pageCount, 3)
    }

    func testWhenPDFIsEncrypted_ThenResultIsEncrypted() throws {
        let data = try makePDFData(pageCount: 1, ownerPassword: "owner", userPassword: "user")
        let result = AIChatPDFInspector.inspect(data: data, mimeType: "application/pdf")
        XCTAssertEqual(result, .encrypted)
        XCTAssertTrue(result.isEncrypted)
        XCTAssertNil(result.pageCount)
    }

    // MARK: - Helpers

    private func makePDFData(pageCount: Int, ownerPassword: String? = nil, userPassword: String? = nil) throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 200, height: 200)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data as CFMutableData))

        var auxInfo: [CFString: Any] = [:]
        if let ownerPassword { auxInfo[kCGPDFContextOwnerPassword] = ownerPassword }
        if let userPassword { auxInfo[kCGPDFContextUserPassword] = userPassword }

        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, auxInfo.isEmpty ? nil : auxInfo as CFDictionary))
        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}
