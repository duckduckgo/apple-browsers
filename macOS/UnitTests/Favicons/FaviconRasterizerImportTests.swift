//
//  FaviconRasterizerImportTests.swift
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

import AppKit
import FeatureFlags_macOS
import PrivacyConfig
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// The part of `FaviconRasterizer` that turns favicon data into images to store: `storableImage(from:)` and
/// `favicons(fromImported:)`, which the data importers use.
@MainActor
final class FaviconRasterizerImportTests: XCTestCase {

    private typealias Fixtures = FaviconTestFixtures

    private var rasterizer: FaviconRasterizer!

    override func setUp() {
        super.setUp()
        rasterizer = Fixtures.makeRasterizer()
    }

    override func tearDown() {
        rasterizer = nil
        super.tearDown()
    }

    // MARK: - Feature flag off

    /// With the flag off the legacy decoding is kept: a lazy `NSImage(data:)`, which for an SVG is vector-backed.
    func testStorableImageUsesLegacyDecodingWhenTheFlagIsOff() async throws {
        let legacy = Fixtures.makeRasterizer(enabled: false)
        let svg = Data(Fixtures.svg(width: 16, height: 16).utf8)

        let rendered = await legacy.storableImage(from: svg)

        let image = try XCTUnwrap(rendered)
        XCTAssertFalse(image.representations.contains { $0 is NSBitmapImageRep })
        XCTAssertFalse(legacy.hasWebView)
    }

    func testImportedFaviconsUseLegacyDecodingWhenTheFlagIsOff() async throws {
        let legacy = Fixtures.makeRasterizer(enabled: false)
        let png = try await rasterizer.rasterize(Data(Fixtures.svg(width: 16, height: 16).utf8))
        let svg = Data(Fixtures.svg(width: 16, height: 16).utf8)
        let imported = ["https://example.com": [ImportedFavicon(imageData: png), ImportedFavicon(imageData: svg)]]

        let faviconsByDocument = await legacy.favicons(fromImported: imported)

        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let images = try XCTUnwrap(faviconsByDocument[url]).map(\.image)
        XCTAssertEqual(images.count, 2)
        XCTAssertTrue(images.allSatisfy { $0 != nil })
        XCTAssertFalse(images[1]?.representations.contains { $0 is NSBitmapImageRep } ?? true)
        XCTAssertFalse(legacy.hasWebView)
    }

    // MARK: - storableImage

    func testStorableImageDecodesRasterDataAsIs() async throws {
        let png = try await rasterizer.rasterize(Data(Fixtures.svg(width: 16, height: 16).utf8))

        let storable = await rasterizer.storableImage(from: png)
        let image = try XCTUnwrap(storable)

        XCTAssertEqual(image.size, NSSize(width: 64, height: 64))
    }

    func testStorableImageRendersSVGWithWebKitAndCapsItAtMaxStoredSize() async throws {
        let rendered = await rasterizer.storableImage(from: Data(Fixtures.recursiveFilterSVG.utf8))
        let image = try XCTUnwrap(rendered)
        XCTAssertTrue(image.representations.allSatisfy { $0 is NSBitmapImageRep })
        XCTAssertTrue(image.hasVisiblePixels())

        let largeImage = await rasterizer.storableImage(from: Data(Fixtures.svg(width: 1024, height: 512).utf8))
        let large = try XCTUnwrap(largeImage)
        XCTAssertEqual(large.size, NSSize(width: 64, height: 32))
    }

    /// The flag is read for every image, so switching it while the app runs takes effect at once, in both
    /// directions, with the web view of the earlier renders still alive.
    func testStorableImageFollowsTheFlagWhileTheRasterizerLives() async throws {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.faviconWebKitSVGRendering]
        let rasterizer = Fixtures.makeRasterizer(featureFlagger: featureFlagger)
        let svg = Data(Fixtures.svg(width: 16, height: 16).utf8)

        let rendered = await rasterizer.storableImage(from: svg)
        featureFlagger.enabledFeatureFlags = []
        let legacy = await rasterizer.storableImage(from: svg)
        featureFlagger.enabledFeatureFlags = [.faviconWebKitSVGRendering]
        let renderedAgain = await rasterizer.storableImage(from: svg)

