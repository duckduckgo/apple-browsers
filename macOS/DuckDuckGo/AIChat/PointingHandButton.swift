//
//  PointingHandButton.swift
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

/// `NSButton` that paints a pointing-hand cursor when the mouse is over it.
///
/// Used for the × remove buttons on attachment cards in the duck.ai omnibar carousel. The
/// carousel sits in the same panel area as the omnibar's text view, whose I-beam cursor would
/// otherwise bleed through during hover. The combination of a `resetCursorRects` rect AND
/// active `NSCursor.pointingHand.set()` on mouse-enter/move kills that flicker.
///
/// Lives next to its only consumers in the AIChat folder rather than in `Common/View/AppKit/`
/// because the active-cursor-set behavior is specific to the carousel (regular AppKit buttons
/// in the rest of the app don't need to override AppKit's automatic cursor management — only
/// buttons near a `NSTextView` do).
final class PointingHandButton: NSButton {

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        // `.inVisibleRect` so the area follows scroll/resize without manual book-keeping;
        // `.activeInKeyWindow` mirrors the surrounding card views' tracking areas.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        // Hand control back to the surrounding card view's tracking area, which sets `.arrow`.
        // Without this, the pointing-hand cursor would linger briefly until the next move.
        NSCursor.arrow.set()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func layout() {
        super.layout()
        // Re-register so the rect tracks the button's resolved size after auto-layout.
        resetCursorRects()
    }
}
