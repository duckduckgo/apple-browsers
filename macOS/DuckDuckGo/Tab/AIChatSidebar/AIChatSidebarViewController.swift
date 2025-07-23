//
//  AIChatSidebarViewController.swift
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
protocol AIChatSidebarViewControllerDelegate: AnyObject {
    /// Called when the user clicks the "Expand" button
    func didClickOpenInNewTabButton(currentAIChatURL: URL, aiChatRestorationData: AIChatRestorationData?)
    /// Called when the user clicks the "Close" button
    func didClickCloseButton()
}

/// A view controller that manages the AI Chat sidebar interface.
/// This controller handles the layout and interaction of the sidebar components including:
/// - A native top navigation bar with buttons and title label
/// - A web view container for displaying AI chat
/// - Additional visual styling including corner radius and separators
final class AIChatSidebarViewController: NSViewController {

    private enum Constants {
        static let separatorWidth: CGFloat = 1
        static let topBarHeight: CGFloat = 48
        static let barButtonHeight: CGFloat = 32
        static let barButtonWidth: CGFloat = 32
        static let barButtonMargin: CGFloat = 12
        static let titleLabelSideMargin: CGFloat = 8
        static let webViewContainerPadding: CGFloat = 4
        static let webViewTopCornerRadius: CGFloat = 16
        static let webViewBottomCornerRadius: CGFloat = 6
    }

    weak var delegate: AIChatSidebarViewControllerDelegate?
    public var aiChatPayload: AIChatPayload?
    private(set) var currentAIChatURL: URL
    private let burnerMode: BurnerMode
    private let visualStyle: VisualStyleProviding

    private var openInNewTabButton: MouseOverButton!
    private var closeButton: MouseOverButton!
    private var webViewContainer: WebViewContainerView!
    private var separator: NSView!
    private var topBar: NSView!

    private lazy var aiTab: Tab = Tab(content: .url(currentAIChatURL, source: .ui), burnerMode: burnerMode, isLoadedInSidebar: true)

    private var cancellables = Set<AnyCancellable>()

    init(currentAIChatURL: URL,
         burnerMode: BurnerMode,
         visualStyle: VisualStyleProviding = NSApp.delegateTyped.visualStyle) {
        self.currentAIChatURL = currentAIChatURL
        self.burnerMode = burnerMode
        self.visualStyle = visualStyle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setAIChatPrompt(_ prompt: AIChatNativePrompt) {
        aiTab.aiChat?.submitAIChatNativePrompt(prompt)
    }

    override func loadView() {
        let container = ColorView(frame: .zero, backgroundColor: visualStyle.colorsProvider.navigationBackgroundColor)

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
    }

    private func createAndSetupSeparator(in container: NSView) {
        separator = NSView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
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

        openInNewTabButton = MouseOverButton(image: .expand, target: self, action: #selector(openInNewTabButtonClicked))
        openInNewTabButton.toolTip = UserText.aiChatSidebarExpandButtonTooltip
        openInNewTabButton.translatesAutoresizingMaskIntoConstraints = false
        openInNewTabButton.bezelStyle = .shadowlessSquare
        openInNewTabButton.cornerRadius = 9
        openInNewTabButton.normalTintColor = .button
        openInNewTabButton.mouseDownColor = .buttonMouseDown
        openInNewTabButton.mouseOverColor = .buttonMouseOver
        openInNewTabButton.isBordered = false
        topBar.addSubview(openInNewTabButton)

        let titleLabel = NSTextField(labelWithString: UserText.aiChatSidebarTitle)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        topBar.addSubview(titleLabel)

        closeButton = MouseOverButton(image: .closeLarge, target: self, action: #selector(closeButtonClicked))
        closeButton.toolTip = UserText.aiChatSidebarCloseButtonTooltip
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .shadowlessSquare
        closeButton.cornerRadius = 9
        closeButton.normalTintColor = .button
        closeButton.mouseDownColor = .buttonMouseDown
        closeButton.mouseOverColor = .buttonMouseOver
        closeButton.isBordered = false
        topBar.addSubview(closeButton)

        NSLayoutConstraint.activate([
            openInNewTabButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: Constants.barButtonMargin),
            openInNewTabButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            openInNewTabButton.heightAnchor.constraint(equalToConstant: Constants.barButtonHeight),
            openInNewTabButton.widthAnchor.constraint(equalToConstant: Constants.barButtonWidth),

            titleLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: openInNewTabButton.trailingAnchor, constant: Constants.titleLabelSideMargin),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -Constants.titleLabelSideMargin),

            closeButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -Constants.barButtonMargin),
            closeButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            closeButton.heightAnchor.constraint(equalToConstant: Constants.barButtonHeight),
            closeButton.widthAnchor.constraint(equalToConstant: Constants.barButtonWidth),
        ])
    }

    private func createAndSetupWebViewContainer(in container: NSView) {
        webViewContainer = WebViewContainerView(tab: aiTab, webView: aiTab.webView, frame: .zero)
        webViewContainer.translatesAutoresizingMaskIntoConstraints = false
        webViewContainer.wantsLayer = true
        webViewContainer.layer?.masksToBounds = true
        webViewContainer.layer?.backgroundColor = NSColor.navigationBarBackground.cgColor
        container.addSubview(webViewContainer)

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
        let aiChatRestorationData = aiTab.aiChat?.aiChatUserScript?.handler.messageHandling.getDataForMessageType(.chatRestorationData) as? AIChatRestorationData

        delegate?.didClickOpenInNewTabButton(currentAIChatURL: currentAIChatURL.removingPlacementParameter(), aiChatRestorationData: aiChatRestorationData)
    }

    @objc private func closeButtonClicked() {
        delegate?.didClickCloseButton()
    }

    func stopLoading() {
        aiTab.webView.navigationDelegate = nil
        aiTab.webView.uiDelegate = nil

        aiTab.webView.stopLoading()
        aiTab.webView.loadHTMLString("", baseURL: nil)
    }
}

extension AIChatSidebarViewController: TabDelegate {

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
