//
//  WebsitePermissionDetailViewModelTests.swift
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
final class WebsitePermissionDetailViewModelTests: XCTestCase {
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

    func testWhenDetailIsCreatedThenItRemainsLoadingUntilPermissionsArePublished() {
        let model = WebsitePermissionDetailViewModel(
            category: .camera,
            permissionManager: permissionManager,
            featureFlagger: featureFlagger
        )

        XCTAssertTrue(model.viewState.isLoading)

        waitForDetailStateUpdate(model) {
            model.send(action: .onAppear)
        }

        XCTAssertFalse(model.viewState.isLoading)
    }

    func testWhenBuildingDetailSitesThenOnlyCategoryEntriesAreIncludedAndSorted() {
        let sut = makeSUT(
            category: .camera,
            entries: [
                WebsitePermissionEntry(domain: "zebra.com", permissionType: .camera, decision: .allow, lastModified: nil),
                WebsitePermissionEntry(domain: "alpha.com", permissionType: .camera, decision: .ask, lastModified: nil),
                WebsitePermissionEntry(domain: "location.com", permissionType: .geolocation, decision: .allow, lastModified: nil),
            ]
        )

        XCTAssertEqual(sut.viewState.sites.map(\.domain), ["alpha.com", "zebra.com"])
    }

    func testWhenExternalAppsShareADomainThenRowsRemainDistinctAndOrderedByScheme() {
        let sut = makeSUT(
            category: .externalApps,
            entries: [
                WebsitePermissionEntry(domain: "example.com", permissionType: .externalScheme(scheme: "zoommtg"), decision: .allow, lastModified: nil),
                WebsitePermissionEntry(domain: "example.com", permissionType: .externalScheme(scheme: "mailto"), decision: .ask, lastModified: nil),
            ]
        )

        XCTAssertEqual(sut.viewState.sites.map(\.id), ["example.com|external_mailto", "example.com|external_zoommtg"])
        XCTAssertTrue(sut.viewState.sites.allSatisfy { $0.permissionTitle != nil })
    }

    func testWhenPopupIsPersistedAsDeniedThenDetailShowsAskAndRejectsDeny() throws {
        let sut = makeSUT(
            category: .popups,
            entries: [
                WebsitePermissionEntry(domain: "example.com", permissionType: .popups, decision: .deny, lastModified: nil),
            ]
        )

        let row = try XCTUnwrap(sut.viewState.sites.first)
        XCTAssertEqual(row.decision, .ask)
        XCTAssertEqual(row.availableDecisions, [.ask, .allow])

        sut.send(action: .changeDecision(rowID: row.id, decision: .deny))

        XCTAssertTrue(permissionManager.setPermissionCalls.isEmpty)
    }

    func testWhenSearchQueryChangesThenDetailFiltersMatchesAndReportsNoResults() {
        let sut = makeSUT(
            category: .notifications,
            entries: [
                WebsitePermissionEntry(domain: "café.example", permissionType: .notification, decision: .allow, lastModified: nil),
                WebsitePermissionEntry(domain: "other.example", permissionType: .notification, decision: .allow, lastModified: nil),
            ]
        )

        sut.send(action: .setSearchQuery("  CAFE  "))

        XCTAssertEqual(sut.viewState.visibleSites.map(\.domain), ["café.example"])
        XCTAssertFalse(sut.viewState.hasNoResults)

        sut.send(action: .setSearchQuery("missing"))

        XCTAssertTrue(sut.viewState.visibleSites.isEmpty)
        XCTAssertTrue(sut.viewState.hasNoResults)
    }

    func testWhenPermissionsUpdateThenDetailPreservesItsSearchQuery() {
        let sut = makeSUT(
            category: .notifications,
            entries: [
                WebsitePermissionEntry(domain: "example.com", permissionType: .notification, decision: .allow, lastModified: nil),
            ]
        )
        sut.send(action: .setSearchQuery("example"))

        waitForDetailStateUpdate(sut) {
            permissionManager.setPermission(.allow, forDomain: "another.example", permissionType: .notification)
        }

        XCTAssertEqual(sut.viewState.searchQuery, "example")
        XCTAssertEqual(sut.viewState.visibleSites.map(\.domain), ["another.example", "example.com"])
    }

