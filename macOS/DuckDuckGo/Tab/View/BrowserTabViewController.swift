//
//  BrowserTabViewController.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Cocoa
import Combine
import Common
import FeatureFlags
import Freemium
import HistoryView
import NewTabPage
import Onboarding
import os.log
import PixelKit
import Subscription
import SwiftUI
import UserScript
import WebKit
import DataBrokerProtection_macOS

protocol BrowserTabViewControllerDelegate: AnyObject {
    func highlightFireButton()
    func highlightPrivacyShield()
    func dismissViewHighlight()
    func closeWindowIfNeeded() -> Bool
}

final class BrowserTabViewController: NSViewController {

    private lazy var browserTabView = BrowserTabView(frame: .zero, backgroundColor: .browserTabBackground)
    private(set) lazy var sidebarContainer = ColorView(frame: .zero, backgroundColor: .browserTabBackground, borderWidth: 0)
    private lazy var hoverLabel = NSTextField(string: URL.duckDuckGo.absoluteString)
    private lazy var hoverLabelContainer = ColorView(frame: .zero, backgroundColor: .browserTabBackground, borderWidth: 0)

    private let activeRemoteMessageModel: ActiveRemoteMessageModel
    private let newTabPageActionsManager: NewTabPageActionsManager
    private(set) lazy var newTabPageWebViewModel: NewTabPageWebViewModel = NewTabPageWebViewModel(
        featureFlagger: featureFlagger,
        actionsManager: newTabPageActionsManager,
        activeRemoteMessageModel: activeRemoteMessageModel
    )

    private let pinnedTabsManagerProvider: PinnedTabsManagerProviding = Application.appDelegate.pinnedTabsManagerProvider

    private(set) weak var webView: WebView?
    private weak var webViewContainer: NSView?
    @Published private var webViewSnapshot: NSView?
    private var containerStackView: NSStackView

    private weak var webExtensionWebView: WebView?

    weak var delegate: BrowserTabViewControllerDelegate?
    var tabViewModel: TabViewModel?

    private let tabCollectionViewModel: TabCollectionViewModel
    private let bookmarkManager: BookmarkManager
    private let bookmarkDragDropManager: BookmarkDragDropManager
    private let dockCustomizer = DockCustomizer()
    private let onboardingDialogTypeProvider: ContextualOnboardingDialogTypeProviding & ContextualOnboardingStateUpdater

    private let onboardingDialogFactory: ContextualDaxDialogsFactory
    private let featureFlagger: FeatureFlagger
    private let windowControllersManager: WindowControllersManagerProtocol
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let tld: TLD

    private var tabViewModelCancellables = Set<AnyCancellable>()
    private var activeUserDialogCancellable: Cancellable?
    private var duckPlayerConsentCancellable: AnyCancellable?
    private var pinnedTabsDelegatesCancellable: AnyCancellable?
    private var keyWindowSelectedTabCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    private weak var previouslySelectedTab: Tab?

    private var hoverLabelWorkItem: DispatchWorkItem?

    private var lastURL: URL?
    private weak var lastTab: Tab?
    private var wasContextualOnboardingDialogDismissed = false
    private let onboardingPixelReporter: OnboardingPixelReporting

    private(set) var transientTabContentViewController: NSViewController?
    private lazy var duckPlayerOnboardingModalManager: DuckPlayerOnboardingModalManager = {
        let modal = DuckPlayerOnboardingModalManager()
        return modal
    }()

    public weak var aiChatSidebarHostingDelegate: AIChatSidebarHostingDelegate?

    required init?(coder: NSCoder) {
        fatalError("BrowserTabViewController: Bad initializer")
    }

    init(tabCollectionViewModel: TabCollectionViewModel,
         bookmarkManager: BookmarkManager = NSApp.delegateTyped.bookmarkManager,
         bookmarkDragDropManager: BookmarkDragDropManager = NSApp.delegateTyped.bookmarkDragDropManager,
         onboardingPixelReporter: OnboardingPixelReporting = OnboardingPixelReporter(),
         onboardingDialogTypeProvider: ContextualOnboardingDialogTypeProviding & ContextualOnboardingStateUpdater = Application.appDelegate.onboardingContextualDialogsManager,
         onboardingDialogFactory: ContextualDaxDialogsFactory = DefaultContextualDaxDialogViewFactory(fireCoordinator: NSApp.delegateTyped.fireCoordinator),
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
         windowControllersManager: WindowControllersManagerProtocol = NSApp.delegateTyped.windowControllersManager,
         newTabPageActionsManager: NewTabPageActionsManager = NSApp.delegateTyped.newTabPageCoordinator.actionsManager,
         activeRemoteMessageModel: ActiveRemoteMessageModel = NSApp.delegateTyped.activeRemoteMessageModel,
         privacyConfigurationManager: PrivacyConfigurationManaging = NSApp.delegateTyped.privacyFeatures.contentBlocking.privacyConfigurationManager,
         tld: TLD = NSApp.delegateTyped.tld
    ) {
        self.tabCollectionViewModel = tabCollectionViewModel
        self.bookmarkManager = bookmarkManager
        self.bookmarkDragDropManager = bookmarkDragDropManager
        self.onboardingPixelReporter = onboardingPixelReporter
        self.onboardingDialogTypeProvider = onboardingDialogTypeProvider
        self.onboardingDialogFactory = onboardingDialogFactory
        self.featureFlagger = featureFlagger
        self.windowControllersManager = windowControllersManager
        self.newTabPageActionsManager = newTabPageActionsManager
        self.activeRemoteMessageModel = activeRemoteMessageModel
        self.privacyConfigurationManager = privacyConfigurationManager
        self.tld = tld
        containerStackView = NSStackView()

        super.init(nibName: nil, bundle: nil)
    }

    override func loadView() {
        view = browserTabView

        hoverLabelContainer.cornerRadius = 4
        view.addSubview(hoverLabelContainer)

        hoverLabel.focusRingType = .none
        hoverLabel.translatesAutoresizingMaskIntoConstraints = false
        hoverLabel.font = .systemFont(ofSize: 13)
        hoverLabel.drawsBackground = false
        hoverLabel.isEditable = false
        hoverLabel.isBordered = false
        hoverLabel.lineBreakMode = .byClipping
        hoverLabel.textColor = .labelColor
        hoverLabelContainer.addSubview(hoverLabel)

        setupLayout()
    }

    private func setupLayout() {
        hoverLabelContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -2).isActive = true
        view.bottomAnchor.constraint(equalTo: hoverLabelContainer.bottomAnchor, constant: -4).isActive = true

        hoverLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
        hoverLabel.setContentHuggingPriority(.init(rawValue: 251), for: .horizontal)
        hoverLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        hoverLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        hoverLabelContainer.bottomAnchor.constraint(equalTo: hoverLabel.bottomAnchor, constant: 10).isActive = true
        hoverLabel.leadingAnchor.constraint(equalTo: hoverLabelContainer.leadingAnchor, constant: 12).isActive = true
        hoverLabelContainer.trailingAnchor.constraint(equalTo: hoverLabel.trailingAnchor, constant: 8).isActive = true
        hoverLabel.topAnchor.constraint(equalTo: hoverLabelContainer.topAnchor, constant: 6).isActive = true

