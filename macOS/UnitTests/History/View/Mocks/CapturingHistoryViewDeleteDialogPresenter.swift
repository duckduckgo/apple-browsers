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

@testable import DuckDuckGo_Privacy_Browser

final class CapturingHistoryViewDeleteDialogPresenter: HistoryViewDialogPresenting {

    var multipleTabsDialogResponse: OpenMultipleTabsWarningDialogModel.Response = .cancel
    var showMultipleTabsDialogCalls: [Int] = []

    var deleteDialogResponse: HistoryViewDeleteDialogModel.Response = .noAction
    var showDeleteDialogCalls: [ShowDialogCall] = []

    struct ShowDialogCall: Equatable {
        let itemsCount: Int
        let deleteMode: HistoryViewDeleteDialogModel.DeleteMode

        init(_ itemsCount: Int, _ deleteMode: HistoryViewDeleteDialogModel.DeleteMode) {
            self.itemsCount = itemsCount
            self.deleteMode = deleteMode
        }
    }

    func showDeleteDialog(for itemsCount: Int, deleteMode: DuckDuckGo_Privacy_Browser.HistoryViewDeleteDialogModel.DeleteMode, in window: NSWindow?) async -> DuckDuckGo_Privacy_Browser.HistoryViewDeleteDialogModel.Response {
        showDeleteDialogCalls.append(.init(itemsCount, deleteMode))
        return deleteDialogResponse
    }

    func showMultipleTabsDialog(for itemsCount: Int, in window: NSWindow?) async -> DuckDuckGo_Privacy_Browser.OpenMultipleTabsWarningDialogModel.Response {
        showMultipleTabsDialogCalls.append(itemsCount)
        return multipleTabsDialogResponse
    }
}
