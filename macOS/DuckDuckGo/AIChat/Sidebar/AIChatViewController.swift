//
//  AIChatViewController.swift
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
import BrowserServicesKit
import AIChat
import Combine

/// A delegate protocol that handles user interactions with the AI Chat sidebar view controller.
/// This protocol defines methods for responding to navigation and UI events in the sidebar.
protocol AIChatViewControllerDelegate: AnyObject {
    /// Called when the user clicks the "Open Duck.ai in Tab" button.
    func didClickOpenInNewTabButton()
    /// Called when the user clicks the "Close" button
    func didClickCloseButton()
    /// Called when the user clicks the "Detach" button to pop the sidebar into a floating window.
    func didClickDetachButton()
    /// Called when the user clicks the "Attach" button to dock the floating sidebar back.
    func didClickAttachButton(for tabID: TabIdentifier)
    /// Called when the user clicks the title button to bring the associated tab to front.
    func didClickTitleButton(for tabID: TabIdentifier)
    /// Returns whether the chat is in floating (detached) presentation mode for the given tab.
    func isChatFloating(for tabID: TabIdentifier) -> Bool
}

/// A view controller that manages the AI Chat sidebar interface.
/// This controller handles the layout and interaction of the sidebar components including:
/// - A native top navigation bar with buttons and title label
/// - A web view container for displaying AI chat
/// - Additional visual styling including corner radius and separators
final class AIChatViewController: NSViewController {

    private enum Constants {
        static let separatorWidth: CGFloat = 1
        static let topBarHeight: CGFloat = 38
        static let barButtonHeight: CGFloat = 28
        static let barButtonWidth: CGFloat = 28
        static let barButtonMargin: CGFloat = 12
        static let titleButtonHeight: CGFloat = 28
        static let titleButtonHorizontalPadding: CGFloat = 8
        static let titleFaviconSize: CGFloat = 16
        static let titleButtonGutter: CGFloat = 32
        static let webViewContainerPadding: CGFloat = 4
        static let webViewTopCornerRadius: CGFloat = 16
        static let webViewBottomCornerRadius: CGFloat = 6
    }

    weak var delegate: AIChatViewControllerDelegate?
    var tabID: TabIdentifier?
    public var aiChatPayload: AIChatPayload?
    var isChatFloatingEnabled = false {
        didSet {
            guard isViewLoaded else { return }
            updateTopBarForHostingContext()
        }
    }
    private var isChatFloating: Bool {
        guard let tabID else { return false }
        return delegate?.isChatFloating(for: tabID) ?? false
    }
    private(set) var currentAIChatURL: URL

    let themeManager: ThemeManaging
    var themeUpdateCancellable: AnyCancellable?

    private let burnerMode: BurnerMode

    private var openInNewTabButton: MouseOverButton!
    private var detachButton: MouseOverButton!
    private var attachButton: MouseOverButton!
    private var closeButton: MouseOverButton!
    private var titleButton: MouseOverButton!
    private var titleFaviconView: NSImageView!
    private var titleTextLabel: NSTextField!
    private var titleArrowView: NSImageView!
    private var webViewContainer: WebViewContainerView!
    private var separator: NSView!
    private var topBar: NSView!

    private lazy var aiTab: Tab = Tab(content: .url(currentAIChatURL, source: .ui), burnerMode: burnerMode, isLoadedInSidebar: true)

    private var cancellables = Set<AnyCancellable>()

