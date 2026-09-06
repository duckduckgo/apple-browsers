//
//  BrowsingMenuBuilderTests.swift
//  DuckDuckGo
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

import AVFoundation
import Bookmarks
import BrowserServicesKitTestsUtils
import Core
import CoreLocation
@_spi(Testing) import Persistence
import PrivacyDashboard
@testable import SitePermissions
import UIKit
import WebKit
import XCTest
@testable import DuckDuckGo

final class BrowsingMenuBuilderTests: XCTestCase {

    func testNewTabPageMenuOmitsChatsWhenFallbackChatsEntryIsUnavailable() {
        let entryBuilder = MockBrowsingMenuEntryBuilder(chatsEntry: nil)
        let model = makeBuilder(entryBuilder: entryBuilder).buildMenu(
            context: .newTabPage,
            bookmarksInterface: MockMenuBookmarksInteractor(),
            mobileCustomization: makeMobileCustomization(),
            clearTabsAndData: {}
        )

        XCTAssertEqual(model?.sections.first?.items.map(\.name), [
            MockBrowsingMenuEntryBuilder.openBookmarksName,
            MockBrowsingMenuEntryBuilder.downloadsName
        ])
    }

    func testNewTabPageMenuPlacesFallbackChatsAfterBookmarksAndDownloads() {
        let entryBuilder = MockBrowsingMenuEntryBuilder(chatsEntry: .named(MockBrowsingMenuEntryBuilder.chatsName))
        let model = makeBuilder(entryBuilder: entryBuilder).buildMenu(
            context: .newTabPage,
            bookmarksInterface: MockMenuBookmarksInteractor(),
            mobileCustomization: makeMobileCustomization(),
            clearTabsAndData: {}
        )

        XCTAssertEqual(model?.sections.first?.items.map(\.name), [
            MockBrowsingMenuEntryBuilder.openBookmarksName,
            MockBrowsingMenuEntryBuilder.downloadsName,
            MockBrowsingMenuEntryBuilder.chatsName
        ])
    }

    func testWebsiteMenuPlacesFallbackChatsAfterBookmarksAndDownloads() {
        let entryBuilder = MockBrowsingMenuEntryBuilder(chatsEntry: .named(MockBrowsingMenuEntryBuilder.chatsName))
        let model = makeBuilder(entryBuilder: entryBuilder).buildMenu(
            context: .website,
            bookmarksInterface: MockMenuBookmarksInteractor(),
            mobileCustomization: makeMobileCustomization(),
            clearTabsAndData: {}
        )

        XCTAssertEqual(model?.sections.first?.items.map(\.name), [
            MockBrowsingMenuEntryBuilder.openBookmarksName,
            MockBrowsingMenuEntryBuilder.downloadsName,
            MockBrowsingMenuEntryBuilder.chatsName
        ])
    }

    func testWebsiteMenuPlacesSitePermissionsInItsOwnSectionBeforeBookmarksInBothLayouts() throws {
        for mergesActionsAndBookmarks in [false, true] {
            let entryBuilder = MockBrowsingMenuEntryBuilder(
                chatsEntry: nil,
                includesBookmarkEntries: true,
                sitePermissionsEntry: .named(MockBrowsingMenuEntryBuilder.sitePermissionsName)
            )
            let model = try XCTUnwrap(makeWebsiteMenu(
                entryBuilder: entryBuilder,
                mergesActionsAndBookmarks: mergesActionsAndBookmarks
            ))
            let sitePermissionsSectionIndex = try XCTUnwrap(model.sections.firstIndex {
                $0.items.contains { $0.name == MockBrowsingMenuEntryBuilder.sitePermissionsName }
            })
            let bookmarkSectionIndex = try XCTUnwrap(model.sections.firstIndex {
                $0.items.contains { $0.name == MockBrowsingMenuEntryBuilder.bookmarkName }
            })

            XCTAssertEqual(model.sections[sitePermissionsSectionIndex].items.map(\.name), [MockBrowsingMenuEntryBuilder.sitePermissionsName])
            XCTAssertEqual(bookmarkSectionIndex, sitePermissionsSectionIndex + 1)
        }
    }

