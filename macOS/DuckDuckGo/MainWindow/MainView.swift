//
//  MainView.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import Cocoa
import Combine
import WebKit

final class MainView: NSView {

    private enum Constants {
        static let bookmarksBarHeight: CGFloat = 28
        static let tabBarHeight: CGFloat = 38
        static let dividerHeight: CGFloat = 1
        static let webContainerMinHeight: CGFloat = 178
        static let webContainerMinWidth: CGFloat = 512
        static let findInPageContainerWidth: CGFloat = 400
        static let findInPageContainerHeight: CGFloat = 40
        static let findInPageContainerTopOffset: CGFloat = -4
        static let fireContainerHeight: CGFloat = 32
        static let bannerHeight: CGFloat = 48
        static let aiChatOmnibarContainerMinHeight: CGFloat = 60
        static let aiChatOmnibarContainerPadding: CGFloat = 50
        static let aiChatOmnibarContainerTopOffset: CGFloat = -20
        static let verticalTabsRevealEdgeWidth: CGFloat = 6
        static let peekingVerticalTabsShadowRadius: CGFloat = 16
        static let verticalTabsAnimationDuration: TimeInterval = 0.2
    }

    enum VerticalTabsLayout {
        /// The window shows horizontal tabs.
        case hidden
        /// The sidebar sits beside the toolbar and the page.
        case docked
        /// The sidebar is hidden until the mouse reaches the window's left edge.
        case collapsed
        /// The collapsed sidebar shown over the page while the mouse is on it.
        case peeking
    }

    let tabBarContainerView = NSView()
    let navigationBarContainerView = NSView()
    let webContainerView = NSView()
    let verticalTabsContainerView = NSView().hidden()
    // Always installed so their tracking areas are live; the owner decides what a hover means in each layout.
    private let verticalTabsRevealEdgeView = HoverDetectionView(assumesMouseInside: false)
    private let peekingVerticalTabsHoverView = HoverDetectionView(assumesMouseInside: true)
    let findInPageContainerView = NSView().hidden()
    let bookmarksBarContainerView = NSView()
    let bannerContainerView = NSView()
    let fireContainerView = NSView()
    let aiChatOmnibarContainerView: NSView = .init()
    let aiChatOmnibarTextContainerView: PassthroughView = .init()

    let divider = ColorView(frame: .zero, backgroundColor: .separatorColor)

    private let themeManager: ThemeManager = NSApp.delegateTyped.themeManager

    private var navigationBarTopConstraint: NSLayoutConstraint!
    private var bookmarksBarHeightConstraint: NSLayoutConstraint!
    private var webContainerTopConstraint: NSLayoutConstraint!
    private var webContainerTopConstraintToNavigation: NSLayoutConstraint!
    private var leadingConstraints: [NSLayoutConstraint] = []
    private var leadingConstraintsToVerticalTabs: [NSLayoutConstraint] = []
    private var verticalTabsShownConstraint: NSLayoutConstraint!
    private var verticalTabsHiddenConstraint: NSLayoutConstraint!
    private var tabBarHeightConstraint: NSLayoutConstraint!
    private var bannerTopConstraint: NSLayoutConstraint!
    private var bannerHeightConstraint: NSLayoutConstraint!
    private var aiChatOmnibarContainerWidthConstraint: NSLayoutConstraint!
    private var aiChatOmnibarContainerCenterXConstraint: NSLayoutConstraint!
    private var aiChatOmnibarContainerHeightConstraint: NSLayoutConstraint!
    private var aiChatOmnibarTextContainerBottomConstraint: NSLayoutConstraint!

