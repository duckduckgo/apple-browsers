//
//  MainWindowController.swift
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

import Cocoa
import Combine
import Common
import PixelKit

@MainActor
final class MainWindowController: NSWindowController {

    private var fireViewModel: FireViewModel
    private var cancellables: Set<AnyCancellable> = []
    private static var knownFullScreenMouseDetectionWindows = Set<NSValue>()
    let fireWindowSession: FireWindowSession?
    private let appearancePreferences: AppearancePreferences = NSApp.delegateTyped.appearancePreferences
    let fullscreenController = FullscreenController()
    private let visualStyle: VisualStyleProviding

    var mainViewController: MainViewController {
        // swiftlint:disable force_cast
        contentViewController as! MainViewController
        // swiftlint:enable force_cast
    }

    var titlebarView: NSView? {
        return window?.standardWindowButton(.closeButton)?.superview
    }

    @MainActor
    init(window: NSWindow? = nil,
         mainViewController: MainViewController,
         fireWindowSession: FireWindowSession? = nil,
         fireViewModel: FireViewModel,
         visualStyle: VisualStyleProviding) {

        // Compute initial window frame
        let frame = InitialWindowFrameProvider.initialFrame()

        assert(window == nil || [.unitTests, .integrationTests].contains(AppVersion.runType),
               "Window should not be set in non-test environment")
        let popUp = mainViewController.tabCollectionViewModel.isPopup
        let window = window ?? (popUp
            ? PopUpWindow(frame: frame)
            : MainWindow(frame: frame))
        window.contentViewController = mainViewController
        window.setContentSize(frame.size)
        self.fireViewModel = fireViewModel

        assert(!mainViewController.isBurner || fireWindowSession != nil)
        self.fireWindowSession = fireWindowSession
        fireWindowSession?.addWindow(window)

        self.visualStyle = visualStyle

        super.init(window: window)

        setupWindow(window)
        setupToolbar()
        subscribeToTrafficLightsAlpha()
        subscribeToBurningData()
        subscribeToResolutionChange()
        subscribeToFullScreenToolbarChanges()
        subscribeToKeyWindow()

#if !APPSTORE && WEB_EXTENSIONS_ENABLED
        if #available(macOS 15.4, *) {
            WebExtensionManager.shared.eventsListener.didOpenWindow(self)
        }
#endif
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private var shouldShowOnboarding: Bool {
#if DEBUG
        return false
#elseif REVIEW
        if AppVersion.runType == .uiTests {
            Application.appDelegate.onboardingContextualDialogsManager.state = .onboardingCompleted
            return false
        } else {
            if AppVersion.runType == .uiTestsOnboarding {
                Application.appDelegate.onboardingContextualDialogsManager.state = .onboardingCompleted
            }
            let onboardingIsComplete = OnboardingActionsManager.isOnboardingFinished || LocalStatisticsStore().waitlistUnlocked
            return !onboardingIsComplete
        }
#else
        let onboardingIsComplete = OnboardingActionsManager.isOnboardingFinished || LocalStatisticsStore().waitlistUnlocked
        return !onboardingIsComplete
#endif
    }

    private func setupWindow(_ window: NSWindow) {
        window.delegate = self

        // Prevent a 2px white line from appearing above the tab bar on macOS 26
        window.backgroundColor = visualStyle.colorsProvider.baseBackgroundColor

        if shouldShowOnboarding {
            mainViewController.tabCollectionViewModel.selectedTabViewModel?.tab.startOnboarding()
        }
    }