    func testWebsiteMenuOmitsSitePermissionsInBothLayoutsWhenEntryIsUnavailable() throws {
        for mergesActionsAndBookmarks in [false, true] {
            let entryBuilder = MockBrowsingMenuEntryBuilder(
                chatsEntry: nil,
                includesBookmarkEntries: true,
                sitePermissionsEntry: nil
            )
            let model = try XCTUnwrap(makeWebsiteMenu(
                entryBuilder: entryBuilder,
                mergesActionsAndBookmarks: mergesActionsAndBookmarks
            ))

            XCTAssertFalse(model.sections.flatMap(\.items).contains { $0.name == MockBrowsingMenuEntryBuilder.sitePermissionsName })
        }
    }

    func testWebsiteMenuPreferredDetentTracksOpenBookmarksPosition() throws {
        let scenarios: [(
            sitePermissionsEntry: BrowsingMenuEntry?,
            includesYouTubeEntry: Bool,
            includesTabActions: Bool,
            mergesActionsAndBookmarks: Bool
        )] = [
            (nil, false, true, false),
            (.named(MockBrowsingMenuEntryBuilder.sitePermissionsName), false, true, true),
            (.named(MockBrowsingMenuEntryBuilder.sitePermissionsName), true, true, false),
            (nil, false, false, true)
        ]
        let expectedCounts = [7, 8, 9, 4]

        for (scenario, expectedCount) in zip(scenarios, expectedCounts) {
            let entryBuilder = MockBrowsingMenuEntryBuilder(
                chatsEntry: nil,
                includesBookmarkEntries: true,
                sitePermissionsEntry: scenario.sitePermissionsEntry,
                includesTabActions: scenario.includesTabActions,
                includesYouTubeEntry: scenario.includesYouTubeEntry
            )
            let model = try XCTUnwrap(makeWebsiteMenu(
                entryBuilder: entryBuilder,
                mergesActionsAndBookmarks: scenario.mergesActionsAndBookmarks
            ))
            let openBookmarksIndex = try XCTUnwrap(model.sections.flatMap(\.items).firstIndex { $0.tag == .openBookmarks })

            XCTAssertEqual(model.preferredDetentItemCount, expectedCount)
            XCTAssertEqual(model.preferredDetentItemCount, openBookmarksIndex + 1)
        }
    }

    @MainActor
    func testSitePermissionsEntryIsShownForStoredRecordInLegacyAndSheetMenus() {
        assertSitePermissionsEntry(isPresent: true, featureEnabled: true, storedDecision: .allow)
    }

    @MainActor
    func testSitePermissionsEntryIsShownForExplicitAskInLegacyAndSheetMenus() {
        assertSitePermissionsEntry(isPresent: true, featureEnabled: true, storedDecision: .ask)
    }

    @MainActor
    func testSitePermissionsEntryIsHiddenWithoutRecordInLegacyAndSheetMenus() {
        assertSitePermissionsEntry(isPresent: false, featureEnabled: true, storedDecision: nil)
    }

    @MainActor
    func testSitePermissionsEntryIsHiddenWithFlagOffInLegacyAndSheetMenus() {
        assertSitePermissionsEntry(isPresent: false, featureEnabled: false, storedDecision: .allow)
    }

    @MainActor
    func testSitePermissionsEntryIsShownForCurrentEphemeralSessionInLegacyAndSheetMenus() async {
        let sut = makeTabViewController(featureEnabled: true, storedDecision: nil)
        await grantCurrentSessionCameraPermission(on: sut)

        assertSitePermissionsEntry(isPresent: true, on: sut)
    }

    @MainActor
    func testRevokingMatchingSiteClearsCurrentSessionMenuEligibility() async {
        let sut = makeTabViewController(featureEnabled: true, storedDecision: nil)
        await grantCurrentSessionCameraPermission(on: sut)
        XCTAssertTrue(sut.isSitePermissionsManagementAvailable)

        let matchingSite = SitePermissionKey(committedURL: URL(string: "https://example.com")!)!
        sut.revokeSitePermissions([.camera], for: matchingSite)

        XCTAssertFalse(sut.isSitePermissionsManagementAvailable)
    }

