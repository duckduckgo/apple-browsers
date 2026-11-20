//
//  FaviconTests.swift
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

import AppKit
import Foundation
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class FaviconTests: XCTestCase {

    func testThatSmallerReturnsSmallerSizeCategory() {
        XCTAssertEqual(Favicon.SizeCategory.noImage.smaller, nil)
        XCTAssertEqual(Favicon.SizeCategory.tiny.smaller, .noImage)
        XCTAssertEqual(Favicon.SizeCategory.small.smaller, .tiny)
        XCTAssertEqual(Favicon.SizeCategory.medium.smaller, .small)
        XCTAssertEqual(Favicon.SizeCategory.large.smaller, .medium)
        XCTAssertEqual(Favicon.SizeCategory.huge.smaller, .large)
    }

    // MARK: - Favicon downscaling tests (F4)

    func testDownscaleCapsLongestSideAtMaxPixelSize() throws {
        let data = try makePNGData(pixelsWide: 1024, pixelsHigh: 1024)
        let image = try XCTUnwrap(NSImage(dataUsingCIImage: data, maxPixelSize: 64))
        let rep = try bitmapRep(of: image)
        XCTAssertEqual(rep.pixelsWide, 64)
        XCTAssertEqual(rep.pixelsHigh, 64)
    }

    func testDownscalePreservesAspectRatio() throws {
        let data = try makePNGData(pixelsWide: 1024, pixelsHigh: 512)
        let image = try XCTUnwrap(NSImage(dataUsingCIImage: data, maxPixelSize: 64))
        let rep = try bitmapRep(of: image)
        XCTAssertEqual(max(rep.pixelsWide, rep.pixelsHigh), 64)
        XCTAssertEqual(rep.pixelsWide, 64)
        XCTAssertEqual(rep.pixelsHigh, 32)
    }

    func testDownscaleDoesNotUpscaleSmallImage() throws {
        let data = try makePNGData(pixelsWide: 16, pixelsHigh: 16)
        let image = try XCTUnwrap(NSImage(dataUsingCIImage: data, maxPixelSize: 64))
        let rep = try bitmapRep(of: image)
        XCTAssertEqual(rep.pixelsWide, 16)
        XCTAssertEqual(rep.pixelsHigh, 16)
    }

    func testNilMaxPixelSizeKeepsOriginalResolution() throws {
        let data = try makePNGData(pixelsWide: 1024, pixelsHigh: 1024)
        let image = try XCTUnwrap(NSImage(dataUsingCIImage: data, maxPixelSize: nil))
        let rep = try bitmapRep(of: image)
        XCTAssertEqual(rep.pixelsWide, 1024)
        XCTAssertEqual(rep.pixelsHigh, 1024)
    }

    // MARK: - Transparent SVG detection

    func testSVGStyledOnlyWithCSSHasNoVisiblePixels() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="180" height="180" viewBox="0 0 180 180" fill="none">
          <style>:root { fill: #000; }</style>
          <rect x="10" y="10" width="160" height="160"/>
        </svg>
        """
        let image = try XCTUnwrap(NSImage(dataUsingCIImage: Data(svg.utf8), maxPixelSize: nil))
        XCTAssertFalse(image.hasVisiblePixels())
    }

    func testSVGWithFillAttributeHasVisiblePixels() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="180" height="180" viewBox="0 0 180 180">
          <rect x="10" y="10" width="160" height="160" fill="#000"/>
        </svg>
        """
        let image = try XCTUnwrap(NSImage(dataUsingCIImage: Data(svg.utf8), maxPixelSize: nil))
        XCTAssertTrue(image.hasVisiblePixels())
    }

    func testSVGDataIsRasterizedToBitmapRepresentation() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="180" height="180" viewBox="0 0 180 180">
          <rect x="10" y="10" width="160" height="160" fill="#000"/>
        </svg>
        """
        let image = try XCTUnwrap(NSImage(dataUsingCIImage: Data(svg.utf8), maxPixelSize: nil))
        XCTAssertFalse(image.representations.isEmpty)
        XCTAssertTrue(image.representations.allSatisfy { $0 is NSBitmapImageRep })
        XCTAssertEqual(image.size, NSSize(width: 180, height: 180))
        XCTAssertTrue(image.hasVisiblePixels())
    }

    func testSVGDataIsDownscaledToMaxPixelSize() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="180" height="90" viewBox="0 0 180 90">
          <rect width="180" height="90" fill="#000"/>
        </svg>
        """
        let image = try XCTUnwrap(NSImage(dataUsingCIImage: Data(svg.utf8), maxPixelSize: 64))
        XCTAssertEqual(image.size, NSSize(width: 64, height: 32))
        XCTAssertTrue(image.representations.allSatisfy { $0 is NSBitmapImageRep })
    }

    /// CoreSVG recurses infinitely (stack overflow, `EXC_BAD_ACCESS` in `SVGFilter::draw`) when the root `<svg>`
    /// and one of its children reference the same filter. Such SVGs must be rejected, not rendered.
    func testSVGWithRecursiveFilterIsRejectedInsteadOfCrashing() {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64" filter="url(#f)">
          <filter id="f"><feOffset/></filter>
          <rect width="20" height="20" filter="url(#f)"/>
        </svg>
        """
        XCTAssertNil(NSImage(dataUsingCIImage: Data(svg.utf8), maxPixelSize: nil))
        XCTAssertNil(NSImage(dataUsingCIImage: Data(svg.utf8), maxPixelSize: 64))
    }

    func testSVGWithFilterIsDetected() {
        XCTAssertTrue(Data("<svg><filter id=\"f\"/></svg>".utf8).isUnsafeSVG)
        XCTAssertTrue(Data("<svg><rect style=\"FILTER: blur(2px)\"/></svg>".utf8).isUnsafeSVG)
        XCTAssertTrue(Data("<svg><rect FILTER=\"url(#f)\"/></svg>".utf8).isUnsafeSVG)
        XCTAssertTrue(Data("<svg><FiLtEr id=\"f\"/></svg>".utf8).isUnsafeSVG)
        XCTAssertFalse(Data("<svg><rect width=\"1\" height=\"1\"/></svg>".utf8).isUnsafeSVG)
        XCTAssertFalse(Data().isUnsafeSVG)
    }

    func testNonSVGDataContainingFilterWordIsNotUnsafe() throws {
        let png = try makePNGData(pixelsWide: 16, pixelsHigh: 16) + Data("filter".utf8)
        XCTAssertFalse(png.isUnsafeSVG)
        XCTAssertNotNil(NSImage(dataUsingCIImage: png, maxPixelSize: nil))
        XCTAssertFalse(Data("plain text with a filter in it".utf8).isUnsafeSVG)
    }

    func testOversizedSVGIsRejectedAndOversizedNonSVGIsNot() {
        let padding = Data(repeating: UInt8(ascii: " "), count: Data.maxSVGFaviconSize)
        let oversizedSVG = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8) + padding
        XCTAssertTrue(oversizedSVG.isUnsafeSVG)
        XCTAssertNil(NSImage(dataUsingCIImage: oversizedSVG, maxPixelSize: nil))

        let oversizedNonSVG = Data(repeating: 0x42, count: Data.maxSVGFaviconSize + 1)
        XCTAssertFalse(oversizedNonSVG.isUnsafeSVG)
    }

    func testOversizedSVGWithLongPrologIsRejected() {
        let prolog = Data("<!--".utf8) + Data(repeating: UInt8(ascii: "x"), count: 2048) + Data("-->".utf8)
        let padding = Data(repeating: UInt8(ascii: " "), count: Data.maxSVGFaviconSize)
        let svg = prolog + Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8) + padding
        XCTAssertTrue(svg.isUnsafeSVG)
    }

    func testSmallSVGIsRasterizedAtMinimumSizeToStaySharp() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
          <rect width="16" height="16" fill="#000"/>
        </svg>
        """
        let capped = try XCTUnwrap(NSImage(dataUsingCIImage: Data(svg.utf8), maxPixelSize: 64))
        XCTAssertEqual(capped.size, NSSize(width: 64, height: 64))
        let uncapped = try XCTUnwrap(NSImage(dataUsingCIImage: Data(svg.utf8), maxPixelSize: nil))
        XCTAssertEqual(uncapped.size, NSSize(width: 64, height: 64))
    }

    func testFullyTransparentBitmapHasNoVisiblePixels() throws {
        let data = try makePNGData(pixelsWide: 16, pixelsHigh: 16)
        let image = try XCTUnwrap(NSImage(dataUsingCIImage: data, maxPixelSize: nil))
        XCTAssertFalse(image.hasVisiblePixels())
    }

    func testIsSVGImageDataDetectsSVGAfterLeadingComment() {
        let svg = "<!-- comment -->\n<?xml version=\"1.0\"?>\n<SVG xmlns=\"http://www.w3.org/2000/svg\"></SVG>"
        XCTAssertTrue(Data(svg.utf8).isSVGImageData)
    }

    func testIsSVGImageDataIsFalseForPNGData() throws {
        let data = try makePNGData(pixelsWide: 16, pixelsHigh: 16)
        XCTAssertFalse(data.isSVGImageData)
    }

    // MARK: - Helpers

    private func makePNGData(pixelsWide: Int, pixelsHigh: Int) throws -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0)!
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    private func bitmapRep(of image: NSImage) throws -> NSBitmapImageRep {
        try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
    }
}
