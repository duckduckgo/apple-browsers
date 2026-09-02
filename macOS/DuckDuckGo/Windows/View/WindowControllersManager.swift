//
//  WindowControllersManager.swift
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

import AIChat
import BrowserServicesKit
import Cocoa
import Combine
import Common
import ConcurrencyExtensions
import FoundationExtensions
import History
import os.log
import PrivacyConfig

@MainActor
protocol WindowControllersManagerProtocol: AnyObject {

    var stateChanged: AnyPublisher<Void, Never> { get }
    var tabsChanged: AnyPublisher<Void, Never> { get }

    var mainWindowControllers: [MainWindowController] { get }
    var selectedTab: Tab? { get }
    var allTabCollectionViewModels: [TabCollectionViewModel] { get }

    var pinnedTabsManagerProvider: PinnedTabsManagerProviding { get }

    var didRegisterWindowController: PassthroughSubject<(MainWindowController), Never> { get }
    var didUnregisterWindowController: PassthroughSubject<(MainWindowController), Never> { get }

    func register(_ windowController: MainWindowController)
    func unregister(_ windowController: MainWindowController)

    func show(url: URL?, tabId: String?, source: Tab.TabContent.URLSource, newTab: Bool, selected: Bool?)
    func showBookmarksTab()

    @discardableResult
    func openNewWindow(with tabCollectionViewModel: TabCollectionViewModel?,
                       burnerMode: BurnerMode,
                       droppingPoint: NSPoint?,
                       contentSize: NSSize?,
                       showWindow: Bool,
                       popUp: Bool,
                       lazyLoadTabs: Bool,
                       isMiniaturized: Bool,
                       isMaximized: Bool,
                       isFullscreen: Bool) -> NSWindow?

    func open(_ url: URL, source: Tab.TabContent.URLSource, target window: NSWindow?, with: NSEvent?)
    func showTab(with content: Tab.TabContent)
    func openTab(_ tab: Tab, afterParentTab parentTab: Tab, selected: Bool)
}

extension WindowControllersManagerProtocol {

    @discardableResult
    func openNewWindow(with tabCollectionViewModel: TabCollectionViewModel? = nil,
                       burnerMode: BurnerMode = .regular,
                       droppingPoint: NSPoint? = nil,
                       contentSize: NSSize? = nil,
                       showWindow: Bool = true,
                       popUp: Bool = false,
                       lazyLoadTabs: Bool = false) -> NSWindow? {
        openNewWindow(with: tabCollectionViewModel, burnerMode: burnerMode, droppingPoint: droppingPoint, contentSize: contentSize, showWindow: showWindow, popUp: popUp, lazyLoadTabs: lazyLoadTabs, isMiniaturized: false, isMaximized: false, isFullscreen: false)
    }

    func show(url: URL?, source: Tab.TabContent.URLSource, newTab: Bool, selected: Bool?) {
        show(url: url, tabId: nil, source: source, newTab: newTab, selected: selected)
    }

    var lastKeyMainWindowController: MainWindowController? {
        return lastKeyMainWindowController(where: { _ in true })
    }

    func lastKeyMainWindowController(where predicate: (MainWindowController) -> Bool) -> MainWindowController? {
        return withoutActuallyEscaping(predicate) { predicate in
            mainWindowControllers.lazy
                .filter { windowController in
                    !(windowController.window?.isPopUpWindow ?? true) && predicate(windowController)
                }.max {
                    $0.lastWindowDidBecomeKeyTimestamp < $1.lastWindowDidBecomeKeyTimestamp
                }
        }
    }

}

@MainActor
final class WindowControllersManager: WindowControllersManagerProtocol {

    var activeViewController: MainViewController? {
        lastKeyMainWindowController?.mainViewController
    }

    init(pinnedTabsManagerProvider: PinnedTabsManagerProviding,
         subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
         internalUserDecider: InternalUserDecider,
         featureFlagger: FeatureFlagger,
         pinningManager: PinningManager,
         isTerminating: @escaping @MainActor () -> Bool = { false }) {
        self.pinnedTabsManagerProvider = pinnedTabsManagerProvider
        self.subscriptionFeatureAvailability = subscriptionFeatureAvailability
        self.internalUserDecider = internalUserDecider
        self.featureFlagger = featureFlagger
        self.pinningManager = pinningManager
        self.isTerminating = isTerminating
    }

    /**
     * _Initial_ meaning a single window with a single home page tab.
     */
    @Published private(set) var isInInitialState: Bool = true
    @Published private(set) var mainWindowControllers = [MainWindowController]()

    /// `TabsPreferences` reference is needed to compute `shouldSwitchToNewTabWhenOpened`.
    weak var tabsPreferences: TabsPreferences?

