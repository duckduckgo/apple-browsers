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
import FeatureFlags_macOS
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class WebsitePermissionsViewModelTests: XCTestCase {
    private var permissionManager: PermissionManagerMock!
    private var featureFlagger: MockFeatureFlagger!

    override func setUp() {
        super.setUp()
        permissionManager = PermissionManagerMock()
        featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue: false])
    }

    override func tearDown() {
        permissionManager = nil
        featureFlagger = nil
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
            WebsitePermissionEntry(domain: "example.com", permissionType: .notification, decision: .allow, lastModified: nil),
            WebsitePermissionEntry(domain: "example.com", permissionType: .camera, decision: .deny, lastModified: nil),
            WebsitePermissionEntry(domain: "example.com", permissionType: .externalScheme(scheme: "mailto"), decision: .ask, lastModified: nil),
            WebsitePermissionEntry(domain: "example.com", permissionType: .externalScheme(scheme: "zoommtg"), decision: .allow, lastModified: nil),
            WebsitePermissionEntry(domain: "example.com", permissionType: .autoplayPolicy, decision: .allow, lastModified: nil),
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

    // MARK: - Recents

    private func makeRecentsModel(_ entries: [WebsitePermissionEntry],
                                  permissionManager: PermissionManagerMock) -> WebsitePermissionsViewModel {
        permissionManager.setPersistedPermissions(entries)
        let model = WebsitePermissionsViewModel(permissionManager: permissionManager, featureFlagger: featureFlagger)
        waitForViewStateUpdate(model) {
            model.send(action: .onAppear)
        }
        return model
    }

    func testWhenNoPermissionHasATimestampThenRecentsIsEmpty() {
        let permissionManager = PermissionManagerMock()
        permissionManager.setPersistedPermissions([
            WebsitePermissionEntry(domain: "example.com", permissionType: .camera, decision: .allow, lastModified: nil),
        ])
        let model = WebsitePermissionsViewModel(permissionManager: permissionManager, featureFlagger: featureFlagger)

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

        let model = makeRecentsModel(entries, permissionManager: PermissionManagerMock())

        XCTAssertEqual(model.viewState.recents.map(\.domain), ["newest.com", "second.com", "oldest.com"])
        XCTAssertTrue(model.viewState.hasRecents)
    }

    func testWhenPermissionIsAutoplayThenItIsExcludedFromRecents() {
        let entries = [
            WebsitePermissionEntry(domain: "autoplay.com", permissionType: .autoplayPolicy, decision: .allow, lastModified: Date()),
            WebsitePermissionEntry(domain: "camera.com", permissionType: .camera, decision: .allow,
                                   lastModified: Date(timeIntervalSinceNow: -10)),
        ]

        let model = makeRecentsModel(entries, permissionManager: PermissionManagerMock())

        XCTAssertEqual(model.viewState.recents.map(\.domain), ["camera.com"])
    }

    func testWhenRecentIsPopupsThenDeniedDecisionIsNotOffered() {
        let entries = [
            WebsitePermissionEntry(domain: "popups.com", permissionType: .popups, decision: .allow, lastModified: Date()),
        ]

        let model = makeRecentsModel(entries, permissionManager: PermissionManagerMock())

        XCTAssertEqual(model.viewState.recents.first?.availableDecisions, [.ask, .allow])
    }

    func testWhenRecentIsPopupsAlreadyDeniedThenDeniedDecisionStaysSelectable() {
        let entries = [
            WebsitePermissionEntry(domain: "popups.com", permissionType: .popups, decision: .deny, lastModified: Date()),
        ]

        let model = makeRecentsModel(entries, permissionManager: PermissionManagerMock())

        XCTAssertEqual(model.viewState.recents.first?.availableDecisions, [.deny, .ask, .allow])
    }

    func testWhenRecentDecisionIsChangedThenPermissionManagerIsUpdated() {
        let entries = [
            WebsitePermissionEntry(domain: "example.com", permissionType: .camera, decision: .allow, lastModified: Date()),
        ]
        let permissionManager = PermissionManagerMock()
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
        let permissionManager = PermissionManagerMock()
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
        let permissionManager = PermissionManagerMock()
        let model = makeRecentsModel(entries, permissionManager: permissionManager)
        guard let row = model.viewState.recents.first else {
            return XCTFail("Expected a recent row")
        }

        model.send(action: .removeRecent(row))

        XCTAssertFalse(permissionManager.hasPermissionPersisted(forDomain: "example.com", permissionType: .camera))
    }

    func testWhenRecentIsExternalSchemeThenTitleUsesTheOpenAppFormat() {
        let entries = [
            WebsitePermissionEntry(domain: "example.com", permissionType: .externalScheme(scheme: "mailto"),
                                   decision: .allow, lastModified: Date()),
        ]

        let model = makeRecentsModel(entries, permissionManager: PermissionManagerMock())

        guard let title = model.viewState.recents.first?.permissionTitle else {
            return XCTFail("Expected a recent row")
        }
        XCTAssertTrue(title.hasPrefix("Open "), "Expected the Open “app” format, got \(title)")
    }

    func testWhenRecentsShareATimestampThenOrderIsStable() {
        let timestamp = Date()
        let entries = [
            WebsitePermissionEntry(domain: "b.com", permissionType: .camera, decision: .allow, lastModified: timestamp),
            WebsitePermissionEntry(domain: "a.com", permissionType: .microphone, decision: .allow, lastModified: timestamp),
            WebsitePermissionEntry(domain: "a.com", permissionType: .camera, decision: .allow, lastModified: timestamp),
        ]

        let model = makeRecentsModel(entries, permissionManager: PermissionManagerMock())

        XCTAssertEqual(model.viewState.recents.map(\.id), ["a.com|camera", "a.com|microphone", "b.com|camera"])
    }

    // MARK: - Duck.ai Native Voice Permissions

    func testWhenNativeVoiceFlowChangesThenDuckAiMicrophoneVisibilityUpdates() {
        let timestamp = Date()
        let entries = [
            WebsitePermissionEntry(domain: "duck.ai", permissionType: .microphone, decision: .deny, lastModified: timestamp),
        ]
        let model = makeRecentsModel(entries, permissionManager: permissionManager)
        let originalState = model.viewState
        XCTAssertEqual(originalState.recents.first?.decision, .deny)
        XCTAssertEqual(originalState.rows.first { $0.category == .microphone }?.count, 1)

        featureFlagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = true
        waitForViewStateUpdate(model) {
            featureFlagger.triggerUpdate()
        }

        XCTAssertFalse(model.viewState.hasRecents)
        XCTAssertEqual(model.viewState.rows.first { $0.category == .microphone }?.count, 0)
        XCTAssertEqual(permissionManager.persistedDecision(forDomain: "duck.ai", permissionType: .microphone), .deny)

        featureFlagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = false
        waitForViewStateUpdate(model) {
            featureFlagger.triggerUpdate()
        }

        XCTAssertEqual(model.viewState, originalState)
        XCTAssertEqual(permissionManager.persistedDecision(forDomain: "duck.ai", permissionType: .microphone), .deny)
        XCTAssertEqual(permissionManager.savedLastModified["duck.ai"]?[.microphone], timestamp)
        XCTAssertTrue(permissionManager.setPermissionCalls.isEmpty)
    }

    // MARK: - Table

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
        return WebsitePermissionsViewModel(permissionManager: permissionManager, featureFlagger: featureFlagger)
    }

    private func waitForViewStateUpdate(_ model: WebsitePermissionsViewModel, action: () -> Void) {
        let expectation = expectation(description: "Permissions updated")
        let cancellable = model.$viewState
            .dropFirst()
            .prefix(1)
            .sink { _ in expectation.fulfill() }

        action()
        wait(for: [expectation], timeout: 1)
        withExtendedLifetime(cancellable) {}
    }
}