    @MainActor
    func testRevokingNonmatchingSiteKeepsCurrentSessionMenuEligibility() async {
        let sut = makeTabViewController(featureEnabled: true, storedDecision: nil)
        await grantCurrentSessionCameraPermission(on: sut)
        XCTAssertTrue(sut.isSitePermissionsManagementAvailable)

        let nonmatchingSite = SitePermissionKey(committedURL: URL(string: "https://other.example")!)!
        sut.revokeSitePermissions([.camera], for: nonmatchingSite)

        XCTAssertTrue(sut.isSitePermissionsManagementAvailable)
    }

    @MainActor
    func testNormalManagementRevocationPropagatesToOtherMatchingTabs() async {
        let store = SitePermissionsStore(storage: InMemoryKeyValueStore().keyedStoring())
        var secondaryTab: TabViewController?
        let primaryTab = makeTabViewController(
            featureEnabled: true,
            storedDecision: nil,
            store: store,
            revokePermissionsInOtherTabs: { site, permissionTypes, _ in
                secondaryTab?.revokeSitePermissions(permissionTypes, for: site)
            }
        )
        secondaryTab = makeTabViewController(featureEnabled: true, storedDecision: nil, store: store)
        guard let secondaryTab else {
            XCTFail("Expected secondary tab")
            return
        }
        await grantCurrentSessionCameraPermission(on: primaryTab)
        await grantCurrentSessionCameraPermission(on: secondaryTab)
        let site = SitePermissionKey(committedURL: URL(string: "https://example.com")!)!

        primaryTab.revokeSitePermissionsFromManagement([.camera], for: site)

        XCTAssertFalse(primaryTab.isSitePermissionsManagementAvailable)
        XCTAssertFalse(secondaryTab.isSitePermissionsManagementAvailable)
    }

    @MainActor
    func testManagementPresenterRefusesFlagOffAndStaleCommittedSite() {
        let flagOff = makeTabViewController(featureEnabled: false, storedDecision: .allow)
        flagOff.presentSitePermissionsManagement()
        XCTAssertNil(flagOff.presentedViewController)

        let staleCommittedSite = makeTabViewController(featureEnabled: true, storedDecision: .allow)
        staleCommittedSite.webView(staleCommittedSite.webView, didStartProvisionalNavigation: nil)
        staleCommittedSite.presentSitePermissionsManagement()
        XCTAssertNil(staleCommittedSite.presentedViewController)
    }

    // MARK: - Privacy Protection toggle SERP gating

    func testToggleProtectionDomainIsNilOnSERP() {
        // On the SERP the Privacy Dashboard is unavailable, so the browsing-menu toggle must be hidden too.
        let privacyInfo = makePrivacyInfo(url: URL(string: "https://duckduckgo.com/?q=catfood&t=h_&ia=web")!)
        XCTAssertTrue(privacyInfo.url.isDuckDuckGoSearch)
        XCTAssertNil(TabViewController.privacyProtectionToggleDomain(for: privacyInfo))
    }

    func testToggleProtectionDomainIsResolvedForRegularSite() {
        let privacyInfo = makePrivacyInfo(url: URL(string: "https://example.com")!)
        XCTAssertEqual(TabViewController.privacyProtectionToggleDomain(for: privacyInfo), "example.com")
    }

    func testToggleProtectionDomainIsResolvedForDuckDuckGoHomepage() {
        // The DuckDuckGo homepage is not a SERP, so the toggle (like the shield/dashboard) stays available.
        let privacyInfo = makePrivacyInfo(url: URL(string: "https://duckduckgo.com")!)
        XCTAssertFalse(privacyInfo.url.isDuckDuckGoSearch)
        XCTAssertEqual(TabViewController.privacyProtectionToggleDomain(for: privacyInfo), "duckduckgo.com")
    }

    func testToggleProtectionDomainIsNilWithoutPrivacyInfo() {
        XCTAssertNil(TabViewController.privacyProtectionToggleDomain(for: nil))
    }