    private weak var onboardingTab: Tab?
    private var onboardingTabCancellable: AnyCancellable?

    /// Records a skip that leaves the tab where it is. Cleared once used, so the same onboarding
    /// session is only ever recorded once.
    private var onboardingSkipInPlaceHandler: (@MainActor () -> Void)?

    /// Tabs already wired up by `observeNavigationForBrowsingBeforeCompletion(in:)`, so a tab isn't
    /// subscribed twice as a tab collection's `$tabs` republishes on unrelated changes.
    private var browsingBeforeCompletionObservedTabs = Set<ObjectIdentifier>()

    /// Every subscription `setUpBrowsingBeforeCompletionTracking()` creates: one per tracked tab,
    /// one per window's tab list, and one for windows registered after onboarding started. Cleared
    /// in `clearOnboardingTracking()`/`setOnboardingTab(_:)` only — never from inside a sink stored
    /// here, so tearing down never races the very subscription that's delivering it.
    private var browsingBeforeCompletionCancellables = Set<AnyCancellable>()

    /// Tracks which tabs currently host an active Duck.ai voice session, so voice entry points
    /// can focus an existing tab instead of opening a new one. Lazy so the tracker can capture
    /// `self` (the `WindowControllersManager` is its source of truth for tab membership).
    private(set) lazy var voiceSessionTracker: VoiceSessionTracker = VoiceSessionTracker(windowControllersManager: self)

    var pinnedTabsManagerProvider: PinnedTabsManagerProviding
    private let subscriptionFeatureAvailability: SubscriptionFeatureAvailability
    private let internalUserDecider: InternalUserDecider
    private let featureFlagger: FeatureFlagger
    private let pinningManager: PinningManager
    private let isTerminating: @MainActor () -> Bool

    /// find Main Window Controller being currently interacted with even when ⌘-clicked in background
    func mainWindowController(for sourceWindow: NSWindow?) -> MainWindowController? {
        guard let sourceWindow else { return nil }

        // go up from the clicked window (popover or Bookmarks Bar Menu) to find the root target Main Window
        for window in sequence(first: sourceWindow, next: { $0.parent ?? $0.sheetParent }) {
            if let windowController = window.windowController as? MainWindowController {
                return windowController
            }
        }
        return nil
    }

    let didChangeKeyWindowController = PassthroughSubject<MainWindowController?, Never>()
    let didRegisterWindowController = PassthroughSubject<(MainWindowController), Never>()
    let didUnregisterWindowController = PassthroughSubject<(MainWindowController), Never>()

    func register(_ windowController: MainWindowController) {
        guard !mainWindowControllers.contains(windowController) else {
            assertionFailure("Window controller already registered")
            return
        }

        mainWindowControllers.append(windowController)
        didRegisterWindowController.send(windowController)
    }

    func unregister(_ windowController: MainWindowController) {
        recordOnboardingSkipIfWindowHostsOnboarding(windowController)

        pinnedTabsManagerProvider.cacheClosedWindowPinnedTabsIfNeeded(pinnedTabsManager: windowController.mainViewController.tabCollectionViewModel.pinnedTabsManager)

        guard let idx = mainWindowControllers.firstIndex(of: windowController) else {
            Logger.general.error("WindowControllersManager: Window Controller not registered")
            return
        }
        mainWindowControllers.remove(at: idx)
        didUnregisterWindowController.send(windowController)
    }

    /// Closing the window that hosts onboarding disposes of onboarding just as deliberately as
    /// closing its tab, so it counts as a skip. Quitting is excluded: it closes every window as its
    /// final step, and `isTerminating` is what tells the two apart.
    @MainActor
    private func recordOnboardingSkipIfWindowHostsOnboarding(_ windowController: MainWindowController) {
        guard !isTerminating(), let onboardingTab else { return }
        guard windowController.mainViewController.tabCollectionViewModel.indexInAllTabs(of: onboardingTab) != nil else { return }

        recordOnboardingSkipInPlace()
    }

    func updateIsInInitialState() {
        if isInInitialState {

            isInInitialState = mainWindowControllers.isEmpty ||
            (
                mainWindowControllers.count == 1 &&
                mainWindowControllers.first?.mainViewController.tabCollectionViewModel.tabs.count == 1 &&
                mainWindowControllers.first?.mainViewController.tabCollectionViewModel.tabs.first?.content == .newtab &&
                pinnedTabsManagerProvider.arePinnedTabsEmpty
            )
        }
    }

    // MARK: - Active Domain

    var activeDomain: String? {
        if let tabContent = lastKeyMainWindowController?.activeTab?.content {
            return Self.domain(from: tabContent)
        }

        return nil
    }

