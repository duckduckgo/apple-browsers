//
//  AIChatMentionPickerPanel.swift
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

/// A borderless, non-activating panel that hosts the `@`-mention tab picker above the
/// omnibar's prompt input.
///
/// Why a non-activating panel: the user is typing into the omnibar's `NSTextView` while
/// this picker is on screen, and the text view must stay first responder so keystrokes
/// keep flowing into it. `.nonactivatingPanel` (plus `canBecomeKey == false`) is the
/// AppKit recipe for "transient overlay that takes clicks but doesn't steal focus".
///
/// Why `NSPanel` (not `NSPopover`): `NSPopover` has its own arrow and `behavior` model;
/// it also imposes its own focus management that fights `.nonactivatingPanel`. A bare
/// panel anchored manually gives us full control over positioning and dismissal — the
/// coordinator (`AIChatMentionPickerCoordinator`) owns that lifecycle.
final class AIChatMentionPickerPanel: NSPanel {

    init(contentViewController: NSViewController) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        // Floating panels stay above their parent window when added as a child. We rely on
        // `addChildWindow(_:ordered:)` from the coordinator to keep this panel attached to
        // the omnibar window so it travels with omnibar moves/resizes and is destroyed
        // when the omnibar window goes away.
        isFloatingPanel = true
        // The picker is informational — it shouldn't be hidden when the user clicks on a
        // different window. Dismissal is driven explicitly by the coordinator based on the
        // token state, not by app-level activation changes.
        hidesOnDeactivate = false
        hasShadow = true
        // The rounded chrome is painted by the content view's CALayer, so the window itself
        // is transparent. Without this, AppKit would paint a default rectangular background
        // behind our rounded corners.
        backgroundColor = .clear
        isOpaque = false
        // Panels default to releasing themselves on close, which would break the coordinator's
        // lifecycle (we want to reuse the same panel across multiple show/hide cycles for the
        // same omnibar session).
        isReleasedWhenClosed = false
        // `mouseMoved:` events are only dispatched to the window when this flag is on; we
        // need them so the picker's centralized hover tracking can update the highlighted
        // row as the cursor moves over the list.
        acceptsMouseMovedEvents = true

        self.contentViewController = contentViewController
        setContentSize(contentViewController.view.fittingSize)
    }

    /// Never becomes key. The omnibar text view stays first responder so the user keeps
    /// typing without interruption.
    override var canBecomeKey: Bool { false }
    /// Never becomes main, for the same reason.
    override var canBecomeMain: Bool { false }
}