        if featureFlagger.isFeatureOn(.aiChatSidebar) {
            view.addSubview(sidebarContainer)

            sidebarContainerLeadingConstraint = sidebarContainer.leadingAnchor.constraint(equalTo: browserTabView.trailingAnchor)
            sidebarContainerWidthConstraint = sidebarContainer.widthAnchor.constraint(equalToConstant: 0)

            NSLayoutConstraint.activate([
                sidebarContainer.topAnchor.constraint(equalTo: browserTabView.topAnchor),
                sidebarContainer.bottomAnchor.constraint(equalTo: browserTabView.bottomAnchor),
                sidebarContainerLeadingConstraint!,
                sidebarContainerWidthConstraint!
            ])
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        hoverLabelContainer.alphaValue = 0

        if let webViewContainer {
            removeChild(in: self.containerStackView, webViewContainer: webViewContainer)
        }

        view.registerForDraggedTypes([.URL, .fileURL])
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        subscribeToTabs()
        subscribeToSelectedTabViewModel()
        addMouseMonitors()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()

        cancellables.removeAll()
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        subscribeToNotifications()
    }

    @objc
    private func windowWillClose(_ notification: NSNotification) {
        self.removeWebViewFromHierarchy()
        self.newTabPageWebViewModel.removeUserScripts()
    }

    @objc
    private func onDuckDuckGoEmailIncontextSignup(_ notification: Notification) {
        guard Application.appDelegate.windowControllersManager.lastKeyMainWindowController === self.view.window?.windowController else { return }

        self.previouslySelectedTab = tabCollectionViewModel.selectedTab
        let tab = Tab(content: .url(EmailUrls().emailProtectionInContextSignupLink, source: .ui), shouldLoadInBackground: true, burnerMode: tabCollectionViewModel.burnerMode)
        tabCollectionViewModel.append(tab: tab)
    }

    @objc
    private func onCloseDuckDuckGoEmailProtection(_ notification: Notification) {
        guard Application.appDelegate.windowControllersManager.lastKeyMainWindowController === self.view.window?.windowController,
              let previouslySelectedTab else { return }

        if let activeTab = tabViewModel?.tab,
           let url = activeTab.url,
           EmailUrls().isDuckDuckGoEmailProtection(url: url) {

            self.closeTab(activeTab)
        }

        tabCollectionViewModel.select(tab: previouslySelectedTab)
        previouslySelectedTab.webView.evaluateJavaScript("window.openAutofillAfterClosingEmailProtectionTab()", in: nil, in: WKContentWorld.defaultClient)
        self.previouslySelectedTab = nil
    }

