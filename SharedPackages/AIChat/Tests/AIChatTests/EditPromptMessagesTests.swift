//
//  EditPromptMessagesTests.swift
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

#if os(iOS)
import XCTest
@testable import AIChat

final class EditPromptMessagesTests: XCTestCase {

    private func jsonObject(_ reply: EditPromptReply) throws -> [String: Any] {
        let data = try JSONEncoder().encode(reply)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Reply encoding

    func testCancelReplyEncodesOnlyCancelledTrue() throws {
        let json = try jsonObject(.cancelled)
        XCTAssertEqual(json["cancelled"] as? Bool, true)
        XCTAssertEqual(json.keys.count, 1, "Cancel must be the distinct shape { cancelled: true } with no other keys")
    }

    func testSubmitReplyEncodesContentAndOmitsCancelled() throws {
        let reply = EditPromptReply.submit(
            prompt: "edited",
            images: [.init(data: "aW1hZ2U=", format: "png")],
            files: [.init(data: "ZmlsZQ==", fileName: "a.pdf", mimeType: "application/pdf")]
        )
        let json = try jsonObject(reply)
        XCTAssertEqual(json["prompt"] as? String, "edited")
        XCTAssertNotNil(json["images"])
        XCTAssertNotNil(json["files"])
        XCTAssertNil(json["cancelled"], "Submit must not carry a `cancelled` key")
    }

    func testSubmitReplyOmitsNilAttachmentArrays() throws {
        let json = try jsonObject(.submit(prompt: "edited", images: nil, files: nil))
        XCTAssertEqual(json["prompt"] as? String, "edited")
        XCTAssertNil(json["images"])
        XCTAssertNil(json["files"])
        XCTAssertNil(json["cancelled"])
    }

    // MARK: - Request decoding

    func testRequestDecodesPromptAttachmentsAndWarningFlag() throws {
        let json = """
        {
          "prompt": "hi",
          "hasResponsesToLose": true,
          "images": [{ "data": "aW1n", "format": "jpeg" }],
          "files": [{ "data": "ZmlsZQ==", "fileName": "a.pdf", "mimeType": "application/pdf" }]
        }
        """
        let request = try JSONDecoder().decode(EditPromptRequest.self, from: Data(json.utf8))
        XCTAssertEqual(request.prompt, "hi")
        XCTAssertTrue(request.hasResponsesToLose)
        XCTAssertEqual(request.images?.count, 1)
        XCTAssertEqual(request.images?.first?.format, "jpeg")
        XCTAssertEqual(request.files?.first?.fileName, "a.pdf")
        XCTAssertEqual(request.files?.first?.mimeType, "application/pdf")
    }

    func testRequestDecodesWithoutAttachments() throws {
        let json = #"{ "prompt": "hi", "hasResponsesToLose": false }"#
        let request = try JSONDecoder().decode(EditPromptRequest.self, from: Data(json.utf8))
        XCTAssertEqual(request.prompt, "hi")
        XCTAssertFalse(request.hasResponsesToLose)
        XCTAssertNil(request.images)
        XCTAssertNil(request.files)
    }
}
#endif