    static func domain(from tabContent: Tab.TabContent) -> String? {
        if case .url(let url, _, _) = tabContent {

            return url.host
        } else {
            return nil
        }
    }
}

// MARK: - Opening a url from the external event

extension WindowControllersManager {

    func showDataBrokerProtectionTab() {
        showTab(with: .dataBrokerProtection)
    }

    func showBookmarksTab() {
        showTab(with: .bookmarks)
    }

    func showPreferencesTab(withSelectedPane pane: PreferencePaneIdentifier? = nil) {
        showTab(with: .settings(pane: pane))
    }

    /// Opens a bookmark in a tab, respecting the current modifier keys when deciding where to open the bookmark's URL.
    func open(_ bookmark: Bookmark, target window: NSWindow? = nil, with event: NSEvent?) {
        guard let url = bookmark.urlObject else { return }

        // Call updated openBookmark
        open(url, source: .bookmark(isFavorite: bookmark.isFavorite), target: window, with: event)
    }

    /// Opens a history entry in a tab, respecting the current modifier keys when deciding where to open the URL.
    func open(_ historyEntry: HistoryEntry, target window: NSWindow? = nil, with event: NSEvent?) {
        open(historyEntry.url, source: .historyEntry, target: window, with: event)
    }

    /// Helper method for opening URL with an event respecting its Key Modifiers
    func open(_ url: URL, source: Tab.TabContent.URLSource, target window: NSWindow? = nil, with event: NSEvent? = nil) {
        // get clicked window or last key window if menu item selected
        let eventWindowController = mainWindowController(for: window ?? event?.window)
        let targetWindowController = eventWindowController ?? lastKeyMainWindowController
        let tabCollectionViewModel = targetWindowController?.mainViewController.tabCollectionViewModel

        let isPinnedTab = tabCollectionViewModel?.selectedTab?.isPinned ?? false
        // mainWindowController(for: popupWindow) would return nil
        let canOpenLinkInCurrentWindow = eventWindowController != nil && !(targetWindowController?.window?.isPopUpWindow ?? false)

        // For pinned tabs or popup windows, force new tab by disallowing current tab
        let canOpenLinkInCurrentTab = canOpenLinkInCurrentWindow && !isPinnedTab
        let switchToNewTabWhenOpened = shouldSwitchToNewTabWhenOpened

        let behavior = LinkOpenBehavior(
            event: event,
            switchToNewTabWhenOpenedPreference: switchToNewTabWhenOpened,
            canOpenLinkInCurrentTab: canOpenLinkInCurrentTab,
            shouldSelectNewTab: !canOpenLinkInCurrentTab // when user intent was to open in current context (no key modifiers) – always select the new tab.
        )

        open(url, with: behavior, source: source, target: targetWindowController)
    }

    func open(_ url: URL, with linkOpenBehavior: LinkOpenBehavior, setBurner: Bool? = nil, source: Tab.TabContent.URLSource, target: MainWindowController?) {
        let windowController = target ?? lastKeyMainWindowController
        switch (linkOpenBehavior, windowController) {
        case (.currentTab, let .some(windowController)) where windowController.window?.isPopUpWindow == false:
            // Open in current tab in regular window
            show(url: url, in: windowController, source: source, newTab: false, selected: true)

        case (.newTab(let selected), let .some(windowController)) where windowController.window?.isPopUpWindow == false:
            // Open in new tab in regular window
            let tabCollectionViewModel = windowController.mainViewController.tabCollectionViewModel
            tabCollectionViewModel.insertOrAppendNewTab(.contentFromURL(url, source: source), selected: selected)
            if selected {
                windowController.window?.makeKeyAndOrderFront(nil)
            }

        case (.newTab, _), (.currentTab, _): // windowController == nil || isPopUpWindow == true
            // Open in new tab in last active regular window
            // when called from popup window or there is no windows open
            show(url: url, source: source, newTab: true, selected: linkOpenBehavior.shouldSelectNewTab)

            // for `selected == false` order the window below the popup window without activating it.
            if !linkOpenBehavior.shouldSelectNewTab,
               target !== lastKeyMainWindowController,
               let lastKeyWindow = lastKeyMainWindowController?.window,
               let popupWindow = target?.window {
                lastKeyWindow.order(.below, relativeTo: popupWindow.windowNumber)
                popupWindow.makeKey()
            }

        case (.newWindow(let selected), _):
            // Open in new window
            WindowsManager.openNewWindow(with: url, source: source, isBurner: setBurner, showWindow: selected)
        }
    }

