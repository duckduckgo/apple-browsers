//
//  CapturingActionsHandler.swift
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
import HistoryView

final class CapturingActionsHandler: ActionsHandling {

    func showDeleteDialog(for query: HistoryView.DataModel.HistoryQueryKind, in window: NSWindow?) async -> HistoryView.DataModel.DeleteDialogResponse {
        showDeleteDialogForQueryCalls.append(query)
        return await showDeleteDialogForQuery(query)
    }

    func showDeleteDialog(for entries: [String], in window: NSWindow?) async -> HistoryView.DataModel.DeleteDialogResponse {
        showDeleteDialogForEntriesCalls.append(entries)
        return await showDeleteDialogForEntries(entries)
    }

    func showContextMenu(for entries: [String], using presenter: any ContextMenuPresenting) async -> DataModel.DeleteDialogResponse {
        return .noAction
    }

    func open(_ url: URL, window: NSWindow?) async {
        openCalls.append(url)
    }

    var showDeleteDialogForQueryCalls: [DataModel.HistoryQueryKind] = []
    var showDeleteDialogForQuery: (DataModel.HistoryQueryKind) async -> DataModel.DeleteDialogResponse = { _ in .delete }

    var showDeleteDialogForEntriesCalls: [[String]] = []
    var showDeleteDialogForEntries: ([String]) async -> DataModel.DeleteDialogResponse = { _ in .delete }

    var openCalls: [URL] = []
}
