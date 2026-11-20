//
//  TabDragPreview.swift
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
import DesignResourcesKit

@MainActor
enum TabDragPreview {
    private static let width: CGFloat = 228
    private static let maximumPageHeight: CGFloat = 168

    static func nativePageSnapshot(of layer: CALayer, backingScale: CGFloat) -> NSImage? {
        let bounds = layer.bounds
        guard !bounds.isEmpty else { return nil }
        let pageHeight = min(maximumPageHeight, width * bounds.height / bounds.width)
        let scale = min(max(backingScale, 1), 2)
        let pixelsWide = Int(ceil(width * scale))
        let pixelsHigh = Int(ceil(pageHeight * scale))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelsWide, height: pixelsHigh, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        // Render the top of the page directly into the thumbnail, including on Retina displays.
        let pageScale = CGFloat(pixelsWide) / bounds.width
        context.translateBy(x: 0, y: CGFloat(pixelsHigh))
        context.scaleBy(x: pageScale, y: -pageScale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        layer.render(in: context)
        guard let image = context.makeImage() else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: width, height: pageHeight))
    }

    static func makeImage(for tab: any TabBarViewModel, snapshot: NSImage? = nil) -> NSImage {
        let header = URLDragPreviewProvider(text: tab.title,
                                            favicon: tab.favicon,
                                            backgroundColor: NSColor(designSystemColor: .surfacePrimary),
                                            textColor: NSColor(designSystemColor: .textPrimary),
                                            width: width).createPreview()
        header.setFrameSize(header.fittingSize)
        header.layoutSubtreeIfNeeded()
        let headerImage = header.imageRepresentation()
        guard let preview = tab as? any Previewable, preview.shouldShowPreview,
              let snapshot = snapshot ?? preview.snapshot, snapshot.size.width > 0, snapshot.size.height > 0 else { return headerImage }

        let scale = width / snapshot.size.width
        let pageHeight = min(maximumPageHeight, snapshot.size.height * scale)
        let sourceHeight = pageHeight / scale
        let source = NSRect(x: 0, y: snapshot.size.height - sourceHeight, width: snapshot.size.width, height: sourceHeight)
        let size = NSSize(width: width, height: pageHeight + headerImage.size.height)
        return NSImage(size: size, flipped: false) { bounds in
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).addClip()
            NSColor(designSystemColor: .surfacePrimary).setFill()
            bounds.fill()
            NSGraphicsContext.current?.imageInterpolation = .high
            snapshot.draw(in: NSRect(x: 0, y: 0, width: bounds.width, height: pageHeight), from: source, operation: .sourceOver, fraction: 1)
            headerImage.draw(at: NSPoint(x: 0, y: pageHeight), from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }
}
