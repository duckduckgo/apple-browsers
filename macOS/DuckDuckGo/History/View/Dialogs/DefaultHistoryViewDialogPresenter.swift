//
//  DefaultHistoryViewDialogPresenter.swift
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
import Foundation
import History
import SwiftUI
import HistoryView

protocol HistoryViewDialogPresenting: AnyObject {
    @MainActor
    func showMultipleTabsDialog(for itemsCount: Int, in window: NSWindow?) async -> OpenMultipleTabsWarningDialogModel.Response

    @MainActor
    func showDeleteDialog(for visits: [Visit],
                          deleteMode: HistoryViewDeleteDialogModel.DeleteMode,
                          in window: NSWindow?,
                          scopeCookieDomains: Set<String>?) async -> HistoryViewDeleteDialogModel.Response
}

final class DefaultHistoryViewDialogPresenter: HistoryViewDialogPresenting {

    private let featureFlagger: FeatureFlagger
    private let fireCoordinator: FireCoordinator

    init(featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger,
         fireCoordinator: FireCoordinator = Application.appDelegate.fireCoordinator) {
        self.featureFlagger = featureFlagger
        self.fireCoordinator = fireCoordinator
    }

    @MainActor
    func showMultipleTabsDialog(for itemsCount: Int, in window: NSWindow?) async -> OpenMultipleTabsWarningDialogModel.Response {
        await withCheckedContinuation { continuation in
            let parentWindow = window ?? Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.window
            let model = OpenMultipleTabsWarningDialogModel(count: itemsCount)
            let dialog = OpenMultipleTabsWarningDialog(model: model)
            dialog.show(in: parentWindow) {
                continuation.resume(returning: model.response)
            }
        }
    }

    @MainActor
    func showDeleteDialog(for visits: [Visit],
                          deleteMode: HistoryViewDeleteDialogModel.DeleteMode,
                          in window: NSWindow?,
                          scopeCookieDomains: Set<String>? = nil) async -> HistoryViewDeleteDialogModel.Response {
        if featureFlagger.isFeatureOn(.fireDialog) {
            return await presentFireDialog(mode: deleteMode,
                                           visits: visits,
                                           in: window,
                                           scopeCookieDomains: scopeCookieDomains)
        }

        return await withCheckedContinuation { continuation in
            let parentWindow = window ?? Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.window
            let model = HistoryViewDeleteDialogModel(entriesCount: visits.count, mode: deleteMode)
            let dialog = HistoryViewDeleteDialog(model: model)
            dialog.show(in: parentWindow) {
                continuation.resume(returning: model.response ?? .noAction)
            }
        }
    }

    @MainActor
    private func presentFireDialog(mode: HistoryViewDeleteDialogModel.DeleteMode,
                                   visits: [Visit],
                                   in window: NSWindow?,
                                   scopeCookieDomains: Set<String>?) async -> HistoryViewDeleteDialogModel.Response {
        let window = window ?? Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.window
        var mainWindowController: MainWindowController? {
            guard let mainWindowController = window?.windowController as? MainWindowController else {
                assertionFailure("Unexpected window controller: \(window?.windowController?.description ?? "<nil>")")
                return nil
            }
            return mainWindowController
        }

        // Delegate to unified FireCoordinator API; pass precomputed scope to avoid recomputation
        let mode: FireDialogViewModel.Mode = {
            switch mode {
            case .all: return .historyAll
            case .today: return .historyToday
            case .yesterday: return .historyYesterday
            case .sites(let domains): return .historySites(domains)
            case .date(let date): return .historyDate(date)
            case .older: return .historyOlder
            case .unspecified: return .historyVisits
            }
        }()

        let response = await fireCoordinator.presentFireDialog(mode: mode, in: window, scopeCookieDomains: scopeCookieDomains, scopeVisits: visits)
        switch response {
        case .noAction: return .noAction
        case .burn: return .burn
        }
    }

}
