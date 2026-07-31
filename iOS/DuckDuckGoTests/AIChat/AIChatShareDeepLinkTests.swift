//
//  AIChatShareDeepLinkTests.swift
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
import Core
import UIKit
import XCTest
@testable import DuckDuckGo

final class AIChatShareDeepLinkTests: XCTestCase {

    // MARK: - Deep link parsing

    func testWhenLinkHasPromptThenInlineLaneIsParsed() throws {
        let url = try XCTUnwrap(URL(string: "ddgOpenAIChat://ask?source=shareExtension&prompt=hello%20there%20%26%20friends"))

        XCTAssertEqual(AIChatDeepLinkHandler.sharePayloadLink(from: url), .inline(prompt: "hello there & friends"))
    }

    func testWhenLinkHasPayloadTokenThenTokenLaneIsParsed() throws {
        let token = UUID().uuidString
        let url = try XCTUnwrap(URL(string: "ddgOpenAIChat://ask?source=shareExtension&payloadToken=\(token)"))

        XCTAssertEqual(AIChatDeepLinkHandler.sharePayloadLink(from: url), .token(token))
    }

    func testWhenLinkHasBothLanesThenTokenWins() throws {
        let url = try XCTUnwrap(URL(string: "ddgOpenAIChat://ask?prompt=hello&payloadToken=DE305D54-75B4-431B-ADB2-EB6B9E546014"))

        XCTAssertEqual(AIChatDeepLinkHandler.sharePayloadLink(from: url), .token("DE305D54-75B4-431B-ADB2-EB6B9E546014"))
    }

    func testWhenLinkHasNeitherLaneThenNoSharePayload() throws {
        let url = try XCTUnwrap(URL(string: "ddgOpenAIChat://ask?source=quickActions"))

        XCTAssertNil(AIChatDeepLinkHandler.sharePayloadLink(from: url))
    }

    func testWhenLinkHasEmptyValuesThenNoSharePayload() throws {
        let url = try XCTUnwrap(URL(string: "ddgOpenAIChat://ask?prompt=&payloadToken="))

        XCTAssertNil(AIChatDeepLinkHandler.sharePayloadLink(from: url))
    }

    // MARK: - Payload round-trip

    func testWhenManifestIsWrittenThenItDecodesBackIdentically() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let payload = AIChatSharePayload(
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            prompt: "What is in these?",
            items: [
                .init(kind: .image, fileName: "shot.png", mimeType: "image/png", relativePath: "shot.png"),
                .init(kind: .file, fileName: "notes.pdf", mimeType: "application/pdf", relativePath: "notes.pdf")
            ]
        )

