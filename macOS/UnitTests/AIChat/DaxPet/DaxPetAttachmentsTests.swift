//
//  DaxPetAttachmentsTests.swift
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
import AppKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class DaxPetAttachmentsTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    private static func capabilities(images: Bool = true, fileTypes: [String] = ["application/pdf"], maxImagesPerTurn: Int = 2) -> DaxPetAttachmentCapabilities {
        let model = AIChatModel(id: "model", name: "Model", provider: .openAI,
                                supportsImageUpload: images,
                                supportedFileTypes: fileTypes,
                                supportedImageFormats: ["png", "jpeg"],
                                entityHasAccess: true)
        let limits = AIChatAttachmentTierLimits(
            files: AIChatAttachmentFileLimits(maxPerConversation: 3, maxFileSizeMB: 10, maxTotalFileSizeBytes: 30_000_000, maxPagesPerFile: 100),
            images: AIChatAttachmentImageLimits(maxPerTurn: maxImagesPerTurn, maxPerConversation: 10, maxInputCharsWithAttachments: 10_000))
        return DaxPetAttachmentCapabilities(model: model, limits: limits)
    }

    private func pngFile(named name: String = "duck.png") throws -> URL {
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.orange.setFill()
            rect.fill()
            return true
        }
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let url = directory.appendingPathComponent(name)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    private func pdfFile() throws -> URL {
        let url = directory.appendingPathComponent("notes.pdf")
        var box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        return url
    }

    private func file(named name: String, contents: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Reading drops

    func testWhenFilesAreDroppedThenTheyAreReadAsFiles() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let url = try pngFile()
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])

        XCTAssertEqual(DaxPetDroppedItem.items(from: pasteboard), [.file(url)])
    }

    func testWhenALinkIsDroppedThenItIsReadAsALink() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let url = try XCTUnwrap(URL(string: "https://duckduckgo.com/about"))
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])

        XCTAssertEqual(DaxPetDroppedItem.items(from: pasteboard), [.link(url)])
    }

    func testWhenTextIsDroppedThenItIsReadTrimmed() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString("  Ducks can sleep with one eye open.\n", forType: .string)

        XCTAssertEqual(DaxPetDroppedItem.items(from: pasteboard), [.text("Ducks can sleep with one eye open.")])
    }

    func testWhenNothingUsableIsDroppedThenThereAreNoItems() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString("   ", forType: .string)

        XCTAssertEqual(DaxPetDroppedItem.items(from: pasteboard), [])
    }

    // MARK: - Loading

    func testWhenTheModelTakesImagesAndPDFsThenBothAreAccepted() throws {
        let result = DaxPetAttachmentLoader.load([.file(try pngFile()), .file(try pdfFile())], adding: [], capabilities: Self.capabilities())

        XCTAssertNil(result.rejection)
        XCTAssertEqual(result.accepted.map(\.name), ["duck.png", "notes.pdf"])
    }

    func testWhenTheModelTakesNoImagesThenAnImageIsRefusedWithAReason() throws {
        let result = DaxPetAttachmentLoader.load([.file(try pngFile())], adding: [], capabilities: Self.capabilities(images: false))

        XCTAssertTrue(result.accepted.isEmpty)
        XCTAssertEqual(result.rejection, UserText.aiChatAttachmentUnsupportedFileType)
    }

    func testWhenMoreImagesThanATurnAllowsAreDroppedThenTheExtraOnesAreRefused() throws {
        let items: [DaxPetDroppedItem] = [.file(try pngFile(named: "a.png")), .file(try pngFile(named: "b.png")), .file(try pngFile(named: "c.png"))]

        let result = DaxPetAttachmentLoader.load(items, adding: [], capabilities: Self.capabilities(maxImagesPerTurn: 2))

        XCTAssertEqual(result.accepted.map(\.name), ["a.png", "b.png"])
        XCTAssertEqual(result.rejection, UserText.aiChatAttachmentImageTurnLimit(maxImagesPerTurn: 2))
    }

    func testWhenAFileTypeIsNotSupportedThenItIsRefusedWithTheValidatorsReason() throws {
        let zip = try file(named: "archive.zip", contents: "PK")

        let result = DaxPetAttachmentLoader.load([.file(zip)], adding: [], capabilities: Self.capabilities())

        XCTAssertTrue(result.accepted.isEmpty)
        XCTAssertNotNil(result.rejection)
    }

    func testWhenAPlainTextFileIsDroppedThenItsTextIsTaken() throws {
        let notes = try file(named: "notes.txt", contents: "Quack")

        let result = DaxPetAttachmentLoader.load([.file(notes)], adding: [], capabilities: .unknown)

        guard case .text(_, let text) = try XCTUnwrap(result.accepted.first) else { return XCTFail("Expected text") }
        XCTAssertEqual(text, "Quack")
    }

    func testTextAndLinksNeedNoModelSupport() throws {
        let link = try XCTUnwrap(URL(string: "https://duckduckgo.com"))

        let result = DaxPetAttachmentLoader.load([.text("Hello"), .link(link)], adding: [], capabilities: .unknown)

        XCTAssertEqual(result.accepted.count, 2)
        XCTAssertNil(result.rejection)
    }

    // MARK: - Prompt

    func testWhenThereAreNoAttachmentsThenTheQuestionGoesAlone() {
        let prompt = DaxPetAttachmentLoader.prompt("What's a duck?", attachments: [], capabilities: Self.capabilities())

        XCTAssertEqual(prompt.query, "What's a duck?")
        XCTAssertNil(prompt.payload)
    }

    func testWhenTextAndLinksWereDroppedThenTheyFollowTheQuestion() throws {
        let link = try XCTUnwrap(URL(string: "https://duckduckgo.com"))

        let prompt = DaxPetAttachmentLoader.prompt("Explain", attachments: [.text("Quack"), .link(link)], capabilities: .unknown)

        XCTAssertEqual(prompt.query, "Explain\n\nQuack\n\nhttps://duckduckgo.com")
        XCTAssertNil(prompt.payload)
    }

    func testWhenImagesAndFilesWereDroppedThenTheyTravelAsAttachmentsForTheCheckedModel() throws {
        let capabilities = Self.capabilities()
        let accepted = DaxPetAttachmentLoader.load([.file(try pngFile()), .file(try pdfFile())], adding: [], capabilities: capabilities).accepted

        let prompt = DaxPetAttachmentLoader.prompt("What's this?", attachments: accepted, capabilities: capabilities)

        guard case .query(let query) = try XCTUnwrap(prompt.payload?.tool) else { return XCTFail("Expected a query") }
        XCTAssertEqual(query.prompt, "What's this?")
        XCTAssertEqual(query.images?.count, 1)
        XCTAssertEqual(query.images?.first?.format, "png")
        XCTAssertEqual(query.files?.map(\.fileName), ["notes.pdf"])
        XCTAssertEqual(query.files?.first?.mimeType, "application/pdf")
        XCTAssertEqual(query.modelId, "model")
    }
}
