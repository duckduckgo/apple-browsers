//
//  HistoryViewTabOpening.swift
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

import Foundation

/**
 * This protocol describes opening tabs from history view.
 *
 * User needs to be warned before opening multiple tabs (with a threshold
 * specified in `DefaultHistoryViewTabOpener.Const.numberOfTabsToOpenForDisplayingWarning`),
 * so this protocol abstracts the implementation of displaying a dialog if needed
 * and, if the dialog was accepted, proceeding with opening tabs.
 */
protocol HistoryViewTabOpening: AnyObject {
    var dialogPresenter: HistoryViewDialogPresenting? { get set }

    @MainActor func open(_ url: URL) async
    @MainActor func openInNewTab(_ urls: [URL]) async
    @MainActor func openInNewWindow(_ urls: [URL]) async
    @MainActor func openInNewFireWindow(_ urls: [URL]) async
}

/**
 * This protocol is used by `DefaultHistoryViewTabOpener` to abstract
 * actual opening tabs and remove the dependency on `WindowControllersManager`.
 */
@MainActor
protocol URLOpening: AnyObject {
    func open(_ url: URL)
    func openInNewTab(_ urls: [URL])
    func openInNewWindow(_ urls: [URL])
    func openInNewFireWindow(_ urls: [URL])
}

final class DefaultHistoryViewTabOpener: HistoryViewTabOpening {

    enum Const {
        static let numberOfTabsToOpenForDisplayingWarning: Int = 20
    }

    weak var dialogPresenter: HistoryViewDialogPresenting?
    let urlOpener: () async -> URLOpening

    init(urlOpener: (() async -> URLOpening)? = nil) {
        self.urlOpener = urlOpener ?? { await WindowControllersManager.shared }
    }

    @MainActor func open(_ url: URL) async {
        await urlOpener().open(url)
    }

    @MainActor func openInNewTab(_ urls: [URL]) async {
        guard await confirmOpeningMultipleTabsIfNeeded(count: urls.count) else {
            return
        }
        await urlOpener().openInNewTab(urls)
    }

    @MainActor func openInNewWindow(_ urls: [URL]) async {
        guard await confirmOpeningMultipleTabsIfNeeded(count: urls.count) else {
            return
        }
        await urlOpener().openInNewWindow(urls)
    }

    @MainActor func openInNewFireWindow(_ urls: [URL]) async {
        guard await confirmOpeningMultipleTabsIfNeeded(count: urls.count) else {
            return
        }
        await urlOpener().openInNewFireWindow(urls)
    }

    // MARK: - Private

    private func confirmOpeningMultipleTabsIfNeeded(count: Int) async -> Bool {
        guard count >= Const.numberOfTabsToOpenForDisplayingWarning else {
            return true
        }
        let response = await dialogPresenter?.showMultipleTabsDialog(for: count)
        return response == .open
    }
}
