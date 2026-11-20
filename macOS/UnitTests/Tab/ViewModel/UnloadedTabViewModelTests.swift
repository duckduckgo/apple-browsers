//
//  UnloadedTabViewModelTests.swift
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

import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

class UnloadedTabViewModelTests: XCTestCase {

    private var fileStore: FileStoreMock!

    override func setUp() {
        super.setUp()
        fileStore = FileStoreMock()
    }

    override func tearDown() {
        fileStore = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeUnloadedTab(
        content: Tab.TabContent = .url(.duckDuckGo, source: .link),
        title: String? = "Test Tab",
        tabSnapshotIdentifier: String? = nil
    ) -> UnloadedTab {
        UnloadedTab(content: content, title: title, tabSnapshotIdentifier: tabSnapshotIdentifier)
    }

    private func makeViewModel(unloadedTab: UnloadedTab) -> UnloadedTabViewModel {
        UnloadedTabViewModel(unloadedTab: unloadedTab, fileStore: fileStore)
    }

    private func persistTestSnapshot(for uuid: UUID) {
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation else {
            XCTFail("Failed to create TIFF data")
            return
        }

        fileStore.storage[uuid.uuidString] = tiffData
    }

    // MARK: - Previewable: snapshot

    func testSnapshotLoadsFromDisk() {
        let snapshotUUID = UUID()
        persistTestSnapshot(for: snapshotUUID)

        let tab = makeUnloadedTab(tabSnapshotIdentifier: snapshotUUID.uuidString)
        let viewModel = makeViewModel(unloadedTab: tab)

        XCTAssertNotNil(viewModel.snapshot)
    }

    func testSnapshotReturnsNilWhenIdentifierMissing() {
        let tab = makeUnloadedTab(tabSnapshotIdentifier: nil)
        let viewModel = makeViewModel(unloadedTab: tab)

        XCTAssertNil(viewModel.snapshot)
    }

    func testSnapshotReturnsNilWhenFileNotOnDisk() {
        let tab = makeUnloadedTab(tabSnapshotIdentifier: UUID().uuidString)
        let viewModel = makeViewModel(unloadedTab: tab)

        XCTAssertNil(viewModel.snapshot)
    }

    func testSnapshotIsCached() {
        let snapshotUUID = UUID()
        persistTestSnapshot(for: snapshotUUID)

        let tab = makeUnloadedTab(tabSnapshotIdentifier: snapshotUUID.uuidString)
        let viewModel = makeViewModel(unloadedTab: tab)

        let first = viewModel.snapshot
        XCTAssertNotNil(first)

        // Remove the data from the store — a second access should still return the cached image
        fileStore.storage.removeAll()

        let second = viewModel.snapshot
        XCTAssertNotNil(second)
    }

    @MainActor
    func testDragPreviewIncludesTheUnloadedTabsSavedPageAndFallsBackWhenItHasNoSnapshot() throws {
        let snapshotID = UUID()
        persistTestSnapshot(for: snapshotID)
        let savedTab = makeViewModel(unloadedTab: makeUnloadedTab(tabSnapshotIdentifier: snapshotID.uuidString))
        let unsavedTab = makeViewModel(unloadedTab: makeUnloadedTab())

        let pagePreview = TabDragPreview.makeImage(for: savedTab)
        let fallback = TabDragPreview.makeImage(for: unsavedTab)

        XCTAssertGreaterThan(fallback.size.height, 0)
        XCTAssertGreaterThan(pagePreview.size.height, fallback.size.height)
        let data = try XCTUnwrap(pagePreview.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let center = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(center.redComponent - max(center.greenComponent, center.blueComponent), 0.6,
                             "The center of the preview should contain the red saved page")
    }

    @MainActor
    func testNativeDragPreviewRendersOnlyTheTopOfATallPageAtRetinaResolution() throws {
        let page = CALayer()
        page.bounds = CGRect(x: 0, y: 0, width: 2_000, height: 4_000)
        page.backgroundColor = NSColor.blue.cgColor
        let top = CALayer()
        top.frame = CGRect(x: 0, y: 0, width: 2_000, height: 1_500)
        top.backgroundColor = NSColor.red.cgColor
        page.addSublayer(top)

        let image = try XCTUnwrap(TabDragPreview.nativePageSnapshot(of: page, backingScale: 2))
        XCTAssertEqual(image.size, NSSize(width: 228, height: 168))
        let representation = try XCTUnwrap(image.representations.first)
        XCTAssertEqual(representation.pixelsWide, 456)
        XCTAssertEqual(representation.pixelsHigh, 336)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let color = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(color.redComponent - color.blueComponent, 0.8)
    }

    // MARK: - Previewable: other properties

    func testShouldShowPreviewIsTrue() {
        let viewModel = makeViewModel(unloadedTab: makeUnloadedTab())

        XCTAssertTrue(viewModel.shouldShowPreview)
    }

    func testAddressBarStringMatchesURL() {
        let url = URL(string: "https://example.com/path")!
        let tab = makeUnloadedTab(content: .url(url, source: .link))
        let viewModel = makeViewModel(unloadedTab: tab)

        XCTAssertEqual(viewModel.addressBarString, "https://example.com/path")
    }

    func testAddressBarStringForNonURLContent() {
        let tab = makeUnloadedTab(content: .newtab)
        let viewModel = makeViewModel(unloadedTab: tab)

        // .newtab has a userEditableUrl (duck://newtab), so addressBarString is non-empty
        XCTAssertEqual(viewModel.addressBarString, Tab.TabContent.newtab.userEditableUrl?.absoluteString ?? "")
    }
}
