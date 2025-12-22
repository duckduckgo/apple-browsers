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
import Foundation
import History
import SwiftUI
import HistoryView
import PixelKit
import PrivacyConfig

protocol HistoryViewDialogPresenting: AnyObject {
    @MainActor
    func showMultipleTabsDialog(for itemsCount: Int, in window: NSWindow?) async -> OpenMultipleTabsWarningDialogModel.Response

    @MainActor
    func showDeleteDialog(for query: DataModel.HistoryQueryKind, visits: [Visit], in window: NSWindow?, fromMainMenu: Bool) async -> HistoryViewDeleteDialogModel.Response
}
extension HistoryViewDialogPresenting {
    func showDeleteDialog(for query: DataModel.HistoryQueryKind, visits: [Visit], in window: NSWindow?) async -> HistoryViewDeleteDialogModel.Response {
        await showDeleteDialog(for: query, visits: visits, in: window, fromMainMenu: false)
    }
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
    func showDeleteDialog(for query: DataModel.HistoryQueryKind, visits: [Visit], in window: NSWindow?, fromMainMenu: Bool) async -> HistoryViewDeleteDialogModel.Response {
        if featureFlagger.isFeatureOn(.fireDialog) {
            return await presentFireDialog(for: query, visits: visits, in: window, fromMainMenu: fromMainMenu)
        }

        return await withCheckedContinuation { continuation in
            let parentWindow = window ?? Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.window
            let model = HistoryViewDeleteDialogModel(entriesCount: visits.count, mode: query.deleteMode)
            let dialog = HistoryViewDeleteDialog(model: model)
            dialog.show(in: parentWindow) {
                switch model.response {
                case .burn(includeChats: let burnChats) where burnChats,
                    .delete(includeChats: let burnChats) where burnChats:
                    PixelKit.fire(AIChatPixel.aiChatDeleteHistoryRequested, frequency: .dailyAndCount)
                default:
                    break
                }
                continuation.resume(returning: model.response ?? .noAction)
            }
        }
    }

    @MainActor
    private func presentFireDialog(for query: DataModel.HistoryQueryKind, visits: [Visit], in window: NSWindow?, fromMainMenu: Bool) async -> HistoryViewDeleteDialogModel.Response {
        assert(!fromMainMenu || query == .rangeFilter(.all))
        let response = await fireCoordinator.presentFireDialog(mode: fromMainMenu ? .mainMenuAll : .historyView(query: query), in: window, scopeVisits: visits)
        switch response {
        case .noAction: return .noAction
        case .burn(options: .some(let options)) where !options.includeHistory:
            return .noAction // don‘t delete history records from History View, burning is done by FireCoordinator
        case .burn(options: .some(let options)) where options.includeCookiesAndSiteData:
            return .burn(includeChats: options.includeChatHistory)
        case .burn(let options):
            return .delete(includeChats: options?.includeChatHistory ?? false)
        }
    }

}
