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