    @objc
    private func onPasswordImportFlowFinish(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard Application.appDelegate.windowControllersManager.lastKeyMainWindowController === self.view.window?.windowController else { return }
            if let previouslySelectedTab {
                tabCollectionViewModel.select(tab: previouslySelectedTab)
                previouslySelectedTab.webView.evaluateJavaScript("window.credentialsImportFinished()", in: nil, in: WKContentWorld.defaultClient)
                self.previouslySelectedTab = nil
            } else {
                webView?.evaluateJavaScript("window.credentialsImportFinished()", in: nil, in: WKContentWorld.defaultClient)
            }
        }
    }

    @objc
    private func onDBPFeatureDisabled(_ notification: Notification) {
        Task { @MainActor in
            tabCollectionViewModel.removeAll(with: .dataBrokerProtection)
        }
    }

    @objc
    private func onCloseDataBrokerProtection(_ notification: Notification) {
        guard let activeTab = tabViewModel?.tab,
              view.window?.isKeyWindow == true else { return }

        self.closeTab(activeTab)

        if let previouslySelectedTab = self.previouslySelectedTab {
            tabCollectionViewModel.select(tab: previouslySelectedTab)
            self.previouslySelectedTab = nil
        }
    }

    @objc
    private func onDataBrokerWaitlistGetStartedPressedByUser(_ notification: Notification) {
        Application.appDelegate.windowControllersManager.showDataBrokerProtectionTab()
    }

    @objc
    private func onCloseSubscriptionPage(_ notification: Notification) {
        guard let activeTab = tabViewModel?.tab else { return }
        self.closeTab(activeTab)

        if let previouslySelectedTab = self.previouslySelectedTab {
            tabCollectionViewModel.select(tab: previouslySelectedTab)
            self.previouslySelectedTab = nil
        }

        openNewTab(with: .settings(pane: .subscriptionSettings))
    }

    @objc
    private func onSubscriptionAccountDidSignOut(_ notification: Notification) {
        Task { @MainActor in
            tabCollectionViewModel.removeAll { tabContent in
                if case .subscription = tabContent {
                    return true
                } else if case .identityTheftRestoration = tabContent {
                    return true
                } else {
                    return false
                }
            }
        }
    }

    @objc
    private func onSubscriptionUpgradeFromFreemium(_ notification: Notification) {
        Task { @MainActor in
            tabCollectionViewModel.removeAll(with: .dataBrokerProtection)
        }
    }

    private func subscribeToSelectedTabViewModel() {
        tabCollectionViewModel.$selectedTabViewModel
            .sink { [weak self] selectedTabViewModel in
                guard let self else { return }

                tabViewModelCancellables.removeAll(keepingCapacity: true)
                removeExistingDialog()

                generateNativePreviewIfNeeded()
                tabViewModel = selectedTabViewModel
                showTabContent(of: selectedTabViewModel)

                subscribeToTabContent(of: selectedTabViewModel)
                subscribeToHoveredLink(of: selectedTabViewModel)
                subscribeToUserDialogs(of: selectedTabViewModel)

                // changing tab is considered equivalent to dismissing the dialog
                wasContextualOnboardingDialogDismissed = true

                adjustFirstResponder(force: true)
            }
            .store(in: &cancellables)
    }

    private func subscribeToTabs() {
        tabCollectionViewModel.tabCollection.$tabs
            .sink {  [weak self] tabs in
                guard let self else { return }
                setDelegate(for: tabs)
                removeDataBrokerViewIfNecessary(for: tabs)
                cleanUpSidebarsForClosedTabs(for: tabs)
            }
            .store(in: &cancellables)
    }

    private func subscribeToPinnedTabs() {
        pinnedTabsDelegatesCancellable = tabCollectionViewModel.pinnedTabsCollection?.$tabs
            .sink(receiveValue: { [weak self] tabs in
                guard let self else { return }
                setDelegate(for: tabs)
            })
    }

    private func subscribeToNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(windowWillClose(_:)),
                                               name: NSWindow.willCloseNotification,
                                               object: self.view.window)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onDuckDuckGoEmailIncontextSignup),
                                               name: .emailDidIncontextSignup,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onCloseDuckDuckGoEmailProtection),
                                               name: .emailDidCloseEmailProtection,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onPasswordImportFlowFinish),
                                               name: .passwordImportDidCloseImportDialog,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onDBPFeatureDisabled),
                                               name: .dbpWasDisabled,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onCloseDataBrokerProtection),
                                               name: .dbpDidClose,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onCloseSubscriptionPage),
                                               name: .subscriptionPageCloseAndOpenPreferences,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onSubscriptionAccountDidSignOut),
                                               name: .accountDidSignOut,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onSubscriptionUpgradeFromFreemium),
                                               name: .subscriptionUpgradeFromFreemium,
                                               object: nil)
    }

    private func removeDataBrokerViewIfNecessary(for tabs: [Tab]) {
        if let dataBrokerProtectionHomeViewController,
           !tabs.contains(where: { $0.content == .dataBrokerProtection }) {
            dataBrokerProtectionHomeViewController.removeCompletely()
            self.dataBrokerProtectionHomeViewController = nil
        }
    }

    private func setDelegate(for tabs: [Tab]) {
        for tab in tabs {
            tab.setDelegate(self)
            tab.autofill?.setDelegate(self)
            tab.downloads?.delegate = self
        }
    }

    private func cleanUpSidebarsForClosedTabs(for currentTabs: [Tab]) {
        let currentTabIDs = currentTabs.map { $0.id }
        let currentPinnedTabIDs = tabCollectionViewModel.pinnedTabsCollection?.tabs.map { $0.id } ?? []
        aiChatSidebarHostingDelegate?.sidebarHostDidUpdateTabs(currentTabIDs + currentPinnedTabIDs)
    }

    private func removeWebViewFromHierarchy(webView: WebView? = nil,
                                            container: NSView? = nil) {

        func removeWebInspectorFromHierarchy(container: NSView) {
            // Fixes the issue of web inspector unintentionally detaching from the parent view to a standalone window
            for subview in container.subviews where subview.className.contains("WKInspector") {
                subview.removeFromSuperview()
            }
        }

        guard let webView = webView ?? self.webView,
              let container = container ?? self.webViewContainer
        else { return }

        if self.webView === webView {
            self.webView = nil
        }

        if webView.window === view.window, webView.isInspectorShown {
            removeWebInspectorFromHierarchy(container: container)
        }
        container.removeFromSuperview()
        if self.webViewContainer === container {
            self.webViewContainer = nil
        }
    }

    private(set) var sidebarContainerLeadingConstraint: NSLayoutConstraint?
    private(set) var sidebarContainerWidthConstraint: NSLayoutConstraint?

    private func addWebViewToViewHierarchy(_ webView: WebView, tab: Tab) {
        let container = WebViewContainerView(tab: tab, webView: webView, frame: view.bounds)
        self.webViewContainer = container
        containerStackView.orientation = .vertical
        containerStackView.alignment = .leading
        containerStackView.distribution = .fillProportionally
        containerStackView.spacing = 0

        // Make sure link preview (tooltip shown in the bottom-left) is on top
        view.addSubview(containerStackView, positioned: .below, relativeTo: hoverLabelContainer)

        containerStackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            containerStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerStackView.topAnchor.constraint(equalTo: view.topAnchor),
            containerStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let constraint =  featureFlagger.isFeatureOn(.aiChatSidebar) ? sidebarContainer.leadingAnchor : view.trailingAnchor
        NSLayoutConstraint.activate([
            containerStackView.trailingAnchor.constraint(equalTo: constraint)
        ])

        containerStackView.addArrangedSubview(container)
    }

    private func removeExistingDialog() {
        containerStackView.arrangedSubviews.filter({ $0 != webViewContainer }).forEach {
            containerStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    private func presentContextualOnboarding(showLastDialog: Bool = false) {
        // Before presenting a new dialog, remove any existing ones.
        removeExistingDialog()
        // Remove any existing highlights animation
        delegate?.dismissViewHighlight()

        // Checks if the feature is on
        guard featureFlagger.isFeatureOn(.contextualOnboarding) else {
            onboardingDialogTypeProvider.turnOffFeature()
            return
        }

        guard let tab = tabViewModel?.tab else { return }

        // if showLastDialog is true it asks the onboardingDialogTypeProvider for the lastDialog if the last dialog was shown on this tab
        // If there is it will show it
        // This allow seeing the dialog when leaving and coming back to the Window but will avoid reloading the same when opening a new Window
        guard let dialogType = showLastDialog ? onboardingDialogTypeProvider.lastDialogForTab(tab) : onboardingDialogTypeProvider.dialogTypeForTab(tab, privacyInfo: tab.privacyInfo) else {
            delegate?.dismissViewHighlight()
            return
        }
        // once a dialog is presented we reset the is dismissed flag
        self.wasContextualOnboardingDialogDismissed = false

        var onDismissAction: () -> Void = {}
        if let webViewContainer {
            onDismissAction = { [weak self] in
                guard let self else { return }
                // we mark the flag for dialog dismissed
                wasContextualOnboardingDialogDismissed = true
                delegate?.dismissViewHighlight()
                self.removeChild(in: self.containerStackView, webViewContainer: webViewContainer)
                if let lastDialog = onboardingDialogTypeProvider.lastDialog {
                    self.onboardingPixelReporter.measureDialogDismissed(dialogType: lastDialog)
                }
            }
        }

        let onGotItPressed = { [weak self] in
            guard let self else { return }

            onboardingDialogTypeProvider.gotItPressed()

            let currentState = onboardingDialogTypeProvider.lastDialog

            // Reset highlight animations
            delegate?.dismissViewHighlight()

            // Process state
            if case .tryFireButton = currentState {
                delegate?.highlightFireButton()
            }
        }

        let daxView = onboardingDialogFactory.makeView(
            for: dialogType,
            delegate: tab,
            onDismiss: onDismissAction,
            onGotItPressed: onGotItPressed,
            onFireButtonPressed: { [weak delegate] in
                delegate?.dismissViewHighlight()
            })
        let hostingController = NSHostingController(rootView: AnyView(daxView))
        insertChild(hostingController, in: containerStackView, at: 0)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.widthAnchor.constraint(equalTo: containerStackView.widthAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: containerStackView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: containerStackView.trailingAnchor),
        ])

        containerStackView.layoutSubtreeIfNeeded()
        webViewContainer?.layoutSubtreeIfNeeded()

        if dialogType == .tryFireButton {
            delegate?.highlightFireButton()
        } else if case .trackers = dialogType {
            delegate?.highlightPrivacyShield()
        }
    }

    private func changeWebView(tabViewModel: TabViewModel?) {

        func cleanUpRemoteWebViewIfNeeded(_ webView: WebView) {
            if webView.containerView !== webViewContainer {
                webView.containerView?.removeFromSuperview()
            }
        }

        func displayWebView(of tabViewModel: TabViewModel) {
            let newWebView = webView(for: tabViewModel)
            // if a pinned tab displayed in another window is ⌘-clicked in a background window
            // don‘t display the web view but its snapshot instead
            if view.window?.isKeyWindow == false,
               pinnedTabsManagerProvider.pinnedTabsMode == .shared,
               let window = newWebView.window, window !== view.window,
               let mainWindowController = window.windowController as? MainWindowController,
               let tabIndex = mainWindowController.mainViewController.browserTabViewController.tabCollectionViewModel.selectionIndex,
               tabIndex.isPinnedTab, tabIndex == tabCollectionViewModel.selectionIndex {
                guard webViewSnapshot == nil else { return }

                makeWebViewSnapshot(newWebView)
                return
            }
            cleanUpRemoteWebViewIfNeeded(newWebView)
            webView = newWebView

            addWebViewToViewHierarchy(newWebView, tab: tabViewModel.tab)
            if let webViewSnapshot {
                webViewSnapshot.removeFromSuperview()
                self.webViewSnapshot = nil
            }
        }

        guard let tabViewModel else {
            removeWebViewFromHierarchy()
            return
        }

        let oldWebView = webView
        let webViewContainer = webViewContainer

        displayWebView(of: tabViewModel)

        if let oldWebView = oldWebView, let webViewContainer = webViewContainer, oldWebView !== webView {
            removeWebViewFromHierarchy(webView: oldWebView, container: webViewContainer)
        }
        adjustFirstResponderAfterAddingContentViewIfNeeded()
    }

    private func webView(for tabViewModel: TabViewModel, tabContent: Tab.TabContent? = nil) -> WebView {
        let tabContent = tabContent ?? tabViewModel.tabContent
        switch tabContent {
        case .newtab:
            return newTabPageWebViewModel.webView
        default:
            return tabViewModel.tab.webView
        }
    }

    private func subscribeToTabContent(of tabViewModel: TabViewModel?) {
        tabViewModel?.tab.$content
            .dropFirst()
            .removeDuplicates(by: { old, new in
                // no need to call showTabContent if webView stays in place and only its URL changes
                if old.isUrl && new.isUrl {
                    return true
                }
                return old == new
            })
            .map { [weak self, tabViewModel] tabContent -> AnyPublisher<Void, Never> in
                // For non-URL tabs, just emit an event displaying the tab content
                guard let tabViewModel, tabContent.isUrl else {
                    return Just(()).eraseToAnyPublisher()
                }

                // If the current content is the native internal site, delay the webview presentation
                // until a website renders (or edge cases) to avoid white flash
                if [URL.newtab, URL.settings, URL.bookmarks].contains(self?.lastURL) &&
                    self?.featureFlagger.isFeatureOn(.delayedWebviewPresentation) == true {
                    return Publishers.Merge5(
                        tabViewModel.tab.webViewDidReceiveRedirectPublisher,
                        tabViewModel.tab.webViewRenderingProgressDidChangePublisher,
                        tabViewModel.tab.webViewDidFailNavigationPublisher,
                        tabViewModel.tab.webViewDidReceiveUserInteractiveChallengePublisher,
                        tabViewModel.tab.webViewDidFinishNavigationPublisher
                        )
                    // take the first such event and move forward.
                    .prefix(1)
                    .eraseToAnyPublisher()
                } else {
                    // For URL tabs, we only want to show tab content (webView) when
                    // it has content to display (first navigation had been committed)
                    // or starts navigation.
                    return Publishers.Merge(
                        tabViewModel.tab.$hasCommittedContent
                            .filter { $0 == true }
                            .asVoid(),
                        tabViewModel.tab.navigationStatePublisher.compactMap { $0 }
                            .filter{ $0 >= .started }
                            .asVoid()
                    )
                    // take the first such event and move forward.
                    .prefix(1)
                    .eraseToAnyPublisher()
                }
            }
            .switchToLatest()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak tabViewModel] in
                guard let tabViewModel else { return }
                self?.showTabContent(of: tabViewModel)
            }
            .store(in: &tabViewModelCancellables)

        tabViewModel?.tab.webViewDidFinishNavigationPublisher.sink { [weak self] in
            guard let self else { return }
            // remove dialog on reload
            if tabViewModel?.tab == lastTab && self.lastURL == tabViewModel?.tab.url && self.lastURL != nil {
                self.removeExistingDialog()
                return
            }
            // present contextual onboarding dialog if needed
            self.presentContextualOnboarding()
            self.lastURL = self.tabViewModel?.tab.url
            self.lastTab = self.tabViewModel?.tab
        }.store(in: &tabViewModelCancellables)
    }

    private func subscribeToUserDialogs(of tabViewModel: TabViewModel?) {
        guard let tabViewModel else { return }

        struct CombinedArg: Equatable {
            let dialog: Tab.UserDialog?
            let isDisplayingSnapshot: Bool
        }
        Publishers.CombineLatest3(
            tabViewModel.tab.$userInteractionDialog,
            tabViewModel.tab.downloads?.savePanelDialogPublisher ?? Just(nil).eraseToAnyPublisher(),
            // when switching to a window containing a pinned tab snapshot re-display an already-presented dialog in this window
            $webViewSnapshot.map { $0 != nil }
        )
        .map { userDialog, saveDialog, isDisplayingSnapshot in
            return CombinedArg(dialog: saveDialog ?? userDialog, isDisplayingSnapshot: isDisplayingSnapshot)
        }
        .removeDuplicates()
        .sink { [weak self] arg in
            self?.show(arg.dialog, isDisplayingSnapshot: arg.isDisplayingSnapshot)
        }
        .store(in: &tabViewModelCancellables)
    }

    func subscribeToHoveredLink(of tabViewModel: TabViewModel?) {
        tabViewModel?.tab.hoveredLinkPublisher.sink { [weak self] in
            self?.scheduleHoverLabelUpdatesForUrl($0)
        }.store(in: &tabViewModelCancellables)
#if DEBUG
        if case .xcPreviews = AppVersion.runType {
            self.scheduleHoverLabelUpdatesForUrl(.duckDuckGo)
        }
#endif
    }

    private func shouldMakeContentViewFirstResponder(for tabContent: Tab.TabContent) -> Bool {
        // always steal focus when first responder is not a text field
        guard view.window?.firstResponder is NSText else {
            return true
        }

        switch tabContent {
        case .newtab:
            return false
        case .url(_, _, source: .webViewUpdated):
            // prevent Address Bar deactivation when the WebView is restoring state or updates url on redirect
            return false

        case .url(_, _, source: .pendingStateRestoration),
             .url(_, _, source: .loadedByStateRestoration),
             .url(_, _, source: .userEntered),
             .url(_, _, source: .historyEntry),
             .url(_, _, source: .bookmark),
             .url(_, _, source: .ui),
             .url(_, _, source: .link),
             .url(_, _, source: .appOpenUrl),
             .url(_, _, source: .switchToOpenTab),
             .url(_, _, source: .reload):
            return true

        case .settings, .bookmarks, .history, .dataBrokerProtection, .subscription, .onboarding, .releaseNotes, .identityTheftRestoration, .webExtensionUrl, .aiChat:
            return true

        case .none:
            return false
        }
    }

    func adjustFirstResponder(force: Bool = false, tabViewModel: TabViewModel? = nil, tabContent: Tab.TabContent? = nil) {
        viewToMakeFirstResponderAfterAdding = nil
        guard let window = view.window, window.isVisible,
              let tabViewModel = tabViewModel ?? self.tabViewModel else { return }
        let tabContent = tabContent ?? tabViewModel.tab.content
        guard force || shouldMakeContentViewFirstResponder(for: tabContent) else { return }

        let getView: (() -> NSView?)?
        switch tabContent {
        case .newtab:
            // don‘t steal focus from the address bar at .newtab page
            return
        case .url, .subscription, .identityTheftRestoration, .onboarding, .releaseNotes, .history, .aiChat:
            getView = { [weak self, weak tabViewModel] in
                guard let self, let tabViewModel else { return nil }
                return webView(for: tabViewModel, tabContent: tabContent)
            }
        case .settings:
            getView = { [weak self] in self?.preferencesViewController?.view }
        case .bookmarks:
            getView = { [weak self] in self?.bookmarksViewController?.view }
        case .dataBrokerProtection:
            getView = { [weak self] in self?.dataBrokerProtectionHomeViewController?.view }
        case .webExtensionUrl:
            getView = { [weak self] in self?.webExtensionWebView }
        case .none:
            getView = nil
        }

        var contentView = getView?()
        if let getView, contentView == nil || contentView?.window !== window {
            // if contentView in wrong window or not created yet - activate after adding
            viewToMakeFirstResponderAfterAdding = getView
            contentView = nil
        }

        guard window.firstResponder !== contentView ?? window else { return }
        window.makeFirstResponder(contentView)
    }

    private var viewToMakeFirstResponderAfterAdding: (() -> NSView?)?
    private func adjustFirstResponderAfterAddingContentViewIfNeeded() {
        guard let window = view.window,
              let contentView = viewToMakeFirstResponderAfterAdding?() else {
            return
        }

        guard contentView.window === window else {
            Logger.general.error("BrowserTabViewController: Content view window is \(contentView.window?.description ?? "<nil>") but expected: \(window)")
            return
        }
        viewToMakeFirstResponderAfterAdding = nil

        // if the Address Bar was activated after the initial adjustFirstResponder call -
        // don‘t steal focus from the Address Bar
        guard window.firstResponder === window else {
            self.viewToMakeFirstResponderAfterAdding = nil
            return
        }

        window.makeFirstResponder(contentView)
    }

    @discardableResult
    func openNewTab(with content: Tab.TabContent) -> Tab? {
        guard tabCollectionViewModel.selectDisplayableTabIfPresent(content) == false else {
            return nil
        }

        // shouldn't open New Tabs in PopUp window
        if view.window?.isPopUpWindow ?? true {
            // Prefer Tab's Parent
            Application.appDelegate.windowControllersManager.showTab(with: content)
            return nil
        }

        let tab = Tab(content: content,
                      shouldLoadInBackground: true,
                      burnerMode: tabCollectionViewModel.burnerMode,
                      webViewSize: view.frame.size)

        tabCollectionViewModel.insertOrAppend(tab: tab, selected: true)

        return tab
    }

    // MARK: - Browser Tabs

    private func removeAllTabContent(includingWebView: Bool = true) {
        transientTabContentViewController?.removeCompletely()
        preferencesViewController?.removeCompletely()
        bookmarksViewController?.removeCompletely()
        burnerHomePageViewController?.removeCompletely()
        webExtensionWebView?.superview?.removeFromSuperview()
        webExtensionWebView = nil
        dataBrokerProtectionHomeViewController?.removeCompletely()
        if includingWebView {
            self.removeWebViewFromHierarchy()
        }
    }

    private func showTransientTabContentController(_ vc: NSViewController) {
        transientTabContentViewController?.removeCompletely()
        addAndLayoutChild(vc)
        transientTabContentViewController = vc
    }

    private func requestDisableUI() {
        (view.window?.windowController as? MainWindowController)?.userInteraction(prevented: true)
    }

    private func showTabContent(of tabViewModel: TabViewModel?) {
        // window closing is handled in the MainWindowController
        guard delegate?.closeWindowIfNeeded() != true else { return }

        scheduleHoverLabelUpdatesForUrl(nil)
        defer {
            adjustFirstResponderAfterAddingContentViewIfNeeded()
        }

        switch tabViewModel?.tab.content {
        case .bookmarks:
            removeAllTabContent()
            addAndLayoutChild(bookmarksViewControllerCreatingIfNeeded())

        case let .settings(pane):
            showTabContentForSettings(pane: pane)

        case .onboarding, .releaseNotes:
            removeAllTabContent()
            updateTabIfNeeded(tabViewModel: tabViewModel)

        case .url, .subscription, .identityTheftRestoration, .aiChat:
            updateTabIfNeeded(tabViewModel: tabViewModel)

        case .newtab:
            // We only use HTML New Tab Page in regular windows for now
            if tabCollectionViewModel.isBurner {
                removeAllTabContent()
                addAndLayoutChild(burnerHomePageViewControllerCreatingIfNeeded())
            } else {
                updateTabIfNeeded(tabViewModel: tabViewModel)
            }

        case .history:
            if featureFlagger.isFeatureOn(.historyView) {
                updateTabIfNeeded(tabViewModel: tabViewModel)
            } else {
                removeAllTabContent()
            }

        case .dataBrokerProtection:
            removeAllTabContent()
            let dataBrokerProtectionViewController = dataBrokerProtectionHomeViewControllerCreatingIfNeeded()
            self.previouslySelectedTab = tabCollectionViewModel.selectedTab
            addAndLayoutChild(dataBrokerProtectionViewController)

        case .webExtensionUrl:
            removeAllTabContent()
#if !APPSTORE && WEB_EXTENSIONS_ENABLED
            if #available(macOS 15.4, *) {
                if let tab = tabViewModel?.tab,
                   let url = tab.url,
                   let webExtensionWebView = WebExtensionManager.shared.internalSiteHandler.webViewForExtensionUrl(url) {
                    self.webExtensionWebView = webExtensionWebView
                    self.addWebViewToViewHierarchy(webExtensionWebView, tab: tab)
                }
            }
#endif
        default:
            removeAllTabContent()
        }
    }

    func updateTabIfNeeded(tabViewModel: TabViewModel?) {
        if shouldReplaceWebView(for: tabViewModel) {
            removeAllTabContent(includingWebView: true)
            changeWebView(tabViewModel: tabViewModel)

            if let tabID = tabViewModel?.tab.id {
                aiChatSidebarHostingDelegate?.sidebarHostDidSelectTab(with: tabID)
            }
        }
    }

    func showTabContentForSettings(pane: PreferencePaneIdentifier?) {
        let preferencesViewController = preferencesViewControllerCreatingIfNeeded()
        if preferencesViewController.parent !== self {
            removeAllTabContent()
        }
        if let pane = pane, preferencesViewController.model.selectedPane != pane {
            preferencesViewController.model.selectPane(pane)
        }
        if preferencesViewController.parent !== self {
            addAndLayoutChild(preferencesViewController)
        }
    }

    private func shouldReplaceWebView(for tabViewModel: TabViewModel?) -> Bool {
        guard let tabViewModel else { return false }

        let newWebView = webView(for: tabViewModel)
        let isPinnedTab = tabCollectionViewModel.pinnedTabsCollection?.tabs.contains(tabViewModel.tab) == true
        let isKeyWindow = view.window?.isKeyWindow == true

        let tabIsNotOnScreen = webView?.tabContentView.superview == nil
        let isDifferentTabDisplayed = webView !== newWebView

        return isDifferentTabDisplayed
        || tabIsNotOnScreen
        || (isPinnedTab && isKeyWindow && webView?.tabContentView.window !== view.window)
    }

    func generateNativePreviewIfNeeded() {
        guard let tabViewModel = tabViewModel, !tabViewModel.tab.content.isUrl, tabViewModel.tab.content != .history, !tabViewModel.isShowingErrorPage else {
            return
        }

        var containsHostingView: Bool
        switch tabViewModel.tab.content {
        case .onboarding:
            return
        case .newtab:
            guard tabCollectionViewModel.isBurner else {
                return
            }
            containsHostingView = false
        case .settings:
            containsHostingView = true
        default:
            containsHostingView = false
        }

        guard let viewForRendering = browserTabView.findContentSubview(containsHostingView: containsHostingView) else {
            assertionFailure("No view for rendering of the snapshot")
            return
        }

        Task {
            await tabViewModel.tab.tabSnapshots?.renderSnapshot(from: viewForRendering)
        }
    }

    // MARK: - New Tab page

    var burnerHomePageViewController: BurnerHomePageViewController?
    private func burnerHomePageViewControllerCreatingIfNeeded() -> BurnerHomePageViewController {
        return burnerHomePageViewController ?? {
            let burnerHomePageViewController = BurnerHomePageViewController()
            self.burnerHomePageViewController = burnerHomePageViewController
            return burnerHomePageViewController
        }()
    }

    // MARK: - DataBrokerProtection

    var dataBrokerProtectionHomeViewController: DBPHomeViewController?
    private func dataBrokerProtectionHomeViewControllerCreatingIfNeeded() -> DBPHomeViewController {
        return dataBrokerProtectionHomeViewController ?? {
            let freemiumDBPFeature = Application.appDelegate.freemiumDBPFeature
            let dataBrokerProtectionHomeViewController = DBPHomeViewController(
                dataBrokerProtectionManager: DataBrokerProtectionManager.shared,
                vpnBypassService: VPNBypassService(),
                privacyConfigurationManager: privacyConfigurationManager,
                freemiumDBPFeature: freemiumDBPFeature
            )
            self.dataBrokerProtectionHomeViewController = dataBrokerProtectionHomeViewController
            return dataBrokerProtectionHomeViewController
        }()
    }

    // MARK: - Preferences

    var preferencesViewController: PreferencesViewController?
    private func preferencesViewControllerCreatingIfNeeded() -> PreferencesViewController {
        return preferencesViewController ?? {
            guard let syncService = NSApp.delegateTyped.syncService else {
                fatalError("Sync service is nil")
            }
            let preferencesViewController = PreferencesViewController(
                syncService: syncService,
                tabCollectionViewModel: tabCollectionViewModel,
                privacyConfigurationManager: privacyConfigurationManager,
                featureFlagger: featureFlagger
            )
            preferencesViewController.delegate = self
            self.preferencesViewController = preferencesViewController
            return preferencesViewController
        }()
    }

    // MARK: - Bookmarks

    var bookmarksViewController: BookmarkManagementSplitViewController?
    private func bookmarksViewControllerCreatingIfNeeded() -> BookmarkManagementSplitViewController {
        return bookmarksViewController ?? {
            let bookmarksViewController = BookmarkManagementSplitViewController(bookmarkManager: bookmarkManager, dragDropManager: bookmarkDragDropManager)
            bookmarksViewController.delegate = self
            self.bookmarksViewController = bookmarksViewController
            return bookmarksViewController
        }()
    }

    private var contentOverlayPopover: ContentOverlayPopover?
    private func contentOverlayPopoverCreatingIfNeeded() -> ContentOverlayPopover {
        return contentOverlayPopover ?? {
            let overlayPopover = ContentOverlayPopover(
                currentTabView: self.view,
                privacyConfigurationManager: privacyConfigurationManager,
                featureFlagger: featureFlagger,
                tld: tld
            )
            self.contentOverlayPopover = overlayPopover
            windowControllersManager.stateChanged
                .sink { [weak overlayPopover] _ in
                    overlayPopover?.viewController.closeContentOverlayPopover()
                }.store(in: &self.cancellables)
            return overlayPopover
        }()
    }

    // MARK: - Alerts

    private func showAlert(with query: JSAlertQuery) -> AnyCancellable {
        let jsAlertController = JSAlertController.create(query)
        present(jsAlertController, animator: jsAlertController)

        return AnyCancellable { [weak self] in
            self?.dismiss(jsAlertController)
        }
    }

}

