//
//  TabRestorationDataCodingTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class TabRestorationDataCodingTests: XCTestCase {

    // MARK: - Test 1: Round-trip preserves all fields

    func testRoundTripPreservesAllFields() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let interactionState = Data([0x01, 0x02, 0x03])
        let visitedURLs = [URL(string: "https://example.com")!, URL(string: "https://duckduckgo.com")!]
        let snapshotID = UUID().uuidString

        let original = TabRestorationData(
            uuid: "test-uuid-123",
            content: .url(URL(string: "https://example.com")!, credential: nil, source: .pendingStateRestoration),
            title: "Example",
            favicon: nil,
            interactionStateData: interactionState,
            lastSelectedAt: date,
            localHistoryIDs: visitedURLs,
            tabSnapshotIdentifier: snapshotID
        )

        let decoded = try encodeThenDecode(original)

        XCTAssertEqual(decoded.uuid, "test-uuid-123")
        XCTAssertEqual(decoded.content.urlForWebView, URL(string: "https://example.com")!)
        XCTAssertEqual(decoded.title, "Example")
        XCTAssertEqual(decoded.interactionStateData, interactionState)
        XCTAssertEqual(decoded.lastSelectedAt, date)
        XCTAssertEqual(decoded.localHistoryIDs, visitedURLs)
        XCTAssertEqual(decoded.tabSnapshotIdentifier, snapshotID)
    }

    // MARK: - Test 2: Round-trip with className "Tab" mapping (production path)

    func testRoundTripWithClassNameMapping() throws {
        let original = TabRestorationData(
            uuid: "mapped-uuid",
            content: .url(URL(string: "https://duckduckgo.com")!, credential: nil, source: .pendingStateRestoration),
            title: "DuckDuckGo",
            favicon: nil,
            interactionStateData: nil,
            lastSelectedAt: nil,
            localHistoryIDs: nil,
            tabSnapshotIdentifier: nil
        )

        // Encode with module-qualified class name (matches production TabCollection.encode)
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.setClassName(NSStringFromClass(Tab.self), for: TabRestorationData.self)
        archiver.encode([original], forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()

        // Decode with class remapping (matches production TabCollection.init?(coder:))
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        unarchiver.requiresSecureCoding = true
        unarchiver.setClass(TabRestorationData.self, forClassName: NSStringFromClass(Tab.self))

        let result = unarchiver.decodeObject(
            of: [NSArray.self, TabRestorationData.self],
            forKey: NSKeyedArchiveRootObjectKey
        ) as? [TabRestorationData]

        let decoded = try XCTUnwrap(result?.first)
        XCTAssertEqual(decoded.uuid, "mapped-uuid")
        XCTAssertEqual(decoded.content.urlForWebView, URL(string: "https://duckduckgo.com")!)
        XCTAssertEqual(decoded.title, "DuckDuckGo")
    }

    // MARK: - Test 3: Decode without class remapping fails (NSSecureCoding class validation)

    func testDecodeWithoutRemappingReturnsNil() throws {
        let original = TabRestorationData(
            uuid: "fail-uuid",
            content: .url(URL(string: "https://example.com")!, credential: nil, source: .pendingStateRestoration),
            title: "Example",
            favicon: nil,
            interactionStateData: nil,
            lastSelectedAt: nil,
            localHistoryIDs: nil,
            tabSnapshotIdentifier: nil
        )

        // Encode with className "Tab" (production encoding)
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.setClassName("Tab", for: TabRestorationData.self)
        archiver.encode([original], forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()

        // Decode WITHOUT remapping — ask for [Tab] directly
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        unarchiver.requiresSecureCoding = true

        let result = unarchiver.decodeObject(
            of: [NSArray.self, Tab.self],
            forKey: NSKeyedArchiveRootObjectKey
        )

        // NSSecureCoding rejects: actual class is TabRestorationData, not Tab
        XCTAssertNil(result, "Decode should fail — NSSecureCoding validates actual class, not just mapped className")
    }

    // MARK: - Test 4: Various content types survive round-trip

    func testURLContentRoundTrip() throws {
        let original = makeRestorationData(content: .url(URL(string: "https://nasa.gov")!, credential: nil, source: .pendingStateRestoration))
        let decoded = try encodeThenDecode(original)
        XCTAssertEqual(decoded.content.urlForWebView, URL(string: "https://nasa.gov")!)
    }

    func testNewTabContentRoundTrip() throws {
        let original = makeRestorationData(content: .newtab)
        let decoded = try encodeThenDecode(original)
        XCTAssertEqual(decoded.content, .newtab)
    }

    func testSettingsContentRoundTrip() throws {
        let original = makeRestorationData(content: .settings(pane: .general))
        let decoded = try encodeThenDecode(original)
        if case .settings(let pane) = decoded.content {
            XCTAssertEqual(pane, .general)
        } else {
            XCTFail("Expected .settings content, got \(decoded.content)")
        }
    }

    // MARK: - Test 5: Nil/optional fields handled correctly

    func testNilFieldsPreserved() throws {
        let original = TabRestorationData(
            uuid: "nil-fields",
            content: .newtab,
            title: nil,
            favicon: nil,
            interactionStateData: nil,
            lastSelectedAt: nil,
            localHistoryIDs: nil,
            tabSnapshotIdentifier: nil
        )

        let decoded = try encodeThenDecode(original)

        XCTAssertEqual(decoded.uuid, "nil-fields")
        XCTAssertNil(decoded.title)
        XCTAssertNil(decoded.favicon)
        XCTAssertNil(decoded.interactionStateData)
        XCTAssertNil(decoded.lastSelectedAt)
        XCTAssertNil(decoded.localHistoryIDs)
        XCTAssertNil(decoded.tabSnapshotIdentifier)
    }

    // MARK: - Test 6: UnloadedTab from decoded data preserves fields

    func testUnloadedTabFromDecodedDataPreservesFields() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let interactionState = Data([0xAA, 0xBB])
        let visitedURLs = [URL(string: "https://example.com")!]
        let snapshotID = "snapshot-123"

        let original = TabRestorationData(
            uuid: "unloaded-uuid",
            content: .url(URL(string: "https://example.com")!, credential: nil, source: .pendingStateRestoration),
            title: "Unloaded Example",
            favicon: nil,
            interactionStateData: interactionState,
            lastSelectedAt: date,
            localHistoryIDs: visitedURLs,
            tabSnapshotIdentifier: snapshotID
        )

        let decoded = try encodeThenDecode(original)
        let unloaded = UnloadedTab(from: decoded)

        XCTAssertEqual(unloaded.uuid, "unloaded-uuid")
        XCTAssertEqual(unloaded.content.urlForWebView, URL(string: "https://example.com")!)
        XCTAssertEqual(unloaded.title, "Unloaded Example")
        XCTAssertEqual(unloaded.interactionStateData, interactionState)
        XCTAssertEqual(unloaded.lastSelectedAt, date)
        XCTAssertEqual(unloaded.localHistoryIDs, visitedURLs)
        XCTAssertEqual(unloaded.tabSnapshotIdentifier, snapshotID)
    }

    // MARK: - Test 7: Materialized tab from decoded data preserves extension fields

    @MainActor
    func testMaterializedTabFromDecodedDataPreservesFields() throws {
        let domainURLs = [URL(string: "https://a.com")!, URL(string: "https://b.com")!]
        let snapshotID = UUID().uuidString

        let historyMock = HistoryTabExtensionMock()
        let snapshotMock = TabSnapshotExtensionMock()
        let extensionsBuilder = TestTabExtensionsBuilder(
            load: [HistoryTabExtensionMock.self, TabSnapshotExtensionMock.self]
        ) { builder in { _, _ in
            builder.override { historyMock }
            builder.override { snapshotMock }
        }}

        let unloaded = UnloadedTab(
            uuid: "materialized-uuid",
            content: .url(URL(string: "https://example.com")!, credential: nil, source: .pendingStateRestoration),
            title: "Materialized Example",
            localHistoryIDs: domainURLs,
            tabSnapshotIdentifier: snapshotID
        )

        let tab = unloaded.materialize(extensionsBuilder: extensionsBuilder)

        XCTAssertEqual(tab.uuid, "materialized-uuid")
        XCTAssertEqual(tab.content.urlForWebView, URL(string: "https://example.com")!)
        XCTAssertEqual(tab.title, "Materialized Example")

        XCTAssertEqual(historyMock.restoredURLs, domainURLs,
                       "localHistoryIDs must be injected into HistoryTabExtension")
        XCTAssertEqual(snapshotMock.setIdentifierValue, UUID(uuidString: snapshotID),
                       "tabSnapshotIdentifier must be injected into TabSnapshotExtension")
    }

    // MARK: - Test 8: Backwards compatibility — old Tab-encoded archive decoded by new code

    @MainActor
    func testLegacyTabEncodedArchiveDecodesAsTabRestorationData() throws {
        let url = URL(string: "https://legacy.example.com")!
        let tab = Tab(content: .url(url, credential: nil, source: .link), shouldLoadInBackground: true)
        tab.title = "Legacy Tab"

        // Encode exactly as old TabCollection.encode(with:) did — no class name remapping
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.encode([tab], forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()

        // Decode with class remapping — exactly as new TabCollection.init?(coder:) does
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        unarchiver.requiresSecureCoding = true
        unarchiver.setClass(TabRestorationData.self, forClassName: "Tab")
        unarchiver.setClass(TabRestorationData.self, forClassName: NSStringFromClass(Tab.self))

        let result = unarchiver.decodeObject(
            of: [NSArray.self, TabRestorationData.self],
            forKey: NSKeyedArchiveRootObjectKey
        ) as? [TabRestorationData]

        let decoded = try XCTUnwrap(result?.first)
        XCTAssertEqual(decoded.uuid, tab.uuid)
        XCTAssertEqual(decoded.content.urlForWebView, url)
        XCTAssertEqual(decoded.title, "Legacy Tab")
    }

    // MARK: - Test 9: Rollback safety — new TabRestorationData archive decoded as Tab by old code

    @MainActor
    func testNewArchiveDecodesAsTabForRollback() throws {
        let url = URL(string: "https://new-version.example.com")!
        let unloaded = UnloadedTab(
            uuid: "rollback-uuid",
            content: .url(url, credential: nil, source: .pendingStateRestoration),
            title: "New Tab"
        )

        // Encode exactly as new TabCollection.encode(with:) does
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.setClassName(NSStringFromClass(Tab.self), for: TabRestorationData.self)
        let restorationData = TabRestorationData(
            uuid: unloaded.uuid,
            content: unloaded.content,
            title: unloaded.title,
            favicon: nil,
            interactionStateData: nil,
            lastSelectedAt: nil,
            localHistoryIDs: nil,
            tabSnapshotIdentifier: nil
        )
        archiver.encode([restorationData], forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()

        // Decode exactly as old TabCollection.init?(coder:) did — no class remapping,
        // just decodeObject(of: [Tab.self])
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        unarchiver.requiresSecureCoding = true

        let result = unarchiver.decodeObject(
            of: [NSArray.self, Tab.self],
            forKey: NSKeyedArchiveRootObjectKey
        ) as? [Tab]

        let decoded = try XCTUnwrap(result?.first)
        XCTAssertEqual(decoded.uuid, "rollback-uuid")
        XCTAssertEqual(decoded.content.urlForWebView, url)
        XCTAssertEqual(decoded.title, "New Tab")
    }

    // MARK: - Helpers

    private func encodeThenDecode(_ data: TabRestorationData) throws -> TabRestorationData {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.encode(data, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()

        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        unarchiver.requiresSecureCoding = true
        return try XCTUnwrap(
            unarchiver.decodeObject(of: TabRestorationData.self, forKey: NSKeyedArchiveRootObjectKey)
        )
    }

    private func makeRestorationData(content: Tab.TabContent) -> TabRestorationData {
        TabRestorationData(
            uuid: UUID().uuidString,
            content: content,
            title: "Test",
            favicon: nil,
            interactionStateData: nil,
            lastSelectedAt: nil,
            localHistoryIDs: nil,
            tabSnapshotIdentifier: nil
        )
    }
}

// MARK: - Mocks

private class TabSnapshotExtensionMock: TabExtension, TabSnapshotExtensionProtocol {

    var snapshot: NSImage?
    var identifier = UUID()
    var setIdentifierValue: UUID?
    var shouldClearSnapshotOnDeinit: Bool = true

    func getPublicProtocol() -> TabSnapshotExtensionProtocol { self }

    func setIdentifier(_ identifier: UUID) {
        self.identifier = identifier
        setIdentifierValue = identifier
    }

    func renderWebViewSnapshot() async {}
    func renderSnapshot(from view: @escaping () -> NSView?) async {}
}
