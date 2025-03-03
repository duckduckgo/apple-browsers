//
//  HistoryViewActionsHandler.swift
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

import HistoryView
import SwiftUIExtensions

final class HistoryViewActionsHandler: HistoryView.ActionsHandling {

    weak var dataProvider: HistoryView.DataProviding?
    let deleteDialogPresenter: HistoryViewDeleteDialogPresenting

    init(
        dataProvider: HistoryView.DataProviding,
        deleteDialogPresenter: HistoryViewDeleteDialogPresenting = DefaultHistoryViewDeleteDialogPresenter()
    ) {
        self.dataProvider = dataProvider
        self.deleteDialogPresenter = deleteDialogPresenter
    }

    func showDeleteDialog(for range: DataModel.HistoryRange) async -> DataModel.DeleteDialogResponse {
        guard let dataProvider else {
            return .noAction
        }

        let visitsCount = await dataProvider.countVisibleVisits(for: range)
        guard visitsCount > 0 else {
            return .noAction
        }

        switch await deleteDialogPresenter.showDialog(for: visitsCount) {
        case .burn:
            await dataProvider.burnVisits(for: range)
            return .delete
        case .delete:
            await dataProvider.deleteVisits(for: range)
            return .delete
        default:
            return .noAction
        }
    }

    @MainActor
    func open(_ url: URL) {
        guard let tabCollectionViewModel else {
            return
        }

        if NSApplication.shared.isCommandPressed && NSApplication.shared.isOptionPressed {
            WindowsManager.openNewWindow(with: url, source: .bookmark, isBurner: tabCollectionViewModel.isBurner)
        } else if NSApplication.shared.isCommandPressed && NSApplication.shared.isShiftPressed {
            tabCollectionViewModel.insertOrAppendNewTab(.contentFromURL(url, source: .bookmark), selected: true)
        } else if NSApplication.shared.isCommandPressed {
            tabCollectionViewModel.insertOrAppendNewTab(.contentFromURL(url, source: .bookmark), selected: false)
        } else {
            tabCollectionViewModel.selectedTabViewModel?.tab.setContent(.contentFromURL(url, source: .historyEntry))
        }
    }

    @MainActor
    private var tabCollectionViewModel: TabCollectionViewModel? {
        WindowControllersManager.shared.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel
    }
}