    /// Opens a URL in a specified tab or creates a new tab/window if necessary.
    ///
    /// This function can activate or reuse an existing tab, create a new one, or open a new window based on the provided parameters.
    ///
    /// - Parameters:
    ///   - url: The URL to open. If `nil`, New Tab page will be open (`.newtab`).
    ///   - tabId: An optional identifier for an existing tab to switch to.
    ///            If provided along with the `source` matching `.appOpenUrl` or `.switchToOpenTab`,
    ///            the function will attempt to activate the tab with this ID.
    ///   - source: The origin of the URL being opened, which can indicate whether it is from a bookmark, history record, external link, etc.
    ///   - newTab: A Boolean value indicating whether to create a new tab instead of reusing an existing one.
    ///             The default is `false`.
    ///   - selected: An optional Boolean value that determines whether the new tab should be selected (active) or opened in the background.
    ///               If `nil`, the new tab activation setting value will be followed (`TabsPreferences.switchToNewTabWhenOpened`).
    ///               The default is `true`.
    func show(url: URL?, tabId: String? = nil, source: Tab.TabContent.URLSource, newTab: Bool = false, selected: Bool? = true) {
        let nonPopupMainWindowControllers = mainWindowControllers.filter { $0.window?.isPopUpWindow == false }
        // If there is a main window, open the URL in it
        if let windowController = nonPopupMainWindowControllers.first(where: { $0.window?.isMainWindow == true })
            // If a last key window is available, open the URL in it
            ?? lastKeyMainWindowController
            // If there is any open window on the current screen, open the URL in it
            ?? nonPopupMainWindowControllers.first(where: { $0.window?.screen == NSScreen.main })
            // If there is any non-popup window available, open the URL in it
            ?? nonPopupMainWindowControllers.first {

            let tabCollectionViewModel = windowController.mainViewController.tabCollectionViewModel
            let selectedTabViewModel = tabCollectionViewModel.selectedTabViewModel
            let selectionIndex = tabCollectionViewModel.selectionIndex

            // Switch to already open tab if present
            if [.appOpenUrl, .switchToOpenTab].contains(source),
               let url, switchToOpenTab(withId: tabId, url: url, preferring: windowController) == true {

                if let selectedTabViewModel, let selectionIndex,
                   case .newtab = selectedTabViewModel.tab.content {
                    // close tab with "new tab" page open
                    tabCollectionViewModel.remove(at: selectionIndex)

                    // close the window if no more non-pinned tabs are open
                    if tabCollectionViewModel.tabs.isEmpty, let window = windowController.window, window.isVisible,
                       mainWindowController?.mainViewController.tabCollectionViewModel.selectedTabIndex?.isPinnedTab != true {
                        window.close()
                    }
                }
                return
            }

            let selected = selected ?? shouldSwitchToNewTabWhenOpened
            show(url: url, in: windowController, source: source, newTab: newTab, selected: selected)
            return
        }

        // Open a new window
        if let url = url {
            WindowsManager.openNewWindow(with: url, source: source, isBurner: false)
        } else {
            WindowsManager.openNewWindow() // Use default behavior which respects user preference
        }
    }

    var shouldSwitchToNewTabWhenOpened: Bool {
        guard let tabsPreferences else {
            assertionFailure("tabsPreferences must not be nil")
            return false
        }
        return tabsPreferences.switchToNewTabWhenOpened
    }

    private func switchToOpenTab(withId tabId: String?, url: URL, preferring mainWindowController: MainWindowController) -> Bool {
        for (windowIdx, windowController) in ([mainWindowController] + mainWindowControllers).enumerated() {
            // prefer current main window
            guard windowIdx == 0 || windowController !== mainWindowController else { continue }
            let tabCollectionViewModel = windowController.mainViewController.tabCollectionViewModel
            guard let index = tabCollectionViewModel.indexInAllTabs(where: {
                if let tabId {
                    return $0.uuid == tabId
                }
                return $0.content.urlForWebView == url || (url.isSettingsURL && $0.content.urlForWebView?.isSettingsURL == true)
            }) else { continue }

            windowController.window?.makeKeyAndOrderFront(self)
            if let tab = tabCollectionViewModel.selectTab(at: index),
               tab.content.urlForWebView != url && url != URL.empty {
                // navigate to another settings pane
                tab.setContent(.contentFromURL(url, source: .switchToOpenTab))
            }

            return true
        }
        if tabId != nil { // fallback to Switch to Tab by URL
            return switchToOpenTab(withId: nil, url: url, preferring: mainWindowController)
        }
        return false
    }