extension BrowserTabViewController: NSDraggingDestination {

    func draggingEntered(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
        return draggingUpdated(draggingInfo)
    }

    func draggingUpdated(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
        guard draggingInfo.draggingPasteboard.url != nil else { return .none }
        if let selectedTab = tabCollectionViewModel.selectedTab,
           selectedTab.isPinned {
            return .copy
        }

        return (NSApp.isCommandPressed || NSApp.isOptionPressed || !draggingInfo.draggingSourceOperationMask.contains(.move)) ? .copy : .move
    }

    func performDragOperation(_ draggingInfo: NSDraggingInfo) -> Bool {
        guard let url = draggingInfo.draggingPasteboard.url else { return false }

        guard !(NSApp.isCommandPressed || NSApp.isOptionPressed),
              let selectedTab = tabCollectionViewModel.selectedTab,
              !selectedTab.isPinned else {

            self.openNewTab(with: .url(url, source: .appOpenUrl))
            return true
        }

        selectedTab.setContent(.contentFromURL(url, source: .appOpenUrl))
        return true
    }

}

extension BrowserTabViewController: ContentOverlayUserScriptDelegate {
    public func websiteAutofillUserScriptCloseOverlay(_ websiteAutofillUserScript: WebsiteAutofillUserScript?) {
        contentOverlayPopoverCreatingIfNeeded().websiteAutofillUserScriptCloseOverlay(websiteAutofillUserScript)
    }
    public func websiteAutofillUserScript(_ websiteAutofillUserScript: WebsiteAutofillUserScript,
                                          willDisplayOverlayAtClick: NSPoint?,
                                          serializedInputContext: String,
                                          inputPosition: CGRect) {

        self.contentOverlayPopoverCreatingIfNeeded().websiteAutofillUserScript(websiteAutofillUserScript,
                                                                              willDisplayOverlayAtClick: willDisplayOverlayAtClick,
                                                                              serializedInputContext: serializedInputContext,
                                                                              inputPosition: inputPosition)

    }

}

