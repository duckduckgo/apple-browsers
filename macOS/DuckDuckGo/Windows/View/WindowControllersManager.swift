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

import BrowserServicesKit
import Cocoa
import Combine
import Common
import History
import os.log
import AIChat

@MainActor
protocol WindowControllersManagerProtocol {

    var stateChanged: AnyPublisher<Void, Never> { get }

    var mainWindowControllers: [MainWindowController] { get }
    var selectedTab: Tab? { get }
    var allTabCollectionViewModels: [TabCollectionViewModel] { get }

    var lastKeyMainWindowController: MainWindowController? { get }
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
                       isFullscreen: Bool) -> MainWindow?
    func showTab(with content: Tab.TabContent)

    func openAIChat(_ url: URL, with linkOpenBehavior: LinkOpenBehavior)
    func openAIChat(_ url: URL, with linkOpenBehavior: LinkOpenBehavior, hasPrompt: Bool)
}

extension WindowControllersManagerProtocol {
    @discardableResult
    func openNewWindow(with tabCollectionViewModel: TabCollectionViewModel? = nil,
                       burnerMode: BurnerMode = .regular,
                       droppingPoint: NSPoint? = nil,
                       contentSize: NSSize? = nil,
                       showWindow: Bool = true,
                       popUp: Bool = false,
                       lazyLoadTabs: Bool = false) -> MainWindow? {
        openNewWindow(with: tabCollectionViewModel, burnerMode: burnerMode, droppingPoint: droppingPoint, contentSize: contentSize, showWindow: showWindow, popUp: popUp, lazyLoadTabs: lazyLoadTabs, isMiniaturized: false, isMaximized: false, isFullscreen: false)
    }
    func show(url: URL?, source: Tab.TabContent.URLSource, newTab: Bool, selected: Bool?) {
        show(url: url, tabId: nil, source: source, newTab: newTab, selected: selected)
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
         featureFlagger: FeatureFlagger) {
        self.pinnedTabsManagerProvider = pinnedTabsManagerProvider
        self.subscriptionFeatureAvailability = subscriptionFeatureAvailability
        self.internalUserDecider = internalUserDecider
        self.featureFlagger = featureFlagger
    }

    /**
     * _Initial_ meaning a single window with a single home page tab.
     */
    @Published private(set) var isInInitialState: Bool = true
    @Published private(set) var mainWindowControllers = [MainWindowController]()
    private(set) var pinnedTabsManagerProvider: PinnedTabsManagerProviding
    private let subscriptionFeatureAvailability: SubscriptionFeatureAvailability
    private let internalUserDecider: InternalUserDecider
    private let featureFlagger: FeatureFlagger

    weak var lastKeyMainWindowController: MainWindowController? {
        didSet {
            if lastKeyMainWindowController != oldValue {
                didChangeKeyWindowController.send(lastKeyMainWindowController)
            }
        }
    }

