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
        let model = VerticalTabsViewModel(tabCollectionViewModel: collection, onCloseTab: { requestedIndex = $0 }, openNewTab: {})
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

    private func tabCollectionViewModel(tabCount: Int, selectedIndex: Int) -> TabCollectionViewModel {
        let tabs = (0..<tabCount).map { _ in Tab(content: .newtab) }
        return TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs),
                                      selectionIndex: .unpinned(selectedIndex),
                                      pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock())
    }

    private func verticalTabsViewModel(for tabCollectionViewModel: TabCollectionViewModel) -> VerticalTabsViewModel {
        VerticalTabsViewModel(tabCollectionViewModel: tabCollectionViewModel,
                              onCloseTab: { tabCollectionViewModel.close(at: $0) },
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