extension BrowserTabViewController: TabDelegate {

    func tabWillStartNavigation(_ tab: Tab, isUserInitiated: Bool) {
        if isUserInitiated,
           let window = self.view.window,
           window.isPopUpWindow == true,
           window.isKeyWindow == false {

            window.makeKeyAndOrderFront(nil)
        }
    }

    func tabPageDOMLoaded(_ tab: Tab) {
        if tabViewModel?.tab === tab {
            tabViewModel?.isLoading = false
        }
    }

    func tabDidStartNavigation(_ tab: Tab) {
        guard let tabViewModel, tabViewModel.tab === tab else { return }

        if !tabViewModel.isLoading,
           tabViewModel.tab.webView.isLoading {
            tabViewModel.isLoading = true
        }
    }

    func tab(_ parentTab: Tab, createdChild childTab: Tab, of kind: NewWindowPolicy) {
        switch kind {
        case .popup(origin: let origin, size: let contentSize):
            WindowsManager.openPopUpWindow(with: childTab, origin: origin, contentSize: contentSize)
        case .window(active: let active, let isBurner):
            assert(isBurner == childTab.burnerMode.isBurner)
            WindowsManager.openNewWindow(with: childTab, showWindow: active)
        case .tab(selected: let selected, _, _):
            self.tabCollectionViewModel.insert(childTab, after: parentTab, selected: selected)
        }
    }

