//
//  DefaultBrowserAndDockPromptPopover.swift
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

import SwiftUI
import SwiftUIExtensions

final class DefaultBrowserAndDockPromptPopover: NSPopover {
    private static let topInset: CGFloat = 22

    init(viewController: NSHostingController<PopoverMessageView>) {
        super.init()

        shouldHideAnchor = true
        behavior = .semitransient
        contentViewController = viewController
    }

    required init?(coder: NSCoder) {
        fatalError("DefaultBrowserAndDockPromptPopover: Bad initializer")
    }

    @objc override func adjustFrame(_ frame: NSRect) -> NSRect {
        guard let positioningView, let mainWindow, let screenFrame = mainWindow.screen?.visibleFrame else { return frame }
        let offset: CGPoint = .zero
        let windowPoint = positioningView.convert(NSPoint(x: offset.x, y: (positioningView.isFlipped ? positioningView.bounds.minY : positioningView.bounds.maxY) + offset.y), to: nil)
        let screenPoint = mainWindow.convertPoint(toScreen: windowPoint)
        var frame = frame

        let positioningViewCenter = positioningView.convert(positioningView.bounds.center, to: nil)
        let positioningViewScreenCenter = mainWindow.convertPoint(toScreen: positioningViewCenter)
        // Adjusts the popover to be always centered in the parent view
        frame.origin.x = positioningViewScreenCenter.x - (frame.size.width / 2)
        // Adjusts the popover to be shown some pixels below the parent view
        frame.origin.y = min(max(screenFrame.minY, screenPoint.y - frame.size.height - DefaultBrowserAndDockPromptPopover.topInset), screenFrame.maxY)

        return frame
    }
}
