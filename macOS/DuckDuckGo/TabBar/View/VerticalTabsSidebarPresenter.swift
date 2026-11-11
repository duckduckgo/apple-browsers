//
//  VerticalTabsSidebarPresenter.swift
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

/// Puts the vertical tabs sidebar into a window and lays it out, keeping it apart from the window's horizontal layout.
/// Its views, tracking areas and constraints exist only between `install()` and `uninstall()`.
@MainActor
final class VerticalTabsSidebarPresenter {
    enum Layout {
        /// The sidebar sits beside the toolbar and the page.
        case docked
        /// The sidebar is hidden until the mouse reaches the window's left edge.
        case collapsed
        /// The collapsed sidebar shown over the page while the mouse is on it.
        case peeking
    }

    private enum Constants {
        static let revealEdgeWidth: CGFloat = 6
        static let peekingShadowRadius: CGFloat = 16
        static let animationDuration: TimeInterval = 0.2
    }

    private(set) var layout: Layout = .docked

    private let mainView: MainView
    private weak var parentViewController: NSViewController?
    private let sidebarViewController: VerticalTabsViewController
    private let themeManager: ThemeManager
    private let containerView = NSView()
    private let revealEdgeView = VerticalTabsHoverDetectionView(assumesMouseInside: false)
    private let peekingHoverView = VerticalTabsHoverDetectionView(assumesMouseInside: true)
    private var contentLeadingConstraintsToSidebar: [NSLayoutConstraint] = []
    private var sidebarShownConstraint: NSLayoutConstraint?
    private var sidebarHiddenConstraint: NSLayoutConstraint?

    init(
        mainView: MainView,
        parentViewController: NSViewController,
        tabCollectionViewModel: TabCollectionViewModel,
        aiChatCoordinator: AIChatCoordinating?,
        themeManager: ThemeManager = NSApp.delegateTyped.themeManager
    ) {
        self.mainView = mainView
        self.parentViewController = parentViewController
        self.themeManager = themeManager
        self.sidebarViewController = VerticalTabsViewController(
            tabCollectionViewModel: tabCollectionViewModel,
            aiChatCoordinator: aiChatCoordinator,
            themeManager: themeManager
        )
    }

    func install() {
        for view in [containerView, revealEdgeView, peekingHoverView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        mainView.addSubview(containerView, positioned: .above, relativeTo: mainView.navigationBarContainerView)
        mainView.addSubview(revealEdgeView, positioned: .above, relativeTo: containerView)
        mainView.addSubview(peekingHoverView, positioned: .above, relativeTo: revealEdgeView)
        parentViewController?.addAndLayoutChild(sidebarViewController, into: containerView)

        revealEdgeView.onMouseEntered = { [weak self] in
            guard self?.layout == .collapsed else { return }
            self?.setLayout(.peeking)
        }
        peekingHoverView.onMouseExited = { [weak self] in
            guard self?.layout == .peeking else { return }
            self?.setLayout(.collapsed)
        }

        let sidebarShownConstraint = containerView.leadingAnchor.constraint(equalTo: mainView.leadingAnchor)
        self.sidebarShownConstraint = sidebarShownConstraint
        sidebarHiddenConstraint = containerView.trailingAnchor.constraint(equalTo: mainView.leadingAnchor)
        contentLeadingConstraintsToSidebar = mainView.contentLeadingConstraints.compactMap {
            ($0.firstItem as? NSView)?.leadingAnchor.constraint(equalTo: containerView.trailingAnchor)
        }

        NSLayoutConstraint.deactivate(mainView.contentLeadingConstraints)
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: mainView.navigationBarContainerView.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: mainView.bottomAnchor),
            sidebarShownConstraint,

            revealEdgeView.topAnchor.constraint(equalTo: mainView.navigationBarContainerView.topAnchor),
            revealEdgeView.bottomAnchor.constraint(equalTo: mainView.bottomAnchor),
            revealEdgeView.leadingAnchor.constraint(equalTo: mainView.leadingAnchor),
            revealEdgeView.widthAnchor.constraint(equalToConstant: Constants.revealEdgeWidth),

            peekingHoverView.topAnchor.constraint(equalTo: containerView.topAnchor),
            peekingHoverView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            peekingHoverView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            peekingHoverView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ] + contentLeadingConstraintsToSidebar)
    }

    func uninstall() {
        NSLayoutConstraint.deactivate(contentLeadingConstraintsToSidebar)
        NSLayoutConstraint.activate(mainView.contentLeadingConstraints)
        sidebarViewController.removeCompletely()
        for view in [containerView, revealEdgeView, peekingHoverView] {
            view.removeFromSuperview()
        }
    }

    func toggle() {
        setLayout(layout == .docked ? .collapsed : .docked)
    }

    private func setLayout(_ newLayout: Layout) {
        guard layout != newLayout else { return }
        layout = newLayout
        sidebarViewController.isFloating = layout == .peeking
        if layout == .peeking {
            containerView.shadow = peekingShadow()
        }

        // Collapsed, the sidebar waits just off the window's left edge, so it can slide back in.
        let isSidebarOnScreen = layout != .collapsed
        if let sidebarShownConstraint, let sidebarHiddenConstraint {
            NSLayoutConstraint.deactivate([isSidebarOnScreen ? sidebarHiddenConstraint : sidebarShownConstraint])
            NSLayoutConstraint.activate([isSidebarOnScreen ? sidebarShownConstraint : sidebarHiddenConstraint])
        }

        // Peeking, the sidebar floats over the page instead of pushing it aside.
        let isContentBesideSidebar = layout != .peeking
        NSLayoutConstraint.deactivate(isContentBesideSidebar ? mainView.contentLeadingConstraints : contentLeadingConstraintsToSidebar)
        NSLayoutConstraint.activate(isContentBesideSidebar ? contentLeadingConstraintsToSidebar : mainView.contentLeadingConstraints)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Constants.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            mainView.layoutSubtreeIfNeeded()
        }, completionHandler: { [weak self] in
            guard let self, layout != .peeking else { return }
            containerView.shadow = nil
        })
    }

    private func peekingShadow() -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = themeManager.theme.palette.shadowSecondary
        shadow.shadowBlurRadius = Constants.peekingShadowRadius
        return shadow
    }
}

/// Reports the mouse entering and leaving it, and lets clicks through to the views beneath.
private final class VerticalTabsHoverDetectionView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    private let assumesMouseInside: Bool
    private var trackingArea: NSTrackingArea?

    init(assumesMouseInside: Bool) {
        self.assumesMouseInside = assumesMouseInside
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("VerticalTabsHoverDetectionView: Bad initializer")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        if assumesMouseInside {
            options.insert(.assumeInside)
        }
        let trackingArea = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}
