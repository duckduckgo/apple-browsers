//
//  Tab+WKWebExtensionTab.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import WebExtensions
import WebKit

@available(macOS 15.4, *)
@MainActor
extension Tab: WKWebExtensionTab {

    enum WebExtensionTabError: Error {
        case notSupported
        case tabNotFound
        case alreadyPinned
        case notPinned
        case alreadyMuted
        case notMuted
    }

    private var mainWindowController: MainWindowController? {
        // The manager prefers the current hosting window for shared pinned tabs, but ignores it
        // during a handoff once the source collection no longer owns the tab.
        return Application.appDelegate.windowControllersManager.windowController(for: self)
    }

    private var tabCollectionViewModel: TabCollectionViewModel? {
        return mainWindowController?.mainViewController.tabCollectionViewModel
    }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        return mainWindowController
    }

    private func indexInWindow(for context: WKWebExtensionContext!) -> UInt {
        return UInt(tabCollectionViewModel?.webExtensionIndex(of: self) ?? 0)
    }

    func parentTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        return parentTab
    }

    func setParentTab(_ parentTab: (any WKWebExtensionTab)?, for context: WKWebExtensionContext) async throws {
        throw WebExtensionAPICompatibilityLog.unsupportedAPI("tabs.update.openerTabId", in: context)
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        return webExtensionPageWebView ?? webView
    }

    func title(for context: WKWebExtensionContext) -> String? {
        return title
    }

    func isPinned(for context: WKWebExtensionContext) -> Bool {
        return isPinned
    }

    func setPinned(_ pinned: Bool, for context: WKWebExtensionContext) async throws {
        guard let tabIndex = tabCollectionViewModel?.indexInAllTabs(of: self) else {
            throw WebExtensionTabError.tabNotFound
        }

        if pinned {
            switch tabIndex {
            case .pinned:
                throw WebExtensionTabError.alreadyPinned
            case .unpinned(let index):
                tabCollectionViewModel?.pinTab(at: index)
            }
        } else {
            switch tabIndex {
            case .pinned(let index):
                tabCollectionViewModel?.unpinTab(at: index)
            case .unpinned:
                throw WebExtensionTabError.notPinned
            }
        }
    }

    func isReaderModeAvailable(for context: WKWebExtensionContext) -> Bool {
        return false
    }

    func isReaderModeActive(for context: WKWebExtensionContext) -> Bool {
        return false
    }

    func setReaderModeActive(_ active: Bool, for context: WKWebExtensionContext) async throws {
        throw WebExtensionAPICompatibilityLog.unsupportedAPI("tabs.toggleReaderMode", in: context)
    }

    func isPlayingAudio(for context: WKWebExtensionContext) -> Bool {
        return false
    }

    func isMuted(for context: WKWebExtensionContext) -> Bool {
        return audioState.isMuted
    }

    func setMuted(_ muted: Bool, for context: WKWebExtensionContext) async throws {
        if muted {
            guard !audioState.isMuted else {
                throw WebExtensionTabError.notMuted
            }
        } else {
            guard audioState.isMuted else {
                throw WebExtensionTabError.alreadyMuted
            }
        }
        muteUnmuteTab()
    }

    func size(for context: WKWebExtensionContext) -> CGSize {
        webView.frame.size
    }

    func zoomFactor(for context: WKWebExtensionContext) -> Double {
        return webView.pageZoom
    }

    func setZoomFactor(_ zoomFactor: Double, for context: WKWebExtensionContext) async throws {
        throw WebExtensionAPICompatibilityLog.unsupportedAPI("tabs.setZoom", in: context)
    }

    func url(for context: WKWebExtensionContext) -> URL? {
        return content.urlForWebView
    }

    func pendingURL(for context: WKWebExtensionContext) -> URL? {
        return isLoading ? content.urlForWebView : nil
    }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool {
        return !isLoading
    }

    func detectWebpageLocale(for context: WKWebExtensionContext) async throws -> Locale? {
        return Locale.current
    }

    func snapshot(using configuration: WKSnapshotConfiguration, for context: WKWebExtensionContext) async throws -> NSImage? {
        try await webView(for: context)?.takeSnapshot(configuration: configuration)
    }

    func loadURL(_ url: URL, for context: WKWebExtensionContext) async throws {
        setContent(.url(url, credential: nil, source: .ui))
    }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext) async throws {
        reload()
    }

    func goBack(for context: WKWebExtensionContext) async throws {
        goBack()
    }

    func goForward(for context: WKWebExtensionContext) async throws {
        goForward()
    }

    func activate(for context: WKWebExtensionContext) async throws {
        tabCollectionViewModel?.select(tab: self)
    }

    func isSelected(for context: WKWebExtensionContext) -> Bool {
        return tabCollectionViewModel?.selectedTab == self
    }

    func setSelected(_ selected: Bool, for context: WKWebExtensionContext) async throws {
        if selected {
            tabCollectionViewModel?.select(tab: self)
        } else {
            throw WebExtensionAPICompatibilityLog.unsupportedAPI("tabs.update.highlighted", in: context)
        }
    }

    func duplicate(using configuration: WKWebExtension.TabConfiguration, for context: WKWebExtensionContext) async throws -> (any WKWebExtensionTab)? {
        throw WebExtensionAPICompatibilityLog.unsupportedAPI("tabs.duplicate", in: context)
    }

    func close(for context: WKWebExtensionContext) async throws {
        if let index = tabCollectionViewModel?.indexInAllTabs(of: self) {
            tabCollectionViewModel?.close(at: index)
        } else {
            throw WebExtensionTabError.tabNotFound
        }
    }

    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool {
        return true
    }

}
