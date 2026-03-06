//
//  AutomationServer.swift
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
import AutomationServer
import BrowserServicesKit
import Foundation
import WebKit
import os.log

/// macOS-specific implementation of BrowserAutomationProvider
@MainActor
final class MacOSAutomationProvider: BrowserAutomationProvider {
    let windowControllersManager: WindowControllersManager
    let contentBlockingManager: ContentBlockerRulesManagerProtocol

    init(windowControllersManager: WindowControllersManager, contentBlockingManager: ContentBlockerRulesManagerProtocol) {
        self.windowControllersManager = windowControllersManager
        self.contentBlockingManager = contentBlockingManager
    }

    private var activeMainViewController: MainViewController? {
        windowControllersManager.lastKeyMainWindowController?.mainViewController
    }

    private var activeTabCollectionViewModel: TabCollectionViewModel? {
        activeMainViewController?.tabCollectionViewModel
    }

    private var currentTab: Tab? {
        activeTabCollectionViewModel?.selectedTab
    }

    var currentTabHandle: String? {
        currentTab?.uuid
    }

    var isLoading: Bool {
        currentTab?.isLoading ?? false
    }

    var isContentBlockerReady: Bool {
        // Content blocker is ready when rules have been compiled
        !contentBlockingManager.currentRules.isEmpty
    }

    var currentURL: URL? {
        currentWebView?.url
    }

    var currentWebView: WKWebView? {
        currentTab?.webView
    }

    // MARK: - Tab Iteration Helpers

    /// Iterates over all tabs (pinned and unpinned) across all windows.
    /// Pinned tabs are shared across windows, so they are only yielded once.
    private func forEachTab(_ body: (Tab) -> Void) {
        var seenPinnedTabUUIDs = Set<String>()

        for windowController in windowControllersManager.mainWindowControllers {
            let tabCollectionViewModel = windowController.mainViewController.tabCollectionViewModel

            for tab in tabCollectionViewModel.pinnedTabs where !seenPinnedTabUUIDs.contains(tab.uuid) {
                seenPinnedTabUUIDs.insert(tab.uuid)
                body(tab)
            }

            for tab in tabCollectionViewModel.tabs {
                body(tab)
            }
        }
    }

    /// Finds a tab matching the predicate across all windows, returning the window controller and tab index.
    private func findTab(where predicate: (Tab) -> Bool) -> (windowController: MainWindowController, index: TabIndex)? {
        for windowController in windowControllersManager.mainWindowControllers {
            let tabCollectionViewModel = windowController.mainViewController.tabCollectionViewModel

            if let index = tabCollectionViewModel.pinnedTabs.firstIndex(where: predicate) {
                return (windowController, .pinned(index))
            }

            if let index = tabCollectionViewModel.tabs.firstIndex(where: predicate) {
                return (windowController, .unpinned(index))
            }
        }
        return nil
    }

    // MARK: - BrowserAutomationProvider

    func navigate(to url: URL) -> Bool {
        guard let tab = currentTab else {
            return false
        }
        tab.setContent(.contentFromURL(url, source: .userEntered(url.absoluteString, downloadRequested: false)))
        return true
    }

    func getAllTabHandles() -> [String] {
        var handles: [String] = []
        forEachTab { handles.append($0.uuid) }
        return handles
    }

    func closeCurrentTab() {
        guard let tab = currentTab,
              let tabCollectionViewModel = activeTabCollectionViewModel,
              let tabIndex = tabCollectionViewModel.indexInAllTabs(of: tab) else {
            return
        }
        tabCollectionViewModel.remove(at: tabIndex)
    }

    func switchToTab(handle: String) -> Bool {
        guard let (windowController, index) = findTab(where: { $0.uuid == handle }) else {
            return false
        }
        windowController.window?.makeKeyAndOrderFront(nil)
        windowController.mainViewController.tabCollectionViewModel.select(at: index)
        return true
    }

    func newTab() -> String? {
        guard let tabCollectionViewModel = activeTabCollectionViewModel else {
            return nil
        }
        tabCollectionViewModel.appendNewTab(with: .newtab, selected: true)
        return tabCollectionViewModel.selectedTab?.uuid
    }

    func executeScript(_ script: String, args: [String: Any]) async -> Result<Any?, Error> {
        guard let webView = currentWebView else {
            return .failure(AutomationServerError.noWindow)
        }

        guard #available(macOS 12.0, *) else {
            return .failure(AutomationServerError.unsupportedOSVersion)
        }

        do {
            let result = try await webView.callAsyncJavaScript(
                script,
                arguments: args,
                in: nil,
                contentWorld: .page
            )
            return .success(result)
        } catch {
            return .failure(error)
        }
    }

    func takeScreenshot(rect: CGRect?) async -> Data? {
        guard let webView = currentWebView else { return nil }

        return await withCheckedContinuation { continuation in
            let config = WKSnapshotConfiguration()
            if let rect = rect {
                config.rect = rect
            }
            webView.takeSnapshot(with: config) { image, _ in
                guard let image = image else {
                    continuation.resume(returning: nil)
                    return
                }
                guard let tiffData = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmap.representation(using: .png, properties: [:]) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: pngData)
            }
        }
    }
}

/// Wrapper that creates the automation server with the macOS provider
@MainActor
final class AutomationServer {
    private let core: AutomationServerCore?

    init(windowControllersManager: WindowControllersManager, contentBlockingManager: ContentBlockerRulesManagerProtocol, port: Int?) {
        let provider = MacOSAutomationProvider(windowControllersManager: windowControllersManager, contentBlockingManager: contentBlockingManager)
        do {
            self.core = try AutomationServerCore(provider: provider, port: port)
        } catch {
            Logger.automationServer.error("Failed to start automation server: \(error)")
            self.core = nil
        }
    }
}
