//
//  FaviconImageView.swift
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

/// This class was implemented to work around a macOS Tahoe Regression, that resulted in blurry images in SD.
/// Will run a custom `draw` implementation, when the Window has an SD backingScaleFactor, and we're on macOS 26 or later.
///
/// Ref.: https://app.asana.com/1/137249556945/project/1201048563534612/task/1211961221757398/comment/1212149100646594?focus=true
///
final class FaviconImageView: NSImageView {

    override func draw(_ dirtyRect: NSRect) {
        guard requiresCustomDrawing, let image, let context = NSGraphicsContext.current else {
            super.draw(dirtyRect)
            return
        }

        drawImage(image: image, in: context, destinationRect: bounds)
    }

    private func drawImage(image: NSImage, in context: NSGraphicsContext, destinationRect: NSRect) {
        context.saveGraphicsState()
        context.shouldAntialias = false

        image.draw(in: destinationRect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: [
            .interpolation: NSImageInterpolation.none
        ])

        context.restoreGraphicsState()
    }

    private var requiresCustomDrawing: Bool {
        isRunningMacOsTahoeOrLater && isStandardDefinitionWindow
    }

    private var isStandardDefinitionWindow: Bool {
        guard let backingScaleFactor = window?.backingScaleFactor else {
            return false
        }

        return backingScaleFactor < 2
    }

    private var isRunningMacOsTahoeOrLater: Bool {
        if #available(macOS 26.0, *) {
            return true
        }

        return false
    }
}