    private func show(url: URL?, in windowController: MainWindowController, source: Tab.TabContent.URLSource, newTab: Bool, selected: Bool) {
        let viewController = windowController.mainViewController
        if selected || windowController !== lastKeyMainWindowController /* only activate `selected == false` when the target window is not last known key window */ {
            windowController.window?.makeKeyAndOrderFront(self)
        }

        let tabCollectionViewModel = viewController.tabCollectionViewModel
        let tabCollection = tabCollectionViewModel.tabCollection

        if tabCollection.tabs.count == 1,
           case .newtab = tabCollection.tabs.first?.content,
           !newTab {
            let tab = tabCollectionViewModel.materialize(at: .unpinned(0))
            tab?.setContent(url.map { .contentFromURL($0, source: source) } ?? .newtab)
        } else if let tab = tabCollectionViewModel.selectedTabViewModel?.tab, !newTab {
            tab.setContent(url.map { .contentFromURL($0, source: source) } ?? .newtab)
        } else {
            let newTab = Tab(content: url.map { .url($0, source: source) } ?? .newtab, shouldLoadInBackground: true, burnerMode: tabCollectionViewModel.burnerMode)
            newTab.setContent(url.map { .contentFromURL($0, source: source) } ?? .newtab)
            tabCollectionViewModel.insertOrAppend(tab: newTab, selected: selected)
        }
    }

    func showTab(with content: Tab.TabContent) {
        guard let windowController = self.mainWindowController else {
            let tabCollection = TabCollection(tabs: [Tab(content: content)])
            let tabCollectionViewModel = TabCollectionViewModel(tabCollection: tabCollection)
            WindowsManager.openNewWindow(with: tabCollectionViewModel)
            return
        }

        let viewController = windowController.mainViewController
        let tabCollectionViewModel = viewController.tabCollectionViewModel
        tabCollectionViewModel.insertOrAppendNewTab(content)
        windowController.window?.orderFront(nil)
    }

    /// Used to open a Tab from a pop up window in its original parent
    func openTab(_ tab: Tab, afterParentTab parentTab: Tab, selected: Bool) {
        guard let originatingWindowController = windowController(containing: parentTab),
              let windowController = windowController(forOpeningTabFrom: originatingWindowController, parentTab: parentTab) else {
            openNewWindow(with: TabCollectionViewModel(tabCollection: TabCollection(tabs: [tab], isPopup: false), burnerMode: tab.burnerMode), burnerMode: tab.burnerMode)
            return
        }
        windowController.mainViewController.tabCollectionViewModel.insertOrAppend(tab: tab, selected: selected)
        if !selected,
           let originatingWindowNumber = originatingWindowController.window?.windowNumber {
            // place the target window under the originating popup window if should not select
            windowController.window?.order(.below, relativeTo: originatingWindowNumber)
        } else {
            windowController.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// Returns the window controller containing the given tab.
    private func windowController(containing tab: Tab) -> MainWindowController? {
        return mainWindowControllers.first(where: { $0.mainViewController.tabCollectionViewModel.tabCollection.contains(tab: tab) })
    }

    /// Returns the window controller for opening a tab from the given originating window controller and opener tab.
    /// If the originating window controller is a popup window, the function will recursively call itself with the popup's parent tab.
    private func windowController(forOpeningTabFrom originatingWindowController: MainWindowController, parentTab: Tab) -> MainWindowController? {
        if !originatingWindowController.mainViewController.isInPopUpWindow  {
            return originatingWindowController
        }
        // originatingWindowController is a popUp, look for its parent window controller
        guard let parentTab = parentTab.parentTab,
              let parentWindowController = windowController(containing: parentTab) else { return nil }
        return windowController(forOpeningTabFrom: parentWindowController, parentTab: parentTab)
    }

    // MARK: - VPN

    @MainActor
    func showNetworkProtectionStatus(retry: Bool = false) async {
        guard let windowController = mainWindowControllers.first else {
            guard !retry else {
                return
            }

            WindowsManager.openNewWindow()

            // Not proud of this ugly hack... ideally openNewWindow() should let us know when the window is ready
            try? await Task.sleep(interval: 0.5)
            await showNetworkProtectionStatus(retry: true)
            return
        }

        windowController.mainViewController.navigationBarViewController.showNetworkProtectionStatus()
    }

    /// Shows the non-subscription feedback modal
    func showFeedbackModal(preselectedFormOption: FeedbackViewController.FormOption? = nil) {
        if internalUserDecider.isInternalUser {
            Application.appDelegate.quickFeedbackService.openFeedbackPopup(from: NSApp.mainWindow)
        } else {
            FeedbackPresenter.presentFeedbackForm(preselectedFormOption: preselectedFormOption)
        }
    }

    /// Shows the Subscription feedback modal
    func showShareFeedbackModal(source: UnifiedFeedbackSource = .default) {
        let feedbackFormViewController = UnifiedFeedbackFormViewController(source: source, featureFlagger: featureFlagger)
        let feedbackFormWindowController = feedbackFormViewController.wrappedInWindowController()

        guard let feedbackFormWindow = feedbackFormWindowController.window else {
            assertionFailure("Couldn't get window for feedback form")
            return
        }

        if let parentWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController {
            parentWindowController.window?.beginSheet(feedbackFormWindow)
        } else {
            let tabCollection = TabCollection()
            let tabCollectionViewModel = TabCollectionViewModel(tabCollection: tabCollection)
            let window = WindowsManager.openNewWindow(with: tabCollectionViewModel)
            window?.beginSheet(feedbackFormWindow)
        }
    }

    func showMainWindow() {
        guard Application.appDelegate.windowControllersManager.lastKeyMainWindowController == nil else { return }
        let tabCollection = TabCollection()
        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: tabCollection)
        _ = WindowsManager.openNewWindow(with: tabCollectionViewModel)
    }

    func showLocationPickerSheet() {
        let locationsViewController = VPNLocationsHostingViewController()
        let locationsWindowController = locationsViewController.wrappedInWindowController()

        guard let locationsFormWindow = locationsWindowController.window,
              let parentWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController else {
            assertionFailure("Failed to present native VPN feedback form")
            return
        }

        parentWindowController.window?.beginSheet(locationsFormWindow)
    }

    @discardableResult
    func openNewWindow(with tabCollectionViewModel: TabCollectionViewModel? = nil,
                       burnerMode: BurnerMode = .regular,
                       droppingPoint: NSPoint? = nil,
                       contentSize: NSSize? = nil,
                       showWindow: Bool = true,
                       popUp: Bool = false,
                       lazyLoadTabs: Bool = false,
                       isMiniaturized: Bool = false,
                       isMaximized: Bool = false,
                       isFullscreen: Bool = false) -> NSWindow? {
        return WindowsManager.openNewWindow(with: tabCollectionViewModel, burnerMode: burnerMode, droppingPoint: droppingPoint, contentSize: contentSize, showWindow: showWindow, popUp: popUp, lazyLoadTabs: lazyLoadTabs, isMiniaturized: isMiniaturized, isMaximized: isMaximized, isFullscreen: isFullscreen)
    }

}

extension Tab {
    var isPinned: Bool {
        guard let pinnedTabsManager = self.pinnedTabsManagerProvider.pinnedTabsManager(for: self) else {
            return false
        }

        return pinnedTabsManager.isTabPinned(self)
    }
}

// MARK: - Accessing all TabCollectionViewModels
extension WindowControllersManagerProtocol {