    func testWhenDetailDecisionChangesThenPermissionManagerUpdatesTheCurrentRow() throws {
        let sut = makeSUT(
            category: .camera,
            entries: [
                WebsitePermissionEntry(domain: "example.com", permissionType: .camera, decision: .ask, lastModified: nil),
            ]
        )
        let row = try XCTUnwrap(sut.viewState.sites.first)

        waitForDetailStateUpdate(sut) {
            sut.send(action: .changeDecision(rowID: row.id, decision: .allow))
        }

        sut.send(action: .changeDecision(rowID: row.id, decision: .allow))

        XCTAssertEqual(permissionManager.persistedDecision(forDomain: "example.com", permissionType: .camera), .allow)
        XCTAssertEqual(permissionManager.setPermissionCalls.count, 1)
    }

    func testWhenDetailRowWasRemovedThenAStaleDecisionChangeDoesNotRecreateIt() throws {
        let sut = makeSUT(
            category: .camera,
            entries: [
                WebsitePermissionEntry(domain: "example.com", permissionType: .camera, decision: .ask, lastModified: nil),
            ]
        )
        let row = try XCTUnwrap(sut.viewState.sites.first)

        waitForDetailStateUpdate(sut) {
            sut.send(action: .remove(rowID: row.id))
        }
        sut.send(action: .changeDecision(rowID: row.id, decision: .allow))

        XCTAssertNil(permissionManager.persistedDecision(forDomain: "example.com", permissionType: .camera))
        XCTAssertTrue(permissionManager.setPermissionCalls.isEmpty)
    }

    func testWhenNativeVoiceFlowChangesThenDetailHidesAndRestoresDuckAiMicrophone() throws {
        let sut = makeSUT(
            category: .microphone,
            entries: [
                WebsitePermissionEntry(domain: "duck.ai", permissionType: .microphone, decision: .deny, lastModified: nil),
            ]
        )

        let row = try XCTUnwrap(sut.viewState.sites.first)
        featureFlagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = true
        sut.send(action: .changeDecision(rowID: row.id, decision: .allow))
        sut.send(action: .remove(rowID: row.id))
        XCTAssertTrue(permissionManager.setPermissionCalls.isEmpty)
        XCTAssertEqual(permissionManager.persistedDecision(forDomain: "duck.ai", permissionType: .microphone), .deny)

        waitForDetailStateUpdate(sut) {
            featureFlagger.triggerUpdate()
        }
        XCTAssertTrue(sut.viewState.isEmpty)

        featureFlagger.featuresStub[FeatureFlag.aiChatNativeVoicePermissionFlow.rawValue] = false
        waitForDetailStateUpdate(sut) {
            featureFlagger.triggerUpdate()
        }
        XCTAssertEqual(sut.viewState.sites.map(\.domain), ["duck.ai"])
    }

    private func makeSUT(
        category: WebsitePermissionCategory,
        entries: [WebsitePermissionEntry]
    ) -> WebsitePermissionDetailViewModel {
        permissionManager.setPersistedPermissions(entries)
        let model = WebsitePermissionDetailViewModel(
            category: category,
            permissionManager: permissionManager,
            featureFlagger: featureFlagger
        )
        waitForDetailStateUpdate(model) {
            model.send(action: .onAppear)
        }
        return model
    }

    private func waitForDetailStateUpdate(_ model: WebsitePermissionDetailViewModel, action: () -> Void) {
        let expectation = expectation(description: "Detail permissions updated")
        let cancellable = model.$viewState
            .dropFirst()
            .prefix(1)
            .sink { _ in expectation.fulfill() }

        action()
        wait(for: [expectation], timeout: 1)
        withExtendedLifetime(cancellable) {}
    }
}
