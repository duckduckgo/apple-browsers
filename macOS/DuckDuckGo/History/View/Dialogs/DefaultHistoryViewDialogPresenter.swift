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

import Foundation

protocol HistoryViewDialogPresenting: AnyObject {
    @MainActor
    func showMultipleTabsDialog(for itemsCount: Int, in window: NSWindow?) async -> OpenMultipleTabsWarningDialogModel.Response

    @MainActor
    func showDeleteDialog(for itemsCount: Int, deleteMode: HistoryViewDeleteDialogModel.DeleteMode, in window: NSWindow?) async -> HistoryViewDeleteDialogModel.Response
}

final class DefaultHistoryViewDialogPresenter: HistoryViewDialogPresenting {

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
    func showDeleteDialog(for itemsCount: Int, deleteMode: HistoryViewDeleteDialogModel.DeleteMode, in window: NSWindow?) async -> HistoryViewDeleteDialogModel.Response {
        await withCheckedContinuation { continuation in
            let parentWindow = window ?? Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.window
            let model = HistoryViewDeleteDialogModel(entriesCount: itemsCount, mode: deleteMode)
            let dialog = HistoryViewDeleteDialog(model: model)
            dialog.show(in: parentWindow) {
                continuation.resume(returning: model.response)
            }
        }
    }
}
