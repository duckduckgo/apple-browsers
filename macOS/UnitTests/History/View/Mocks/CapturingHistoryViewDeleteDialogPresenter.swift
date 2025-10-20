//
//  CapturingHistoryViewDeleteDialogPresenter.swift
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
import History
import HistoryView

@testable import DuckDuckGo_Privacy_Browser

final class CapturingHistoryViewDeleteDialogPresenter: HistoryViewDialogPresenting {

    var multipleTabsDialogResponse: OpenMultipleTabsWarningDialogModel.Response = .cancel
    var showMultipleTabsDialogCalls: [Int] = []

    var deleteDialogResponse: HistoryViewDeleteDialogModel.Response = .noAction
    var showDeleteDialogCalls: [ShowDialogCall] = []

    struct ShowDialogCall: Equatable {
        let query: HistoryView.DataModel.HistoryQueryKind
        let visits: [History.Visit]

        init(_ query: HistoryView.DataModel.HistoryQueryKind, _ visits: [History.Visit], fromMainMenu: Bool = false) {
            self.query = query
            self.visits = visits
        }
    }

    func showDeleteDialog(for query: HistoryView.DataModel.HistoryQueryKind, visits: [History.Visit], in window: NSWindow?, fromMainMenu: Bool) async -> DuckDuckGo_Privacy_Browser.HistoryViewDeleteDialogModel.Response {
        showDeleteDialogCalls.append(.init(query, visits, fromMainMenu: fromMainMenu))
        return deleteDialogResponse
    }

    func showMultipleTabsDialog(for itemsCount: Int, in window: NSWindow?) async -> DuckDuckGo_Privacy_Browser.OpenMultipleTabsWarningDialogModel.Response {
        showMultipleTabsDialogCalls.append(itemsCount)
        return multipleTabsDialogResponse
    }
}