    private func subscribeToResolutionChange() {
        NotificationCenter.default.addObserver(self, selector: #selector(didChangeScreenParameters), name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
    }

    private func subscribeToFullScreenToolbarChanges() {
        NotificationCenter.default.publisher(for: AppearancePreferences.Notifications.showTabsAndBookmarksBarOnFullScreenChanged)
            .compactMap { $0.userInfo?[AppearancePreferences.Constants.showTabsAndBookmarksBarOnFullScreenParameter] as? Bool }
            .sink { [weak self] showTabsAndBookmarksBarOnFullScreen in
                if self?.window?.isFullScreen == true {
                    if showTabsAndBookmarksBarOnFullScreen {
                        self?.showTabBarAndBookmarksBar()
                    } else {
                        self?.hideTabBarAndBookmarksBar()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func subscribeToKeyWindow() {
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .sink { [weak self] notification in
                self?.windowDidBecomeKeyNotification(notification)
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
            .sink { [weak self] notification in
                self?.windowDidResignKeyNotification(notification)
            }
            .store(in: &cancellables)
    }

    @objc
    private func didChangeScreenParameters(_ notification: NSNotification) {
        if let visibleWindowFrame = window?.screen?.visibleFrame,
           let windowFrame = window?.frame {

            if windowFrame.width > visibleWindowFrame.width || windowFrame.height > visibleWindowFrame.height {
                window?.performZoom(nil)
            }
        }
    }

    private func setupToolbar() {
        // Empty toolbar ensures that window buttons are centered vertically
        window?.toolbar = NSToolbar()
        window?.toolbar?.showsBaselineSeparator = true
        window?.toolbarStyle = .unifiedCompact
        moveTabBarView(toTitlebarView: true)
    }

    private var trafficLightsAlphaCancellable: AnyCancellable?
    private func subscribeToTrafficLightsAlpha() {
        let tabBarViewController = mainViewController.tabBarViewController

        // slide tabs to the left in full screen
        trafficLightsAlphaCancellable = window?.standardWindowButton(.closeButton)?
            .publisher(for: \.alphaValue)
            .map { alphaValue in
                if #available(macOS 26, *) {
                    return TabBarViewController.HorizontalSpace.pinnedTabsScrollViewPaddingMacOS26.rawValue * alphaValue
                } else {
                    return TabBarViewController.HorizontalSpace.pinnedTabsScrollViewPadding.rawValue * alphaValue
                }
            }
            .assign(to: \.constant, onWeaklyHeld: tabBarViewController.pinnedTabsViewLeadingConstraint)
    }

    private var burningDataCancellable: AnyCancellable?
    private func subscribeToBurningData() {
        burningDataCancellable = fireViewModel.fire.$burningData
            .dropFirst()
            .removeDuplicates()
            .sink(receiveValue: { [weak self] burningData in
                guard let self else { return }
                self.userInteraction(prevented: burningData != nil, forBurning: true)
                self.moveTabBarView(toTitlebarView: burningData == nil)
            })
    }

    func userInteraction(prevented: Bool, forBurning: Bool = false) {
        mainViewController.tabCollectionViewModel.changesEnabled = !prevented
        mainViewController.tabCollectionViewModel.selectedTabViewModel?.tab.contentChangeEnabled = !prevented

        mainViewController.tabBarViewController.fireButton.isEnabled = !prevented
        mainViewController.tabBarViewController.isInteractionPrevented = prevented
        mainViewController.navigationBarViewController.controlsForUserPrevention.forEach { $0?.isEnabled = !prevented }
        mainViewController.bookmarksBarViewController.userInteraction(prevented: prevented)

        NSApplication.shared.mainMenuTyped.autoupdatingMenusForUserPrevention.forEach { $0.autoenablesItems = !prevented }
        NSApplication.shared.mainMenuTyped.menuItemsForUserPrevention.forEach { $0.isEnabled = !prevented }

        guard forBurning else { return }
        if prevented {
             window?.styleMask.remove(.closable)
             mainViewController.view.makeMeFirstResponder()
         } else {
             window?.styleMask.update(with: .closable)
             mainViewController.adjustFirstResponder()
         }
    }

    private func moveTabBarView(toTitlebarView: Bool) {
        guard let newParentView = toTitlebarView ? titlebarView : mainViewController.view else {
            assertionFailure("Failed to move tab bar view")
            return
        }
        let tabBarViewController = mainViewController.tabBarViewController
        tabBarViewController.view.removeFromSuperview()

        if toTitlebarView {
            // Prevent 1px line from appearing below Tab Bar when hiding and subsequently showing it in fullscreen mode
            // https://app.asana.com/1/137249556945/project/1201048563534612/task/1209999815083499?focus=true
            newParentView.layer?.masksToBounds = true
            newParentView.addSubview(tabBarViewController.view)
        } else {
            newParentView.addSubview(tabBarViewController.view, positioned: .below, relativeTo: mainViewController.fireViewController.view)
        }

        // enable Tab Bar appear as an AX child of the Window
        // this won‘t work by-default since we‘re adding it to the NSToolbar view
        // providing its own a11y implementation: see TabBarViewController
        if let toolbarView = newParentView.subviews.first(where: { $0.className == "NSToolbarView" }) {
            toolbarView.setAccessibilityEnabled(false)
            toolbarView.setAccessibilityElement(false)
            tabBarViewController.view.setAccessibilityParent(window)
        }

        tabBarViewController.view.frame = newParentView.bounds
        tabBarViewController.view.translatesAutoresizingMaskIntoConstraints = false
        let constraints = tabBarViewController.view.addConstraints(to: newParentView, [
            .leading: .leading(),
            .trailing: .trailing(),
            .top: .top()
        ])
        NSLayoutConstraint.activate(constraints)
    }

    override func showWindow(_ sender: Any?) {
        window?.makeKeyAndOrderFront(sender)
        register()
    }

    override func cancelOperation(_ sender: Any?) {
        guard let window, !fullscreenController.shouldPreventFullscreenExit else {
            // Just consume the ESC key to prevent exiting from full screen
            fullscreenController.resetFullscreenExitFlag()
            return
        }

        if window.styleMask.contains(.fullScreen) {
            fullscreenController.manuallyExitFullscreen(window: window)
        }
    }

    func orderWindowBack(_ sender: Any?) {
        if let lastKeyWindow = Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.window {
            window?.order(.below, relativeTo: lastKeyWindow.windowNumber)
        } else {
            window?.orderFront(sender)
        }
        register()
    }

    private func register() {
        Application.appDelegate.windowControllersManager.register(self)
    }

}

extension MainWindowController: NSWindowDelegate {

    private func windowDidBecomeKeyNotification(_ notification: Notification) {
        guard let keyWindow = notification.object as? NSWindow,
              let mainWindow = self.window,
              keyWindow.isInHierarchy(of: mainWindow) else { return }

        mainViewController.windowDidBecomeKey()

        if !mainWindow.isPopUpWindow {
            Application.appDelegate.windowControllersManager.lastKeyMainWindowController = self
        }

#if !APPSTORE && WEB_EXTENSIONS_ENABLED
        if #available(macOS 15.4, *) {
            WebExtensionManager.shared.eventsListener.didFocusWindow(self)
        }
#endif
    }

    private func windowDidResignKeyNotification(_ notification: Notification) {
        guard let exKeyWindow = notification.object as? NSWindow,
              let mainWindow = self.window,
              exKeyWindow.isInHierarchy(of: mainWindow),
              // if one of the windows in the window controller chain became key instead of a sheet
              NSApp.keyWindow?.isInHierarchy(of: mainWindow) != true else { return }

        mainViewController.windowDidResignKey()
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        mainViewController.tabBarViewController.draggingSpace.isHidden = true
        mainViewController.windowWillEnterFullScreen()

        if !appearancePreferences.showTabsAndBookmarksBarOnFullScreen {
            hideTabBarAndBookmarksBar()
        }
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        mainViewController.tabBarViewController.draggingSpace.isHidden = false

        if !appearancePreferences.showTabsAndBookmarksBarOnFullScreen {
            showTabBarAndBookmarksBar()
        }

        fullscreenController.resetFullscreenExitFlag()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        mainViewController.windowDidEndLiveResize()
    }

    private func hideTabBarAndBookmarksBar() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            mainViewController.disableTabPreviews()
            mainViewController.mainView.isTabBarShown = false
            mainViewController.mainView.webContainerTopBinding = .navigationBar
            mainViewController.updateBookmarksBarViewVisibility(visible: false)
            moveTabBarView(toTitlebarView: false)
            window?.titlebarAppearsTransparent = false
            window?.toolbar = nil
        }
    }

    private func showTabBarAndBookmarksBar() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            mainViewController.enableTabPreviews()
            mainViewController.mainView.isTabBarShown = true
            mainViewController.mainView.webContainerTopBinding = .tabBar
            mainViewController.updateBookmarksBarViewVisibility(visible: mainViewController.shouldShowBookmarksBar)
            window?.titlebarAppearsTransparent = true
            setupToolbar()
        }
    }