    private func makePrivacyInfo(url: URL) -> PrivacyInfo {
        PrivacyInfo(
            url: url,
            parentEntity: nil,
            protectionStatus: ProtectionStatus(unprotectedTemporary: false, enabledFeatures: [], allowlisted: false, denylisted: false)
        )
    }

    private func makeBuilder(entryBuilder: BrowsingMenuEntryBuilding) -> BrowsingMenuBuilder {
        BrowsingMenuBuilder(entryBuilder: entryBuilder)
    }

    private func makeWebsiteMenu(
        entryBuilder: BrowsingMenuEntryBuilding,
        mergesActionsAndBookmarks: Bool = false
    ) -> BrowsingMenuModel? {
        BrowsingMenuBuilder(
            entryBuilder: entryBuilder,
            options: .init(mergeActionsAndBookmarks: mergesActionsAndBookmarks)
        ).buildMenu(
            context: .website,
            bookmarksInterface: MockMenuBookmarksInteractor(),
            mobileCustomization: makeMobileCustomization(),
            clearTabsAndData: {}
        )
    }

    private func makeMobileCustomization() -> MobileCustomization {
        MobileCustomization(keyValueStore: MockKeyValueStore(), isPad: false)
    }

    @MainActor
    private func assertSitePermissionsEntry(
        isPresent: Bool,
        featureEnabled: Bool,
        storedDecision: SitePermissionDecision?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let sut = makeTabViewController(featureEnabled: featureEnabled, storedDecision: storedDecision)
        assertSitePermissionsEntry(isPresent: isPresent, on: sut, file: file, line: line)
    }

    @MainActor
    private func assertSitePermissionsEntry(
        isPresent: Bool,
        on sut: TabViewController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let bookmarksInterface = MockMenuBookmarksInteractor()
        let legacyEntries = sut.buildBrowsingMenu(
            with: bookmarksInterface,
            mobileCustomization: makeMobileCustomization(),
            clearTabsAndData: {}
        )
        let legacyNames = legacyEntries.compactMap(\.name)
        let sheetSections = sut.buildSheetBrowsingMenu(
            context: .website,
            with: bookmarksInterface,
            mobileCustomization: makeMobileCustomization(),
            browsingMenuSheetCapability: BrowsingMenuSheetDefaultCapability(),
            clearTabsAndData: {}
        )?.sections ?? []
        let sheetNames = sheetSections.flatMap(\.items).map(\.name)

        XCTAssertEqual(legacyNames.contains(UserText.sitePermissions), isPresent, file: file, line: line)
        XCTAssertEqual(sheetNames.contains(UserText.sitePermissions), isPresent, file: file, line: line)

        guard isPresent else { return }
        guard let legacySitePermissionsIndex = legacyNames.firstIndex(of: UserText.sitePermissions),
              let legacyBookmarkIndex = legacyNames.firstIndex(of: UserText.actionSaveBookmark),
              let sheetSitePermissionsIndex = sheetNames.firstIndex(of: UserText.sitePermissions),
              let sheetBookmarkIndex = sheetNames.firstIndex(of: UserText.actionSaveBookmark) else {
            XCTFail("Expected Site Permissions and Add Bookmark entries", file: file, line: line)
            return
        }
        XCTAssertLessThan(legacySitePermissionsIndex, legacyBookmarkIndex, file: file, line: line)
        XCTAssertLessThan(sheetSitePermissionsIndex, sheetBookmarkIndex, file: file, line: line)
        XCTAssertTrue(legacyEntries[legacySitePermissionsIndex + 1].isSeparator, file: file, line: line)
        XCTAssertEqual(sheetSections.first { section in
            section.items.contains { $0.name == UserText.sitePermissions }
        }?.items.map(\.name), [UserText.sitePermissions], file: file, line: line)
    }

