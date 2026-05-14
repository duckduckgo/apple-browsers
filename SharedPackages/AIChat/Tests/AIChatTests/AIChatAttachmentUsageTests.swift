//
//  AIChatAttachmentUsageTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

#if os(iOS)
import XCTest
@testable import AIChat

final class AIChatAttachmentUsageTests: XCTestCase {

    func testWhenStatusHasAttachmentsThenAllFieldsAreDecoded() throws {
        let json = """
        {
            "status": "ready",
            "attachments": {
                "imagesUsed": 4,
                "filesUsed": 1,
                "fileSizeBytesUsed": 4194304
            }
        }
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(AIChatStatus.self, from: json)
        XCTAssertEqual(status.status, .ready)
        XCTAssertEqual(status.attachments?.imagesUsed, 4)
        XCTAssertEqual(status.attachments?.filesUsed, 1)
        XCTAssertEqual(status.attachments?.fileSizeBytesUsed, 4194304)
    }

    func testWhenStatusHasNoAttachmentsThenAttachmentsIsNil() throws {
        let json = """
        {"status": "ready"}
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(AIChatStatus.self, from: json)
        XCTAssertEqual(status.status, .ready)
        XCTAssertNil(status.attachments)
    }

    func testWhenStatusIsStreamingThenAttachmentsAreIgnored() throws {
        let json = """
        {"status": "streaming"}
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(AIChatStatus.self, from: json)
        XCTAssertEqual(status.status, .streaming)
        XCTAssertNil(status.attachments)
    }

    func testWhenStatusIsErrorThenAttachmentsAreDecoded() throws {
        let json = """
        {
            "status": "error",
            "attachments": {
                "imagesUsed": 2,
                "filesUsed": 0,
                "fileSizeBytesUsed": 0
            }
        }
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(AIChatStatus.self, from: json)
        XCTAssertEqual(status.status, .error)
        XCTAssertEqual(status.attachments?.imagesUsed, 2)
    }

    func testWhenAttachmentsHasPartialFieldsThenMissingFieldsDefaultToZero() throws {
        let json = """
        {
            "status": "ready",
            "attachments": {
                "imagesUsed": 3
            }
        }
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(AIChatStatus.self, from: json)
        XCTAssertEqual(status.status, .ready)
        XCTAssertEqual(status.attachments?.imagesUsed, 3)
        XCTAssertEqual(status.attachments?.filesUsed, 0)
        XCTAssertEqual(status.attachments?.fileSizeBytesUsed, 0)
    }

    func testWhenAttachmentsIsEmptyObjectThenAllFieldsDefaultToZero() throws {
        let json = """
        {
            "status": "ready",
            "attachments": {}
        }
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(AIChatStatus.self, from: json)
        XCTAssertEqual(status.status, .ready)
        XCTAssertNotNil(status.attachments)
        XCTAssertEqual(status.attachments?.imagesUsed, 0)
        XCTAssertEqual(status.attachments?.filesUsed, 0)
        XCTAssertEqual(status.attachments?.fileSizeBytesUsed, 0)
    }

    func testWhenAttachmentUsageValuesMatchThenTheyAreEqual() {
        let a = AIChatAttachmentUsage(imagesUsed: 3, filesUsed: 1, fileSizeBytesUsed: 100)
        let b = AIChatAttachmentUsage(imagesUsed: 3, filesUsed: 1, fileSizeBytesUsed: 100)
        let c = AIChatAttachmentUsage(imagesUsed: 0, filesUsed: 0, fileSizeBytesUsed: 0)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
#endif