    /// find Main Window Controller being currently interacted with even when ⌘-clicked in background
    func mainWindowController(for sourceWindow: NSWindow?) -> MainWindowController? {
        guard let sourceWindow else { return nil }

        // go up from the clicked window (popover or Bookmarks Bar Menu) to find the root target Main Window
        for window in sequence(first: sourceWindow, next: \.parent) {
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
        pinnedTabsManagerProvider.cacheClosedWindowPinnedTabsIfNeeded(pinnedTabsManager: windowController.mainViewController.tabCollectionViewModel.pinnedTabsManager)

        guard let idx = mainWindowControllers.firstIndex(of: windowController) else {
            Logger.general.error("WindowControllersManager: Window Controller not registered")
            return
        }
        mainWindowControllers.remove(at: idx)
        didUnregisterWindowController.send(windowController)
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

    func openAIChat(_ url: URL, with linkOpenBehavior: LinkOpenBehavior = .currentTab) {
        openAIChat(url, with: linkOpenBehavior, hasPrompt: false)
    }

    /// Opens an AI chat URL in the application.
    ///
    /// - Parameters:
    ///   - url: The AI chat URL to open.
    ///   - linkOpenBehavior: Specifies where to open the URL. Defaults to `.currentTab`.
    ///   - hasPrompt: If `true` and the current tab is an AI chat, reloads the tab. Ignored if `target` is `.newTabSelected`
    ///                or `.newTabUnselected`.
    func openAIChat(_ url: URL, with linkOpenBehavior: LinkOpenBehavior = .currentTab, hasPrompt: Bool) {

        let tabCollectionViewModel = mainWindowController?.mainViewController.tabCollectionViewModel

        switch linkOpenBehavior {
        case .currentTab:
            if let currentURL = tabCollectionViewModel?.selectedTab?.url, currentURL.isDuckAIURL {
                if hasPrompt {
                    tabCollectionViewModel?.selectedTab?.reload()
                }
            } else {
                show(url: url, source: .ui, newTab: false)
            }
        default:
            open(url, with: linkOpenBehavior, source: .ui, target: nil)
        }
    }

    func showPreferencesTab(withSelectedPane pane: PreferencePaneIdentifier? = nil) {
        showTab(with: .settings(pane: pane))
    }

    /// Opens a bookmark in a tab, respecting the current modifier keys when deciding where to open the bookmark's URL.
    func open(_ bookmark: Bookmark, with event: NSEvent?) {
        guard let url = bookmark.urlObject else { return }

        // Call updated openBookmark
        open(url, source: .bookmark(isFavorite: bookmark.isFavorite), target: nil, event: event)
    }

    /// Opens a history entry in a tab, respecting the current modifier keys when deciding where to open the URL.
    func open(_ historyEntry: HistoryEntry, with event: NSEvent?) {
        open(historyEntry.url, source: .historyEntry, target: nil, event: event)
    }

    /// Helper method for opening URL with an event respecting its Key Modifiers
    func open(_ url: URL, source: Tab.TabContent.URLSource, target window: NSWindow?, event: NSEvent?) {
        // get clicked window or last key window if menu item selected
        let windowController = mainWindowController(for: window ?? event?.window) ?? lastKeyMainWindowController
        let tabCollectionViewModel = windowController?.mainViewController.tabCollectionViewModel

        let isPinnedTab = tabCollectionViewModel?.selectedTab?.isPinned ?? false
        let isPopUpWindow = windowController?.window?.isPopUpWindow ?? false

        // For pinned tabs or popup windows, force new tab by disallowing current tab
        let canOpenLinkInCurrentTab = !(isPinnedTab || isPopUpWindow)
        let switchToNewTabWhenOpened = TabsPreferences.shared.switchToNewTabWhenOpened

        let behavior = LinkOpenBehavior(
            event: event,
            switchToNewTabWhenOpenedPreference: switchToNewTabWhenOpened,
            canOpenLinkInCurrentTab: canOpenLinkInCurrentTab
        )

        open(url, with: behavior, source: source, target: windowController)
    }

    func open(_ url: URL, with linkOpenBehavior: LinkOpenBehavior, setBurner: Bool? = nil, source: Tab.TabContent.URLSource, target: MainWindowController?) {
        let windowController = target ?? lastKeyMainWindowController
        switch linkOpenBehavior {
        case .currentTab:
            if let windowController, windowController.window?.isPopUpWindow == false {
                show(url: url, in: windowController, source: source, newTab: false, selected: true)
            } else {
                show(url: url, source: source)
            }
        case .newTab(let selected):
            guard windowController?.window?.isPopUpWindow == false,
                  let tabCollectionViewModel = windowController?.mainViewController.tabCollectionViewModel else { fallthrough }
            tabCollectionViewModel.insertOrAppendNewTab(.contentFromURL(url, source: source), selected: selected)
        case .newWindow(let selected):
            WindowsManager.openNewWindow(with: url, source: source, isBurner: setBurner ?? (windowController?.mainViewController.isBurner ?? false), showWindow: selected)
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
    ///               If `nil`, the new tab activation setting value will be followed (`TabsPreferences.shared.switchToNewTabWhenOpened`).
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
                        window.performClose(nil)
                    }
                }
                return
            }

            let selected = selected ?? TabsPreferences.shared.switchToNewTabWhenOpened
            show(url: url, in: windowController, source: source, newTab: newTab, selected: selected)
            return
        }