    func closeTab(_ tab: Tab) {
        guard let index = tabCollectionViewModel.tabCollection.tabs.firstIndex(of: tab) else {
            return
        }
        tabCollectionViewModel.remove(at: .unpinned(index))
    }

    func tab(_ tab: Tab,
             requestedBasicAuthenticationChallengeWith protectionSpace: URLProtectionSpace,
             completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let window = view.window else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let alert = AuthenticationAlert(host: protectionSpace.host, isEncrypted: protectionSpace.receivesCredentialSecurely)
        alert.beginSheetModal(for: window) { response in
            guard case .OK = response else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(user: alert.usernameTextField.stringValue,
                                                            password: alert.passwordTextField.stringValue,
                                                            persistence: .forSession))

        }
    }

    func windowDidBecomeKey() {
        keyWindowSelectedTabCancellable = nil
        subscribeToPinnedTabs()
        hideWebViewSnapshotIfNeeded()

        // When a windows become key it will reload the last contextual onboarding dialog if needed
        // This helps keep dialogs consistent when moving between Windows
        //  - If the dialog was dismissed it will not reload when leaving and coming back to the Window
        //  - It tells presentContextualOnboarding that should show the lastDialog if possible
        if !wasContextualOnboardingDialogDismissed && onboardingDialogTypeProvider.state != .onboardingCompleted {
            presentContextualOnboarding(showLastDialog: true)
        }
    }

    func windowDidResignKey() {
        pinnedTabsDelegatesCancellable = nil
        scheduleHoverLabelUpdatesForUrl(nil)
        subscribeToTabSelectedInCurrentKeyWindow()
    }

    private func scheduleHoverLabelUpdatesForUrl(_ url: URL?) {
        // cancel previous animation, if any
        hoverLabelWorkItem?.cancel()

        // schedule an animation if needed
        var animationItem: DispatchWorkItem?
        var delay: Double = 0
        if url == nil && hoverLabelContainer.alphaValue > 0 {
            // schedule a fade out
            delay = 0.1
            animationItem = DispatchWorkItem { [weak self] in
                self?.hoverLabelContainer.animator().alphaValue = 0
            }
        } else if url != nil && hoverLabelContainer.alphaValue < 1 {
            // schedule a fade in
            delay = 0.5
            animationItem = DispatchWorkItem { [weak self] in
                self?.hoverLabel.stringValue = url?.absoluteString ?? ""
                self?.hoverLabelContainer.animator().alphaValue = 1
            }
        } else {
            hoverLabel.stringValue = url?.absoluteString ?? ""
        }

        if let item = animationItem {
            hoverLabelWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    func tab(_ tab: Tab, requestedSaveAutofillData autofillData: AutofillData) {
        tabViewModel?.autofillDataToSave = autofillData
    }

    // MARK: - Dialogs

    fileprivate func show(_ dialog: Tab.UserDialog?, isDisplayingSnapshot: Bool) {
        // don‘t show dialogs in non-key windows displaying a pinned tab snapshot
        guard !isDisplayingSnapshot else {
            activeUserDialogCancellable = nil
            return
        }
        guard activeUserDialogCancellable == nil || dialog == nil else {
            // first hide a displayed dialog before showing another one
            activeUserDialogCancellable = nil
            DispatchQueue.main.async { [weak self] in
                self?.show(dialog, isDisplayingSnapshot: self!.webViewSnapshot != nil)
            }
            return
        }

        switch dialog?.dialog {
        case .basicAuthenticationChallenge(let query):
            activeUserDialogCancellable = showBasicAuthenticationChallenge(with: query)
        case .jsDialog(let query):
            activeUserDialogCancellable = showAlert(with: query)
        case .savePanel(let query):
            activeUserDialogCancellable = showSavePanel(with: query)
        case .openPanel(let query):
            activeUserDialogCancellable = showOpenPanel(with: query)
        case .print(let query):
            activeUserDialogCancellable = runPrintOperation(with: query)
        case .none:
            // modal sheet will close automatically (or switch to another Tab‘s dialog) when switching tabs
            activeUserDialogCancellable = nil
        }
    }

    private func showBasicAuthenticationChallenge(with request: BasicAuthDialogRequest) -> ModalSheetCancellable? {
        guard let window = view.window else { return nil }

        let alert = AuthenticationAlert(host: request.parameters.host,
                                        isEncrypted: request.parameters.receivesCredentialSecurely)
        alert.beginSheetModal(for: window) { [weak request] response in
            // don‘t submit the query when tab is switched
            if case .abort = response { return }
            guard case .OK = response else {
                request?.submit(nil)
                return
            }
            request?.submit(.credential(URLCredential(user: alert.usernameTextField.stringValue,
                                                     password: alert.passwordTextField.stringValue,
                                                     persistence: .forSession)))
        }

        // when subscribing to another Tab, the sheet will be temporarily closed with response == .abort on the cancellable deinit
        return ModalSheetCancellable(ownerWindow: window, modalSheet: alert.window, condition: !request.isComplete)
    }

    func showSavePanel(with request: SavePanelDialogRequest) -> ModalSheetCancellable? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let window = view.window else { return nil }

        let preferences = DownloadsPreferences.shared
        let directoryURL = preferences.lastUsedCustomDownloadLocation ?? preferences.effectiveDownloadLocation
        let savePanel = NSSavePanel.savePanelWithFileTypeChooser(fileTypes: request.parameters.fileTypes,
                                                                 suggestedFilename: request.parameters.suggestedFilename,
                                                                 directoryURL: directoryURL)

        savePanel.beginSheetModal(for: window) { [weak request, weak self] response in
            switch response {
            case .abort:
                // panel not closed by user but by a tab switching
                return
            case .OK:
                guard let self,
                      let window = view.window,
                      let url = savePanel.url else { fallthrough }

                do {
                    // validate selected URL is writable
                    try FileManager.default.checkWritability(url)
                } catch {
                    // hide the save panel
                    self.activeUserDialogCancellable = nil
                    NSAlert(error: error).beginSheetModal(for: window) { [weak self] _ in
                        guard let self, let request else { return }
                        self.activeUserDialogCancellable = showSavePanel(with: request)
                    }
                    return
                }
                request?.submit( (url, savePanel.selectedFileType) )
            default:
                request?.submit(nil)
            }
        }

        // when subscribing to another Tab, the sheet will be temporarily closed with response == .abort on the cancellable deinit
        return ModalSheetCancellable(ownerWindow: window, modalSheet: savePanel, condition: !request.isComplete)
    }

    func showOpenPanel(with request: OpenPanelDialogRequest) -> ModalSheetCancellable? {
        guard let window = view.window else { return nil }

        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = request.parameters.allowsMultipleSelection

        openPanel.beginSheetModal(for: window) { [weak request] response in
            switch response {
            case .abort:
                // don‘t submit the query when tab is switched
                return
            case .OK:
                request?.submit(openPanel.urls)
            default:
                request?.submit(nil)
            }
        }

        // when subscribing to another Tab, the sheet will be temporarily closed with response == .abort on the cancellable deinit
        return ModalSheetCancellable(ownerWindow: window, modalSheet: openPanel, condition: !request.isComplete)
    }

    private class PrintContext {
        let request: PrintDialogRequest
        weak var printPanel: NSWindow?
        var shouldRemoveWebView = false
        init(request: PrintDialogRequest) {
            self.request = request
        }
    }
    func runPrintOperation(with request: PrintDialogRequest) -> ModalSheetCancellable? {
        guard let window = view.window,
              let webView = tabViewModel?.tab.webView else { return nil }

        let printOperation = request.parameters
        // prevent running already started operation (e.g. when the same pinned tab is open in 2 windows)
        guard !printOperation.printInfo.isStarted else { return nil }
        printOperation.printInfo.isStarted = true

        let didRunSelector = #selector(printOperationDidRun(printOperation:success:contextInfo:))

        let windowSheetsBeforePrintOperation = window.sheets

        let context = PrintContext(request: request)
        let contextInfo = Unmanaged<PrintContext>.passRetained(context).toOpaque()

        printOperation.printPanel.options.formUnion([.showsPaperSize, .showsOrientation, .showsScaling])
        printOperation.runModal(for: window, delegate: self, didRun: didRunSelector, contextInfo: contextInfo)

        // get the Print Panel that (hopefully) was added to the window.sheets
        context.printPanel = Set(window.sheets).subtracting(windowSheetsBeforePrintOperation).first

        // when subscribing to another Tab, the print dialog will be cancelled on the cancellable deinit
        return ModalSheetCancellable(ownerWindow: window, modalSheet: context.printPanel, returnCode: .cancel, condition: {
            guard !context.request.isComplete else { return false }

            return true

        }(), cancellationHandler: { [weak self] in
            // Print operation temporarily pauses web view and window rendering
            // if the Web View is moved to another window or removed from view hierarchy
            // the WKPrintingView calls `setAutodisplay` on wrong `webView.window`
            // causing our window to fall into broken state.
            self?.view.window?.isAutodisplay = true
            self?.webView?.displayIfNeeded()
        })
    }

    @objc private func printOperationDidRun(printOperation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        guard let contextInfo else {
            assertionFailure("could not get query")
            return
        }
        let context = Unmanaged<PrintContext>.fromOpaque(contextInfo).takeRetainedValue()
        context.request.submit(success)
    }

}

