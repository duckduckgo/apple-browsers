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
import Combine

/// Puts the vertical tabs sidebar into a window and lays it out, keeping it apart from the window's horizontal layout.
/// Its views, tracking areas and constraints exist only between `install()` and `uninstall()`.
@MainActor
final class VerticalTabsSidebarPresenter {
    enum Layout {
        /// Fullscreen hides the tab bar and suppresses edge reveal.
        case hidden
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

    @Published private(set) var layout: Layout = .collapsed

    /// A popover attached to the peeking sidebar would disappear when the pointer moves onto it.
    var dockedNewTabButtonAnchor: NSView? {
        layout == .docked ? sidebarViewController.newTabButtonAnchor : nil
    }

    private var prefersDocked = true
    private var canDock = false

    var toggleWillHideSidebar: Bool {
        layout == .docked || (!canDock && layout == .peeking)
    }

    private var preferredLayout: Layout {
        prefersDocked && canDock ? .docked : .collapsed
    }

    private let mainView: MainView
    private weak var parentViewController: NSViewController?
    private let sidebarViewController: VerticalTabsViewController
    private let themeManager: ThemeManager
    private var sidebarView: NSView { sidebarViewController.view }
    private let revealEdgeView = VerticalTabsHoverDetectionView(assumesMouseInside: false)
    private let peekingHoverView = VerticalTabsHoverDetectionView(assumesMouseInside: true)
    private var contentLeadingConstraintsToSidebar: [NSLayoutConstraint] = []
    private var sidebarShownConstraint: NSLayoutConstraint?
    private var sidebarHiddenConstraint: NSLayoutConstraint?

    init(
        mainView: MainView,
        parentViewController: NSViewController,
        viewModel: VerticalTabsViewModel,
        themeManager: ThemeManager
    ) {
        self.mainView = mainView
        self.parentViewController = parentViewController
        self.themeManager = themeManager
        self.sidebarViewController = VerticalTabsViewController(viewModel: viewModel, themeManager: themeManager)
    }

    func install(hiddenInFullScreen: Bool) {
        parentViewController?.addChild(sidebarViewController)
        for view in [sidebarView, revealEdgeView, peekingHoverView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        mainView.addSubview(sidebarView, positioned: .above, relativeTo: mainView.navigationBarContainerView)
        mainView.addSubview(revealEdgeView, positioned: .above, relativeTo: sidebarView)
        mainView.addSubview(peekingHoverView, positioned: .above, relativeTo: revealEdgeView)

        revealEdgeView.onMouseEntered = { [weak self] in
            guard self?.layout == .collapsed else { return }
            self?.setLayout(.peeking)
        }
        peekingHoverView.onMouseExited = { [weak self] in
            guard let self, layout == .peeking, !sidebarViewController.dragSession.isDragging else { return }
            setLayout(.collapsed)
        }
        sidebarViewController.dragSession.onDragEnded = { [weak self] in
            guard let self, layout == .peeking, !sidebarViewController.dragSession.isPointerOverSidebar else { return }
            setLayout(.collapsed)
        }

        let sidebarShownConstraint = sidebarView.leadingAnchor.constraint(equalTo: mainView.leadingAnchor)
        self.sidebarShownConstraint = sidebarShownConstraint
        let sidebarHiddenConstraint = sidebarView.trailingAnchor.constraint(equalTo: mainView.leadingAnchor)
        self.sidebarHiddenConstraint = sidebarHiddenConstraint
        contentLeadingConstraintsToSidebar = mainView.contentLeadingConstraints.compactMap {
            // Let the window resize through the docking threshold before the next layout pass collapses the sidebar.
            ($0.firstItem as? NSView)?.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor).priority(999)
        }

        NSLayoutConstraint.activate([
            sidebarView.topAnchor.constraint(equalTo: mainView.navigationBarContainerView.topAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: mainView.bottomAnchor),
            sidebarHiddenConstraint,

            revealEdgeView.topAnchor.constraint(equalTo: mainView.navigationBarContainerView.topAnchor),
            revealEdgeView.bottomAnchor.constraint(equalTo: mainView.bottomAnchor),
            revealEdgeView.leadingAnchor.constraint(equalTo: mainView.leadingAnchor),
            revealEdgeView.widthAnchor.constraint(equalToConstant: Constants.revealEdgeWidth),

            peekingHoverView.topAnchor.constraint(equalTo: sidebarView.topAnchor),
            peekingHoverView.bottomAnchor.constraint(equalTo: sidebarView.bottomAnchor),
            peekingHoverView.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor),
            peekingHoverView.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
        ])
        canDock = hasRoomToDock
        setLayout(hiddenInFullScreen ? .hidden : preferredLayout, animated: false)
    }

    func uninstall() {
        sidebarViewController.dragSession.onDragEnded = nil
        sidebarViewController.dragSession.cancel()
        NSLayoutConstraint.deactivate(contentLeadingConstraintsToSidebar)
        NSLayoutConstraint.activate(mainView.contentLeadingConstraints)
        peekingHoverView.removeFromSuperview()
        revealEdgeView.removeFromSuperview()
        sidebarViewController.removeCompletely()
    }

    func toggle() {
        guard layout != .hidden else { return }
        if canDock {
            prefersDocked = layout != .docked
            setLayout(preferredLayout)
        } else {
            setLayout(layout == .peeking ? .collapsed : .peeking)
        }
    }

    private var hasRoomToDock: Bool {
        mainView.bounds.width >= MainView.minimumWebContentWidth + VerticalTabsViewController.minimumWidth
    }

    func updateForWindowWidth() {
        guard canDock != hasRoomToDock else { return }
        canDock = hasRoomToDock
        if layout != .hidden {
            setLayout(preferredLayout, animated: false)
        }
    }

    func setHiddenInFullScreen(_ hidden: Bool) {
        guard hidden != (layout == .hidden) else { return }
        setLayout(hidden ? .hidden : preferredLayout, animated: false)
    }

    private func setLayout(_ newLayout: Layout, animated: Bool = true) {
        guard layout != newLayout else { return }
        layout = newLayout
        if layout == .hidden {
            sidebarViewController.dragSession.cancel()
        }
        sidebarView.isHidden = layout == .hidden
        revealEdgeView.isHidden = layout == .hidden
        peekingHoverView.isHidden = layout == .hidden
        sidebarViewController.isFloating = layout == .peeking
        if layout == .peeking {
            sidebarView.shadow = peekingShadow()
        }

        // Collapsed, the sidebar waits just off the window's left edge, so it can slide back in.
        let isSidebarOnScreen = layout == .docked || layout == .peeking
        if let sidebarShownConstraint, let sidebarHiddenConstraint {
            NSLayoutConstraint.deactivate([isSidebarOnScreen ? sidebarHiddenConstraint : sidebarShownConstraint])
            NSLayoutConstraint.activate([isSidebarOnScreen ? sidebarShownConstraint : sidebarHiddenConstraint])
        }

        // Only a docked sidebar needs space beside the page.
        let isContentBesideSidebar = layout == .docked
        NSLayoutConstraint.deactivate(isContentBesideSidebar ? mainView.contentLeadingConstraints : contentLeadingConstraintsToSidebar)
        NSLayoutConstraint.activate(isContentBesideSidebar ? contentLeadingConstraintsToSidebar : mainView.contentLeadingConstraints)

        guard animated else {
            sidebarView.shadow = nil
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Constants.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            mainView.layoutSubtreeIfNeeded()
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.layout != .peeking else { return }
                self.sidebarView.shadow = nil
            }
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
