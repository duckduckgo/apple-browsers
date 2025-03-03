//
//  HistoryViewActionsHandlerTests.swift
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

import History
import HistoryView
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class CapturingHistoryViewDataProvider: DataProviding {
    var ranges: [DataModel.HistoryRange] {
        rangesCallCount += 1
        return _ranges
    }

    func refreshData() {
        resetCacheCallCount += 1
    }

    func visitsBatch(for query: DataModel.HistoryQueryKind, limit: Int, offset: Int) async -> DataModel.HistoryItemsBatch {
        visitsBatchCalls.append(.init(query: query, limit: limit, offset: offset))
        return await visitsBatch(query, limit, offset)
    }

    func countVisibleVisits(for range: DataModel.HistoryRange) async -> Int {
        countVisibleVisitsCalls.append(range)
        return await countVisibleVisits(range)
    }

    func deleteVisits(for range: DataModel.HistoryRange) async {
        deleteVisitsCalls.append(range)
    }

    func burnVisits(for range: DataModel.HistoryRange) async {
        burnVisitsCalls.append(range)
    }

    // swiftlint:disable:next identifier_name
    var _ranges: [DataModel.HistoryRange] = []
    var rangesCallCount: Int = 0
    var resetCacheCallCount: Int = 0

    var countVisibleVisitsCalls: [DataModel.HistoryRange] = []
    var countVisibleVisits: (DataModel.HistoryRange) async -> Int = { _ in return 0 }

    var deleteVisitsCalls: [DataModel.HistoryRange] = []
    var burnVisitsCalls: [DataModel.HistoryRange] = []

    var visitsBatchCalls: [VisitsBatchCall] = []
    var visitsBatch: (DataModel.HistoryQueryKind, Int, Int) async -> DataModel.HistoryItemsBatch = { _, _, _ in .init(finished: true, visits: []) }

    struct VisitsBatchCall: Equatable {
        let query: DataModel.HistoryQueryKind
        let limit: Int
        let offset: Int
    }
}

final class CapturingHistoryViewDeleteDialogPresenter: HistoryViewDeleteDialogPresenting {
    var response: HistoryViewDeleteDialogModel.Response = .noAction
    var showDialogCalls: [Int] = []

    func showDialog(for itemsCount: Int) async -> HistoryViewDeleteDialogModel.Response {
        showDialogCalls.append(itemsCount)
        return response
    }
}

final class HistoryViewActionsHandlerTests: XCTestCase {

    var actionsHandler: HistoryViewActionsHandler!
    var dataProvider: CapturingHistoryViewDataProvider!
    var dialogPresenter: CapturingHistoryViewDeleteDialogPresenter!

    override func setUp() async throws {
        dataProvider = CapturingHistoryViewDataProvider()
        dialogPresenter = CapturingHistoryViewDeleteDialogPresenter()
        actionsHandler = HistoryViewActionsHandler(dataProvider: dataProvider, deleteDialogPresenter: dialogPresenter)
    }

    // MARK: - showDeleteDialog

    func testWhenDataProviderIsNilThenShowDeleteDialogReturnsNoAction() async {
        dataProvider = nil
        let dialogResponse = await actionsHandler.showDeleteDialog(for: .all)
        XCTAssertEqual(dialogResponse, .noAction)
    }

    func testWhenDataProviderHasNoVisitsForRangeThenShowDeleteDialogReturnsNoAction() async {
        dataProvider.countVisibleVisits = { _ in return 0 }
        let dialogResponse = await actionsHandler.showDeleteDialog(for: .all)
        XCTAssertEqual(dataProvider.deleteVisitsCalls.count, 0)
        XCTAssertEqual(dataProvider.burnVisitsCalls.count, 0)
        XCTAssertEqual(dialogResponse, .noAction)
    }

    func testWhenDeleteDialogIsCancelledThenShowDeleteDialogReturnsNoAction() async {
        dataProvider.countVisibleVisits = { _ in return 100 }
        dialogPresenter.response = .noAction
        let dialogResponse = await actionsHandler.showDeleteDialog(for: .all)
        XCTAssertEqual(dataProvider.deleteVisitsCalls.count, 0)
        XCTAssertEqual(dataProvider.burnVisitsCalls.count, 0)
        XCTAssertEqual(dialogResponse, .noAction)
    }

    func testWhenDeleteDialogReturnsUnknownResponseThenShowDeleteDialogReturnsNoAction() async {
        // this scenario shouldn't happen in real life anyway but is included for completeness
        dataProvider.countVisibleVisits = { _ in return 100 }
        dialogPresenter.response = .unknown
        let dialogResponse = await actionsHandler.showDeleteDialog(for: .all)
        XCTAssertEqual(dataProvider.deleteVisitsCalls.count, 0)
        XCTAssertEqual(dataProvider.burnVisitsCalls.count, 0)
        XCTAssertEqual(dialogResponse, .noAction)
    }

    func testWhenDeleteDialogIsAcceptedWithBurningThenShowDeleteDialogPerformsBurningAndReturnsDeleteAction() async {
        // this scenario shouldn't happen in real life anyway but is included for completeness
        dataProvider.countVisibleVisits = { _ in return 100 }
        dialogPresenter.response = .burn
        let dialogResponse = await actionsHandler.showDeleteDialog(for: .all)
        XCTAssertEqual(dataProvider.deleteVisitsCalls.count, 0)
        XCTAssertEqual(dataProvider.burnVisitsCalls.count, 1)
        XCTAssertEqual(dialogResponse, .delete)
    }

    func testWhenDeleteDialogIsAcceptedWithoutBurningThenShowDeleteDialogPerformsDeletiongAndReturnsDeleteAction() async {
        // this scenario shouldn't happen in real life anyway but is included for completeness
        dataProvider.countVisibleVisits = { _ in return 100 }
        dialogPresenter.response = .delete
        let dialogResponse = await actionsHandler.showDeleteDialog(for: .all)
        XCTAssertEqual(dataProvider.deleteVisitsCalls.count, 1)
        XCTAssertEqual(dataProvider.burnVisitsCalls.count, 0)
        XCTAssertEqual(dialogResponse, .delete)
    }
}