    var mainWindowController: MainWindowController? {
        return mainWindowControllers.first(where: {
            let isMain = $0.window?.isMainWindow ?? false
            let hasMainChildWindow = $0.window?.childWindows?.contains { $0.isMainWindow } ?? false
            return $0.window?.isPopUpWindow == false && (isMain || hasMainChildWindow)
        })
    }

    var selectedTab: Tab? {
        return mainWindowController?.mainViewController.tabCollectionViewModel.selectedTab
    }

    var allTabCollectionViewModels: [TabCollectionViewModel] {
        return mainWindowControllers.map {
            $0.mainViewController.tabCollectionViewModel
        }
    }

    func allTabViewModels(for burnerMode: BurnerMode, includingPinnedTabs: Bool = false) -> [any TabBarViewModel] {
        let currentBurnerModeTabCollectionViewModels = allTabCollectionViewModels
            .filter { tabCollectionViewModel in
                tabCollectionViewModel.burnerMode == burnerMode
            }
        let unpinnedTabBarViewModels = currentBurnerModeTabCollectionViewModels.flatMap { tabCollectionViewModel in
            (0..<tabCollectionViewModel.tabViewModels.count).compactMap { index in
                tabCollectionViewModel.tabBarViewModel(at: .unpinned(index))
            }
        }
        let pinnedTabBarViewModels: [any TabBarViewModel] = includingPinnedTabs ? pinnedTabsManagerProvider.currentPinnedTabManagers.flatMap { pinnedManager in
            (0..<pinnedManager.tabViewModels.count).compactMap { index in
                pinnedManager.tabBarViewModel(at: index)
            }
        } : []
        return pinnedTabBarViewModels + unpinnedTabBarViewModels
    }

    func windowController(for tabCollectionViewModel: TabCollectionViewModel) -> MainWindowController? {
        return mainWindowControllers.first(where: {
            tabCollectionViewModel === $0.mainViewController.tabCollectionViewModel
        })
    }

    func windowController(for tab: Tab) -> MainWindowController? {
        return mainWindowControllers.first(where: {
            $0.mainViewController.tabCollectionViewModel.tabCollection.contains(tab: tab)
        })
    }

    // MARK: - Web Notifications Support

