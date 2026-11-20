//
//  VerticalTabsViewModelTests.swift
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
final class VerticalTabsViewModelTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
    }

    func testListsTheTabsAndTheSelectedTab() {
        let tabCollectionViewModel = tabCollectionViewModel(tabCount: 3, selectedIndex: 1)

        let model = verticalTabsViewModel(for: tabCollectionViewModel)

        XCTAssertEqual(model.tabs.map(\.id), tabIDs(of: tabCollectionViewModel))
        XCTAssertEqual(model.selectedTabID, tabIDs(of: tabCollectionViewModel)[1])
    }

    func testWhenTabIsClosedThenItLeavesTheList() {
        let tabCollectionViewModel = tabCollectionViewModel(tabCount: 3, selectedIndex: 0)
        let model = verticalTabsViewModel(for: tabCollectionViewModel)
        let closedTabID = model.tabs[1].id
        let tabsUpdated = expectTabsUpdate(of: model)

        tabCollectionViewModel.close(at: .unpinned(1))

        wait(for: [tabsUpdated], timeout: 1)
        XCTAssertEqual(model.tabs.map(\.id), tabIDs(of: tabCollectionViewModel))
        XCTAssertFalse(model.tabs.map(\.id).contains(closedTabID))
    }

    func testSidebarCloseWaitsForTheWindowToHandleTheRequest() {
        let collection = tabCollectionViewModel(tabCount: 3, selectedIndex: 0)
        var requestedIndex: TabIndex?
        let model = VerticalTabsViewModel(tabCollectionViewModel: collection, onCloseTab: { requestedIndex = $0 }, onTearOffTab: { _, _ in }, openNewTab: {})
        let originalIDs = tabIDs(of: collection)

        model.close(originalIDs[1])

        XCTAssertEqual(requestedIndex, .unpinned(1))
        XCTAssertEqual(tabIDs(of: collection), originalIDs)
    }

    func testWhenTabMovesToAnotherPlaceThenTheListFollows() {
        let tabCollectionViewModel = tabCollectionViewModel(tabCount: 3, selectedIndex: 0)
        let model = verticalTabsViewModel(for: tabCollectionViewModel)
        let originalIDs = model.tabs.map(\.id)
        let tabsUpdated = expectTabsUpdate(of: model)

        model.moveTab(originalIDs[0], to: 2)

        wait(for: [tabsUpdated], timeout: 1)
        XCTAssertEqual(tabIDs(of: tabCollectionViewModel), [originalIDs[1], originalIDs[2], originalIDs[0]])
        XCTAssertEqual(model.tabs.map(\.id), [originalIDs[1], originalIDs[2], originalIDs[0]])
    }

    func testTearOffUsesTheDraggedTabsCurrentIndexAndTheScreenDropPoint() {
        let collection = tabCollectionViewModel(tabCount: 3, selectedIndex: 0)
        let draggedID = tabIDs(of: collection)[1]
        var requestedIndices: [Int] = []
        var requestedPoints: [NSPoint] = []
        let model = verticalTabsViewModel(for: collection) { index, point in
            requestedIndices.append(index)
            requestedPoints.append(point)
        }
        let dropPoint = NSPoint(x: -235, y: 502)

        XCTAssertTrue(model.canTearOffTab(draggedID))
        model.moveTab(draggedID, to: 2)
        model.tearOffTab(draggedID, at: dropPoint)

        XCTAssertEqual(requestedIndices, [2])
        XCTAssertEqual(requestedPoints, [dropPoint])
    }

    func testTearOffIgnoresATabClosedDuringTheDrag() {
        let collection = tabCollectionViewModel(tabCount: 3, selectedIndex: 0)
        let model = verticalTabsViewModel(for: collection)
        let originalIDs = tabIDs(of: collection)
        let draggedID = originalIDs[1]
        XCTAssertTrue(model.canTearOffTab(draggedID))

        collection.close(at: .unpinned(1))
        model.tearOffTab(draggedID, at: .zero)

        XCTAssertFalse(model.canTearOffTab(draggedID))
        XCTAssertEqual(tabIDs(of: collection), [originalIDs[0], originalIDs[2]])
    }

    func testTearOffKeepsTheLastTabInItsWindow() {
        let collection = tabCollectionViewModel(tabCount: 2, selectedIndex: 0)
        let model = verticalTabsViewModel(for: collection)
        let draggedID = tabIDs(of: collection)[0]
        XCTAssertTrue(model.canTearOffTab(draggedID))

        collection.close(at: .unpinned(1))
        model.tearOffTab(draggedID, at: .zero)

        XCTAssertFalse(model.canTearOffTab(draggedID))
        XCTAssertEqual(tabIDs(of: collection), [draggedID])
    }

    func testTearOffKeepsFireWindowTabsInTheirWindow() {
        let collection = tabCollectionViewModel(tabCount: 2, selectedIndex: 0, burnerMode: BurnerMode(isBurner: true))
        let model = verticalTabsViewModel(for: collection)
        let originalIDs = tabIDs(of: collection)

        XCTAssertFalse(model.canTearOffTab(originalIDs[1]))
        model.tearOffTab(originalIDs[1], at: .zero)

        XCTAssertEqual(tabIDs(of: collection), originalIDs)
    }

    func testDraggingOutsideShowsAPreviewAndReturningInsideDismissesItWithoutMovingTheTab() throws {
        let collection = tabCollectionViewModel(tabCount: 2, selectedIndex: 0)
        let model = verticalTabsViewModel(for: collection)
        let window = makeDragSourceWindow()
        defer { window.close() }
        let session = VerticalTabDragSession(sidebarView: try XCTUnwrap(window.contentView), model: model)
        let inside = NSPoint(x: window.frame.midX, y: window.frame.midY)
        let outside = NSPoint(x: window.frame.minX - 20, y: window.frame.midY)

        session.beginDragging(model.tabs[1].id)
        session.update(at: inside)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)

        session.update(at: outside)
        let preview = try XCTUnwrap(window.childWindows?.first as? NSPanel)
        XCTAssertTrue(preview.ignoresMouseEvents)
        session.update(at: inside)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)

        session.end(at: inside)
        XCTAssertEqual(collection.tabs.count, 2)
    }

    func testDroppingOutsideRequestsOneNewWindowAndCancellingTheSameDragRequestsNone() throws {
        let collection = tabCollectionViewModel(tabCount: 2, selectedIndex: 0)
        var requestedPoints: [NSPoint] = []
        let model = verticalTabsViewModel(for: collection) { _, point in requestedPoints.append(point) }
        let window = makeDragSourceWindow()
        defer { window.close() }
        let session = VerticalTabDragSession(sidebarView: try XCTUnwrap(window.contentView), model: model)
        let outside = NSPoint(x: window.frame.maxX + 15, y: window.frame.midY)
        let tabID = model.tabs[1].id

        session.beginDragging(tabID)
        session.update(at: outside)
        XCTAssertNotNil(window.childWindows?.first as? NSPanel)
        session.cancel()
        session.end(at: outside)
        XCTAssertTrue(requestedPoints.isEmpty)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)

        session.beginDragging(tabID)
        session.update(at: outside)
        session.end(at: outside)
        XCTAssertEqual(requestedPoints, [outside])
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    }

    func testDuplicatesRegularTabsAndRejectsSettingsTabs() {
        let regularTab = Tab(content: .newtab)
        let settingsTab = Tab(content: .settings(pane: nil))
        let collection = TabCollection(tabs: [regularTab, settingsTab])
        let collectionModel = TabCollectionViewModel(tabCollection: collection, pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock())
        let model = verticalTabsViewModel(for: collectionModel)

        XCTAssertEqual(model.tabs.map(\.canBeDuplicated), [true, false])
        model.duplicate(settingsTab.uuid)
        XCTAssertEqual(collection.tabs.map(\.uuid), [regularTab.uuid, settingsTab.uuid])

        model.duplicate(regularTab.uuid)
        XCTAssertEqual(collection.tabs.map(\.content), [.newtab, .newtab, .settings(pane: nil)])
    }

    func testContinuesObservingTabAfterItIsLoadedWithTheSameID() throws {
        let unloaded = UnloadedTab(content: .newtab)
        let collection = TabCollection(tabs: [.loaded(Tab(content: .newtab)), .unloaded(unloaded)])
        let collectionModel = TabCollectionViewModel(tabCollection: collection, pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock())
        let model = verticalTabsViewModel(for: collectionModel)
        let selected = expectation(description: "Selected the restored tab")
        model.$selectedTabID
            .first(where: { $0 == unloaded.uuid })
            .sink { _ in selected.fulfill() }
            .store(in: &cancellables)

        model.select(unloaded.uuid)
        wait(for: [selected], timeout: 1)
        let loaded = try XCTUnwrap(collectionModel.selectedTabViewModel?.tab)
        XCTAssertEqual(loaded.uuid, unloaded.uuid)

        let updated = expectation(description: "Sidebar shows the loaded tab's new content")
        model.$tabs
            .first(where: { $0.last?.canBeDuplicated == false })
            .sink { _ in updated.fulfill() }
            .store(in: &cancellables)
        loaded.setContent(.settings(pane: nil))
        wait(for: [updated], timeout: 1)
    }

    func testDisplaysOnlyActiveCameraMicrophoneAndLocationIndicators() {
        let source = TabBarViewModelMock(usedPermissions: [.geolocation: .active, .camera: .active, .microphone: .active, .notification: .active])
        XCTAssertEqual(VerticalTab(source).activePermissions, [.camera, .microphone, .geolocation])

        source.usedPermissions = [.camera: .inactive, .microphone: .paused, .geolocation: .denied]
        XCTAssertTrue(VerticalTab(source).activePermissions.isEmpty)
    }

    private func makeDragSourceWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 640, height: 480),
                              styleMask: [.titled, .resizable],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    private func tabCollectionViewModel(tabCount: Int, selectedIndex: Int, burnerMode: BurnerMode = .regular) -> TabCollectionViewModel {
        let tabs = (0..<tabCount).map { _ in Tab(content: .newtab, burnerMode: burnerMode) }
        return TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs),
                                      selectionIndex: .unpinned(selectedIndex),
                                      pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock(),
                                      burnerMode: burnerMode)
    }

    private func verticalTabsViewModel(for tabCollectionViewModel: TabCollectionViewModel,
                                       onTearOffTab: @escaping (Int, NSPoint) -> Void = { _, _ in XCTFail("Unexpected tab tear-off") }) -> VerticalTabsViewModel {
        VerticalTabsViewModel(tabCollectionViewModel: tabCollectionViewModel,
                              onCloseTab: { tabCollectionViewModel.close(at: $0) },
                              onTearOffTab: onTearOffTab,
                              openNewTab: { tabCollectionViewModel.insertOrAppendNewTab() })
    }

    private func tabIDs(of tabCollectionViewModel: TabCollectionViewModel) -> [TabIdentifier] {
        tabCollectionViewModel.tabCollection.tabs.map(\.uuid)
    }

    private func expectTabsUpdate(of model: VerticalTabsViewModel) -> XCTestExpectation {
        let expectation = expectation(description: "Tabs updated")
        model.$tabs
            .dropFirst()
            .first()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)
        return expectation
    }
}