    @MainActor
    private func makeTabViewController(
        featureEnabled: Bool,
        storedDecision: SitePermissionDecision?,
        store: SitePermissionsStore? = nil,
        revokePermissionsInOtherTabs: @escaping (SitePermissionKey, Set<SitePermissionType>, String) -> Void = { _, _, _ in }
    ) -> TabViewController {
        let url = URL(string: "https://example.com/path")!
        let store = store ?? SitePermissionsStore(storage: InMemoryKeyValueStore().keyedStoring())
        let site = SitePermissionKey(committedURL: url)!
        if storedDecision == .ask {
            store.resetDecision(for: .camera, at: site)
        } else if let storedDecision {
            store.setPersistentDecision(storedDecision, for: .camera, at: site)
        }

        let sut = TabViewController.fake(
            customWebView: { SitePermissionsMenuURLWebView(url: url, configuration: $0) },
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: featureEnabled ? [.sitePermissions] : []),
            link: Link(title: nil, url: url)
        )
        sut.sitePermissionsDependenciesProvider = {
            SitePermissionsDependencies(
                store: store,
                systemPermissionClient: SystemPermissionClient(
                    locationManager: CLLocationManager(),
                    locationServicesEnabled: { false },
                    avAuthorizationStatus: { _ in .authorized },
                    avRequestAccess: { _, completion in completion(true) },
                    notificationCenter: NotificationCenter()
                ),
                revokePermissionsInOtherTabs: revokePermissionsInOtherTabs
            )
        }
        sut.webView(sut.webView, didCommit: nil)
        return sut
    }

    @MainActor
    private func grantCurrentSessionCameraPermission(on sut: TabViewController,
                                                     file: StaticString = #filePath,
                                                     line: UInt = #line) async {
        let decisionExpectation = expectation(description: "Ephemeral camera permission granted")
        var decisions = [WKPermissionDecision]()
        sut.sitePermissionsPromptHandlerOverride = { _, completion in
            completion(.allowOnce)
        }
        let frameURL = URL(string: "https://example.com/frame")!
        let origin = MockWKSecurityOrigin.new(url: frameURL)
        let frame = WKFrameInfo.mock(
            isMainFrame: false,
            securityOrigin: origin,
            webView: sut.webView,
            request: URLRequest(url: frameURL)
        )
        let bridgeDecision = await sut.mediaCaptureUserScript(
            MediaCaptureUserScript(),
            requestPermissionFor: [.camera],
            requestID: UUID().uuidString.replacingOccurrences(of: "-", with: "") + ":1",
            in: frame,
            webView: sut.webView
        )
        XCTAssertEqual(bridgeDecision, .allow, file: file, line: line)

        sut.webView(sut.webView,
                    requestMediaCapturePermissionFor: origin,
                    initiatedByFrame: frame,
                    type: .camera,
                    decisionHandler: {
                        decisions.append($0)
                        decisionExpectation.fulfill()
                    })

        await fulfillment(of: [decisionExpectation], timeout: 1)
        XCTAssertEqual(decisions, [.grant], file: file, line: line)
    }
}

private final class MockBrowsingMenuEntryBuilder: BrowsingMenuEntryBuilding {

    static let chatsName = "Chats"
    static let bookmarkName = "Bookmark"
    static let downloadsName = "Downloads"
    static let openBookmarksName = "Bookmarks"
    static let sitePermissionsName = "Site Permissions"

    private let chatsEntry: BrowsingMenuEntry?
    private let includesBookmarkEntries: Bool
    private let sitePermissionsEntry: BrowsingMenuEntry?
    private let includesTabActions: Bool
    private let includesYouTubeEntry: Bool

    init(
        chatsEntry: BrowsingMenuEntry?,
        includesBookmarkEntries: Bool = false,
        sitePermissionsEntry: BrowsingMenuEntry? = nil,
        includesTabActions: Bool = false,
        includesYouTubeEntry: Bool = false
    ) {
        self.chatsEntry = chatsEntry
        self.includesBookmarkEntries = includesBookmarkEntries
        self.sitePermissionsEntry = sitePermissionsEntry
        self.includesTabActions = includesTabActions
        self.includesYouTubeEntry = includesYouTubeEntry
    }

