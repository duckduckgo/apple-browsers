//
//  make-icons.swift
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

// Draws the extension's icons into icons/: a plug on a rounded blue square.
// Run from this directory: swift make-icons.swift

import AppKit

func drawIcon(size: Int) -> Data {
    let pixels = CGFloat(size)
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    do {
        let context = NSGraphicsContext.current!.cgContext
        // Draw top-down, in a 128-point canvas.
        context.translateBy(x: 0, y: pixels)
        context.scaleBy(x: pixels / 128, y: -pixels / 128)
        let tile = NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: 120, height: 120), xRadius: 28, yRadius: 28)
        NSGradient(
            starting: NSColor(srgbRed: 0.33, green: 0.52, blue: 0.98, alpha: 1),
            ending: NSColor(srgbRed: 0.20, green: 0.33, blue: 0.85, alpha: 1)
        )?.draw(in: tile, angle: 90)

        NSColor.white.setFill()
        NSColor.white.setStroke()
        // Prongs.
        NSBezierPath(roundedRect: NSRect(x: 47, y: 22, width: 10, height: 24), xRadius: 5, yRadius: 5).fill()
        NSBezierPath(roundedRect: NSRect(x: 71, y: 22, width: 10, height: 24), xRadius: 5, yRadius: 5).fill()
        // Body.
        let body = NSBezierPath()
        body.move(to: NSPoint(x: 36, y: 44))
        body.line(to: NSPoint(x: 92, y: 44))
        body.line(to: NSPoint(x: 92, y: 62))
        body.curve(to: NSPoint(x: 64, y: 88), controlPoint1: NSPoint(x: 92, y: 78), controlPoint2: NSPoint(x: 80, y: 88))
        body.curve(to: NSPoint(x: 36, y: 62), controlPoint1: NSPoint(x: 48, y: 88), controlPoint2: NSPoint(x: 36, y: 78))
        body.close()
        body.fill()
        // Cable.
        let cable = NSBezierPath()
        cable.lineWidth = 10
        cable.lineCapStyle = .round
        cable.move(to: NSPoint(x: 64, y: 86))
        cable.line(to: NSPoint(x: 64, y: 106))
        cable.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 48, 128] {
    let url = URL(fileURLWithPath: "icons/icon-\(size).png")
    do {
        try drawIcon(size: size).write(to: url)
        print("Wrote \(url.path)")
    } catch {
        print("Could not write \(url.path): \(error)")
        exit(1)
    }
}
