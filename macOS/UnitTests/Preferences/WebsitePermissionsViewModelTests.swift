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
        let rows = WebsitePermissionsViewModel.makeRows(from: [])

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
            WebsitePermissionEntry(domain: "example.com", permissionType: .notification, decision: .allow),
            WebsitePermissionEntry(domain: "example.com", permissionType: .camera, decision: .deny),
            WebsitePermissionEntry(domain: "example.com", permissionType: .externalScheme(scheme: "mailto"), decision: .ask),
            WebsitePermissionEntry(domain: "example.com", permissionType: .externalScheme(scheme: "zoommtg"), decision: .allow),
            WebsitePermissionEntry(domain: "example.com", permissionType: .autoplayPolicy, decision: .allow),
        ]

        let counts = Dictionary(uniqueKeysWithValues: WebsitePermissionsViewModel.makeRows(from: entries).map { ($0.category, $0.count) })

        XCTAssertEqual(counts[.notifications], 1)
        XCTAssertEqual(counts[.location], 0)
        XCTAssertEqual(counts[.camera], 1)
        XCTAssertEqual(counts[.microphone], 0)
        XCTAssertEqual(counts[.externalApps], 2)
        XCTAssertEqual(counts[.popups], 0)
    }

    func testWhenPermissionSnapshotChangesThenRowsAreUpdated() {
        let permissionManager = WebsitePermissionManagerMock()
        let model = WebsitePermissionsViewModel(permissionManager: permissionManager)
        let expectation = expectation(description: "Rows updated")
        var cancellable: AnyCancellable?
        cancellable = model.$rows
            .first { rows in
                rows.first(where: { $0.category == .microphone })?.count == 1
            }
            .sink { _ in
                expectation.fulfill()
            }

        permissionManager.send([
            WebsitePermissionEntry(domain: "example.com", permissionType: .microphone, decision: .allow),
        ])

        wait(for: [expectation], timeout: 1)
        withExtendedLifetime(cancellable) {}
    }
}

private final class WebsitePermissionManagerMock: WebsitePermissionManaging {

    private let subject = CurrentValueSubject<[WebsitePermissionEntry], Never>([])

    var persistedPermissionsPublisher: AnyPublisher<[WebsitePermissionEntry], Never> {
        subject.eraseToAnyPublisher()
    }

    func send(_ entries: [WebsitePermissionEntry]) {
        subject.send(entries)
    }
}
