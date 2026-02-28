//
//  TabViewController+WKWebExtensionTab.swift
//  DuckDuckGo
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

import UIKit
import WebKit

@available(iOS 18.4, *)
@MainActor
extension TabViewController: WKWebExtensionTab {

    enum WebExtensionTabError: Error {
        case notSupported
        case tabNotFound
    }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        return delegate as? MainViewController
    }

    func parentTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        return nil
    }

    func setParentTab(_ parentTab: (any WKWebExtensionTab)?, for context: WKWebExtensionContext) async throws {
        throw WebExtensionTabError.notSupported
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        return webView
    }

    func title(for context: WKWebExtensionContext) -> String? {
        return tabModel.link?.title ?? webView.title
    }

    func isPinned(for context: WKWebExtensionContext) -> Bool {
        return false
    }

    func setPinned(_ pinned: Bool, for context: WKWebExtensionContext) async throws {
        throw WebExtensionTabError.notSupported
    }

    func isReaderModeAvailable(for context: WKWebExtensionContext) -> Bool {
        return false
    }

    func isReaderModeActive(for context: WKWebExtensionContext) -> Bool {
        return false
    }

    func setReaderModeActive(_ active: Bool, for context: WKWebExtensionContext) async throws {
        throw WebExtensionTabError.notSupported
    }

    func isPlayingAudio(for context: WKWebExtensionContext) -> Bool {
        return false
    }

    func isMuted(for context: WKWebExtensionContext) -> Bool {
        return false
    }

    func setMuted(_ muted: Bool, for context: WKWebExtensionContext) async throws {
        throw WebExtensionTabError.notSupported
    }

    func size(for context: WKWebExtensionContext) -> CGSize {
        return webView.frame.size
    }

    func zoomFactor(for context: WKWebExtensionContext) -> Double {
        return 1.0
    }

    func setZoomFactor(_ zoomFactor: Double, for context: WKWebExtensionContext) async throws {
        throw WebExtensionTabError.notSupported
    }

    func url(for context: WKWebExtensionContext) -> URL? {
        return tabModel.link?.url ?? webView.url
    }

    func pendingURL(for context: WKWebExtensionContext) -> URL? {
        return isLoading ? (tabModel.link?.url ?? webView.url) : nil
    }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool {
        return !isLoading
    }

    func detectWebpageLocale(for context: WKWebExtensionContext) async throws -> Locale? {
        return Locale.current
    }

    func loadURL(_ url: URL, for context: WKWebExtensionContext) async throws {
        load(url: url)
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
        delegate?.tabDidRequestActivate(self)
    }

    func isSelected(for context: WKWebExtensionContext) -> Bool {
        guard let mainVC = delegate as? MainViewController else { return false }
        return mainVC.tabManager.current() === self
    }

    func setSelected(_ selected: Bool, for context: WKWebExtensionContext) async throws {
        if selected {
            try await activate(for: context)
        } else {
            throw WebExtensionTabError.notSupported
        }
    }

    func duplicate(using configuration: WKWebExtension.TabConfiguration, for context: WKWebExtensionContext) async throws -> (any WKWebExtensionTab)? {
        throw WebExtensionTabError.notSupported
    }

    func close(for context: WKWebExtensionContext) async throws {
        if let delegate = delegate {
            delegate.tabDidRequestClose(self)
        } else {
            dismiss()
        }
    }

    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool {
        return true
    }
}