    init(currentAIChatURL: URL,
         burnerMode: BurnerMode,
         themeManager: ThemeManaging = NSApp.delegateTyped.themeManager) {
        self.currentAIChatURL = currentAIChatURL
        self.burnerMode = burnerMode
        self.themeManager = themeManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setAIChatPrompt(_ prompt: AIChatNativePrompt) {
        aiTab.aiChat?.submitAIChatNativePrompt(prompt)
    }

    public func setPageContext(_ pageContext: AIChatPageContextData?) {
        aiTab.aiChat?.submitAIChatPageContext(pageContext)
    }

    public func setAIChatRestorationData(_ restorationData: AIChatRestorationData?) {
        aiTab.aiChat?.setAIChatRestorationData(restorationData)
    }

    public var pageContextRequestedPublisher: AnyPublisher<Void, Never>? {
        aiTab.aiChat?.pageContextRequestedPublisher
    }

    public var chatRestorationDataPublisher: AnyPublisher<AIChatRestorationData?, Never>? {
        aiTab.aiChat?.chatRestorationDataPublisher
    }

    override func loadView() {
        let colorsProvider = themeManager.theme.colorsProvider
        let container = ColorView(frame: .zero, backgroundColor: colorsProvider.navigationBackgroundColor)

        if let aiChatPayload {
            aiTab.aiChat?.setAIChatNativeHandoffData(payload: aiChatPayload)
        }

        createAndSetupSeparator(in: container)
        createAndSetupTopBar(in: container)
        createAndSetupWebViewContainer(in: container)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: container.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: separator.trailingAnchor),
            topBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: Constants.topBarHeight),