    /// Focuses the tab with the given UUID across all windows, materializing it if unloaded.
    /// - Parameter uuid: The tab's UUID.
    /// - Returns: The loaded tab if found, nil otherwise.
    @discardableResult
    func focusTab(byUUID uuid: String) -> Tab? {
        for windowController in mainWindowControllers {
            let tabCollectionViewModel = windowController.mainViewController.tabCollectionViewModel
            if let index = tabCollectionViewModel.indexInAllTabs(where: { $0.uuid == uuid }) {
                windowController.window?.makeKeyAndOrderFront(nil)
                return tabCollectionViewModel.selectTab(at: index)
            }
        }
        return nil
    }

    /// Focuses the most recently active browser window.
    func focusBrowser() {
        lastKeyMainWindowController?.window?.makeKeyAndOrderFront(nil)
    }

}

extension WindowControllersManager: WebNotificationTabFinding {}

extension WindowControllersManager: OnboardingNavigating {
    @MainActor
    func updatePreventUserInteraction(prevent: Bool) {
        mainWindowController?.userInteraction(prevented: prevent)
    }

    @MainActor
    func showImportDataView() {
        DataImportFlowLauncher(pinningManager: pinningManager).launchDataImport(title: UserText.importDataTitleOnboarding, isDataTypePickerExpanded: false)
    }

    /// Whether a tab is already hosting async onboarding. The reference is weak, so this goes back to
    /// `false` on its own once that tab is gone.
    @MainActor
    var hasOnboardingTab: Bool { onboardingTab != nil }

    /// Records the tab hosting onboarding. Called at window setup, where the tab is unambiguous —
    /// `selectedTab` is not reliable later, because async onboarding lets the user switch tabs
    /// before the onboarding page finishes loading.
    @MainActor
    func setOnboardingTab(_ tab: Tab?) {
        onboardingTabCancellable = nil
        onboardingSkipInPlaceHandler = nil
        onboardingTab?.closeInterceptor = nil
        onboardingTab = tab
        browsingBeforeCompletionObservedTabs.removeAll()
        browsingBeforeCompletionCancellables.removeAll()
    }

    /// Wires the onboarding tab so that leaving onboarding is always recorded as a skip:
    /// `onClose` runs when the user closes the tab outright and something has to take its place,
    /// `onSkipInPlace` when onboarding goes away on its own — navigated away from, swept up in a
    /// bulk close, or carried off by its window closing.
    @MainActor
    func setOnboardingHandlers(onClose: @escaping @MainActor () -> Void,
                               onSkipInPlace: @escaping @MainActor () -> Void) {
        guard let onboardingTab else { return }

        onboardingSkipInPlaceHandler = onSkipInPlace

        onboardingTab.closeInterceptor = { [weak self] reason in
            switch reason {
            case .userInitiated:
                // `onClose` swaps the tab out itself, so cancel the plain removal.
                onClose()
                return true
            case .bulk:
                // Quitting sweeps every tab up in a bulk removal. Main records nothing when the
                // user quits mid-onboarding, so neither does this — otherwise the treatment would
                // lose the "onboarding shows again next launch" nudge that control keeps.
                if self?.isTerminating() == true {
                    self?.clearOnboardingTracking()
                } else {
                    self?.recordOnboardingSkipInPlace()
                }
                return false
            case .programmatic:
                // Not reachable — `removeUnpinnedTab` only consults the interceptor for
                // `.userInitiated`, and bulk paths pass `.bulk` explicitly.
                return false
            }
        }

        // Before the content subscription below, which republishes the current value on subscribe
        // and so can record a skip synchronously. Set up this way round, that skip tears down the
        // browsing observers along with everything else instead of leaving them behind it.
        setUpBrowsingBeforeCompletionTracking()

        onboardingTabCancellable = onboardingTab.$content
            .filter { if case .onboarding = $0 { false } else { true } }
            .first()
            .sink { [weak self] _ in self?.recordOnboardingSkipInPlace() }
    }

    /// Fires `.browsingBeforeCompletion` the first time the user completes a navigation to a real
    /// URL in a tab other than the onboarding tab while onboarding is still unfinished — something
    /// only the non-blocking treatment allows. Watches every tab in every window, including ones
    /// opened after onboarding started, until it fires or the tracking below is torn down.
    @MainActor
    private func setUpBrowsingBeforeCompletionTracking() {
        for windowController in mainWindowControllers {
            observeTabsForBrowsingBeforeCompletion(in: windowController)
        }

        didRegisterWindowController
            .sink { [weak self] windowController in
                self?.observeTabsForBrowsingBeforeCompletion(in: windowController)
            }
            .store(in: &browsingBeforeCompletionCancellables)
    }

