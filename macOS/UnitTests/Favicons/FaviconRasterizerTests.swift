//
//  FaviconRasterizerTests.swift
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

import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class FaviconRasterizerTests: XCTestCase {

    private var rasterizer: FaviconRasterizer!

    override func setUp() {
        super.setUp()
        rasterizer = FaviconRasterizer()
    }

    override func tearDown() {
        rasterizer = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    /// CoreSVG overflows the stack (`EXC_BAD_ACCESS` in `SVGFilter::draw`) when the root `<svg>` and a child
    /// reference the same filter.
    private static let recursiveFilterSVG = ##"""
    <svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64" filter="url(#f)">
      <filter id="f"><feOffset/></filter>
      <rect width="64" height="64" fill="#000" filter="url(#f)"/>
    </svg>
    """##

    private static func svg(width: Int, height: Int) -> String {
        ##"<svg xmlns="http://www.w3.org/2000/svg" width="\##(width)" height="\##(height)"><rect width="\##(width)" height="\##(height)" fill="#000"/></svg>"##
    }

    // MARK: - Rasterization

    func testRasterizesSVGThatCrashesCoreSVG() async throws {
        let png = try await rasterizer.rasterize(Data(Self.recursiveFilterSVG.utf8))

        let image = try decode(png)
        XCTAssertEqual(image.size, NSSize(width: 64, height: 64))
        XCTAssertTrue(image.hasVisiblePixels())
    }

    func testSmallSVGIsRasterizedAtMinimumSizeToStaySharp() async throws {
        let png = try await rasterizer.rasterize(Data(Self.svg(width: 16, height: 16).utf8))

        XCTAssertEqual(try decode(png).size, NSSize(width: 64, height: 64))
    }

    func testLargeSVGIsCappedAtMaximumSize() async throws {
        let png = try await rasterizer.rasterize(Data(Self.svg(width: 1024, height: 512).utf8))

        XCTAssertEqual(try decode(png).size, NSSize(width: 256, height: 128))
    }

    func testSVGWithoutIntrinsicSizeUsesViewBoxAspectRatio() async throws {
        let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 20"><rect width="10" height="20" fill="#000"/></svg>"##

        let png = try await rasterizer.rasterize(Data(svg.utf8))

        XCTAssertEqual(try decode(png).size, NSSize(width: 32, height: 64))
    }

    /// AppKit ignores CSS in SVG and renders this one fully transparent; WebKit applies it.
    func testSVGColoredOnlyWithCSSHasVisiblePixels() async throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="180" height="180" fill="none">
          <style>:root { fill: #000; }</style>
          <rect x="10" y="10" width="160" height="160"/>
        </svg>
        """

        let png = try await rasterizer.rasterize(Data(svg.utf8))

        XCTAssertTrue(try decode(png).hasVisiblePixels())
    }

    /// The same SVG in other encodings and with a long prolog, which a byte scan or a sniff of the first bytes
    /// would miss. It matters only that rendering doesn't crash, whatever WebKit makes of the data.
    func testSVGInOtherEncodingsDoesNotCrash() async throws {
        let svg = Self.recursiveFilterSVG
        let prolog = "<!--" + String(repeating: "x", count: 8192) + "-->"
        let utf7 = "+ADw-svg xmlns=+ACI-http://www.w3.org/2000/svg+ACI- filter=+ACI-url(+ACM-f)+ACI-+AD4-+ADw-/svg+AD4-"
        let entity = "<!DOCTYPE svg [<!ENTITY n \"&#102;ilter\">]><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"64\" height=\"64\" &n;=\"url(#f)\"><filter id=\"f\"/></svg>"
        let variants: [Data] = try [
            XCTUnwrap(svg.data(using: .utf16)),
            XCTUnwrap(svg.data(using: .utf16LittleEndian)),
            XCTUnwrap(svg.data(using: .utf16BigEndian)),
            Data((prolog + svg).utf8),
            Data(utf7.utf8),
            Data(entity.utf8)
        ]

        for data in variants {
            _ = try? await rasterizer.rasterize(data)
        }
    }

    func testThrowsForDataThatIsNotAnImage() async {
        do {
            _ = try await rasterizer.rasterize(Data("not an image".utf8))
            XCTFail("Expected an error")
        } catch {}
    }

    func testThrowsForDataLargerThanTheLimit() async {
        let data = Data(Self.svg(width: 16, height: 16).utf8) + Data(repeating: UInt8(ascii: " "), count: FaviconRasterizer.maxDataSize)
        do {
            _ = try await rasterizer.rasterize(data)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? FaviconRasterizer.RasterizationError, .dataTooLarge)
        }
    }

    func testConcurrentCallsAreAllRasterized() async throws {
        let data = Data(Self.recursiveFilterSVG.utf8)

        async let first = rasterizer.rasterize(data)
        async let second = rasterizer.rasterize(data)
        async let third = rasterizer.rasterize(data)
        let results = try await [first, second, third]

        XCTAssertTrue(try results.allSatisfy { try decode($0).hasVisiblePixels() })
    }

    // MARK: - Failures

    func testHardTimeoutThrowsDiscardsTheWebViewAndTheNextCallRecovers() async throws {
        rasterizer.hardTimeout = 0.001
        do {
            _ = try await rasterizer.rasterize(Data(Self.recursiveFilterSVG.utf8))
            XCTFail("Expected a timeout")
        } catch {
            XCTAssertEqual(error as? FaviconRasterizer.RasterizationError, .timedOut)
        }
        XCTAssertFalse(rasterizer.hasWebView)

        rasterizer.hardTimeout = FaviconRasterizer.defaultHardTimeout
        let png = try await rasterizer.rasterize(Data(Self.recursiveFilterSVG.utf8))

        XCTAssertTrue(try decode(png).hasVisiblePixels())
    }

    func testDecodeFailureKeepsTheWebView() async throws {
        _ = try? await rasterizer.rasterize(Data("not an image".utf8))

        XCTAssertTrue(rasterizer.hasWebView)
    }

    func testCancellingTheCallerReleasesItWithoutWaitingForTheWebView() async {
        let data = Data(Self.recursiveFilterSVG.utf8)
        let task = Task { try await rasterizer.rasterize(data) }
        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected a cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testWebViewIsReleasedAfterIdleLifetime() async throws {
        rasterizer.idleLifetime = 0.05
        _ = try await rasterizer.rasterize(Data(Self.svg(width: 16, height: 16).utf8))
        XCTAssertTrue(rasterizer.hasWebView)

        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertFalse(rasterizer.hasWebView)
    }

    func testScriptTimeoutIsReportedAndDiscardsTheWebView() async throws {
        rasterizer.scriptTimeout = 0
        var timedOut = false
        for _ in 0..<20 where !timedOut {
            do {
                _ = try await rasterizer.rasterize(Data(Self.recursiveFilterSVG.utf8))
            } catch {
                timedOut = (error as? FaviconRasterizer.RasterizationError) == .scriptTimedOut
            }
        }
        try XCTSkipUnless(timedOut, "The image always loaded before a zero script timeout fired")
        XCTAssertFalse(rasterizer.hasWebView)

        rasterizer.scriptTimeout = FaviconRasterizer.timeout
        let png = try await rasterizer.rasterize(Data(Self.recursiveFilterSVG.utf8))

        XCTAssertTrue(try decode(png).hasVisiblePixels())
    }

    func testSVGWithOnlyWidthKeepsASaneSize() async throws {
        let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" width="32"><rect width="32" height="16" fill="#000"/></svg>"##

        let png = try await rasterizer.rasterize(Data(svg.utf8))

        let size = try decode(png).size
        XCTAssertTrue((64...256).contains(max(size.width, size.height)))
    }

    // MARK: - Imported favicons

    func testStorableImageDecodesRasterDataAsIs() async throws {
        let png = try await rasterizer.rasterize(Data(Self.svg(width: 16, height: 16).utf8))

        let storable = await rasterizer.storableImage(from: png)
        let image = try XCTUnwrap(storable)

        XCTAssertEqual(image.size, NSSize(width: 64, height: 64))
    }

    func testStorableImageRendersSVGWithWebKitAndCapsItAtMaxStoredSize() async throws {
        let rendered = await rasterizer.storableImage(from: Data(Self.recursiveFilterSVG.utf8))
        let image = try XCTUnwrap(rendered)
        XCTAssertTrue(image.representations.allSatisfy { $0 is NSBitmapImageRep })
        XCTAssertTrue(image.hasVisiblePixels())

        let largeImage = await rasterizer.storableImage(from: Data(Self.svg(width: 1024, height: 512).utf8))
        let large = try XCTUnwrap(largeImage)
        XCTAssertEqual(large.size, NSSize(width: 64, height: 32))
    }

    func testStorableImageIsNilForDataThatIsNotAnImage() async {
        let image = await rasterizer.storableImage(from: Data("not an image".utf8))
        XCTAssertNil(image)
    }

    func testImportedFaviconsAreBuiltPerPageURLAndSVGIsRendered() async throws {
        let png = try await rasterizer.rasterize(Data(Self.svg(width: 16, height: 16).utf8))
        let imported = [
            "https://example.com": [ImportedFavicon(imageData: png), ImportedFavicon(imageData: Data(Self.recursiveFilterSVG.utf8))],
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

    func testImportedFaviconsKeepTheirOrderWhenDecodedConcurrently() async throws {
        let wide = Data(Self.svg(width: 100, height: 50).utf8)
        let tall = Data(Self.svg(width: 50, height: 100).utf8)
        let datas = (0..<12).map { $0.isMultiple(of: 2) ? wide : tall }
        let imported = ["https://example.com": datas.map(ImportedFavicon.init)]

        let faviconsByDocument = await rasterizer.favicons(fromImported: imported)

        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let sizes = try XCTUnwrap(faviconsByDocument[url]).map { $0.image?.size }
        let expected = (0..<12).map { $0.isMultiple(of: 2) ? NSSize(width: 64, height: 32) : NSSize(width: 32, height: 64) }
        XCTAssertEqual(sizes, expected)
    }

    /// Decoding thousands of imported raster favicons must not block the main thread.
    func testImportingManyRasterFaviconsDoesNotBlockTheMainThread() async throws {
        let png = try await rasterizer.rasterize(Data(Self.svg(width: 16, height: 16).utf8))
        let imported = ["https://example.com": (0..<3000).map { _ in ImportedFavicon(imageData: png) }]
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
        XCTAssertLessThan(longestGap, 0.5)
    }

    // MARK: - Helpers

    private struct ImportedFavicon: ImportedFaviconDataProviding {
        let imageData: Data
    }

    private func decode(_ png: Data) throws -> NSImage {
        try XCTUnwrap(NSImage(dataUsingCIImage: png, maxPixelSize: nil))
    }
}