            webViewContainer.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            webViewContainer.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: Constants.webViewContainerPadding),
            webViewContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Constants.webViewContainerPadding),
            webViewContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Constants.webViewContainerPadding),
        ])

        self.view = container

        // Initial mask update
        updateWebViewMask()
        subscribeToURLChanges()
        subscribeToUserInteractionDialogChanges()
        subscribeToThemeChanges()
    }

    private func createAndSetupSeparator(in container: NSView) {
        separator = ColorView(frame: .zero, backgroundColor: themeManager.theme.colorsProvider.separatorColor)
        separator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(separator)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: container.topAnchor),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.widthAnchor.constraint(equalToConstant: Constants.separatorWidth)
        ])
    }

    private func createAndSetupTopBar(in container: NSView) {
        topBar = NSView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(topBar)

        openInNewTabButton = makeBarButton(image: .expand, action: #selector(openInNewTabButtonClicked),
                                           toolTip: UserText.aiChatSidebarExpandButtonTooltip)
        openInNewTabButton.setAccessibilityIdentifier("AIChatViewController.openInNewTabButton")
        topBar.addSubview(openInNewTabButton)

        attachButton = makeBarButton(image: .aiChatAttach, action: #selector(attachButtonClicked),
                                     toolTip: UserText.aiChatSidebarAttachButtonTooltip)
        attachButton.setAccessibilityIdentifier("AIChatViewController.attachButton")
        attachButton.isHidden = true
        topBar.addSubview(attachButton)

        titleButton = makeTitleButton()
        titleButton.setAccessibilityIdentifier("AIChatViewController.titleButton")
        titleButton.isHidden = true
        topBar.addSubview(titleButton)

        detachButton = makeBarButton(image: .aiChatDetach, action: #selector(detachButtonClicked),
                                     toolTip: UserText.aiChatSidebarDetachButtonTooltip)
        detachButton.setAccessibilityIdentifier("AIChatViewController.detachButton")
        topBar.addSubview(detachButton)

        closeButton = makeBarButton(image: .closeLarge, action: #selector(closeButtonClicked),
                                    toolTip: UserText.aiChatSidebarCloseButtonTooltip)
        closeButton.setAccessibilityIdentifier("AIChatViewController.closeButton")
        topBar.addSubview(closeButton)

        NSLayoutConstraint.activate([
            // Left side: openInNewTab (docked) or attach (floating) -- share the same position
            openInNewTabButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: Constants.barButtonMargin),
            openInNewTabButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            openInNewTabButton.heightAnchor.constraint(equalToConstant: Constants.barButtonHeight),
            openInNewTabButton.widthAnchor.constraint(equalToConstant: Constants.barButtonWidth),

            attachButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -Constants.barButtonMargin),
            attachButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            attachButton.heightAnchor.constraint(equalToConstant: Constants.barButtonHeight),
            attachButton.widthAnchor.constraint(equalToConstant: Constants.barButtonWidth),

            // Center: clickable title button (floating only)
            titleButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            titleButton.heightAnchor.constraint(equalToConstant: Constants.titleButtonHeight),
            titleButton.leadingAnchor.constraint(greaterThanOrEqualTo: openInNewTabButton.trailingAnchor, constant: Constants.titleButtonGutter),
            titleButton.trailingAnchor.constraint(lessThanOrEqualTo: attachButton.leadingAnchor, constant: -Constants.titleButtonGutter),
            titleButton.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),

            // Right side: detach (docked) + close
            closeButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -Constants.barButtonMargin),
            closeButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            closeButton.heightAnchor.constraint(equalToConstant: Constants.barButtonHeight),
            closeButton.widthAnchor.constraint(equalToConstant: Constants.barButtonWidth),

            detachButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),
            detachButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            detachButton.heightAnchor.constraint(equalToConstant: Constants.barButtonHeight),
            detachButton.widthAnchor.constraint(equalToConstant: Constants.barButtonWidth),
        ])
    }

    private func makeTitleButton() -> MouseOverButton {
        let button = FloatingWindowTitleDragButton(frame: .zero)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.title = ""
        button.imagePosition = .noImage
        button.cornerRadius = 9
        button.mouseOverColor = .buttonMouseOver
        button.mouseDownColor = .buttonMouseDown
        button.clipsToBounds = false
        button.target = self
        button.action = #selector(titleButtonClicked)
        button.refusesFirstResponder = true
        button.toolTip = UserText.aiChatSidebarTitleButtonTooltip
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.backgroundInset = .zero
        titleFaviconView = NSImageView()
        titleFaviconView.translatesAutoresizingMaskIntoConstraints = false
        titleFaviconView.imageScaling = .scaleProportionallyUpOrDown
        titleFaviconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleFaviconView.setContentHuggingPriority(.required, for: .horizontal)

        titleTextLabel = NSTextField(labelWithString: "")
        titleTextLabel.translatesAutoresizingMaskIntoConstraints = false
        titleTextLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleTextLabel.textColor = .labelColor
        titleTextLabel.lineBreakMode = .byTruncatingTail
        titleTextLabel.setContentCompressionResistancePriority(.init(rawValue: 500), for: .horizontal)

        titleArrowView = NSImageView(image: .arrowUpRight12)
        titleArrowView.translatesAutoresizingMaskIntoConstraints = false
        titleArrowView.contentTintColor = themeManager.theme.colorsProvider.iconsColor
        titleArrowView.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleArrowView.setContentHuggingPriority(.required, for: .horizontal)

        let stackView = NSStackView(views: [titleFaviconView, titleTextLabel, titleArrowView])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = 0
        stackView.setCustomSpacing(4, after: titleFaviconView)
        stackView.setCustomSpacing(6, after: titleTextLabel)
        stackView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        button.addSubview(stackView)

        NSLayoutConstraint.activate([
            titleFaviconView.widthAnchor.constraint(equalToConstant: Constants.titleFaviconSize),
            titleFaviconView.heightAnchor.constraint(equalToConstant: Constants.titleFaviconSize),

            stackView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: Constants.titleButtonHorizontalPadding),
            stackView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -Constants.titleButtonHorizontalPadding),
            stackView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])

        return button
    }

    func updateFloatingTitle(_ title: String, favicon: NSImage?) {
        titleFaviconView.image = favicon ?? .homeFavicon
        titleTextLabel.stringValue = title
    }

    private func makeBarButton(image: NSImage, action: Selector, toolTip: String) -> MouseOverButton {
        let button = MouseOverButton(image: image, target: self, action: action)
        button.toolTip = toolTip
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .shadowlessSquare
        button.cornerRadius = 9
        button.normalTintColor = themeManager.theme.colorsProvider.iconsColor
        button.mouseDownColor = .buttonMouseDown
        button.mouseOverColor = .buttonMouseOver
        button.isBordered = false
        button.refusesFirstResponder = true
        return button
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateTopBarForHostingContext()
    }

    private func updateTopBarForHostingContext() {
        openInNewTabButton.isHidden = isChatFloating
        detachButton.isHidden = isChatFloating || !isChatFloatingEnabled
        attachButton.isHidden = !isChatFloating
        closeButton.isHidden = isChatFloating
        titleButton.isHidden = !isChatFloating
        titleArrowView?.isHidden = !isChatFloating
        separator.isHidden = isChatFloating
        updateBackgroundForHostingContext()
    }

    private func updateBackgroundForHostingContext() {
        guard let contentView = view as? ColorView else { return }
        let colorsProvider = themeManager.theme.colorsProvider
        contentView.backgroundColor = isChatFloating ? colorsProvider.baseBackgroundColor : colorsProvider.navigationBackgroundColor
    }

    private func createAndSetupWebViewContainer(in container: NSView) {
        webViewContainer = WebViewContainerView(tab: aiTab, webView: aiTab.webView, frame: .zero)
        webViewContainer.translatesAutoresizingMaskIntoConstraints = false
        webViewContainer.wantsLayer = true
        webViewContainer.layer?.masksToBounds = true
        webViewContainer.layer?.backgroundColor = NSColor.navigationBarBackground.cgColor
        container.addSubview(webViewContainer)

        // Pinch zoom does not make sense in the AI Chat sidebar.
        aiTab.webView.allowsMagnification = false

        aiTab.setDelegate(self)

        // Observe bounds changes to update the mask
        webViewContainer.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateWebViewMask),
                                               name: NSView.frameDidChangeNotification,
                                               object: webViewContainer)
    }

    @objc private func updateWebViewMask() {
        let bounds = webViewContainer.bounds

        let path = CGMutablePath()

        // Bottom left corner
        path.move(to: CGPoint(x: bounds.minX, y: bounds.minY + Constants.webViewBottomCornerRadius))
        path.addArc(center: CGPoint(x: bounds.minX + Constants.webViewBottomCornerRadius,
                                    y: bounds.minY + Constants.webViewBottomCornerRadius),
                    radius: Constants.webViewBottomCornerRadius,
                    startAngle: .pi,
                    endAngle: .pi * 3/2,
                    clockwise: false)

        // Bottom right corner
        path.addLine(to: CGPoint(x: bounds.maxX - Constants.webViewBottomCornerRadius, y: bounds.minY))
        path.addArc(center: CGPoint(x: bounds.maxX - Constants.webViewBottomCornerRadius,
                                    y: bounds.minY + Constants.webViewBottomCornerRadius),
                    radius: Constants.webViewBottomCornerRadius,
                    startAngle: .pi * 3/2,
                    endAngle: 0,
                    clockwise: false)

        // Top right corner
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY - Constants.webViewTopCornerRadius))
        path.addArc(center: CGPoint(x: bounds.maxX - Constants.webViewTopCornerRadius,
                                    y: bounds.maxY - Constants.webViewTopCornerRadius),
                    radius: Constants.webViewTopCornerRadius,
                    startAngle: 0,
                    endAngle: .pi/2,
                    clockwise: false)

        // Top left corner
        path.addLine(to: CGPoint(x: bounds.minX + Constants.webViewTopCornerRadius, y: bounds.maxY))
        path.addArc(center: CGPoint(x: bounds.minX + Constants.webViewTopCornerRadius,
                                    y: bounds.maxY - Constants.webViewTopCornerRadius),
                    radius: Constants.webViewTopCornerRadius,
                    startAngle: .pi/2,
                    endAngle: .pi,
                    clockwise: false)

        path.closeSubpath()

        let shape = CAShapeLayer()
        shape.path = path
        webViewContainer.layer?.mask = shape
    }

    private func subscribeToURLChanges() {
        aiTab.$content
            .dropFirst()
            .sink { [weak self] content in
            if let currentURL = content.urlForWebView {
                self?.currentAIChatURL = currentURL
            }
        }
        .store(in: &cancellables)
    }

    private func subscribeToUserInteractionDialogChanges() {
        aiTab.$userInteractionDialog
            .dropFirst()
            .sink { [weak self] userInteractionDialog in
                NotificationCenter.default.post(
                    name: .aiChatSidebarUserInteractionDialogChanged,
                    object: self,
                    userInfo: [NSNotification.Name.UserInfoKeys.userInteractionDialog: userInteractionDialog as Any]
                )
            }
            .store(in: &cancellables)
    }

    @objc private func openInNewTabButtonClicked() {
        delegate?.didClickOpenInNewTabButton()
    }

    @objc private func detachButtonClicked() {
        delegate?.didClickDetachButton()
    }

    @objc private func attachButtonClicked() {
        guard let tabID else { return }
        delegate?.didClickAttachButton(for: tabID)
    }

    @objc private func titleButtonClicked() {
        guard let tabID else { return }
        delegate?.didClickTitleButton(for: tabID)
    }

    @objc private func closeButtonClicked() {
        if let window = view.window, window is AIChatFloatingWindow {
            window.close()
            return
        }
        delegate?.didClickCloseButton()
    }

    func stopLoading() {
        aiTab.webView.navigationDelegate = nil
        aiTab.webView.uiDelegate = nil

        aiTab.webView.stopLoading()
    }
}

