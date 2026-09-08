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
    private var permissionManager: PermissionManagerMock!

    override func setUp() {
        super.setUp()
        permissionManager = PermissionManagerMock()
    }

    override func tearDown() {
        permissionManager = nil
        super.tearDown()
    }

    func testWhenThereAreNoPersistedPermissionsThenAllRowsHaveZeroCount() {
        let sut = createSUT()
        let expectation = expectation(description: "Permission rows published")
        var receivedRows: [WebsitePermissionsViewState.Row] = []

        let cancellable = sut.$viewState
            .dropFirst()
            .prefix(1)
            .sink { state in
                receivedRows = state.rows
                expectation.fulfill()
            }
        defer { cancellable.cancel() }

        sut.send(action: .onAppear)
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(receivedRows.map(\.category), [
            .notifications,
            .location,
            .camera,
            .microphone,
            .externalApps,
            .popups,
        ])
        XCTAssertTrue(receivedRows.allSatisfy { $0.count == 0 })
    }

    func testWhenBuildingRowsThenPermissionsAreGroupedByCategoryAndAutoplayIsExcluded() {
        let entries = [
            WebsitePermissionEntry(domain: "example.com", permissionType: .notification, decision: .allow),
            WebsitePermissionEntry(domain: "example.com", permissionType: .camera, decision: .deny),
            WebsitePermissionEntry(domain: "example.com", permissionType: .externalScheme(scheme: "mailto"), decision: .ask),
            WebsitePermissionEntry(domain: "example.com", permissionType: .externalScheme(scheme: "zoommtg"), decision: .allow),
            WebsitePermissionEntry(domain: "example.com", permissionType: .autoplayPolicy, decision: .allow),
        ]
        let sut = createSUT(entries: entries)
        let expectation = expectation(description: "Initial permissions loaded")
        let cancellable = sut.$viewState
            .map(\.rows)
            .first { $0.first(where: { $0.category == .externalApps })?.count == 2 }
            .sink { _ in expectation.fulfill() }

        sut.send(action: .onAppear)
        wait(for: [expectation], timeout: 1)
        withExtendedLifetime(cancellable) {}

        let counts = Dictionary(uniqueKeysWithValues: sut.viewState.rows.map { ($0.category, $0.count) })
        XCTAssertEqual(counts[.notifications], 1)
        XCTAssertEqual(counts[.location], 0)
        XCTAssertEqual(counts[.camera], 1)
        XCTAssertEqual(counts[.microphone], 0)
        XCTAssertEqual(counts[.externalApps], 2)
        XCTAssertEqual(counts[.popups], 0)

        let loadedRows = sut.viewState.rows

        sut.send(action: .onAppear)

        XCTAssertEqual(sut.viewState.rows, loadedRows)
    }

    func testWhenPermissionSnapshotChangesThenRowsAreUpdated() {
        let sut = createSUT()
        let expectation = expectation(description: "Rows updated")
        var cancellable: AnyCancellable?
        cancellable = sut.$viewState
            .map(\.rows)
            .first { rows in
                rows.first(where: { $0.category == .microphone })?.count == 1
            }
            .sink { _ in
                expectation.fulfill()
            }
        sut.send(action: .onAppear)

        permissionManager.setPermission(.allow, forDomain: "example.com", permissionType: .microphone)

        wait(for: [expectation], timeout: 1)
        withExtendedLifetime(cancellable) {}
    }

    private func createSUT(entries: [WebsitePermissionEntry] = []) -> WebsitePermissionsViewModel {
        for entry in entries {
            permissionManager.setPermission(entry.decision, forDomain: entry.domain, permissionType: entry.permissionType)
        }
        return WebsitePermissionsViewModel(permissionManager: permissionManager)
    }
}
