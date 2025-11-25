//
//  WindowsManager.swift
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

@MainActor
final class WindowsManager {

    internal enum Constants {
        static let defaultPopUpWidth: CGFloat = 1024
        static let defaultPopUpHeight: CGFloat = 752
        static let minimumPopUpWidth: CGFloat = 512
        static let minimumPopUpHeight: CGFloat = 258
    }

    class var windows: [NSWindow] {
        NSApplication.shared.windows
    }

    class var mainWindows: [MainWindow] {
        NSApplication.shared.windows.compactMap { $0 as? MainWindow }
    }

    // Shared type to enable managing `PasswordManagementPopover`s in multiple windows
    private static let autofillPopoverPresenter: AutofillPopoverPresenter = DefaultAutofillPopoverPresenter()

    class func closeWindows(except windows: [NSWindow] = []) {
        for controller in Application.appDelegate.windowControllersManager.mainWindowControllers {
            guard let window = controller.window, !windows.contains(window) else { continue }
            controller.close()
        }
    }

    /// finds window to position newly opened (or popup) windows against
    private class func findPositioningSourceWindow(for tab: Tab?) -> NSWindow? {
        if let parentTab = tab?.parentTab,
           let sourceWindowController = Application.appDelegate.windowControllersManager.mainWindowControllers.first(where: {
               $0.mainViewController.tabCollectionViewModel.tabs.contains(parentTab)
           }) {
            // window that initiated the new window opening
            return sourceWindowController.window
        }

        // fallback to last known main window
        return Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.window
    }

    @discardableResult
    class func openNewWindow(with tabCollectionViewModel: TabCollectionViewModel? = nil,
                             aiChatSidebarProvider: AIChatSidebarProviding = Application.appDelegate.aiChatSidebarProvider,
                             fireCoordinator: FireCoordinator = Application.appDelegate.fireCoordinator,
                             burnerMode: BurnerMode? = nil,
                             droppingPoint: NSPoint? = nil,
                             contentSize: NSSize? = nil,
                             showWindow: Bool = true,
                             popUp: Bool = false,
                             lazyLoadTabs: Bool = false,
                             isMiniaturized: Bool = false,
                             isMaximized: Bool = false,
                             isFullscreen: Bool = false) -> NSWindow? {
        // Determine effective burner mode based on user preference
        let effectiveBurnerMode = burnerModeForNewWindow(burnerMode: burnerMode)
        assert(tabCollectionViewModel == nil || tabCollectionViewModel!.isPopup == popUp)
        let mainWindowController = makeNewWindow(tabCollectionViewModel: tabCollectionViewModel,
                                                 popUp: popUp,
                                                 burnerMode: effectiveBurnerMode,
                                                 autofillPopoverPresenter: autofillPopoverPresenter,
                                                 fireCoordinator: fireCoordinator,
                                                 aiChatSidebarProvider: aiChatSidebarProvider)

        if let contentSize {
            mainWindowController.window?.setContentSize(contentSize)
        }

        mainWindowController.window?.setIsMiniaturized(isMiniaturized)

        if isMaximized {
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                mainWindowController.window?.setFrame(screenFrame, display: true, animate: true)
                mainWindowController.window?.makeKeyAndOrderFront(nil)
            }
        }

        if isFullscreen {
            mainWindowController.window?.toggleFullScreen(self)
        }

        if let droppingPoint {
            mainWindowController.window?.setFrameOrigin(droppingPoint: droppingPoint)
        } else if let sourceWindow = self.findPositioningSourceWindow(for: tabCollectionViewModel?.tabs.first) {
            mainWindowController.window?.setFrameOrigin(cascadedFrom: sourceWindow)
        }

        if showWindow {
            mainWindowController.showWindow(self)
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            mainWindowController.orderWindowBack(self)
        }

        if lazyLoadTabs {
            mainWindowController.mainViewController.tabCollectionViewModel.setUpLazyLoadingIfNeeded()
        }