extension BrowserTabViewController: TabDownloadsDelegate {

    func fileIconFlyAnimationOriginalRect(for downloadTask: WebKitDownloadTask) -> NSRect? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let window = self.view.window,
              let dockScreen = NSScreen.dockScreen
        else { return nil }

        // fly 64x64 icon from the center of Address Bar
        let size = view.bounds.size
        let rect = NSRect(x: size.width / 2 - 32, y: size.height / 2 - 32, width: 64, height: 64)
        let windowRect = view.convert(rect, to: nil)
        let globalRect = window.convertToScreen(windowRect)
        // to the Downloads folder in Dock (in DockScreen coordinates)
        let dockScreenRect = dockScreen.convert(globalRect)

        return dockScreenRect
    }

}

extension BrowserTabViewController: BrowserTabSelectionDelegate {

    func selectedTabContent(_ content: Tab.TabContent) {
        tabViewModel?.tab.setContent(content)
        showTabContent(of: tabViewModel)
    }

    func selectedPreferencePane(_ identifier: PreferencePaneIdentifier) {
        guard let selectedTab = tabViewModel?.tab else {
            return
        }

        if case .settings = selectedTab.content {
            selectedTab.setContent(.settings(pane: identifier))
        }
    }

}

extension BrowserTabViewController {