        try AIChatShareInbox.writeManifest(payload, to: directory)

        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AIChatSharePayload.self, from: data)

        XCTAssertEqual(decoded, payload)
    }

    func testWhenPayloadHasNoPromptThenItRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let payload = AIChatSharePayload(prompt: nil, items: [])
        try AIChatShareInbox.writeManifest(payload, to: directory)

        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AIChatSharePayload.self, from: data)

        XCTAssertNil(decoded.prompt)
        XCTAssertTrue(decoded.items.isEmpty)
    }

    // MARK: - Model auto-switch rule

    func testWhenModelLacksAccessThenItIsNotPicked() {
        let models = [
            makeModel(id: "no-access", supportsImageUpload: true, entityHasAccess: false),
            makeModel(id: "accessible", supportsImageUpload: true, entityHasAccess: true)
        ]

        let pick = AIChatDeepLinkHandler.model(in: models, needsImage: true, fileMimeTypes: [])

        XCTAssertEqual(pick?.id, "accessible")
    }

    func testWhenImageIsSharedThenFirstImageCapableModelIsPicked() {
        let models = [
            makeModel(id: "text-only", supportsImageUpload: false),
            makeModel(id: "vision", supportsImageUpload: true),
            makeModel(id: "vision-2", supportsImageUpload: true)
        ]

        let pick = AIChatDeepLinkHandler.model(in: models, needsImage: true, fileMimeTypes: [])

        XCTAssertEqual(pick?.id, "vision")
    }

    func testWhenFilesAreSharedThenModelMustSupportEveryMimeType() {
        let models = [
            makeModel(id: "pdf-only", supportsImageUpload: false, supportedFileTypes: ["application/pdf"]),
            makeModel(id: "pdf-and-text", supportsImageUpload: false, supportedFileTypes: ["application/pdf", "text/plain"])
        ]

        let pick = AIChatDeepLinkHandler.model(in: models, needsImage: false, fileMimeTypes: ["application/pdf", "text/plain"])

        XCTAssertEqual(pick?.id, "pdf-and-text")
    }

    func testWhenNothingSupportsTheAttachmentsThenNoModelIsPicked() {
        let models = [
            makeModel(id: "text-only", supportsImageUpload: false),
            makeModel(id: "vision", supportsImageUpload: true)
        ]

        let pick = AIChatDeepLinkHandler.model(in: models, needsImage: true, fileMimeTypes: ["application/pdf"])

        XCTAssertNil(pick)
    }

    func testWhenThereAreNoModelsThenNoModelIsPicked() {
        XCTAssertNil(AIChatDeepLinkHandler.model(in: [], needsImage: true, fileMimeTypes: []))
    }

    func testModelSupportsMatchesThePickRule() {
        let vision = makeModel(id: "vision", supportsImageUpload: true, supportedFileTypes: ["application/pdf"])

        XCTAssertTrue(AIChatDeepLinkHandler.model(vision, supports: true, fileMimeTypes: ["application/pdf"]))
        XCTAssertFalse(AIChatDeepLinkHandler.model(vision, supports: true, fileMimeTypes: ["text/plain"]))
        XCTAssertFalse(AIChatDeepLinkHandler.model(
            makeModel(id: "text-only", supportsImageUpload: false),
            supports: true,
            fileMimeTypes: []
        ))
        XCTAssertFalse(AIChatDeepLinkHandler.model(
            makeModel(id: "gated", supportsImageUpload: true, entityHasAccess: false),
            supports: true,
            fileMimeTypes: []
        ))
    }

    // MARK: - Reading staged items

    func testWhenItemBytesAreStagedThenTheyAreRead() throws {
        let directory = try makeTemporaryDirectory()
        try Data("pdf-bytes".utf8).write(to: directory.appendingPathComponent("notes.pdf"))

        let read = AIChatDeepLinkHandler.readItems(
            [.init(kind: .file, fileName: "notes.pdf", mimeType: "application/pdf", relativePath: "notes.pdf")],
            in: directory
        )

        XCTAssertEqual(read.skippedCount, 0)
        XCTAssertEqual(read.items.count, 1)
        XCTAssertEqual(read.items.first?.data, Data("pdf-bytes".utf8))
    }

    func testWhenRelativePathEscapesTheDirectoryThenItemIsSkipped() throws {
        let directory = try makeTemporaryDirectory()

        let read = AIChatDeepLinkHandler.readItems(
            [
                .init(kind: .file, fileName: "a", mimeType: "application/pdf", relativePath: "../outside.pdf"),
                .init(kind: .file, fileName: "b", mimeType: "application/pdf", relativePath: "missing.pdf")
            ],
            in: directory
        )

        XCTAssertTrue(read.items.isEmpty)
        XCTAssertEqual(read.skippedCount, 2)
    }

    func testWhenStagedItemExceedsTheLimitThenItIsSkipped() throws {
        let directory = try makeTemporaryDirectory()
        try Data("pdf-bytes".utf8).write(to: directory.appendingPathComponent("big.pdf"))
        try Data("ok".utf8).write(to: directory.appendingPathComponent("small.pdf"))

        let read = AIChatDeepLinkHandler.readItems(
            [
                .init(kind: .file, fileName: "big.pdf", mimeType: "application/pdf", relativePath: "big.pdf"),
                .init(kind: .file, fileName: "small.pdf", mimeType: "application/pdf", relativePath: "small.pdf")
            ],
            in: directory,
            limit: 4
        )

        XCTAssertEqual(read.skippedCount, 1)
        XCTAssertEqual(read.items.count, 1)
        XCTAssertEqual(read.items.first?.item.fileName, "small.pdf")
    }

    func testWhenStagedItemIsExactlyAtTheLimitThenItIsRead() throws {
        let directory = try makeTemporaryDirectory()
        try Data("abcd".utf8).write(to: directory.appendingPathComponent("exact.pdf"))

        let read = AIChatDeepLinkHandler.readItems(
            [.init(kind: .file, fileName: "exact.pdf", mimeType: "application/pdf", relativePath: "exact.pdf")],
            in: directory,
            limit: 4
        )

        XCTAssertEqual(read.skippedCount, 0)
        XCTAssertEqual(read.items.count, 1)
    }

    // MARK: - Draft construction

    func testWhenPayloadHasAnImageAndFileThenDraftCarriesBoth() throws {
        let imageData = try XCTUnwrap(UIImage(systemName: "star")?.pngData())
        let items = [
            AIChatDeepLinkHandler.ReadItem(
                item: .init(kind: .image, fileName: "shot.png", mimeType: "image/png", relativePath: "shot.png"),
                data: imageData
            ),
            AIChatDeepLinkHandler.ReadItem(
                item: .init(kind: .file, fileName: "notes.pdf", mimeType: "application/pdf", relativePath: "notes.pdf"),
                data: Data("pdf-bytes".utf8)
            )
        ]

        let draft = AIChatDeepLinkHandler.draft(prompt: "describe", items: items)

        XCTAssertEqual(draft.text, "describe")
        XCTAssertEqual(draft.images.count, 1)
        XCTAssertEqual(draft.images.first?.fileName, "shot.png")
        XCTAssertEqual(draft.files.count, 1)
        XCTAssertEqual(draft.files.first?.fileName, "notes.pdf")
        XCTAssertEqual(draft.files.first?.mimeType, "application/pdf")
        XCTAssertEqual(draft.files.first?.data, Data("pdf-bytes".utf8))
    }

    func testWhenImageBytesAreUndecodableThenTheImageIsDropped() {
        let items = [
            AIChatDeepLinkHandler.ReadItem(
                item: .init(kind: .image, fileName: "shot.png", mimeType: "image/png", relativePath: "shot.png"),
                data: Data("not-an-image".utf8)
            )
        ]

        let draft = AIChatDeepLinkHandler.draft(prompt: "", items: items)

        XCTAssertTrue(draft.images.isEmpty)
        XCTAssertTrue(draft.files.isEmpty)
        XCTAssertEqual(draft.text, "")
    }

    // MARK: - Delivery classification

    func testDeliveryTypeReflectsPayloadShape() {
        let image = AIChatSharePayload.Item(kind: .image, fileName: "a.png", mimeType: "image/png", relativePath: "a.png")

        XCTAssertEqual(AIChatDeepLinkHandler.deliveryType(prompt: "long text", items: []), "text")
        XCTAssertEqual(AIChatDeepLinkHandler.deliveryType(prompt: nil, items: [image]), "attachments")
        XCTAssertEqual(AIChatDeepLinkHandler.deliveryType(prompt: "  ", items: [image]), "attachments")
        XCTAssertEqual(AIChatDeepLinkHandler.deliveryType(prompt: "describe", items: [image]), "mixed")
    }

    func testImageFormatDropsTheMIMETypePrefix() {
        XCTAssertEqual(AIChatDeepLinkHandler.imageFormat(for: "image/png"), "png")
        XCTAssertEqual(AIChatDeepLinkHandler.imageFormat(for: "image/jpeg"), "jpeg")
        XCTAssertEqual(AIChatDeepLinkHandler.imageFormat(for: "png"), "png")
    }

    // MARK: - Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makeModel(id: String,
                           supportsImageUpload: Bool,
                           supportedFileTypes: [String] = [],
                           entityHasAccess: Bool = true) -> AIChatModel {
        AIChatModel(
            id: id,
            name: id,
            provider: .openAI,
            supportsImageUpload: supportsImageUpload,
            supportedFileTypes: supportedFileTypes,
            entityHasAccess: entityHasAccess
        )
    }
}