        return mainWindowController.window
    }

    private class func burnerModeForNewWindow(burnerMode: BurnerMode?) -> BurnerMode {
        if let burnerMode {
            return burnerMode
        } else {
            return burnerModeByDefault()
        }
    }

    private class func burnerModeByDefault() -> BurnerMode {
        // Use user preference for default window type
        if let appDelegate = NSApp.delegate as? AppDelegate {
            return appDelegate.visualizeFireSettingsDecider.isOpenFireWindowByDefaultEnabled ? BurnerMode(isBurner: true) : .regular
        } else {
            return .regular
        }
    }

    @discardableResult
    class func openNewWindow(with tab: Tab, droppingPoint: NSPoint? = nil, contentSize: NSSize? = nil, showWindow: Bool = true, popUp: Bool = false) -> NSWindow? {
        let tabCollection = TabCollection(isPopup: popUp)
        tabCollection.append(tab: tab)

        let tabCollectionViewModel: TabCollectionViewModel = {
            if popUp {
                return .init(tabCollection: tabCollection, pinnedTabsManagerProvider: nil, burnerMode: tab.burnerMode, windowControllersManager: Application.appDelegate.windowControllersManager)
            }
            return .init(tabCollection: tabCollection, burnerMode: tab.burnerMode)
        }()

        return openNewWindow(with: tabCollectionViewModel,
                             burnerMode: tab.burnerMode,
                             droppingPoint: droppingPoint,
                             contentSize: contentSize,
                             showWindow: showWindow,
                             popUp: popUp)
    }

    @discardableResult
    class func openNewWindow(with initialUrl: URL, source: Tab.TabContent.URLSource, isBurner: Bool? = nil, parentTab: Tab? = nil, droppingPoint: NSPoint? = nil, showWindow: Bool = true) -> NSWindow? {
        if let isBurner {
            return openNewWindow(with: Tab(content: .contentFromURL(initialUrl, source: source), parentTab: parentTab, shouldLoadInBackground: true, burnerMode: BurnerMode(isBurner: isBurner)), droppingPoint: droppingPoint, showWindow: showWindow)
        } else {
            return openNewWindow(with: Tab(content: .contentFromURL(initialUrl, source: source), parentTab: parentTab, shouldLoadInBackground: true, burnerMode: burnerModeByDefault()), droppingPoint: droppingPoint, showWindow: showWindow)
        }
    }

    @discardableResult
    class func openNewWindow(with tabCollection: TabCollection, isBurner: Bool, droppingPoint: NSPoint? = nil, contentSize: NSSize? = nil) -> NSWindow? {
        let burnerMode = BurnerMode(isBurner: isBurner)
        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: tabCollection, burnerMode: burnerMode)
        defer {
            tabCollectionViewModel.setUpLazyLoadingIfNeeded()
        }
        return openNewWindow(with: tabCollectionViewModel,
                             burnerMode: burnerMode,
                             droppingPoint: droppingPoint,
                             contentSize: contentSize,
                             popUp: tabCollection.isPopup)
    }

    @discardableResult
    class func openPopUpWindow(with tab: Tab, origin: NSPoint?, contentSize: NSSize?, forcePopup: Bool = false) -> NSWindow? {
        if !forcePopup,
           let mainWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController,
           mainWindowController.window?.styleMask.contains(.fullScreen) == true,
           mainWindowController.window?.isPopUpWindow == false {

            mainWindowController.mainViewController.tabCollectionViewModel.insert(tab, selected: true)
            return mainWindowController.window

        } else {
            let (droppingPoint, finalContentSize) = calculatePopupFrame(for: tab, origin: origin, contentSize: contentSize)
            return self.openNewWindow(with: tab, droppingPoint: droppingPoint, contentSize: finalContentSize, popUp: true)
        }
    }

    /// Calculates the popup window frame for a given tab.
    /// - Parameters:
    ///   - tab: The tab that is creating the popup
    ///   - origin: The popup origin in web coordinates (top-left, from window.open)
    ///   - contentSize: The requested popup content size
    /// - Returns: A tuple containing the dropping point (top-center) and final content size
    private class func calculatePopupFrame(for tab: Tab, origin: NSPoint?, contentSize: NSSize?) -> (droppingPoint: NSPoint?, contentSize: NSSize) {
        let sourceWindow = findPositioningSourceWindow(for: tab)
        // Use visibleFrame to ensure popup doesn't go behind dock or menu bar
        let screenFrame = (sourceWindow?.screen ?? .main)?.visibleFrame ?? NSScreen.fallbackHeadlessScreenFrame
        return calculatePopupFrame(screenFrame: screenFrame, origin: origin, contentSize: contentSize)
    }

    /// Calculates the popup window frame with explicit screen and parent frame parameters.
    /// This method is exposed as `internal` for unit testing purposes.
    ///
    /// - Parameters:
    ///   - screenFrame: The visible frame of the screen (excluding dock and menu bar)
    ///   - origin: The popup origin in web coordinates (top-left corner, as provided by window.open)
    ///   - contentSize: The requested popup content size (may be nil or zero)
    ///
    /// - Returns: A tuple containing:
    ///   - droppingPoint: The top-center point for window positioning (nil if no origin provided)
    ///   - contentSize: The final content size after applying minimum dimensions and screen constraints
    ///
    /// - Note: The droppingPoint is in the top-center format expected by `NSRect.frameOrigin(fromDroppingPoint:)`
    class func calculatePopupFrame(screenFrame: NSRect, origin: NSPoint?, contentSize: NSSize?) -> (droppingPoint: NSPoint?, contentSize: NSSize) {
        // Calculate final content size: enforce minimum dimensions and constrain to screen
        // If contentSize is nil or zero, use defaults
        var contentSize = contentSize ?? .zero
        contentSize = NSSize(
            width: min(screenFrame.width, max(Constants.minimumPopUpWidth, contentSize.width > 0 ? contentSize.width : Constants.defaultPopUpWidth)),
            height: min(screenFrame.height, max(Constants.minimumPopUpHeight, contentSize.height > 0 ? contentSize.height : Constants.defaultPopUpHeight))
        )

        // Calculate dropping point if origin is provided
        // Popup should be fully positioned within visible screen bounds
        // Origin is in web coordinates (x: from left, y: from top)
        // droppingPoint is in AppKit coordinates (x: center of window, y: top of window)
        let droppingPoint = origin.map { origin in
            return NSPoint(
                x: max(screenFrame.minX, min(screenFrame.maxX - contentSize.width, screenFrame.minX + origin.x)) + contentSize.width / 2,
                y: max(screenFrame.minY + contentSize.height, min(screenFrame.maxY, screenFrame.maxY - origin.y))
            )
        }

        return (droppingPoint, contentSize)
    }

    private class func makeNewWindow(tabCollectionViewModel: TabCollectionViewModel? = nil,
                                     popUp: Bool = false,
                                     burnerMode: BurnerMode,
                                     autofillPopoverPresenter: AutofillPopoverPresenter,
                                     fireCoordinator: FireCoordinator,
                                     aiChatSidebarProvider: AIChatSidebarProviding) -> MainWindowController {
        assert(tabCollectionViewModel == nil || tabCollectionViewModel!.isPopup == popUp)
        let mainViewController = MainViewController(
            tabCollectionViewModel: tabCollectionViewModel ?? TabCollectionViewModel(isPopup: popUp, burnerMode: burnerMode),
            autofillPopoverPresenter: autofillPopoverPresenter,
            aiChatSidebarProvider: aiChatSidebarProvider,
            fireCoordinator: fireCoordinator
        )

        let fireWindowSession = if case .burner = burnerMode {
            Application.appDelegate.windowControllersManager.mainWindowControllers.first(where: {
                $0.mainViewController.tabCollectionViewModel.burnerMode == burnerMode
            })?.fireWindowSession ?? FireWindowSession()
        } else { FireWindowSession?.none }
        return MainWindowController(
            mainViewController: mainViewController,
            fireWindowSession: fireWindowSession,
            fireViewModel: fireCoordinator.fireViewModel,
            themeManager: NSApp.delegateTyped.themeManager
        )
    }

}

fileprivate extension NSStoryboard.SceneIdentifier {
    static let mainViewController = NSStoryboard.SceneIdentifier("mainViewController")
}