    func addMouseMonitors() {
        NSEvent.addLocalCancellableMonitor(forEventsMatching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            return self.mouseDown(with: event)
        }.store(in: &cancellables)
    }

    func mouseDown(with event: NSEvent) -> NSEvent? {
        guard event.window === self.view.window else { return event }
        tabViewModel?.tab.autofill?.didClick(at: event.locationInWindow)
        return event
    }

}

// MARK: - Web View snapshot for Pinned Tab selected in more than 1 window

extension BrowserTabViewController {

    private func subscribeToTabSelectedInCurrentKeyWindow() {
        let lastKeyWindowOtherThanOurs = Application.appDelegate.windowControllersManager.didChangeKeyWindowController
            .map { $0 }
            .prepend(Application.appDelegate.windowControllersManager.lastKeyMainWindowController)
            .compactMap { $0 }
            .filter { [weak self] in $0.window !== self?.view.window }

        keyWindowSelectedTabCancellable = lastKeyWindowOtherThanOurs
            .flatMap(\.mainViewController.tabCollectionViewModel.$selectionIndex)
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] index in
                self?.handleTabSelectedInOtherKeyWindow(index)
            }
    }

    private func handleTabSelectedInOtherKeyWindow(_ tabIndex: TabIndex) {
        if pinnedTabsManagerProvider.pinnedTabsMode == .shared, tabIndex.isPinnedTab, tabIndex == tabCollectionViewModel.selectionIndex, webViewSnapshot == nil {
            makeWebViewSnapshot()
        } else {
            hideWebViewSnapshotIfNeeded()
        }
    }

    private func makeWebViewSnapshot(_ webView: WebView? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))

        guard let webView = webView ?? self.webView else {
            Logger.general.error("BrowserTabViewController: failed to create a snapshot of webView")
            return
        }

        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = false

        showWebViewSnapshot(with: tabViewModel?.snapshot)
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            guard let self, let image,
                  // the window became key while the snapshot was prepared
                  self.view.window?.isKeyWindow == false else {
                Logger.general.error("BrowserTabViewController: failed to create a snapshot of webView")
                return
            }
            showWebViewSnapshot(with: image)
        }
    }

    private func showWebViewSnapshot(with image: NSImage?) {
        let snapshotView = if let image {
            WebViewSnapshotView(image: image, frame: view.bounds)
        } else {
            NSView(frame: view.bounds)
        }
        snapshotView.autoresizingMask = [.width, .height]
        snapshotView.translatesAutoresizingMaskIntoConstraints = true

        view.addSubview(snapshotView)
        webViewSnapshot?.removeFromSuperview()
        webViewSnapshot = snapshotView
    }

    private func hideWebViewSnapshotIfNeeded() {
        if webViewSnapshot != nil {
            DispatchQueue.main.async { [weak self, tabViewModel] in
                guard let self,
                      self.tabViewModel === tabViewModel else { return }

                // only make web view first responder after replacing the
                // snapshot if the address bar is not the first responder
                if view.window?.firstResponder === view.window {
                    viewToMakeFirstResponderAfterAdding = { [weak self] in
                        self?.webView
                    }
                }
                showTabContent(of: tabViewModel)
                webViewSnapshot?.removeFromSuperview()
            }
        }
    }
}

@available(macOS 14.0, *)
#Preview {
    BrowserTabViewController(tabCollectionViewModel: TabCollectionViewModel(tabCollection: TabCollection(tabs: [.init(content: .url(.duckDuckGo, source: .ui))])))
}

private extension NSViewController {

    func insertChild(_ childController: NSViewController, in stackView: NSStackView, at index: Int) {
        stackView.insertArrangedSubview(childController.view, at: index)
        animateStackViewChanges(stackView)
    }

    func removeChild(in stackView: NSStackView, webViewContainer: NSView) {
        stackView.arrangedSubviews.filter({ $0 != webViewContainer }).forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        animateStackViewChanges(stackView)
    }

    private func animateStackViewChanges(_ stackView: NSStackView) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.allowsImplicitAnimation = true
            stackView.layoutSubtreeIfNeeded()
        }
    }

}
