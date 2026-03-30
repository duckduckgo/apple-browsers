//
//  AIChatImageAttachment.swift
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

import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Represents an image attachment in the AI Chat interface.
public struct AIChatImageAttachment: Identifiable {
    public let id: UUID
    public let fileName: String
    public let fileURL: URL?

    #if os(macOS)
    public let image: NSImage

    public init(id: UUID = UUID(), image: NSImage, fileName: String, fileURL: URL? = nil) {
        self.init(id: id, image: image, fileName: fileName, fileURL: fileURL, skipResize: false)
    }

    /// Public initializer that optionally skips resize.
    /// Used for showing original image as placeholder before background resize completes.
    public init(id: UUID = UUID(), image: NSImage, fileName: String, fileURL: URL? = nil, skipResize: Bool) {
        self.id = id
        self.image = skipResize ? image : Self.resizeIfNeeded(image, maxDimension: 512)
        self.fileName = fileName
        self.fileURL = fileURL
    }

    /// Resizes an image if either dimension exceeds the maximum, maintaining aspect ratio.
    /// Does not upscale images that are already smaller than the maximum dimension.
    /// Uses Core Graphics for efficient resizing.
    /// - Parameters:
    ///   - image: The image to resize
    ///   - maxDimension: Maximum dimension (width or height) in pixels
    /// - Returns: Resized image, or original if no resize needed
    private static func resizeIfNeeded(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size

        // Don't upscale images that are already small enough
        guard size.width > maxDimension || size.height > maxDimension else {
            return image
        }

        // Calculate new size maintaining aspect ratio
        let aspectRatio = size.width / size.height
        let newSize: NSSize
        if size.width > size.height {
            // Landscape or square: constrain width
            newSize = NSSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            // Portrait: constrain height
            newSize = NSSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        // Use Core Graphics for faster resizing
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        let width = Int(newSize.width)
        let height = Int(newSize.height)
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: newSize))

        guard let scaledCGImage = context.makeImage() else {
            return image
        }

        return NSImage(cgImage: scaledCGImage, size: newSize)
    }
    #elseif os(iOS)
    public let image: UIImage

    public init(id: UUID = UUID(), image: UIImage, fileName: String, fileURL: URL? = nil) {
        self.id = id
        self.image = Self.resizeIfNeeded(image, maxDimension: 512)
        self.fileName = fileName
        self.fileURL = fileURL
    }

    private static func resizeIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > maxDimension || size.height > maxDimension else {
            return image
        }

        let aspectRatio = size.width / size.height
        let newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    #endif
}
