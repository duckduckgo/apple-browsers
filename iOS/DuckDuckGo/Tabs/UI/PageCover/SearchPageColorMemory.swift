//
//  SearchPageColorMemory.swift
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

import UIKit

/// Remembers a results page's background colour, per appearance.
///
/// Read from the rendered preview's side margins: results and modules are cards on top of the page
/// background, and that background is what paints first.
///
/// Dark mode is fixed instead: there, organic results sit on a lighter band (#222222) that fills most of
/// the margins, while the header and modules paint on #181818 first.
@MainActor
final class SearchPageColorMemory {

    static let darkPageBackground = UIColor(red: 0x18 / 255, green: 0x18 / 255, blue: 0x18 / 255, alpha: 1)

    private var colors: [UIUserInterfaceStyle: UIColor] = [:]

    func color(for style: UIUserInterfaceStyle) -> UIColor? {
        style == .dark ? Self.darkPageBackground : colors[style]
    }

    func needsSample(for style: UIUserInterfaceStyle) -> Bool {
        style != .dark && colors[style] == nil
    }

    func record(preview: UIImage, for style: UIUserInterfaceStyle) {
        guard style != .dark, let image = preview.cgImage, let color = Self.marginColor(in: image) else { return }
        colors[style] = color
    }

    private enum Sampling {
        /// About 9pt per column on a phone, so the outer columns sit inside the page margins.
        static let width = 48
        static let height = 96
        /// Ignore the top slice, which holds the search header.
        static let topInsetFraction = 0.15
        static let marginColumns = [0, width - 1]
    }

    /// Most common colour down both side margins of a downscaled copy; exact matches, since backgrounds are flat.
    nonisolated static func marginColor(in image: CGImage) -> UIColor? {
        let width = Sampling.width
        let height = Sampling.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        // Bitmap memory starts at the image's top row.
        let firstSampledRow = Int(Double(height) * Sampling.topInsetFraction)
        var counts: [UInt32: Int] = [:]
        for row in firstSampledRow..<height {
            for column in Sampling.marginColumns {
                let offset = (row * width + column) * 4
                guard pixels[offset + 3] == 255 else { continue }
                let key = UInt32(pixels[offset]) << 16 | UInt32(pixels[offset + 1]) << 8 | UInt32(pixels[offset + 2])
                counts[key, default: 0] += 1
            }
        }
        guard let (key, _) = counts.max(by: { $0.value < $1.value }) else { return nil }
        return UIColor(red: CGFloat((key >> 16) & 0xFF) / 255,
                       green: CGFloat((key >> 8) & 0xFF) / 255,
                       blue: CGFloat(key & 0xFF) / 255,
                       alpha: 1)
    }
}