// MARK: - ThemeUpdateListening
extension AIChatViewController: ThemeUpdateListening {

    func applyThemeStyle(theme: ThemeStyleProviding) {
        guard let contentView = view as? ColorView else {
            assertionFailure()
            return
        }

        contentView.backgroundColor = isChatFloating ? theme.colorsProvider.baseBackgroundColor : theme.colorsProvider.navigationBackgroundColor
        (separator as? ColorView)?.backgroundColor = theme.colorsProvider.separatorColor

        let iconsPrimary = theme.colorsProvider.iconsColor
        openInNewTabButton?.normalTintColor = iconsPrimary
        detachButton?.normalTintColor = iconsPrimary
        attachButton?.normalTintColor = iconsPrimary
        closeButton?.normalTintColor = iconsPrimary
        titleArrowView?.contentTintColor = iconsPrimary
    }
}

extension AIChatViewController: TabDelegate {

    var isInPopUpWindow: Bool { false }

    func tab(_ tab: Tab, createdChild childTab: Tab, of kind: NewWindowPolicy) {
        switch kind {
        case .popup(origin: let origin, size: let contentSize):
            WindowsManager.openPopUpWindow(with: childTab, origin: origin, contentSize: contentSize)
        case .window(active: let active, let isBurner):
            assert(isBurner == childTab.burnerMode.isBurner)
            WindowsManager.openNewWindow(with: childTab, showWindow: active)
        case .tab(selected: let selected, _, _):
            if let parentWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController {
                let tabCollectionViewModel = parentWindowController.mainViewController.tabCollectionViewModel
                tabCollectionViewModel.insertOrAppend(tab: childTab, selected: selected)
            }
        }
    }

