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
import Carbon.HIToolbox
import Combine
import SwiftUIExtensions

public final class DefaultBrowserAndDockPromptPopoverViewModel {
    let title: String?
    let message: String
    let image: NSImage
    let buttonText: String
    let buttonAction: () -> Void
    let secondaryButtonText: String?
    let secondaryButtonAction: () -> Void

    public init(title: String?,
                message: String,
                image: NSImage,
                buttonText: String,
                buttonAction: @escaping () -> Void,
                secondaryButtonText: String?,
                secondaryButtonAction: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.image = image
        self.buttonText = buttonText
        self.buttonAction = buttonAction
        self.secondaryButtonText = secondaryButtonText
        self.secondaryButtonAction = secondaryButtonAction
    }
}

struct DefaultBrowserAndDockPromptPopoverView: View {
    private let viewModel: DefaultBrowserAndDockPromptPopoverViewModel

    init(viewModel: DefaultBrowserAndDockPromptPopoverViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack {
            Image(nsImage: viewModel.image)
                .padding(.bottom, 8)

            VStack(alignment: .center, spacing: 12) {
                if let title = viewModel.title {
                    Text(title)
                        .font(Font.system(size: 15))
                        .fontWeight(.bold)
                        .frame(minHeight: 22)
                        .lineLimit(nil)
                        .multilineTextAlignment(.center)
                        .fixMultilineScrollableText()
                }

                Text(viewModel.message)
                    .font(Font.system(size: 13))
                    .frame(minHeight: 22)
                    .lineLimit(nil)
                    .multilineTextAlignment(.center)
                    .fixMultilineScrollableText()
            }
            .frame(width: 300, alignment: .leading)
            .padding(.bottom, 20)

            HStack(spacing: 8) {
                if let secondaryButtonText = viewModel.secondaryButtonText {
                    Button {
                        self.viewModel.secondaryButtonAction()
                    } label: {
                        Text(secondaryButtonText)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(StandardButtonStyle())
                }

                Button {
                    self.viewModel.buttonAction()
                } label: {
                    Text(viewModel.buttonText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(DefaultActionButtonStyle(enabled: true, shouldBeFixedVertical: false))
            }
            .frame(height: 28)
            .frame(maxWidth: .infinity)
        }
        .frame(width: 344)
        .padding([.leading, .trailing, .bottom], 16)
        .padding(.top, 20)
    }
}

final class DefaultBrowserAndDockPromptPopover: NSPopover {
    private static let topInset: CGFloat = 22
    private var eventMonitor: Any?

    init(viewController: NSHostingController<DefaultBrowserAndDockPromptPopoverView>) {
        super.init()

        shouldHideAnchor = true
        behavior = .applicationDefined
        contentViewController = viewController
    }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            self.performClose(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("DefaultBrowserAndDockPromptPopover: Bad initializer")
    }

    deinit {
#if DEBUG
        // Check that our content view controller deallocates
        contentViewController?.ensureObjectDeallocated(after: 1.0, do: .interrupt)
#endif
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