    /// Subscribes to a window's tab list so every tab it ever holds — present or future — gets
    /// `observeNavigationForBrowsingBeforeCompletion(in:)` called on it. `$tabs` republishes the
    /// current value on subscribe, so this alone covers tabs already open in the window.
    @MainActor
    private func observeTabsForBrowsingBeforeCompletion(in windowController: MainWindowController) {
        windowController.mainViewController.tabCollectionViewModel.tabCollection.$tabs
            .sink { [weak self] tabs in
                guard let self else { return }
                for case .loaded(let tab) in tabs {
                    self.observeNavigationForBrowsingBeforeCompletion(in: tab)
                }
            }
            .store(in: &browsingBeforeCompletionCancellables)
    }

    /// Fires the metric on this tab's first completed navigation to a real URL, provided it isn't
    /// the onboarding tab and onboarding hasn't finished by then. Unloaded tabs have no web view and
    /// so never navigate; they're simply excluded (`AnyTab.loaded` above never wraps one to observe).
    @MainActor
    private func observeNavigationForBrowsingBeforeCompletion(in tab: Tab) {
        guard browsingBeforeCompletionObservedTabs.insert(ObjectIdentifier(tab)).inserted else { return }

        tab.navigationDidEndPublisher
            .filter { [weak self] navigatedTab in
                guard let self, navigatedTab !== self.onboardingTab, case .url = navigatedTab.content else { return false }
                return !OnboardingActionsManager.isOnboardingFinished
            }
            .first()
            .sink { [weak self] _ in
                guard let self else { return }
                OnboardingNonBlockingExperiment(featureFlagger: self.featureFlagger).fireMetric(.browsingBeforeCompletion)
            }
            .store(in: &browsingBeforeCompletionCancellables)
    }

    /// Records leaving onboarding without completing it, for the paths that leave the tab alone.
    /// Clearing the handler first makes this idempotent: several of these paths can fire for the
    /// same onboarding session, and only the first one is the outcome.
    @MainActor
    private func recordOnboardingSkipInPlace() {
        guard let handler = onboardingSkipInPlaceHandler else { return }
        clearOnboardingTracking()
        handler()
    }

    /// Releases the onboarding tab without recording anything. Deliberately leaves
    /// `onboardingTabCancellable` alone: the content subscription is `.first()` and retires itself,
    /// and cancelling it from inside its own sink would release the cancellable while the content
    /// subject is still delivering.
    @MainActor
    private func clearOnboardingTracking() {
        onboardingSkipInPlaceHandler = nil
        onboardingTab?.closeInterceptor = nil
        onboardingTab = nil
        browsingBeforeCompletionObservedTabs.removeAll()
        browsingBeforeCompletionCancellables.removeAll()
    }

    /// Replaces the onboarding tab, falling back to the selected tab when none is tracked
    /// (the non-async flow keeps the UI locked, so the two are the same tab there).
    @MainActor
    func replaceTabWith(_ tab: Tab) {
        // Capture before clearing — `setOnboardingTab(nil)` drops the reference this needs.
        guard let tabToRemove = onboardingTab ?? selectedTab else { return }
        setOnboardingTab(nil)
        replaceTab(tabToRemove, with: tab)
    }

    @MainActor
    private func replaceTab(_ tabToRemove: Tab, with tab: Tab) {
        // Resolve the window that actually holds the tab, not whichever one is key — otherwise the
        // index lookup below searches the wrong collection and silently gives up.
        guard let windowController = windowController(containing: tabToRemove) ?? mainWindowController else { return }
        guard let index = windowController.mainViewController.tabCollectionViewModel.indexInAllTabs(of: tabToRemove) else { return }
        var tabToAppend = tab
        if windowController.mainViewController.isBurner {
            let burnerMode = windowController.mainViewController.tabCollectionViewModel.burnerMode
            tabToAppend = Tab(content: tab.content, burnerMode: burnerMode)
        }
        // Append before remove: the tab count must never hit zero, or the window closes.
        windowController.mainViewController.tabCollectionViewModel.append(tab: tabToAppend)
        windowController.mainViewController.tabCollectionViewModel.remove(at: index)
    }

    @MainActor
    func focusOnAddressBar() {
        guard let mainVC = lastKeyMainWindowController?.mainViewController else { return }
        mainVC.navigationBarViewController.addressBarViewController?.addressBarTextField.stringValue = ""
        mainVC.navigationBarViewController.addressBarViewController?.addressBarTextField.makeMeFirstResponder()
    }
}

extension WindowControllersManager: TabAndWindowCountProviding {
    var tabCount: Int {
        mainWindowControllers.reduce(0) { total, controller in
            total + controller.mainViewController.tabCollectionViewModel.allTabsCount
        }
    }

    var windowCount: Int {
        mainWindowControllers.count
    }
}