    func makeShortcutsMenu() -> [BrowsingMenuEntry] { [] }
    func makeAITabMenu() -> [BrowsingMenuEntry] { [] }
    func makeAITabMenuHeaderContent() -> [BrowsingMenuEntry] { [] }
    func makeBrowsingMenu(with bookmarksInterface: MenuBookmarksInteracting,
                          mobileCustomization: MobileCustomization,
                          clearTabsAndData: @escaping () -> Void) -> [BrowsingMenuEntry] { [] }
    func makeBrowsingMenuHeaderContent() -> [BrowsingMenuEntry] { [] }
    func makeNewTabEntry() -> BrowsingMenuEntry { .named("New Tab") }
    func makeChatEntry() -> BrowsingMenuEntry? { nil }
    func makeDuckAiChatsEntry() -> BrowsingMenuEntry? { chatsEntry }
    func makeDuckAIMenuItems() -> [BrowsingMenuEntry] { [] }
    func makeSettingsEntry() -> BrowsingMenuEntry { .named("Settings") }
    func makeShareEntry() -> BrowsingMenuEntry { .named("Share") }
    func makeCopyLinkEntry() -> BrowsingMenuEntry? { nil }
    func makePrintEntry() -> BrowsingMenuEntry { .named("Print") }
    func makeDownloadsEntry() -> BrowsingMenuEntry { .named(Self.downloadsName) }
    func makeAutoFillEntry() -> BrowsingMenuEntry? { nil }
    func makeVPNEntry() -> BrowsingMenuEntry? { nil }
    func makeOpenBookmarksEntry() -> BrowsingMenuEntry { .named(Self.openBookmarksName) }
    func makeSitePermissionsEntry() -> BrowsingMenuEntry? { sitePermissionsEntry }
    func makeBookmarkEntries(with bookmarksInterface: MenuBookmarksInteracting) -> (bookmark: BrowsingMenuEntry, favorite: BrowsingMenuEntry)? {
        guard includesBookmarkEntries else { return nil }
        return (.named(Self.bookmarkName), .named("Favorite"))
    }
    func makeFindInPageEntry() -> BrowsingMenuEntry? { includesTabActions ? .named("Find in Page") : nil }
    func makeZoomEntry() -> BrowsingMenuEntry? { includesTabActions ? .named("Zoom") : nil }
    func makeDesktopSiteEntry() -> BrowsingMenuEntry? { includesTabActions ? .named("Desktop Site") : nil }
    func makeReloadEntry() -> BrowsingMenuEntry? { nil }
    func makeToggleProtectionEntry() -> BrowsingMenuEntry? { nil }
    func makeReportBrokenSiteEntry() -> BrowsingMenuEntry? { nil }
    func makeClearDataEntry(mobileCustomization: MobileCustomization, clearTabsAndData: @escaping () -> Void) -> BrowsingMenuEntry? { nil }
    func makeUseNewDuckAddressEntry() -> BrowsingMenuEntry? { nil }
    func makeKeepSignInEntry() -> BrowsingMenuEntry? { nil }
    func makeYouTubeAdBlockToggleEntry() -> BrowsingMenuEntry? { includesYouTubeEntry ? .named("YouTube Ad Block") : nil }
}

private final class MockMenuBookmarksInteractor: MenuBookmarksInteracting {

    var favoritesDisplayMode: FavoritesDisplayMode = .displayNative(.mobile)

    func createOrToggleFavorite(title: String, url: URL) {}
    func createBookmark(title: String, url: URL) {}
    func favorite(for url: URL) -> BookmarkEntity? { nil }
    func bookmark(for url: URL) -> BookmarkEntity? { nil }
}

private extension BrowsingMenuEntry {

    var name: String? {
        guard case let .regular(name, _, _, _, _, _, _, _, _) = self else { return nil }
        return name
    }

    static func named(_ name: String) -> BrowsingMenuEntry {
        .regular(name: name, image: UIImage(), action: {})
    }
}

private final class SitePermissionsMenuURLWebView: WKWebView {

    private let fixedURL: URL

    init(url: URL, configuration: WKWebViewConfiguration) {
        fixedURL = url
        super.init(frame: .zero, configuration: configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var url: URL? {
        fixedURL
    }
}