    func windowWillMiniaturize(_ notification: Notification) {
        mainViewController.windowWillMiniaturize()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        guard let window = self.window else { return }

        // Detect split screen vs regular fullscreen mode
        if window.isApproximatelyHalfScreenWide {
            // Fire pixel for split screen usage
            PixelKit.fire(GeneralPixel.windowSplitScreen, frequency: .dailyAndCount)
        } else {
            // Fire pixel for regular fullscreen usage
            PixelKit.fire(GeneralPixel.windowFullscreen, frequency: .dailyAndCount)
        }

        // fix NSToolbarFullScreenWindow occurring beneath the MainWindow
        // https://app.asana.com/0/1177771139624306/1203853030672990/f
        // NSApp should be active at the moment of window ordering otherwise toolbar would disappear on activation
        for window in NSApp.windows {
            let windowValue = NSValue(nonretainedObject: window)

            guard window.className.contains("NSFullScreenMouseDetectionWindow"),
                  !Self.knownFullScreenMouseDetectionWindows.contains(windowValue),
                  window.screen == self.window!.screen else { continue }

            // keep record of NSFullScreenMouseDetectionWindow to avoid adding other‘s windows
            Self.knownFullScreenMouseDetectionWindows.insert(windowValue)
            window.onDeinit {
                Self.knownFullScreenMouseDetectionWindows.remove(windowValue)
            }

            // add NSFullScreenMouseDetectionWindow as a child window to activate the app without revealing all of its windows
            let activeApp = NSWorkspace.shared.frontmostApplication
            if activeApp != .current {
                self.window!.addChildWindow(window, ordered: .above)
            }

            // remove the child window and reactivate initially active app as soon as current app becomes active
            // otherwise the fullscreen will reactivate its Space when switching to window in another Space
            var cancellable: AnyCancellable!
            cancellable = NSApp.isActivePublisher().dropFirst().sink { [weak self, weak window] _ in
                withExtendedLifetime(cancellable) {
                    if let activeApp, activeApp != .current {
                        activeApp.activate()
                    }

                    if let self, let window, self.window?.childWindows?.contains(window) == true {
                        self.window?.removeChildWindow(window)
                    }
                    cancellable = nil
                }
            }

            break
        }
    }