    @Published var isMouseAboveWebView: Bool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        for subview in [
            tabBarContainerView,
            divider,
            bookmarksBarContainerView,
            webContainerView,
            bannerContainerView,
            navigationBarContainerView,
            verticalTabsContainerView,
            verticalTabsRevealEdgeView,
            peekingVerticalTabsHoverView,
            aiChatOmnibarContainerView,
            aiChatOmnibarTextContainerView,
            findInPageContainerView,
            fireContainerView
        ] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }

        addConstraints()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var navigationBarTopPadding: CGFloat {
        Constants.tabBarHeight + themeManager.theme.addressBarStyleProvider.tabBarBackgroundTopPadding
    }

    private func addConstraints() {
        bookmarksBarHeightConstraint = bookmarksBarContainerView.heightAnchor.constraint(equalToConstant: Constants.bookmarksBarHeight)
        tabBarHeightConstraint = tabBarContainerView.heightAnchor.constraint(equalToConstant: Constants.tabBarHeight)
        navigationBarTopConstraint = navigationBarContainerView.topAnchor.constraint(equalTo: topAnchor, constant: navigationBarTopPadding)
        webContainerTopConstraint = webContainerView.topAnchor.constraint(equalTo: bannerContainerView.bottomAnchor)
        webContainerTopConstraintToNavigation = webContainerView.topAnchor.constraint(equalTo: navigationBarContainerView.bottomAnchor)

        webContainerTopConstraint.priority = .defaultHigh
        webContainerTopConstraintToNavigation.priority = .defaultLow
        let viewsBesideVerticalTabs = [navigationBarContainerView, divider, bookmarksBarContainerView, bannerContainerView, webContainerView]
        leadingConstraints = viewsBesideVerticalTabs.map { $0.leadingAnchor.constraint(equalTo: leadingAnchor) }
        leadingConstraintsToVerticalTabs = viewsBesideVerticalTabs.map { $0.leadingAnchor.constraint(equalTo: verticalTabsContainerView.trailingAnchor) }
        verticalTabsShownConstraint = verticalTabsContainerView.leadingAnchor.constraint(equalTo: leadingAnchor)
        verticalTabsHiddenConstraint = verticalTabsContainerView.trailingAnchor.constraint(equalTo: leadingAnchor)

        bannerTopConstraint = bannerContainerView.topAnchor.constraint(equalTo: bookmarksBarContainerView.bottomAnchor)
        bannerHeightConstraint = bannerContainerView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            tabBarContainerView.topAnchor.constraint(equalTo: topAnchor),
            tabBarContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabBarContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabBarHeightConstraint,

            divider.topAnchor.constraint(equalTo: navigationBarContainerView.bottomAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            bookmarksBarContainerView.topAnchor.constraint(equalTo: navigationBarContainerView.bottomAnchor),
            bookmarksBarContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bookmarksBarHeightConstraint,

            navigationBarTopConstraint,
            navigationBarContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            bannerHeightConstraint,
            bannerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            bannerTopConstraint,
            bannerContainerView.topAnchor.constraint(equalTo: divider.bottomAnchor).priority(900),

            webContainerTopConstraint,
            webContainerTopConstraintToNavigation,
            webContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            verticalTabsContainerView.topAnchor.constraint(equalTo: navigationBarContainerView.topAnchor),
            verticalTabsContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            verticalTabsHiddenConstraint,

            verticalTabsRevealEdgeView.topAnchor.constraint(equalTo: navigationBarContainerView.topAnchor),
            verticalTabsRevealEdgeView.bottomAnchor.constraint(equalTo: bottomAnchor),
            verticalTabsRevealEdgeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            verticalTabsRevealEdgeView.widthAnchor.constraint(equalToConstant: Constants.verticalTabsRevealEdgeWidth),

            peekingVerticalTabsHoverView.topAnchor.constraint(equalTo: verticalTabsContainerView.topAnchor),
            peekingVerticalTabsHoverView.bottomAnchor.constraint(equalTo: verticalTabsContainerView.bottomAnchor),
            peekingVerticalTabsHoverView.leadingAnchor.constraint(equalTo: verticalTabsContainerView.leadingAnchor),
            peekingVerticalTabsHoverView.trailingAnchor.constraint(equalTo: verticalTabsContainerView.trailingAnchor),
            webContainerView.widthAnchor.constraint(greaterThanOrEqualToConstant: Constants.webContainerMinWidth),
            webContainerView.heightAnchor.constraint(greaterThanOrEqualToConstant: Constants.webContainerMinHeight),

            findInPageContainerView.topAnchor.constraint(equalTo: bookmarksBarContainerView.bottomAnchor, constant: Constants.findInPageContainerTopOffset),
            findInPageContainerView.topAnchor.constraint(equalTo: navigationBarContainerView.bottomAnchor, constant: Constants.findInPageContainerTopOffset).priority(900),
            findInPageContainerView.centerXAnchor.constraint(equalTo: navigationBarContainerView.centerXAnchor),
            findInPageContainerView.widthAnchor.constraint(equalToConstant: Constants.findInPageContainerWidth),
            findInPageContainerView.heightAnchor.constraint(equalToConstant: Constants.findInPageContainerHeight),

            fireContainerView.topAnchor.constraint(equalTo: topAnchor),
            fireContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            fireContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fireContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ] + leadingConstraints)

        aiChatOmnibarContainerWidthConstraint = aiChatOmnibarContainerView.widthAnchor.constraint(lessThanOrEqualToConstant: 832)
        aiChatOmnibarContainerHeightConstraint = aiChatOmnibarContainerView.heightAnchor.constraint(equalToConstant: Constants.aiChatOmnibarContainerMinHeight)
        aiChatOmnibarContainerCenterXConstraint = aiChatOmnibarContainerView.centerXAnchor.constraint(equalTo: navigationBarContainerView.centerXAnchor)
        NSLayoutConstraint.activate([
            aiChatOmnibarContainerView.topAnchor.constraint(equalTo: navigationBarContainerView.bottomAnchor, constant: Constants.aiChatOmnibarContainerTopOffset),
            aiChatOmnibarContainerCenterXConstraint,
            aiChatOmnibarContainerHeightConstraint,
            aiChatOmnibarContainerWidthConstraint,
        ])

        aiChatOmnibarTextContainerBottomConstraint = aiChatOmnibarTextContainerView.bottomAnchor.constraint(equalTo: aiChatOmnibarContainerView.bottomAnchor)
        aiChatOmnibarTextContainerBottomConstraint.isActive = true

        aiChatOmnibarContainerView.isHidden = true
        aiChatOmnibarTextContainerView.isHidden = true
    }

    private typealias CFWebServicesCopyProviderInfoType = @convention(c) (CFString, UnsafeRawPointer?) -> NSDictionary?

    // PDF Plugin context menu
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        // note, this will also handle the New Tab Page context menu
        setupSearchContextMenuItem(menu: menu)
        setupSaveAsAndPrintMenuItems(menu: menu, with: event)

        super.willOpenMenu(menu, with: event)
    }

    private func setupSearchContextMenuItem(menu: NSMenu) {
        // Intercept [_NSServiceEntry invokeWithPasteboard:] to catch selected PDF text "Search with %@" menu item
        PDFSearchTextMenuItemHandler.swizzleInvokeWithPasteboardOnce()

        // Get system default Search Engine name
        guard let CFWebServicesCopyProviderInfo: CFWebServicesCopyProviderInfoType? = dynamicSymbol(named: "_CFWebServicesCopyProviderInfo"),
              let info = CFWebServicesCopyProviderInfo?("NSWebServicesProviderWebSearch" as CFString, nil),
              let providerDisplayName = info["NSDefaultDisplayName"] as? String,
              providerDisplayName != "DuckDuckGo"
        else { return }

        // Find the "Search with %@" item and replace %@ with DuckDuckGo
        for item in menu.items {
            guard !item.isSeparatorItem else { continue }
            if item.title.contains(providerDisplayName) {
                item.title = item.title.replacingOccurrences(of: providerDisplayName, with: "DuckDuckGo")
                break
            }
        }
    }

    private func setupSaveAsAndPrintMenuItems(menu: NSMenu, with event: NSEvent) {
        guard let window else { return }

        // try to find PDF HUD view at the right-click location (it might be a frame click)
        let hudView: WKPDFHUDViewWrapper? = {
            for point in [event.locationInWindow, window.mouseLocationOutsideOfEventStream] {
                let locationInView = convert(point, from: nil)
                guard let view = self.hitTest(locationInView) else { continue }

                if let hudView = WKPDFHUDViewWrapper(view: view) {
                    return hudView
                } else if let webView = view as? WKWebView,
                          let hudView = webView.hudView(at: webView.convert(locationInView, from: self)) {
                    return hudView
                }
            }
            return (self.hitTest(bounds.center) as? WKWebView)?.hudView()
        }()
        guard let hudView else { return }

        // insert Save As… and Print… items after `Open with Preview`
        // 1. find `Copy`
        let idxAfterCopy = menu.indexOfItem(withTitle: UserText.copy) + /* will become 0 if no copy (-1 + 1) */ 1
        let insertionIdx: Int
        if idxAfterCopy > 0 {
            // 2. find separator below `Copy`
            let separatorIdx = (idxAfterCopy..<menu.items.endIndex).first(where: { menu.items[$0].isSeparatorItem }) ?? idxAfterCopy //  separator
            // 3. descend 2 items down: the separator, `Open with Preview`
            insertionIdx = min(separatorIdx + 2, menu.items.count /* just in case… */)
        } else {
            insertionIdx = min(1, menu.items.count /* just in case… */)
        }

        menu.insertItem(NSMenuItem(title: UserText.mainMenuFileSaveAs, action: #selector(MainViewController.saveAs), representedObject: hudView)
            .withAccessibilityIdentifier("PDFContextMenu.saveAs"),
                        at: insertionIdx)
        menu.insertItem(NSMenuItem(title: UserText.printMenuItem, action: #selector(MainViewController.printWebView), representedObject: hudView)
            .withAccessibilityIdentifier("PDFContextMenu.print"),
                        at: insertionIdx)
    }

    // MARK: - View Layout

    var isBookmarksBarShown: Bool {
        get {
            bookmarksBarHeightConstraint.constant > 0
        }
        set {
            bookmarksBarHeightConstraint.animator().constant = newValue ? Constants.bookmarksBarHeight : 0
            bannerTopConstraint.animator().isActive = newValue
        }
    }

    enum WebContainerTopBinding {
        case navigationBar
        case tabBar
    }
    var webContainerTopBinding: WebContainerTopBinding {
        get {
            webContainerTopConstraintToNavigation.priority == .defaultLow ? .navigationBar : .tabBar
        }
        set {
            webContainerTopConstraintToNavigation.priority = newValue == .navigationBar ? .defaultHigh : .defaultLow
            webContainerTopConstraint.priority = newValue == .navigationBar ? .defaultLow : .defaultHigh
        }
    }

    var verticalTabsLayout: VerticalTabsLayout = .hidden {
        didSet {
            guard oldValue != verticalTabsLayout else { return }
            // Turning vertical tabs on or off swaps the whole layout; only collapsing, expanding and peeking slide.
            applyVerticalTabsLayout(animated: oldValue != .hidden && verticalTabsLayout != .hidden)
        }
    }

    func observeVerticalTabsHover(onRevealEdgeEntered: @escaping () -> Void, onPeekingSidebarExited: @escaping () -> Void) {
        verticalTabsRevealEdgeView.onMouseEntered = onRevealEdgeEntered
        peekingVerticalTabsHoverView.onMouseExited = onPeekingSidebarExited
    }

    private func applyVerticalTabsLayout(animated: Bool) {
        verticalTabsContainerView.isHidden = verticalTabsLayout == .hidden
        if verticalTabsLayout == .peeking {
            verticalTabsContainerView.shadow = peekingVerticalTabsShadow()
        }

        // Collapsed, the sidebar waits just off the window's left edge, so it can slide back in.
        let isSidebarOnScreen = [.docked, .peeking].contains(verticalTabsLayout)
        NSLayoutConstraint.deactivate([isSidebarOnScreen ? verticalTabsHiddenConstraint : verticalTabsShownConstraint])
        NSLayoutConstraint.activate([isSidebarOnScreen ? verticalTabsShownConstraint : verticalTabsHiddenConstraint])

        // Peeking, the sidebar floats over the page instead of pushing it aside.
        let isContentBesideSidebar = [.docked, .collapsed].contains(verticalTabsLayout)
        NSLayoutConstraint.deactivate(isContentBesideSidebar ? leadingConstraints : leadingConstraintsToVerticalTabs)
        NSLayoutConstraint.activate(isContentBesideSidebar ? leadingConstraintsToVerticalTabs : leadingConstraints)

        let removeShadowUnlessPeeking = { [weak self] in
            guard let self, verticalTabsLayout != .peeking else { return }
            verticalTabsContainerView.shadow = nil
        }
        guard animated else {
            removeShadowUnlessPeeking()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Constants.verticalTabsAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            self.layoutSubtreeIfNeeded()
        }, completionHandler: removeShadowUnlessPeeking)
    }

    private func peekingVerticalTabsShadow() -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = themeManager.theme.palette.shadowSecondary
        shadow.shadowBlurRadius = Constants.peekingVerticalTabsShadowRadius
        return shadow
    }

    var isBannerViewShown: Bool {
        get {
            bannerHeightConstraint.constant > 0
        }
        set {
            bannerHeightConstraint.animator().constant = newValue ? Constants.bannerHeight : 0
        }
    }

    func setTabBarShown(_ newValue: Bool, animated: Bool) {
        var tabBarHeightConstraint = tabBarHeightConstraint
        var navigationBarTopConstraint = navigationBarTopConstraint
        if animated {
            tabBarHeightConstraint = tabBarHeightConstraint?.animator()
            navigationBarTopConstraint = navigationBarTopConstraint?.animator()
        }
        tabBarHeightConstraint?.constant = newValue ? Constants.tabBarHeight : 0
        navigationBarTopConstraint?.constant = newValue ? navigationBarTopPadding : 0
    }

    var isAIChatOmnibarContainerShown: Bool {
        get {
            !aiChatOmnibarContainerView.isHidden
        }
        set {
            aiChatOmnibarContainerView.isHidden = !newValue
            aiChatOmnibarTextContainerView.isHidden = !newValue
        }
    }

    func setupAIChatOmnibarTextContainerConstraints(addressBarStack: NSView) {
        aiChatOmnibarTextContainerView.translatesAutoresizingMaskIntoConstraints = false

        let styleProvider = themeManager.theme.addressBarStyleProvider
        let topPadding = styleProvider.aiChatOmnibarTextContainerTopPadding
        let leadingPadding = styleProvider.aiChatOmnibarTextContainerLeadingPadding

        NSLayoutConstraint.activate([
            aiChatOmnibarTextContainerView.topAnchor.constraint(equalTo: addressBarStack.topAnchor, constant: topPadding),
            aiChatOmnibarTextContainerView.leadingAnchor.constraint(equalTo: addressBarStack.leadingAnchor, constant: leadingPadding),
            aiChatOmnibarTextContainerView.trailingAnchor.constraint(equalTo: addressBarStack.trailingAnchor, constant: -78),
        ])

        aiChatOmnibarTextContainerBottomConstraint.constant = -5
    }

    /// Updates the text container view's passthrough region to allow clicks to reach suggestions and tool buttons.
    func updateAIChatOmnibarTextContainerPassthrough(_ passthroughHeight: CGFloat) {
        aiChatOmnibarTextContainerView.passthroughBottomHeight = passthroughHeight
    }

    /// Updates the text container's height based on text content.
    /// Note: Currently using bottom constraint approach instead
    func updateAIChatOmnibarTextContainerHeight(_ height: CGFloat) {
        // Using bottom constraint, so this is a no-op for now
    }

    func setupAIChatOmnibarContainerConstraints(addressBarStack: NSView) {
        aiChatOmnibarContainerWidthConstraint.isActive = false
        // Follow the address bar instead of forcing it to stay centered, which blocks the navigation bar overflow
        aiChatOmnibarContainerCenterXConstraint.isActive = false
        NSLayoutConstraint.activate([
            aiChatOmnibarContainerView.leadingAnchor.constraint(equalTo: addressBarStack.leadingAnchor),
            aiChatOmnibarContainerView.trailingAnchor.constraint(equalTo: addressBarStack.trailingAnchor),
        ])
    }

    func updateAIChatOmnibarContainerHeight(_ height: CGFloat, animated: Bool) {
        let clampedHeight = max(Constants.aiChatOmnibarContainerMinHeight, min(height, calculateMaxAIChatOmnibarHeight()))

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                aiChatOmnibarContainerHeightConstraint.animator().constant = clampedHeight
            }
        } else {
            aiChatOmnibarContainerHeightConstraint.constant = clampedHeight
        }
    }

    func calculateMaxAIChatOmnibarHeight() -> CGFloat {
        guard let window = window else {
            return Constants.aiChatOmnibarContainerMinHeight
        }

        // Calculate available height: window height - address bar height - padding
        let addressBarHeight = navigationBarContainerView.frame.height
        let availableHeight = window.frame.height - addressBarHeight - Constants.aiChatOmnibarContainerPadding

        return max(Constants.aiChatOmnibarContainerMinHeight, availableHeight)
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
        return (nextResponder as? NSDraggingDestination)?.draggingEntered?(draggingInfo) ?? .none
    }

    override func draggingUpdated(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
        return (nextResponder as? NSDraggingDestination)?.draggingUpdated?(draggingInfo) ?? .none
    }

    override func performDragOperation(_ draggingInfo: NSDraggingInfo) -> Bool {
        return (nextResponder as? NSDraggingDestination)?.performDragOperation?(draggingInfo) ?? false
    }

    // MARK: - Mouse Tracking

    func setMouseAboveWebViewTrackingAreaEnabled(_ isEnabled: Bool) {
        if isEnabled {
            let trackingArea = makeMouseAboveViewTrackingArea()
            addTrackingArea(trackingArea)
            mouseAboveWebViewTrackingArea = trackingArea
        } else if let mouseAboveWebViewTrackingArea {
            removeTrackingArea(mouseAboveWebViewTrackingArea)
            self.mouseAboveWebViewTrackingArea = nil
            isMouseAboveWebView = false
        }
    }

    override func updateTrackingAreas() {
        if let mouseAboveWebViewTrackingArea {
            removeTrackingArea(mouseAboveWebViewTrackingArea)
            let trackingArea = makeMouseAboveViewTrackingArea()
            self.mouseAboveWebViewTrackingArea = trackingArea
            addTrackingArea(trackingArea)
        }
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        if event.type == .mouseEntered, let mouseAboveWebViewTrackingArea, event.trackingArea == mouseAboveWebViewTrackingArea {
            isMouseAboveWebView = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if event.type == .mouseExited, let mouseAboveWebViewTrackingArea, event.trackingArea == mouseAboveWebViewTrackingArea {
            isMouseAboveWebView = false
        }
    }

    private func makeMouseAboveViewTrackingArea() -> NSTrackingArea {
        var bounds = bounds
        bounds.size.height -= webContainerView.bounds.maxY
        bounds.origin.y += webContainerView.bounds.maxY
        return NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited], owner: self, userInfo: nil)
    }

    private var mouseAboveWebViewTrackingArea: NSTrackingArea?

}

/// Reports the mouse entering and leaving it, and lets clicks through to the views beneath.
private final class HoverDetectionView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    private let assumesMouseInside: Bool
    private var trackingArea: NSTrackingArea?

    init(assumesMouseInside: Bool) {
        self.assumesMouseInside = assumesMouseInside
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("HoverDetectionView: Bad initializer")
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
