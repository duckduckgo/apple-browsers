//
//  VerticalTabsViewController.swift
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
import SwiftUI

final class VerticalTabsViewController: NSViewController {
    private enum Constants {
        static let defaultWidth: CGFloat = 240
        static let minimumWidth: CGFloat = 80
        static let maximumWidth: CGFloat = 500
        static let resizeHandleWidth: CGFloat = 6
    }

    private let viewModel: VerticalTabsViewModel
    private let themeManager: ThemeManager
    private var widthConstraint: NSLayoutConstraint?
    private var widthAtResizeStart: CGFloat = 0

    init(
        tabCollectionViewModel: TabCollectionViewModel,
        aiChatCoordinator: AIChatCoordinating?,
        tabDragAndDropManager: TabDragAndDropManager = NSApp.delegateTyped.tabDragAndDropManager,
        themeManager: ThemeManager = NSApp.delegateTyped.themeManager
    ) {
        self.viewModel = VerticalTabsViewModel(tabCollectionViewModel: tabCollectionViewModel,
                                               aiChatCoordinator: aiChatCoordinator,
                                               tabDragAndDropManager: tabDragAndDropManager)
        self.themeManager = themeManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("VerticalTabsViewController: Bad initializer")
    }

    override func loadView() {
        let view = NSView()
        let hostingView = NSHostingView(rootView: VerticalTabsView(model: viewModel, themeManager: themeManager))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        let resizeHandle = VerticalTabsResizeHandle(
            onDragStart: { [weak self] in
                self?.startResizing()
            },
            onDrag: { [weak self] distance in
                self?.resize(by: distance)
            }
        )
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(hostingView)
        view.addSubview(resizeHandle)

        // Gives way to the web view's minimum width when the window is too narrow, but not to
        // the hosting view, which would otherwise widen the sidebar to fit the longest tab title.
        let widthConstraint = view.widthAnchor.constraint(equalToConstant: Constants.defaultWidth)
        widthConstraint.priority = .init(NSLayoutConstraint.Priority.defaultHigh.rawValue + 1)
        self.widthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            widthConstraint,
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: Constants.minimumWidth),

            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            resizeHandle.topAnchor.constraint(equalTo: view.topAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            resizeHandle.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: Constants.resizeHandleWidth),
        ])

        self.view = view
    }

    private func startResizing() {
        widthAtResizeStart = view.frame.width
    }

    private func resize(by distance: CGFloat) {
        widthConstraint?.constant = min(max(widthAtResizeStart + distance, Constants.minimumWidth), Constants.maximumWidth)
    }
}

private final class VerticalTabsResizeHandle: NSView {
    private let onDragStart: () -> Void
    private let onDrag: (CGFloat) -> Void
    private var dragStartX: CGFloat = 0

    init(onDragStart: @escaping () -> Void, onDrag: @escaping (CGFloat) -> Void) {
        self.onDragStart = onDragStart
        self.onDrag = onDrag
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("VerticalTabsResizeHandle: Bad initializer")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartX = event.locationInWindow.x
        onDragStart()
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag(event.locationInWindow.x - dragStartX)
    }
}