    func tabWillStartNavigation(_ tab: Tab, isUserInitiated: Bool) {}
    func tabDidStartNavigation(_ tab: Tab) {}
    func tabPageDOMLoaded(_ tab: Tab) {}
    func closeTab(_ tab: Tab) {}
    func websiteAutofillUserScriptCloseOverlay(_ websiteAutofillUserScript: BrowserServicesKit.WebsiteAutofillUserScript?) {}
    func websiteAutofillUserScript(_ websiteAutofillUserScript: BrowserServicesKit.WebsiteAutofillUserScript, willDisplayOverlayAtClick: CGPoint?, serializedInputContext: String, inputPosition: CGRect) {}
}

extension NSNotification.Name {
    static let aiChatSidebarUserInteractionDialogChanged = NSNotification.Name("aiChatSidebarUserInteractionDialogChanged")

    enum UserInfoKeys {
        static let userInteractionDialog = "userInteractionDialog"
    }
}

/// Allows the floating-window title button to both click (focus tab) and drag window.
private final class FloatingWindowTitleDragButton: MouseOverButton {

    private enum Constants {
        static let dragThreshold: CGFloat = 3
    }

    override func mouseDown(with event: NSEvent) {
        guard let window, window is AIChatFloatingWindow, !event.isContextClick else {
            super.mouseDown(with: event)
            return
        }

        var shouldStartDrag = false

        while let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if nextEvent.type == .leftMouseDragged {
                let deltaX = nextEvent.locationInWindow.x - event.locationInWindow.x
                let deltaY = nextEvent.locationInWindow.y - event.locationInWindow.y
                let distance = hypot(deltaX, deltaY)

                if distance >= Constants.dragThreshold {
                    shouldStartDrag = true
                    break
                }
            } else if nextEvent.type == .leftMouseUp {
                break
            }
        }

        if shouldStartDrag {
            window.performDrag(with: event)
            return
        }

        // No drag was detected, so this is a regular click.
        isMouseDown = true
        if let action {
            NSApp.sendAction(action, to: target, from: self)
        }
        isMouseDown = false
    }
}
