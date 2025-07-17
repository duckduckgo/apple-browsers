//
//  NSAttributedTextView.swift
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
import SwiftUI

public struct NSAttributedTextView: NSViewRepresentable {
    let attributedString: NSAttributedString

    public init(attributedString: NSAttributedString) {
        self.attributedString = attributedString
    }

    public func makeNSView(context: Context) -> SelfSizingTextView {
        let textView = SelfSizingTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        textView.isAutomaticLinkDetectionEnabled = false
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isRichText = true
        textView.usesFontPanel = false
        textView.usesRuler = false

        textView.delegate = context.coordinator

        return textView
    }

    public func updateNSView(_ textView: SelfSizingTextView, context: Context) {
        textView.textStorage?.setAttributedString(attributedString)
        textView.invalidateIntrinsicContentSize()
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public class Coordinator: NSObject, NSTextViewDelegate {
        public func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL {
                NSWorkspace.shared.open(url)
                return true
            }
            return false
        }
    }
}

public class SelfSizingTextView: NSTextView {

    public override var intrinsicContentSize: NSSize {
        // Use the current bounds width or a reasonable default
        let constrainedWidth = bounds.width > 0 ? bounds.width : 300

        // Calculate height for the given width
        let height = heightForWidth(constrainedWidth)

        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    private func heightForWidth(_ width: CGFloat) -> CGFloat {
        guard let textContainer = textContainer,
              let layoutManager = layoutManager else {
            return 0
        }

        // Save current container size
        let originalSize = textContainer.containerSize

        // Set container to use specified width with unlimited height
        textContainer.containerSize = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)

        // Force layout and get used rect
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)

        // Restore original container size
        textContainer.containerSize = originalSize

        return max(usedRect.height, 1)
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // Invalidate intrinsic content size when frame changes
        // This ensures proper height recalculation when width changes
        invalidateIntrinsicContentSize()
    }
}
