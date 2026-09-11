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

    func testWhenDetailIsCreatedWithInitialStateThenItUsesTheInitialStateCategory() {
        let model = WebsitePermissionDetailViewModel(
            initialState: WebsitePermissionDetailViewState(category: .camera),
            permissionManager: permissionManager,
            featureFlagger: featureFlagger
        )

        XCTAssertEqual(model.viewState.category, .camera)
        XCTAssertTrue(model.viewState.isEmpty)
    }

    func testWhenDetailIsCreatedWithPopulatedInitialStateThenItIsPrepopulated() {
        let model = WebsitePermissionDetailViewModel(
            initialState: WebsitePermissionDetailViewState(
                category: .camera,
                entries: [
                    WebsitePermissionEntry(domain: "example.com", permissionType: .camera, decision: .allow, lastModified: nil),
                ],
                featureFlagger: featureFlagger
            ),
            permissionManager: permissionManager,
            featureFlagger: featureFlagger
        )

        XCTAssertEqual(model.viewState.sites.map(\.domain), ["example.com"])
        XCTAssertEqual(model.viewState.visibleSites.map(\.domain), ["example.com"])
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

        for query in ["", " \n\t "] {
            sut.send(action: .setSearchQuery(query))
            XCTAssertEqual(sut.viewState.visibleSites, sut.viewState.sites)
        }
    }

    func testWhenPermissionsUpdateThenDetailPreservesItsSearchQuery() {
        let sut = makeSUT(
            category: .notifications,
            entries: [
                WebsitePermissionEntry(domain: "example.com", permissionType: .notification, decision: .allow, lastModified: nil),
                WebsitePermissionEntry(domain: "unrelated.com", permissionType: .notification, decision: .allow, lastModified: nil),
            ]
        )
        sut.send(action: .setSearchQuery("example"))

        waitForDetailStateUpdate(sut) {
            permissionManager.setPermission(.allow, forDomain: "another.example", permissionType: .notification)
        }

        XCTAssertEqual(sut.viewState.searchQuery, "example")
        XCTAssertEqual(sut.viewState.visibleSites.map(\.domain), ["another.example", "example.com"])
    }

    func testWhenSearchingExternalAppsThenOnlyMatchingRowsAreVisible() {
        let sut = makeExternalAppsSUT()
        let cases: [(query: String, expectedIDs: [String])] = [
            ("  TASK MANAGER  ", ["example.com|external_asanadesktop", "example.com|external_asanadesktoptest", "other.example|external_asanadesktop"]),
            ("asanadesktoptest", ["example.com|external_asanadesktoptest"]),
            ("  ASANADESKTOPTEST://  ", ["example.com|external_asanadesktoptest"]),
            ("Open", []),
        ]

        for (query, expectedIDs) in cases {
            sut.send(action: .setSearchQuery(query))

            XCTAssertEqual(sut.viewState.visibleSites.map(\.id), expectedIDs, query)
        }
    }

    func testWhenInitialStateHasASearchQueryThenVisibleSitesAreFilteredBeforeAppearing() {
        let sut = makeExternalAppsSUT(searchQuery: "asanadesktoptest://")

        XCTAssertEqual(sut.viewState.visibleSites.map(\.id), ["example.com|external_asanadesktoptest"])
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

    func testWhenExternalAppsShareADomainThenTheyAreGroupedUnderASingleDomainHeader() {
        let sut = makeSUT(
            category: .externalApps,
            entries: [
                WebsitePermissionEntry(domain: "discord.com", permissionType: .externalScheme(scheme: "zoommtg"), decision: .deny, lastModified: nil),
                WebsitePermissionEntry(domain: "discord.com", permissionType: .externalScheme(scheme: "mailto"), decision: .allow, lastModified: nil),
                WebsitePermissionEntry(domain: "facebook.com", permissionType: .externalScheme(scheme: "mailto"), decision: .allow, lastModified: nil),
            ]
        )

        XCTAssertEqual(sut.viewState.visibleGroups.map(\.domain), ["discord.com", "facebook.com"])
        XCTAssertEqual(sut.viewState.visibleGroups.map { $0.rows.count }, [2, 1])
        XCTAssertEqual(sut.viewState.visibleGroups.first?.rows.map(\.id), ["discord.com|external_mailto", "discord.com|external_zoommtg"])
    }

    func testWhenExternalAppsAreGroupedThenEveryGroupShowsADomainHeader() {
        let sut = makeSUT(
            category: .externalApps,
            entries: [
                WebsitePermissionEntry(domain: "discord.com", permissionType: .externalScheme(scheme: "zoommtg"), decision: .deny, lastModified: nil),
                WebsitePermissionEntry(domain: "discord.com", permissionType: .externalScheme(scheme: "mailto"), decision: .allow, lastModified: nil),
                WebsitePermissionEntry(domain: "facebook.com", permissionType: .externalScheme(scheme: "mailto"), decision: .allow, lastModified: nil),
            ]
        )

        XCTAssertEqual(sut.viewState.visibleGroups.map(\.showsDomainHeader), [true, true])
    }

    func testWhenACategoryStoresOnePermissionPerDomainThenGroupsAreShownInline() {
        let sut = makeSUT(
            category: .camera,
            entries: [
                WebsitePermissionEntry(domain: "alpha.com", permissionType: .camera, decision: .allow, lastModified: nil),
                WebsitePermissionEntry(domain: "zebra.com", permissionType: .camera, decision: .ask, lastModified: nil),
            ]
        )

        XCTAssertEqual(sut.viewState.visibleGroups.map(\.domain), ["alpha.com", "zebra.com"])
        XCTAssertEqual(sut.viewState.visibleGroups.map(\.showsDomainHeader), [false, false])
    }

    func testWhenARowHasNoPermissionTitleThenItsSubRowTitleNamesThePermission() {
        let sut = makeSUT(
            category: .camera,
            entries: [
                WebsitePermissionEntry(domain: "alpha.com", permissionType: .camera, decision: .allow, lastModified: nil),
            ]
        )

        XCTAssertEqual(sut.viewState.visibleGroups.first?.rows.first?.subRowTitle, UserText.permissionCamera)
    }

    func testWhenSearchingThenOnlyMatchingDomainsAreGrouped() {
        let sut = makeSUT(
            category: .externalApps,
            entries: [
                WebsitePermissionEntry(domain: "discord.com", permissionType: .externalScheme(scheme: "zoommtg"), decision: .deny, lastModified: nil),
                WebsitePermissionEntry(domain: "discord.com", permissionType: .externalScheme(scheme: "mailto"), decision: .allow, lastModified: nil),
                WebsitePermissionEntry(domain: "facebook.com", permissionType: .externalScheme(scheme: "mailto"), decision: .allow, lastModified: nil),
            ]
        )

        sut.send(action: .setSearchQuery("discord"))

        XCTAssertEqual(sut.viewState.visibleGroups.map(\.domain), ["discord.com"])
        XCTAssertEqual(sut.viewState.visibleGroups.first?.rows.count, 2)
    }

    private func makeExternalAppsSUT(searchQuery: String = "") -> WebsitePermissionDetailViewModel {
        let sites = [
            ("example.com", "asanadesktop", "Tâsk Manager"),
            ("example.com", "asanadesktoptest", "Tâsk Manager"),
            ("example.com", "orbitdesk", "Orbit"),
            ("other.example", "asanadesktop", "Tâsk Manager"),
        ].map { domain, scheme, appName in
            WebsitePermissionDetailViewState.SiteRow(
                domain: domain,
                permissionType: .externalScheme(scheme: scheme),
                decision: .allow,
                externalAppName: appName,
                availableDecisions: [.ask, .allow, .deny]
            )
        }
        return WebsitePermissionDetailViewModel(
            initialState: .init(category: .externalApps, searchQuery: searchQuery, sites: sites),
            permissionManager: permissionManager,
            featureFlagger: featureFlagger
        )
    }

    private func makeSUT(
        category: WebsitePermissionCategory,
        entries: [WebsitePermissionEntry]
    ) -> WebsitePermissionDetailViewModel {
        permissionManager.setPersistedPermissions(entries)
        let model = WebsitePermissionDetailViewModel(
            initialState: WebsitePermissionDetailViewState(
                category: category,
                entries: entries,
                featureFlagger: featureFlagger
            ),
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
