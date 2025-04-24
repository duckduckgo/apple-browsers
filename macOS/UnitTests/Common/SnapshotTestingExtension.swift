//
//  SnapshotTestingExtension.swift
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
import UniformTypeIdentifiers
import SnapshotTesting

extension Snapshotting where Value == NSView, Format == NSImage {
    /// A snapshot strategy for NSView that normalizes image output by rendering into a raw pixel buffer
    /// and re-encoding it without DPI or metadata inconsistencies.
    /// This eliminates false snapshot diffs caused by DPI differences between local and CI environments.
    static func cleanImage(
        precision: Float = 1.0,
        perceptualPrecision: Float = 1.0,
        size: CGSize? = nil
    ) -> Snapshotting<NSView, NSImage> {
        let base = Snapshotting<NSView, NSImage>.image(
            precision: precision,
            perceptualPrecision: perceptualPrecision,
            size: size
        )

        return Snapshotting(pathExtension: base.pathExtension, diffing: base.diffing) { view in
            base.snapshot(view).map { image in
                let width = Int(image.size.width)
                let height = Int(image.size.height)
                let bitsPerComponent = 8
                let bytesPerPixel = 4
                let bitsPerPixel = 32
                let bytesPerRow = width * bytesPerPixel
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))

                // Render into clean buffer
                let buffer = UnsafeMutableRawPointer.allocate(byteCount: height * bytesPerRow, alignment: 1)
                defer { buffer.deallocate() }

                let context = CGContext(
                    data: buffer,
                    width: width,
                    height: height,
                    bitsPerComponent: bitsPerComponent,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo.rawValue
                )!

                let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = graphicsContext
                image.draw(at: .zero, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1)
                NSGraphicsContext.restoreGraphicsState()

                // Use raw buffer to build a clean CGImage
                let provider = CGDataProvider(
                    dataInfo: nil,
                    data: buffer,
                    size: bytesPerRow * height,
                    releaseData: { _, _, _ in }
                )!

                let cleanCGImage = CGImage(
                    width: width,
                    height: height,
                    bitsPerComponent: bitsPerComponent,
                    bitsPerPixel: bitsPerPixel,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo,
                    provider: provider,
                    decode: nil,
                    shouldInterpolate: true,
                    intent: .defaultIntent
                )!

                // Encode to TIFF (no DPI)
                let mutableData = NSMutableData()
                let destination = CGImageDestinationCreateWithData(
                    mutableData,
                    UTType.tiff.identifier as CFString,
                    1,
                    nil
                )!
                CGImageDestinationAddImage(destination, cleanCGImage, nil)
                CGImageDestinationFinalize(destination)

                return NSImage(data: mutableData as Data)!
            }
        }
    }
}
