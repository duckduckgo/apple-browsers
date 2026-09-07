//
//  WebsitePermissionsViewModelTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import Combine
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class WebsitePermissionsViewModelTests: XCTestCase {
    func testWhenThereAreNoPersistedPermissionsThenAllRowsHaveZeroCount() {
        let model = WebsitePermissionsViewModel(permissionManager: WebsitePermissionManagerMock())
        model.send(action: .onAppear)
        let rows = model.viewState.rows

        XCTAssertEqual(rows.map(\.category), [
            .notifications,
            .location,
            .camera,
            .microphone,
            .externalApps,
            .popups,
        ])
        XCTAssertTrue(rows.allSatisfy { $0.count == 0 })
    }

    func testWhenBuildingRowsThenPermissionsAreGroupedByCategoryAndAutoplayIsExcluded() {
        let entries = [
            WebsitePermissionEntry(domain: "example.com", permissionType: .notification, decision: .allow, lastModified: nil),
            WebsitePermissionEntry(domain: "example.com", permissionType: .camera, decision: .deny, lastModified: nil),
            WebsitePermissionEntry(domain: "example.com", permissionType: .externalScheme(scheme: "mailto"), decision: .ask, lastModified: nil),
            WebsitePermissionEntry(domain: "example.com", permissionType: .externalScheme(scheme: "zoommtg"), decision: .allow, lastModified: nil),
            WebsitePermissionEntry(domain: "example.com", permissionType: .autoplayPolicy, decision: .allow, lastModified: nil),
        ]

        let permissionManager = WebsitePermissionManagerMock()
        permissionManager.send(entries)
        let model = WebsitePermissionsViewModel(permissionManager: permissionManager)
        let expectation = expectation(description: "Initial permissions loaded")
        let cancellable = model.$viewState
            .map(\.rows)
            .first { $0.first(where: { $0.category == .externalApps })?.count == 2 }
            .sink { _ in expectation.fulfill() }

        model.send(action: .onAppear)
        wait(for: [expectation], timeout: 1)
        withExtendedLifetime(cancellable) {}

        let counts = Dictionary(uniqueKeysWithValues: model.viewState.rows.map { ($0.category, $0.count) })

        XCTAssertEqual(counts[.notifications], 1)
        XCTAssertEqual(counts[.location], 0)
        XCTAssertEqual(counts[.camera], 1)
        XCTAssertEqual(counts[.microphone], 0)
        XCTAssertEqual(counts[.externalApps], 2)
        XCTAssertEqual(counts[.popups], 0)

        let loadedRows = model.viewState.rows
        model.send(action: .onAppear)
        XCTAssertEqual(model.viewState.rows, loadedRows)
    }

    // MARK: - Recents

    private func makeRecentsModel(_ entries: [WebsitePermissionEntry],
                                  permissionManager: WebsitePermissionManagerMock) -> WebsitePermissionsViewModel {
        permissionManager.send(entries)
        let model = WebsitePermissionsViewModel(permissionManager: permissionManager)
        let expectation = expectation(description: "Recents loaded")
        let cancellable = model.$viewState
            .map(\.recents)
            .first { !$0.isEmpty }
            .sink { _ in expectation.fulfill() }

        model.send(action: .onAppear)
        wait(for: [expectation], timeout: 1)
        withExtendedLifetime(cancellable) {}
        return model
    }

    func testWhenNoPermissionHasATimestampThenRecentsIsEmpty() {
        let permissionManager = WebsitePermissionManagerMock()
        permissionManager.send([
            WebsitePermissionEntry(domain: "example.com", permissionType: .camera, decision: .allow, lastModified: nil),
        ])
        let model = WebsitePermissionsViewModel(permissionManager: permissionManager)

        model.send(action: .onAppear)

        XCTAssertTrue(model.viewState.recents.isEmpty)
        XCTAssertFalse(model.viewState.hasRecents)
    }

    func testWhenPermissionsHaveTimestampsThenRecentsAreOrderedNewestFirstAndLimitedToThree() {
        let now = Date()
        let entries = [
            WebsitePermissionEntry(domain: "oldest.com", permissionType: .camera, decision: .allow,
                                   lastModified: now.addingTimeInterval(-400)),
            WebsitePermissionEntry(domain: "newest.com", permissionType: .notification, decision: .deny,
                                   lastModified: now),
            WebsitePermissionEntry(domain: "fourth.com", permissionType: .microphone, decision: .allow,
                                   lastModified: now.addingTimeInterval(-500)),
            WebsitePermissionEntry(domain: "second.com", permissionType: .geolocation, decision: .allow,
                                   lastModified: now.addingTimeInterval(-100)),
        ]

        let model = makeRecentsModel(entries, permissionManager: WebsitePermissionManagerMock())

        XCTAssertEqual(model.viewState.recents.map(\.domain), ["newest.com", "second.com", "oldest.com"])
        XCTAssertTrue(model.viewState.hasRecents)
    }

    func testWhenPermissionIsAutoplayThenItIsExcludedFromRecents() {
        let entries = [
            WebsitePermissionEntry(domain: "autoplay.com", permissionType: .autoplayPolicy, decision: .allow, lastModified: Date()),
            WebsitePermissionEntry(domain: "camera.com", permissionType: .camera, decision: .allow,
                                   lastModified: Date(timeIntervalSinceNow: -10)),
        ]

        let model = makeRecentsModel(entries, permissionManager: WebsitePermissionManagerMock())

        XCTAssertEqual(model.viewState.recents.map(\.domain), ["camera.com"])
    }

    func testWhenRecentIsPopupsThenDeniedDecisionIsNotOffered() {
        let entries = [
            WebsitePermissionEntry(domain: "popups.com", permissionType: .popups, decision: .allow, lastModified: Date()),
        ]

        let model = makeRecentsModel(entries, permissionManager: WebsitePermissionManagerMock())

        XCTAssertEqual(model.viewState.recents.first?.availableDecisions, [.ask, .allow])
    }

    func testWhenRecentIsPopupsAlreadyDeniedThenDeniedDecisionStaysSelectable() {
        let entries = [
            WebsitePermissionEntry(domain: "popups.com", permissionType: .popups, decision: .deny, lastModified: Date()),
        ]

        let model = makeRecentsModel(entries, permissionManager: WebsitePermissionManagerMock())

        XCTAssertEqual(model.viewState.recents.first?.availableDecisions, [.deny, .ask, .allow])
    }

    func testWhenRecentDecisionIsChangedThenPermissionManagerIsUpdated() {
        let entries = [
            WebsitePermissionEntry(domain: "example.com", permissionType: .camera, decision: .allow, lastModified: Date()),
        ]
        let permissionManager = WebsitePermissionManagerMock()
        let model = makeRecentsModel(entries, permissionManager: permissionManager)
        guard let row = model.viewState.recents.first else {
            return XCTFail("Expected a recent row")
        }

        model.send(action: .changeRecentDecision(row, .deny))

        XCTAssertEqual(permissionManager.setPermissionCalls.count, 1)
        XCTAssertEqual(permissionManager.setPermissionCalls.first?.domain, "example.com")
        XCTAssertEqual(permissionManager.setPermissionCalls.first?.decision, .deny)
        XCTAssertEqual(permissionManager.setPermissionCalls.first?.permissionType, .camera)
    }

    func testWhenRecentDecisionIsUnchangedThenPermissionManagerIsNotCalled() {
        let entries = [
            WebsitePermissionEntry(domain: "example.com", permissionType: .camera, decision: .allow, lastModified: Date()),
        ]
        let permissionManager = WebsitePermissionManagerMock()
        let model = makeRecentsModel(entries, permissionManager: permissionManager)
        guard let row = model.viewState.recents.first else {
            return XCTFail("Expected a recent row")
        }

        model.send(action: .changeRecentDecision(row, .allow))

        XCTAssertTrue(permissionManager.setPermissionCalls.isEmpty)
    }

    func testWhenRecentIsRemovedThenPermissionManagerRemovesIt() {
        let entries = [
            WebsitePermissionEntry(domain: "example.com", permissionType: .camera, decision: .allow, lastModified: Date()),
        ]
        let permissionManager = WebsitePermissionManagerMock()
        let model = makeRecentsModel(entries, permissionManager: permissionManager)
        guard let row = model.viewState.recents.first else {
            return XCTFail("Expected a recent row")
        }

        model.send(action: .removeRecent(row))

        XCTAssertEqual(permissionManager.removePermissionCalls.count, 1)
        XCTAssertEqual(permissionManager.removePermissionCalls.first?.domain, "example.com")
        XCTAssertEqual(permissionManager.removePermissionCalls.first?.permissionType, .camera)
    }

    func testWhenRecentIsExternalSchemeThenTitleUsesTheOpenAppFormat() {
        let entries = [
            WebsitePermissionEntry(domain: "example.com", permissionType: .externalScheme(scheme: "mailto"),
                                   decision: .allow, lastModified: Date()),
        ]

        let model = makeRecentsModel(entries, permissionManager: WebsitePermissionManagerMock())

        guard let title = model.viewState.recents.first?.permissionTitle else {
            return XCTFail("Expected a recent row")
        }
        XCTAssertTrue(title.hasPrefix("Open "), "Expected the Open “app” format, got \(title)")
    }

    func testWhenRecentsShareATimestampThenOrderIsStable() {
        let timestamp = Date()
        let entries = [
            WebsitePermissionEntry(domain: "b.com", permissionType: .camera, decision: .allow, lastModified: timestamp),
            WebsitePermissionEntry(domain: "a.com", permissionType: .camera, decision: .allow, lastModified: timestamp),
        ]

        let model = makeRecentsModel(entries, permissionManager: WebsitePermissionManagerMock())

        XCTAssertEqual(model.viewState.recents.map(\.domain), ["a.com", "b.com"])
    }

    // MARK: - Table

    func testWhenPermissionSnapshotChangesThenRowsAreUpdated() {
        let permissionManager = WebsitePermissionManagerMock()
        let model = WebsitePermissionsViewModel(permissionManager: permissionManager)
        let expectation = expectation(description: "Rows updated")
        var cancellable: AnyCancellable?
        cancellable = model.$viewState
            .map(\.rows)
            .first { rows in
                rows.first(where: { $0.category == .microphone })?.count == 1
            }
            .sink { _ in
                expectation.fulfill()
            }

        model.send(action: .onAppear)

        permissionManager.send([
            WebsitePermissionEntry(domain: "example.com", permissionType: .microphone, decision: .allow, lastModified: nil),
        ])

        wait(for: [expectation], timeout: 1)
        withExtendedLifetime(cancellable) {}
    }
}