        // Open a new window
        if let url = url {
            WindowsManager.openNewWindow(with: url, source: source, isBurner: false)
        } else {
            WindowsManager.openNewWindow(burnerMode: .regular)
        }
    }

    private func switchToOpenTab(withId tabId: String?, url: URL, preferring mainWindowController: MainWindowController) -> Bool {
        for (windowIdx, windowController) in ([mainWindowController] + mainWindowControllers).enumerated() {
            // prefer current main window
            guard windowIdx == 0 || windowController !== mainWindowController else { continue }
            let tabCollectionViewModel = windowController.mainViewController.tabCollectionViewModel
            guard let index = tabCollectionViewModel.indexInAllTabs(where: {
                if let tabId {
                    return $0.id == tabId
                }
                return $0.content.urlForWebView == url || (url.isSettingsURL && $0.content.urlForWebView?.isSettingsURL == true)
            }) else { continue }

            windowController.window?.makeKeyAndOrderFront(self)
            tabCollectionViewModel.select(at: index)
            if let tab = tabCollectionViewModel.tabViewModel(at: index)?.tab,
               tab.content.urlForWebView != url {
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
        windowController.window?.makeKeyAndOrderFront(self)

        let tabCollectionViewModel = viewController.tabCollectionViewModel
        let tabCollection = tabCollectionViewModel.tabCollection

        if tabCollection.tabs.count == 1,
           let firstTab = tabCollection.tabs.first,
           case .newtab = firstTab.content,
           !newTab {
            firstTab.setContent(url.map { .contentFromURL($0, source: source) } ?? .newtab)
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

    /// Shows the non-privacy pro feedback modal
    func showFeedbackModal(preselectedFormOption: FeedbackViewController.FormOption? = nil) {
        if internalUserDecider.isInternalUser {
            showTab(with: .url(.internalFeedbackForm, source: .ui))
        } else {
            FeedbackPresenter.presentFeedbackForm(preselectedFormOption: preselectedFormOption)
        }
    }

    /// Shows the Privacy Pro feedback modal
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
            let tabCollection = TabCollection(tabs: [])
            let tabCollectionViewModel = TabCollectionViewModel(tabCollection: tabCollection)
            let window = WindowsManager.openNewWindow(with: tabCollectionViewModel)
            window?.beginSheet(feedbackFormWindow)
        }
    }

    func showMainWindow() {
        guard Application.appDelegate.windowControllersManager.lastKeyMainWindowController == nil else { return }
        let tabCollection = TabCollection(tabs: [])
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
                       isFullscreen: Bool = false) -> MainWindow? {
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

    var allTabViewModels: [TabViewModel] {
        return allTabCollectionViewModels.flatMap {
            $0.tabViewModels.values
        }
    }

    func allTabViewModels(for burnerMode: BurnerMode, includingPinnedTabs: Bool = false) -> [TabViewModel] {
        let currentBurnerModeTabCollectionViewModels = allTabCollectionViewModels
            .filter { tabCollectionViewModel in
                tabCollectionViewModel.burnerMode == burnerMode
            }
        let tabViewModelsWithOriginalOrder = currentBurnerModeTabCollectionViewModels.flatMap {
            (0..<$0.tabViewModels.count).compactMap($0.tabViewModel(at:)) // TabViewModels ordered by Index
        }
        let pinnedTabSuggestions = includingPinnedTabs ? pinnedTabsManagerProvider.currentPinnedTabManagers.flatMap({
            (0..<$0.tabViewModels.count).compactMap($0.tabViewModel(at:)) // TabViewModels ordered by Index
        }) : []
        let result = pinnedTabSuggestions + tabViewModelsWithOriginalOrder

        return result
    }

    func windowController(for tabCollectionViewModel: TabCollectionViewModel) -> MainWindowController? {
        return mainWindowControllers.first(where: {
            tabCollectionViewModel === $0.mainViewController.tabCollectionViewModel
        })
    }

    func windowController(for tab: Tab) -> MainWindowController? {
        return mainWindowControllers.first(where: {
            $0.mainViewController.tabCollectionViewModel.tabCollection.tabs.contains(tab)
        })
    }

}

extension WindowControllersManager: OnboardingNavigating {
    @MainActor
    func updatePreventUserInteraction(prevent: Bool) {
        mainWindowController?.userInteraction(prevented: prevent)
    }

    @MainActor
    func showImportDataView() {
        DataImportView(title: UserText.importDataTitleOnboarding, isDataTypePickerExpanded: false).show()
    }

    @MainActor
    func replaceTabWith(_ tab: Tab) {
        guard let tabToRemove = selectedTab else { return }
        guard let mainWindowController else { return }
        guard let index = mainWindowController.mainViewController.tabCollectionViewModel.indexInAllTabs(of: tabToRemove) else { return }
        var tabToAppend = tab
        if mainWindowController.mainViewController.isBurner {
            let burnerMode = mainWindowController.mainViewController.tabCollectionViewModel.burnerMode
            tabToAppend = Tab(content: tab.content, burnerMode: burnerMode)
        }
        mainWindowController.mainViewController.tabCollectionViewModel.append(tab: tabToAppend)
        mainWindowController.mainViewController.tabCollectionViewModel.remove(at: index)
    }

    @MainActor
    func focusOnAddressBar() {
        guard let mainVC = lastKeyMainWindowController?.mainViewController else { return }
        mainVC.navigationBarViewController.addressBarViewController?.addressBarTextField.stringValue = ""
        mainVC.navigationBarViewController.addressBarViewController?.addressBarTextField.makeMeFirstResponder()
    }
}