    func windowWillClose(_ notification: Notification) {
        mainViewController.windowWillClose()

        window?.resignKey()
        window?.resignMain()

        // Unregistering triggers deinitialization of this object.
        // Because it's also the delegate, deinit within this method caused crash
        // Push the Window Controller into current autorelease pool so it‘s released when the event loop pass ends
        _=Unmanaged.passRetained(self).autorelease()
        Application.appDelegate.windowControllersManager.unregister(self)

#if !APPSTORE && WEB_EXTENSIONS_ENABLED
        if #available(macOS 15.4, *) {
            WebExtensionManager.shared.eventsListener.didCloseWindow(self)
        }
#endif
    }

    func windowShouldClose(_ window: NSWindow) -> Bool {
        guard mainViewController.tabCollectionViewModel.isBurner else { return true }

        if showAlertIfActiveDownloadsPresent(in: window) {
            return false
        }

        animateBurningIfNeededAndClose(window)
        return false
    }

    private func showAlertIfActiveDownloadsPresent(in window: NSWindow) -> Bool {
        guard let fireWindowSessionRef = FireWindowSessionRef(window: window),
              let fireWindowSession = fireWindowSessionRef.fireWindowSession else {
            assertionFailure("No FireWindowSession in Fire Window \(window)")
            return false
        }
        // only check if it‘s the last Fire Window from the Burner Session
        guard fireWindowSession.windows == [window] else { return false }
        let fireWindowDownloads = Set(FileDownloadManager.shared.downloads.filter { $0.fireWindowSession == fireWindowSessionRef && $0.state.isDownloading })
        guard !fireWindowDownloads.isEmpty else { return false }

        let alert = NSAlert.activeDownloadsFireWindowClosingAlert(for: fireWindowDownloads)
        let downloadsFinishedCancellable = FileDownloadManager.observeDownloadsFinished(fireWindowDownloads) {
            // close alert and burn the window when all downloads finished
            window.endSheet(alert.window, returnCode: .OK)
        }
        alert.beginSheetModal(for: window) { response in
            downloadsFinishedCancellable.cancel()
            if response == .OK {
                fireWindowDownloads.forEach { download in
                    download.cancel()
                }
                self.animateBurningIfNeededAndClose(window)
                return
            } else if self.mainViewController.tabCollectionViewModel.tabs.isEmpty {
                // reopen last closed tab if the window stays open
                DispatchQueue.main.async {
                    self.mainViewController.browserTabViewController.openNewTab(with: .newtab)
                }
            }
        }
        return true
    }

    private func animateBurningIfNeededAndClose(_ window: NSWindow) {
        guard !window.isPopUpWindow else {
            window.close()
            return
        }
        Task {
            moveTabBarView(toTitlebarView: false)
            await mainViewController.fireViewController.animateFireWhenClosing()
            window.close()
        }
    }

}

fileprivate extension MainMenu {

    var menuItemsForUserPrevention: [NSMenuItem] {
        return [
            newWindowMenuItem,
            newTabMenuItem,
            openLocationMenuItem,
            closeWindowMenuItem,
            closeAllWindowsMenuItem,
            closeTabMenuItem,
            importBrowserDataMenuItem,
            manageBookmarksMenuItem,
            importBookmarksMenuItem,
            preferencesMenuItem
        ]
    }

    var autoupdatingMenusForUserPrevention: [NSMenu] {
        return [
            preferencesMenuItem.menu,
            manageBookmarksMenuItem.menu
        ].compactMap { $0 }
    }

}

fileprivate extension NavigationBarViewController {

    var controlsForUserPrevention: [NSControl?] {
        return [homeButton,
                optionsButton,
                overflowButton,
                bookmarkListButton,
                passwordManagementButton,
                addressBarViewController?.addressBarTextField,
                addressBarViewController?.passiveTextField,
                addressBarViewController?.addressBarButtonsViewController?.bookmarkButton
        ]
    }

}

extension NSWindow {
    var isFullScreen: Bool {
        return self.styleMask.contains(.fullScreen) && self.isMiniaturized == false
    }
}