        let isBitmap = try [rendered, legacy, renderedAgain].map { image in
            try XCTUnwrap(image).representations.allSatisfy { $0 is NSBitmapImageRep }
        }
        XCTAssertEqual(isBitmap, [true, false, true])
    }

    func testStorableImageIsNilForDataThatIsNotAnImage() async {
        let image = await rasterizer.storableImage(from: Data("not an image".utf8))
        XCTAssertNil(image)
    }

    func testStoredPDFFaviconIsABitmap() async throws {
        let stored = await rasterizer.storableImage(from: Fixtures.pdfData())

        let image = try XCTUnwrap(stored)
        XCTAssertTrue(image.representations.allSatisfy { $0 is NSBitmapImageRep })
        XCTAssertTrue(rasterizer.hasWebView)
    }

    /// The data is loaded as SVG unless it starts with the PDF magic.
    func testSVGWithPDFMagicInsideIsRenderedAsSVG() async throws {
        let svg = Data(("<!-- %PDF-1.4 -->" + Fixtures.recursiveFilterSVG).utf8)
        XCTAssertFalse(svg.isPDFData)

        let stored = await rasterizer.storableImage(from: svg)

        let image = try XCTUnwrap(stored)
        XCTAssertTrue(image.representations.allSatisfy { $0 is NSBitmapImageRep })
        XCTAssertTrue(image.hasVisiblePixels())
    }

    // MARK: - Imported favicons

    func testImportedFaviconsAreBuiltPerPageURLAndSVGIsRendered() async throws {
        let png = try await rasterizer.rasterize(Data(Fixtures.svg(width: 16, height: 16).utf8))
        let imported = [
            "https://example.com": [ImportedFavicon(imageData: png), ImportedFavicon(imageData: Data(Fixtures.recursiveFilterSVG.utf8))],
            "https://broken.example": [ImportedFavicon(imageData: Data("not an image".utf8))]
        ]

        let faviconsByDocument = await rasterizer.favicons(fromImported: imported)

        let exampleURL = try XCTUnwrap(URL(string: "https://example.com"))
        let brokenURL = try XCTUnwrap(URL(string: "https://broken.example"))
        let example = try XCTUnwrap(faviconsByDocument[exampleURL])
        XCTAssertEqual(example.count, 2)
        XCTAssertTrue(example.allSatisfy { $0.image?.representations.allSatisfy { $0 is NSBitmapImageRep } == true })
        XCTAssertEqual(faviconsByDocument[brokenURL]?.count, 1)
        XCTAssertNil(faviconsByDocument[brokenURL]?.first?.image)
    }

    func testImportedPDFFaviconIsKept() async throws {
        let imported = ["https://example.com": [ImportedFavicon(imageData: Fixtures.pdfData())]]

        let faviconsByDocument = await rasterizer.favicons(fromImported: imported)

        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let image = try XCTUnwrap(faviconsByDocument[url]?.first?.image)
        XCTAssertTrue(image.representations.allSatisfy { $0 is NSBitmapImageRep })
    }

    func testImportedFaviconsWithTheSameDataShareOneImage() async throws {
        let first = Data(Fixtures.svg(width: 100, height: 50).utf8)
        let second = Data(Fixtures.svg(width: 50, height: 100).utf8)
        let imported = [
            "https://a.example": [ImportedFavicon(imageData: first), ImportedFavicon(imageData: second)],
            "https://b.example": [ImportedFavicon(imageData: first)],
            "https://c.example": [ImportedFavicon(imageData: second), ImportedFavicon(imageData: first)]
        ]

        let faviconsByDocument = await rasterizer.favicons(fromImported: imported)

        func image(_ page: String, _ index: Int) throws -> NSImage {
            let url = try XCTUnwrap(URL(string: page))
            return try XCTUnwrap(faviconsByDocument[url]?[index].image)
        }
        let firstImage = try image("https://a.example", 0)
        XCTAssertEqual(firstImage.size, NSSize(width: 64, height: 32))
        XCTAssertTrue(try image("https://b.example", 0) === firstImage)
        XCTAssertTrue(try image("https://c.example", 1) === firstImage)
        let secondImage = try image("https://a.example", 1)
        XCTAssertEqual(secondImage.size, NSSize(width: 32, height: 64))
        XCTAssertTrue(try image("https://c.example", 0) === secondImage)
    }

    /// Every favicon is a different image, so all of them are decoded, several at a time. Each stays with its page
    /// whichever finishes first: the images get taller, so their heights, once scaled to 64 pixels wide, tell them apart.
    func testImportedFaviconsKeepTheirOrderWhenDecodedConcurrently() async throws {
        let heights = (0..<12).map { 20 + $0 * 7 }
        let datas = heights.map { Data(Fixtures.svg(width: 100, height: $0).utf8) }
        let imported = ["https://example.com": datas.map(ImportedFavicon.init)]

        let faviconsByDocument = await rasterizer.favicons(fromImported: imported)

        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let sizes = try XCTUnwrap(faviconsByDocument[url]).map { $0.image?.size ?? .zero }
        XCTAssertEqual(sizes.count, heights.count)
        for (size, height) in zip(sizes, heights) {
            XCTAssertEqual(size.width, 64, accuracy: 1)
            XCTAssertEqual(size.height, (64.0 * Double(height) / 100.0).rounded(), accuracy: 1)
        }
    }

    /// Decoding thousands of imported raster favicons must not block the main thread.
    func testImportingManyRasterFaviconsDoesNotBlockTheMainThread() async throws {
        let imported = ["https://example.com": (0..<3000).map { ImportedFavicon(imageData: Self.solidPNG(index: $0)) }]
        let rasterizer = self.rasterizer!

        let importTask = Task.detached { await rasterizer.favicons(fromImported: imported) }
        var isFinished = false
        Task {
            _ = await importTask.value
            isFinished = true
        }
        var longestGap: TimeInterval = 0
        var last = Date()
        let start = last
        while Date().timeIntervalSince(start) < 30 {
            try await Task.sleep(nanoseconds: 2_000_000)
            let now = Date()
            longestGap = max(longestGap, now.timeIntervalSince(last))
            last = now
            if isFinished { break }
        }
        let result = await importTask.value

        XCTAssertEqual(result.values.first?.count, 3000)
        XCTAssertEqual(result.values.first?.compactMap(\.image).count, 3000)
        XCTAssertLessThan(longestGap, 1)
    }

    // MARK: - Helpers

    private struct ImportedFavicon: ImportedFaviconDataProviding {
        let imageData: Data
    }

    /// A small PNG of a color no other index has, so that identical data doesn't collapse the favicons into one.
    private static func solidPNG(index: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let color = NSColor(deviceRed: CGFloat(index % 256) / 255, green: CGFloat(index / 256 % 256) / 255, blue: 0.5, alpha: 1)
        for x in 0..<16 {
            for y in 0..<16 {
                rep.setColor(color, atX: x, y: y)
            }
        }
        return rep.representation(using: .png, properties: [:])!
    }
}
