//
//  TabCollectionViewModelTests.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import Combine
@testable import DuckDuckGo_Privacy_Browser

// MARK: - Tests for TabCollectionViewModel with PinnedTabsManager but without pinned tabs
final class TabCollectionViewModelTests: XCTestCase {

    // MARK: - TabViewModel

    @MainActor
    func testWhenTabViewModelIsCalledWithIndexOutOfBoundsThenNilIsReturned() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        XCTAssertNil(tabCollectionViewModel.tabViewModel(at: 1))
    }

    @MainActor
    func testWhenTabViewModelIsCalledThenAppropriateTabViewModelIsReturned() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        XCTAssertEqual(tabCollectionViewModel.tabViewModel(at: 0)?.tab,
                       tabCollectionViewModel.tabCollection.tabs[0])
    }

    @MainActor
    func testWhenTabViewModelIsCalledWithSameIndexThenTheResultHasSameIdentity() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        XCTAssert(tabCollectionViewModel.tabViewModel(at: 0) === tabCollectionViewModel.tabViewModel(at: 0))
    }

    @MainActor
    func testWhenTabViewModelIsInitializedWithoutTabsThenNewHomePageTabIsCreated() {
        let tabCollection = TabCollection()
        XCTAssertTrue(tabCollection.tabs.isEmpty)

        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: TabCollection())

        XCTAssertEqual(tabCollectionViewModel.tabCollection.tabs.count, 1)
        XCTAssertEqual(tabCollectionViewModel.tabCollection.tabs[0].content, .newtab)
    }

    // MARK: - Select

    @MainActor
    func testWhenTabCollectionViewModelIsInitializedThenSelectedTabViewModelIsFirst() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        XCTAssert(tabCollectionViewModel.selectedTabViewModel === tabCollectionViewModel.tabViewModel(at: 0))
    }

    @MainActor
    func testWhenSelectionIndexIsOutOfBoundsThenSelectedTabViewModelIsNil() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        tabCollectionViewModel.select(at: .unpinned(1))
        XCTAssertNil(tabCollectionViewModel.selectedTabViewModel)

        tabCollectionViewModel.select(at: .pinned(0))
        XCTAssertNil(tabCollectionViewModel.selectedTabViewModel)
    }

    @MainActor
    func testWhenSelectionIndexPointsToTabThenSelectedTabViewModelReturnsTheTab() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.select(at: .unpinned(0))

        XCTAssert(tabCollectionViewModel.selectedTabViewModel === tabCollectionViewModel.tabViewModel(at: 0))
    }

    @MainActor
    func testWhenSelectNextIsCalledThenNextTabIsSelected() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.select(at: .unpinned(0))
        tabCollectionViewModel.selectNext()

        XCTAssert(tabCollectionViewModel.selectedTabViewModel === tabCollectionViewModel.tabViewModel(at: 1))
    }

    @MainActor
    func testWhenLastTabIsSelectedThenSelectNextChangesSelectionToFirstOne() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.selectNext()

        XCTAssert(tabCollectionViewModel.selectedTabViewModel === tabCollectionViewModel.tabViewModel(at: 0))
    }

    @MainActor
    func testWhenSelectPreviousIsCalledThenPreviousTabIsSelected() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.selectPrevious()

        XCTAssert(tabCollectionViewModel.selectedTabViewModel === tabCollectionViewModel.tabViewModel(at: 0))
    }

    @MainActor
    func testWhenFirstTabIsSelectedThenSelectPreviousChangesSelectionToLastOne() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.select(at: .unpinned(0))
        tabCollectionViewModel.selectPrevious()

        XCTAssert(tabCollectionViewModel.selectedTabViewModel === tabCollectionViewModel.tabViewModel(at: 1))
    }

    @MainActor
    func testWhenPreferencesTabIsPresentThenSelectDisplayableTabIfPresentSelectsPreferencesTab() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        tabCollectionViewModel.tabCollection.append(tab: .init(content: .anySettingsPane))
        tabCollectionViewModel.tabCollection.append(tab: .init(content: .newtab))
        tabCollectionViewModel.select(at: .unpinned(0))

        XCTAssertTrue(tabCollectionViewModel.selectDisplayableTabIfPresent(.anySettingsPane))
        XCTAssert(tabCollectionViewModel.selectedTabViewModel === tabCollectionViewModel.tabViewModel(at: 1))
    }

    @MainActor
    func testWhenPreferencesTabIsPinnedThenSelectDisplayableTabIfPresentSelectsPreferencesTab() throws {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        tabCollectionViewModel.tabCollection.removeAll(andAppend: .init(content: .anySettingsPane))
        tabCollectionViewModel.tabCollection.append(tab: .init(content: .newtab))

        tabCollectionViewModel.pinTab(at: 0)
        tabCollectionViewModel.select(at: .unpinned(0))

        XCTAssertTrue(tabCollectionViewModel.selectDisplayableTabIfPresent(.anySettingsPane))
        XCTAssert(tabCollectionViewModel.selectedTabViewModel === tabCollectionViewModel.tabViewModel(at: .pinned(0)))
    }

    @MainActor
    func testWhenPreferencesTabIsPresentThenOpeningPreferencesWithDifferentPaneUpdatesPaneOnExistingTab() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        tabCollectionViewModel.tabCollection.append(tab: .init(content: .settings(pane: .appearance)))
        tabCollectionViewModel.tabCollection.append(tab: .init(content: .newtab))

        XCTAssertTrue(tabCollectionViewModel.selectDisplayableTabIfPresent(.settings(pane: .general)))
        XCTAssert(tabCollectionViewModel.selectedTabViewModel === tabCollectionViewModel.tabViewModel(at: 1))
        XCTAssertEqual(tabCollectionViewModel.selectedTabViewModel?.tab.content, .settings(pane: .general))
    }

    @MainActor
    func testWhenPreferencesTabIsPresentThenOpeningPreferencesWithAnyPaneDoesNotUpdatePaneOnExistingTab() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        tabCollectionViewModel.tabCollection.append(tab: .init(content: .settings(pane: .appearance)))
        tabCollectionViewModel.tabCollection.append(tab: .init(content: .newtab))

        XCTAssertTrue(tabCollectionViewModel.selectDisplayableTabIfPresent(.anySettingsPane))
        XCTAssert(tabCollectionViewModel.selectedTabViewModel === tabCollectionViewModel.tabViewModel(at: 1))
        XCTAssertEqual(tabCollectionViewModel.selectedTabViewModel?.tab.content, .settings(pane: .appearance))
    }

    @MainActor
    func testWhenBookmarksTabIsPresentThenSelectDisplayableTabIfPresentSelectsBookmarksTab() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        tabCollectionViewModel.tabCollection.append(tab: .init(content: .bookmarks))
        tabCollectionViewModel.tabCollection.append(tab: .init(content: .newtab))
        tabCollectionViewModel.select(at: .unpinned(0))

        XCTAssertTrue(tabCollectionViewModel.selectDisplayableTabIfPresent(.bookmarks))
        XCTAssert(tabCollectionViewModel.selectedTabViewModel === tabCollectionViewModel.tabViewModel(at: 1))
    }

    @MainActor
    func testSelectDisplayableTabDoesNotChangeSelectionIfDisplayableTabIsNotPresent() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        tabCollectionViewModel.tabCollection.append(tab: .init(content: .newtab))
        tabCollectionViewModel.tabCollection.append(tab: .init(content: .newtab))
        tabCollectionViewModel.select(at: .unpinned(2))

        XCTAssertFalse(tabCollectionViewModel.selectDisplayableTabIfPresent(.bookmarks))
        XCTAssert(tabCollectionViewModel.selectedTabViewModel === tabCollectionViewModel.tabViewModel(at: 2))
    }

    @MainActor
    func testSelectDisplayableTabDoesNotChangeSelectionIfDisplayableTabTypeDoesNotMatch() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        tabCollectionViewModel.tabCollection.append(tab: .init(content: .bookmarks))
        tabCollectionViewModel.tabCollection.append(tab: .init(content: .newtab))
        tabCollectionViewModel.select(at: .unpinned(2))

        XCTAssertFalse(tabCollectionViewModel.selectDisplayableTabIfPresent(.anySettingsPane))
        XCTAssert(tabCollectionViewModel.selectedTabViewModel === tabCollectionViewModel.tabViewModel(at: 2))
    }

    // MARK: - Append

    @MainActor
    func testWhenAppendNewTabIsCalledThenNewTabIsAlsoSelected() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        let index = tabCollectionViewModel.tabCollection.tabs.count
        tabCollectionViewModel.appendNewTab()
        XCTAssert(tabCollectionViewModel.selectedTabViewModel === tabCollectionViewModel.tabViewModel(at: index))
    }

    @MainActor
    func testWhenTabIsAppendedWithSelectedAsFalseThenSelectionIsPreserved() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        let selectedTabViewModel = tabCollectionViewModel.selectedTabViewModel

        tabCollectionViewModel.append(tab: Tab(), selected: false)

        XCTAssert(tabCollectionViewModel.selectedTabViewModel === selectedTabViewModel)
    }

    @MainActor
    func testWhenTabIsAppendedWithSelectedAsTrueThenNewTabIsSelected() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        tabCollectionViewModel.append(tab: Tab(), selected: true)
        let lastTabViewModel = tabCollectionViewModel.tabViewModel(at: tabCollectionViewModel.tabCollection.tabs.count - 1)

        XCTAssert(tabCollectionViewModel.selectedTabViewModel === lastTabViewModel)
    }

    @MainActor
    func testWhenMultipleTabsAreAppendedThenTheLastOneIsSelected() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        let lastTab = Tab()
        tabCollectionViewModel.append(tabs: [Tab(), lastTab], andSelect: true)

        XCTAssert(tabCollectionViewModel.selectedTabViewModel?.tab === lastTab)
    }

    @MainActor
    func testWhenMultipleTabsAreAppendedAndNoSelectThenTheLastOneIsNotSelected() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        let firstTab = Tab()
        tabCollectionViewModel.append(tab: firstTab, selected: true)

        let lastTab = Tab()
        tabCollectionViewModel.append(tabs: [Tab(), lastTab], andSelect: false)

        XCTAssert(tabCollectionViewModel.selectedTabViewModel?.tab === firstTab)
    }

    // MARK: - Insert

    @MainActor
    func testWhenInsertNewTabIsCalledThenNewTabIsAlsoSelected() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.select(at: .unpinned(0))
        XCTAssertNotNil(tabCollectionViewModel.selectedTabViewModel)
        tabCollectionViewModel.insertNewTab(after: tabCollectionViewModel.selectedTabViewModel!.tab)
        XCTAssert(tabCollectionViewModel.selectedTabViewModel === tabCollectionViewModel.tabViewModel(at: 1))
    }

    @MainActor
    func testWhenInsertChildAndParentIsntPartOfTheTabCollection_ThenNoChildIsInserted() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        let parentTab = Tab()
        let tab = Tab(content: .none, parentTab: parentTab)
        tabCollectionViewModel.insert(tab, selected: false)

        XCTAssert(tab !== tabCollectionViewModel.tabViewModel(at: 0)?.tab)
        XCTAssert(tabCollectionViewModel.tabCollection.tabs.count == 1)
    }

    @MainActor
    func testWhenInsertChildAndNoOtherChildTabIsNearParent_ThenTabIsInsertedRightNextToParent() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        let parentTab = Tab()
        tabCollectionViewModel.append(tab: parentTab)

        let tab = Tab(parentTab: parentTab)
        tabCollectionViewModel.insert(tab, selected: false)

        XCTAssert(tab === tabCollectionViewModel.tabViewModel(at: 2)?.tab)
    }

    @MainActor
    func testWhenInsertChildAndOtherChildTabsAreNearParent_ThenTabIsInsertedAtTheEndOfChildList() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        tabCollectionViewModel.appendNewTab()

        let parentTab = Tab()
        tabCollectionViewModel.insert(parentTab, at: .unpinned(1), selected: true)

        tabCollectionViewModel.insert(Tab(parentTab: parentTab), selected: false)
        tabCollectionViewModel.insert(Tab(parentTab: parentTab), selected: false)
        tabCollectionViewModel.insert(Tab(parentTab: parentTab), selected: false)

        let tab = Tab(parentTab: parentTab)
        tabCollectionViewModel.insert(tab, selected: true)

        XCTAssert(tab === tabCollectionViewModel.tabViewModel(at: 5)?.tab)
    }

    @MainActor
    func testWhenInsertChildAndParentIsLast_ThenTabIsAppendedAtTheEnd() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        tabCollectionViewModel.appendNewTab()

        let parentTab = Tab()
        tabCollectionViewModel.insert(parentTab, at: .unpinned(1), selected: true)

        let tab = Tab(parentTab: parentTab)
        tabCollectionViewModel.insert(tab, selected: false)

        XCTAssert(tab === tabCollectionViewModel.tabViewModel(at: 2)?.tab)
    }

    // MARK: - Insert or Append

    @MainActor
    func testWhenInsertOrAppendCalledPreferencesAreRespected() {
        let persistor = MockTabsPreferencesPersistor()
        var tabCollectionViewModel = TabCollectionViewModel(tabCollection: TabCollection(), pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock(),
                                                            tabsPreferences: TabsPreferences(persistor: persistor))

        let index = tabCollectionViewModel.tabCollection.tabs.count
        tabCollectionViewModel.insertOrAppendNewTab()
        XCTAssert(tabCollectionViewModel.selectedTabViewModel === tabCollectionViewModel.tabViewModel(at: index))

        persistor.newTabPosition = .nextToCurrent
        tabCollectionViewModel = TabCollectionViewModel(tabCollection: TabCollection(), pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock(),
                                                        tabsPreferences: TabsPreferences(persistor: persistor))

        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.select(at: .unpinned(0))
        XCTAssertNotNil(tabCollectionViewModel.selectedTabViewModel)
        tabCollectionViewModel.insertOrAppendNewTab()
        XCTAssert(tabCollectionViewModel.selectedTabViewModel === tabCollectionViewModel.tabViewModel(at: 1))
    }

    // MARK: - Remove

    @MainActor
    func testWhenRemoveIsCalledWithIndexOutOfBoundsThenNoTabIsRemoved() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        tabCollectionViewModel.remove(at: .unpinned(1))

        XCTAssertEqual(tabCollectionViewModel.tabCollection.tabs.count, 1)
    }

    @MainActor
    func testWhenTabIsRemovedAndSelectedTabHasHigherIndexThenSelectionIsPreserved() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        tabCollectionViewModel.appendNewTab()
        let selectedTab = tabCollectionViewModel.selectedTabViewModel?.tab

        tabCollectionViewModel.remove(at: .unpinned(0))

        XCTAssertEqual(selectedTab, tabCollectionViewModel.selectedTabViewModel?.tab)
    }

    @MainActor
    func testWhenSelectedTabIsRemovedThenNextItemWithLowerIndexIsSelected() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        let firstTab = tabCollectionViewModel.tabCollection.tabs[0]

        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.remove(at: .unpinned(1))

        XCTAssertEqual(firstTab, tabCollectionViewModel.selectedTabViewModel?.tab)
    }

    @MainActor
    func testWhenAllOtherTabsAreRemovedThenRemainedIsAlsoSelected() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        let firstTab = tabCollectionViewModel.tabCollection.tabs[0]

        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.appendNewTab()

        tabCollectionViewModel.removeAllTabs(except: 0)

        XCTAssertEqual(firstTab, tabCollectionViewModel.selectedTabViewModel?.tab)
    }

    @MainActor
    func testWhenTabsToTheLeftAreRemovedAndSelectionIsRemoved_ThenSelectionIsCorrectlyUpdated() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.appendNewTab()

        tabCollectionViewModel.select(at: .unpinned(1))
        tabCollectionViewModel.removeTabs(before: 2)

        XCTAssertEqual(tabCollectionViewModel.selectionIndex?.item, 0)
    }

    @MainActor
    func testWhenTabsToTheLeftAreRemovedAndSelectionRemains_ThenSelectionIsCorrectlyUpdated() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.select(at: .unpinned(3))
        tabCollectionViewModel.removeTabs(before: 3)

        XCTAssertEqual(tabCollectionViewModel.selectionIndex?.item, 0)
    }

    @MainActor
    func testWhenTabsToTheLeftAreRemovedAndSelectionRemainsAndIsToTheRight_ThenSelectionIsCorrectlyUpdated() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.select(at: .unpinned(4))
        tabCollectionViewModel.removeTabs(before: 2)

        XCTAssertEqual(tabCollectionViewModel.selectionIndex?.item, 2)
    }

    @MainActor
    func testWhenTabsToTheRightAreRemovedAndSelectionIsRemoved_ThenSelectionIsCorrectlyUpdated() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.appendNewTab()

        tabCollectionViewModel.select(at: .unpinned(1))
        tabCollectionViewModel.removeTabs(after: 0)

        XCTAssertEqual(tabCollectionViewModel.selectionIndex?.item, 0)
    }

    @MainActor
    func testWhenTabsToTheRightAreRemovedAndSelectionRemains_ThenSelectionIsCorrectlyUpdated() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.select(at: .unpinned(1))
        tabCollectionViewModel.removeTabs(after: 1)

        XCTAssertEqual(tabCollectionViewModel.selectionIndex?.item, 1)
    }

    @MainActor
    func testWhenLastTabIsRemoved_ThenSelectionIsNil() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        tabCollectionViewModel.remove(at: .unpinned(0))

        XCTAssertNil(tabCollectionViewModel.selectionIndex)
        XCTAssertEqual(tabCollectionViewModel.tabCollection.tabs.count, 0)
    }

    @MainActor
    func testWhenNoTabIsSelectedAndTabIsRemoved_ThenSelectionStaysEmpty() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.appendNewTab()

        // Clear selection
        tabCollectionViewModel.select(at: .unpinned(-1))

        tabCollectionViewModel.remove(at: .unpinned(1))

        XCTAssertNil(tabCollectionViewModel.selectionIndex)
    }

    @MainActor
    func testWhenChildTabIsInsertedAndRemovedAndThereIsAChildTabClose_ThenChildTabIsSelected() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        let parentTab = tabCollectionViewModel.tabCollection.tabs[0]
        let childTab1 = Tab(parentTab: parentTab)
        tabCollectionViewModel.append(tab: childTab1, selected: false)
        let childTab2 = Tab(parentTab: parentTab)
        tabCollectionViewModel.append(tab: childTab2, selected: true)

        tabCollectionViewModel.remove(at: .unpinned(2))

        XCTAssertEqual(tabCollectionViewModel.selectedTabViewModel?.tab, childTab1)
    }

    @MainActor
    func testWhenChildTabOnLeftHasTheSameParentAndTabOnRightDont_ThenTabOnLeftIsSelectedAfterRemoval() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        let parentTab = tabCollectionViewModel.tabCollection.tabs[0]
        let childTab1 = Tab(parentTab: parentTab)
        tabCollectionViewModel.append(tab: childTab1, selected: false)
        let childTab2 = Tab(parentTab: parentTab)
        tabCollectionViewModel.append(tab: childTab2, selected: true)
        tabCollectionViewModel.appendNewTab()

        // Select and remove childTab2
        tabCollectionViewModel.selectPrevious()
        tabCollectionViewModel.removeSelected()

        XCTAssertEqual(tabCollectionViewModel.selectedTabViewModel?.tab, childTab1)
    }

    @MainActor
    func testRemoveSelected() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()

        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.appendNewTab()
        let selectedTab = tabCollectionViewModel.selectedTabViewModel?.tab

        tabCollectionViewModel.removeSelected()

        XCTAssertFalse(tabCollectionViewModel.tabCollection.tabs.contains(selectedTab!))
    }

    // MARK: - Duplicate

    @MainActor
    func testWhenTabIsDuplicatedThenItsCopyHasHigherIndexByOne() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        let firstTabViewModel = tabCollectionViewModel.tabViewModel(at: 0)

        tabCollectionViewModel.duplicateTab(at: .unpinned(0))

        XCTAssert(firstTabViewModel === tabCollectionViewModel.tabViewModel(at: 0))
    }

    @MainActor
    func testWhenTabIsDuplicatedThenItsCopyHasTheSameUrl() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        let firstTabViewModel = tabCollectionViewModel.tabViewModel(at: 0)
        firstTabViewModel?.tab.setContent(.url(.duckDuckGo, source: .link))

        tabCollectionViewModel.duplicateTab(at: .unpinned(0))

        XCTAssertEqual(firstTabViewModel?.tab.url, tabCollectionViewModel.tabViewModel(at: 1)?.tab.url)
    }

    // MARK: - Publishers

    @MainActor
    func testWhenSelectionIndexIsUpdatedWithTheSameValueThenSelectedTabViewModelIsOnlyPublishedOnce() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        let firstTabViewModel = tabCollectionViewModel.tabViewModel(at: 0)
        firstTabViewModel?.tab.setContent(.url(.duckDuckGo, source: .link))

        var events: [TabViewModel?] = []
        let cancellable = tabCollectionViewModel.$selectedTabViewModel
            .sink { tabViewModel in
                events.append(tabViewModel)
            }

        tabCollectionViewModel.select(at: .unpinned(0))
        tabCollectionViewModel.select(at: .unpinned(0))
        tabCollectionViewModel.select(at: .unpinned(0))
        tabCollectionViewModel.select(at: .unpinned(0))

        cancellable.cancel()

        XCTAssertEqual(events.count, 1)
        XCTAssertIdentical(events[0], tabCollectionViewModel.selectedTabViewModel)
    }

    // MARK: - Bookmark All Open Tabs

    @MainActor
    func testWhenOneEmptyTabOpenThenCanBookmarkAllOpenTabsIsFalse() throws {
        // GIVEN
        let sut = TabCollectionViewModel.aTabCollectionViewModel()
        let firstTabViewModel = try XCTUnwrap(sut.tabViewModel(at: 0))
        XCTAssertEqual(sut.tabViewModels.count, 1)
        XCTAssertEqual(firstTabViewModel.tabContent, .newtab)

        // WHEN
        let result = sut.canBookmarkAllOpenTabs()

        // THEN
        XCTAssertFalse(result)
    }

    @MainActor
    func testWhenOneURLTabOpenThenCanBookmarkAllOpenTabsIsFalse() throws {
        // GIVEN
        let sut = TabCollectionViewModel.aTabCollectionViewModel()
        sut.replaceTab(at: .unpinned(0), with: .init(content: .url(.duckDuckGo, credential: nil, source: .ui)))
        let firstTabViewModel = try XCTUnwrap(sut.tabViewModel(at: 0))
        XCTAssertEqual(sut.tabViewModels.count, 1)
        XCTAssertEqual(firstTabViewModel.tabContent, .url(.duckDuckGo, credential: nil, source: .ui))

        // WHEN
        let result = sut.canBookmarkAllOpenTabs()

        // THEN
        XCTAssertFalse(result)
    }

    @MainActor
    func testWhenOneURLTabAndOnePinnedTabOpenThenCanBookmarkAllOpenTabsIsFalse() {
        // GIVEN
        let sut = TabCollectionViewModel.aTabCollectionViewModel()
        sut.replaceTab(at: .unpinned(0), with: .init(content: .url(.duckDuckGo, credential: nil, source: .ui)))
        sut.append(tab: .init(content: .url(.duckDuckGoEmail, credential: nil, source: .ui)))
        sut.pinTab(at: 0)
        XCTAssertEqual(sut.pinnedTabs.count, 1)
        XCTAssertEqual(sut.tabViewModels.count, 1)

        // WHEN
        let result = sut.canBookmarkAllOpenTabs()

        // THEN
        XCTAssertFalse(result)
    }

    @MainActor
    func testWhenAtLeastTwoURLTabsOpenThenCanBookmarkAllOpenTabsIsTrue() {
        // GIVEN
        let sut = TabCollectionViewModel.aTabCollectionViewModel()
        let pinnedTab = Tab(content: .url(.aboutDuckDuckGo, credential: nil, source: .ui))
        sut.append(tabs: [
            pinnedTab,
            .init(content: .url(.duckDuckGo, credential: nil, source: .ui)),
            .init(content: .newtab),
            .init(content: .bookmarks),
            .init(content: .anySettingsPane),
            .init(content: .url(.duckDuckGoEmail, credential: nil, source: .ui)),
        ], andSelect: true)
        sut.pinTab(at: 1)
        XCTAssertEqual(sut.pinnedTabs.count, 1)
        XCTAssertEqual(sut.tabViewModels.count, 6)
        XCTAssertEqual(sut.pinnedTabs.first, pinnedTab)
        XCTAssertNil(sut.tabViewModels[pinnedTab])

        // WHEN
        let result = sut.canBookmarkAllOpenTabs()

        // THEN
        XCTAssertTrue(result)
    }

    @MainActor
    func testWhenPreloaderIsSet_thenInsertOrAppendNewTabUsesPreloadedTab() {
        let viewModel = TabCollectionViewModel(tabCollection: TabCollection(), pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock())
        let preloader = MockNewTabPageTabPreloader()
        viewModel.newTabPageTabPreloader = preloader
        viewModel.insertOrAppendNewTab()
        XCTAssertTrue(preloader.didCallNewTab)
        XCTAssertIdentical(preloader.tabToReturn, viewModel.tabCollection.tabs.last!)
    }

    // MARK: - Popup behavior

    @MainActor
    func testPopupVMAppendNewTabRedirectsAndDoesNotGrowTabs() {
        let initialTab = Tab(content: .newtab)
        let tabCollection = TabCollection(tabs: [initialTab], isPopup: true)
        let windowControllersManager = WindowControllersManagerMock()
        let vm = TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManagerProvider: nil, windowControllersManager: windowControllersManager)

        vm.appendNewTab(with: .newtab, selected: true)

        XCTAssertEqual(vm.tabCollection.tabs, [initialTab], "Original tab should remain unchanged")
        XCTAssertEqual(windowControllersManager.showTabCalls, [])
        XCTAssertEqual(windowControllersManager.openCalls, [])
        XCTAssertEqual(windowControllersManager.openTabCalls, [])
        XCTAssertEqual(windowControllersManager.openWindowCalls, [
            .init(
                contents: [.newtab],
                burnerMode: .regular,
                droppingPoint: nil,
                contentSize: nil,
                showWindow: true,
                popUp: false,
                lazyLoadTabs: false,
                isMiniaturized: false,
                isMaximized: false,
                isFullscreen: false
            )
        ])
    }

    @MainActor
    func testPopupVMAppendNewUnselectedTabRedirectsAndDoesNotGrowTabs() {
        let initialTab = Tab(content: .newtab)
        let tabCollection = TabCollection(tabs: [initialTab], isPopup: true)
        let windowControllersManager = WindowControllersManagerMock()
        let vm = TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManagerProvider: nil, windowControllersManager: windowControllersManager)

        vm.appendNewTab(with: .settings(pane: .about), selected: false)

        XCTAssertEqual(vm.tabCollection.tabs, [initialTab], "Original tab should remain unchanged")
        XCTAssertEqual(windowControllersManager.showTabCalls, [])
        XCTAssertEqual(windowControllersManager.openCalls, [])
        XCTAssertEqual(windowControllersManager.openTabCalls, [])
        XCTAssertEqual(windowControllersManager.openWindowCalls, [
            .init(
                contents: [.settings(pane: .about)],
                burnerMode: .regular,
                droppingPoint: nil,
                contentSize: nil,
                showWindow: true,
                popUp: false,
                lazyLoadTabs: false,
                isMiniaturized: false,
                isMaximized: false,
                isFullscreen: false
            )
        ])
    }

    @MainActor
    func testPopupVM_WhenAppendingTabWithoutParent_OpensInNewWindow() {
        // Given: A popup window with a tab that has no parent
        let initialTab = Tab(content: .newtab)
        let tabCollection = TabCollection(tabs: [initialTab], isPopup: true)
        let windowControllersManager = WindowControllersManagerMock()
        let vm = TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManagerProvider: nil, windowControllersManager: windowControllersManager)

        // When: Trying to add a new tab
        let newTab = Tab(content: .url(.duckDuckGo, credential: nil, source: .ui))
        vm.append(tab: newTab, selected: true)

        // Then: The tab should be opened in a new window and not added to popup
        XCTAssertEqual(vm.tabCollection.tabs, [initialTab], "Original tab should remain unchanged")

        // Verify correct window manager calls
        XCTAssertEqual(windowControllersManager.showTabCalls, [])
        XCTAssertEqual(windowControllersManager.openCalls, [])
        XCTAssertEqual(windowControllersManager.openTabCalls, [])
        XCTAssertEqual(windowControllersManager.openWindowCalls, [
            .init(
                contents: [.url(.duckDuckGo, credential: nil, source: .ui)],
                burnerMode: .regular,
                droppingPoint: nil,
                contentSize: nil,
                showWindow: true,
                popUp: false,
                lazyLoadTabs: false,
                isMiniaturized: false,
                isMaximized: false,
                isFullscreen: false
            )
        ])
    }

    @MainActor
    func testPopupVM_WhenAppendingTabWithParent_OpensAfterParentTabInheritingBurnerMode() {
        // Given: A popup window with a tab that has a parent in burner mode
        let burnerMode = BurnerMode(isBurner: true)
        let parentTab = Tab(content: .url(.duckDuckGo, credential: nil, source: .ui), burnerMode: burnerMode)
        let initialTab = Tab(content: .newtab, parentTab: parentTab, burnerMode: burnerMode)
        let tabCollection = TabCollection(tabs: [initialTab], isPopup: true)
        let windowControllersManager = WindowControllersManagerMock()
        let vm = TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManagerProvider: nil, burnerMode: burnerMode, windowControllersManager: windowControllersManager)

        // When: Trying to add a new tab
        let newTab = Tab(content: .url(.duckDuckGoEmail, credential: nil, source: .ui), burnerMode: burnerMode)
        vm.append(tab: newTab, selected: true)

        // Then: The tab should be opened after the parent tab and not added to popup
        XCTAssertEqual(vm.tabCollection.tabs, [initialTab], "Original tab should remain unchanged")

        // Verify correct window manager calls
        XCTAssertEqual(windowControllersManager.showTabCalls, [])
        XCTAssertEqual(windowControllersManager.openCalls, [])
        XCTAssertEqual(windowControllersManager.openWindowCalls, [])
        XCTAssertEqual(windowControllersManager.openTabCalls, [
            .init(tab: newTab, parentTab: parentTab, selected: true)
        ])
    }

    @MainActor
    func testPopupVM_WhenAppendingNonBurnerTabFromBurnerPopUp_OpensNewWindowWithRegularMode() {
        // Given: A popup window with a tab that has a parent in burner mode
        let burnerMode = BurnerMode(isBurner: true)
        let parentTab = Tab(content: .url(.duckDuckGo, credential: nil, source: .ui), burnerMode: burnerMode)
        let initialTab = Tab(content: .newtab, parentTab: parentTab, burnerMode: burnerMode)
        let tabCollection = TabCollection(tabs: [initialTab], isPopup: true)
        let windowControllersManager = WindowControllersManagerMock()
        let vm = TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManagerProvider: nil, burnerMode: burnerMode, windowControllersManager: windowControllersManager)

        // When: Trying to add a new tab
        let newTab = Tab(content: .url(.duckDuckGoEmail, credential: nil, source: .ui))
        vm.append(tab: newTab, selected: true)

        // Then: The tab should be opened after the parent tab and not added to popup
        XCTAssertEqual(vm.tabCollection.tabs, [initialTab], "Original tab should remain unchanged")

        // Verify correct window manager calls
        XCTAssertEqual(windowControllersManager.showTabCalls, [])
        XCTAssertEqual(windowControllersManager.openCalls, [])
        XCTAssertEqual(windowControllersManager.openWindowCalls, [
            .init(
                contents: [newTab.content],
                burnerMode: .regular,
                droppingPoint: nil,
                contentSize: nil,
                showWindow: true,
                popUp: false,
                lazyLoadTabs: false,
                isMiniaturized: false,
                isMaximized: false,
                isFullscreen: false
            )
        ])
        XCTAssertEqual(windowControllersManager.openTabCalls, [])
    }

    @MainActor
    func testPopupVM_WhenAppendingMultipleTabsWithSameParent_OpensAllAfterParent() {
        // Given: A popup window with a tab that has a parent
        let parentTab = Tab(content: .url(.duckDuckGo, credential: nil, source: .ui))
        let initialTab = Tab(content: .newtab, parentTab: parentTab)
        let tabCollection = TabCollection(tabs: [initialTab], isPopup: true)
        let windowControllersManager = WindowControllersManagerMock()
        let vm = TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManagerProvider: nil, windowControllersManager: windowControllersManager)

        // When: Trying to add multiple tabs
        let tabs = [
            Tab(content: .url(.duckDuckGoEmail, credential: nil, source: .ui)),
            Tab(content: .url(.aboutDuckDuckGo, credential: nil, source: .ui)),
            Tab(content: .bookmarks)
        ]
        vm.append(tabs: tabs, andSelect: true)

        // Then: The tabs should be opened after the parent tab and not added to popup
        XCTAssertEqual(vm.tabCollection.tabs, [initialTab], "Original tab should remain unchanged")

        // Verify correct window manager calls
        XCTAssertEqual(windowControllersManager.showTabCalls, [])
        XCTAssertEqual(windowControllersManager.openCalls, [])
        XCTAssertEqual(windowControllersManager.openWindowCalls, [])
        XCTAssertEqual(windowControllersManager.openTabCalls, [
            .init(tab: tabs[0], parentTab: parentTab, selected: false),
            .init(tab: tabs[1], parentTab: parentTab, selected: false),
            .init(tab: tabs[2], parentTab: parentTab, selected: true),
        ])
    }

    @MainActor
    func testPopupVM_WhenAppendingTabsWithDifferentParents_OpensInCorrectLocations() {
        // Given: A popup window with a tab that has a parent
        let parentTab1 = Tab(content: .url(.duckDuckGo, credential: nil, source: .ui))
        let parentTab2 = Tab(content: .url(.aboutDuckDuckGo, credential: nil, source: .ui))
        let initialTab = Tab(content: .newtab, parentTab: parentTab1)
        let tabCollection = TabCollection(tabs: [initialTab], isPopup: true)
        let windowControllersManager = WindowControllersManagerMock()
        let vm = TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManagerProvider: nil, windowControllersManager: windowControllersManager)

        // When: Trying to add tabs with different parents and no parent
        let tabs = [
            Tab(content: .url(.duckDuckGoEmail, credential: nil, source: .ui), parentTab: parentTab1),
            Tab(content: .url(.aboutDuckDuckGo, credential: nil, source: .ui), parentTab: parentTab2),
            Tab(content: .bookmarks) // No parent
        ]
        vm.append(tabs: tabs, andSelect: true)

        // Then: The tabs should be opened in appropriate locations and not added to popup
        XCTAssertEqual(vm.tabCollection.tabs, [initialTab], "Original tab should remain unchanged")

        // Verify window manager calls
        XCTAssertEqual(windowControllersManager.showTabCalls, [])
        XCTAssertEqual(windowControllersManager.openCalls, [])
        XCTAssertEqual(windowControllersManager.openTabCalls, [
            .init(tab: tabs[0], parentTab: parentTab1, selected: false),
            .init(tab: tabs[1], parentTab: parentTab2, selected: false),
            .init(tab: tabs[2], parentTab: parentTab1, selected: true),
        ])
        XCTAssertEqual(windowControllersManager.openWindowCalls, [])
    }

    @MainActor
    func testPopupVM_WhenDuplicatingTab_OpensInCorrectLocation() {
        // Given: A popup window with a tab that has a parent
        let parentTab = Tab(content: .url(.duckDuckGo, credential: nil, source: .ui))
        let initialTab = Tab(content: .url(.duckDuckGoEmail, credential: nil, source: .ui), parentTab: parentTab)
        let tabCollection = TabCollection(tabs: [initialTab], isPopup: true)
        let windowControllersManager = WindowControllersManagerMock()
        let vm = TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManagerProvider: nil, windowControllersManager: windowControllersManager)

        // When: Trying to duplicate a tab
        vm.duplicateTab(at: .unpinned(0))

        // Then: The tab should be opened in the correct location and not added to popup
        XCTAssertEqual(vm.tabCollection.tabs, [initialTab], "Original tab should remain unchanged")

        // Verify window manager calls
        XCTAssertEqual(windowControllersManager.showTabCalls, [])
        XCTAssertEqual(windowControllersManager.openCalls, [])
        XCTAssertEqual(windowControllersManager.openTabCalls, [
            .init(tab: initialTab, parentTab: parentTab, selected: true)
        ])
        XCTAssertEqual(windowControllersManager.openWindowCalls, [])
    }

    @MainActor
    func testPopupVM_WhenInsertingNewTabAfterParent_OpensInCorrectLocationInheritingBurnerMode() throws {
        // Given: A popup window with a tab that has a parent in burner mode
        let burnerMode = BurnerMode(isBurner: true)
        let parentTab = Tab(content: .url(.duckDuckGo, credential: nil, source: .ui), burnerMode: burnerMode)
        let initialTab = Tab(content: .newtab, parentTab: parentTab, burnerMode: burnerMode)
        let tabCollection = TabCollection(tabs: [initialTab], isPopup: true)
        let windowControllersManager = WindowControllersManagerMock()
        let vm = TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManagerProvider: nil, burnerMode: burnerMode, windowControllersManager: windowControllersManager)

        // When: Trying to insert a new tab after parent
        vm.insertNewTab(after: parentTab, with: .url(.duckDuckGoEmail, credential: nil, source: .ui), selected: true)

        // Then: The tab should be opened in the correct location and not added to popup
        XCTAssertEqual(vm.tabCollection.tabs, [initialTab], "Original tab should remain unchanged")

        // Verify window manager calls
        XCTAssertEqual(windowControllersManager.showTabCalls, [])
        XCTAssertEqual(windowControllersManager.openCalls, [])

        let insertedTab = try XCTUnwrap(windowControllersManager.openTabCalls.first?.tab)
        XCTAssertNotEqual(insertedTab, initialTab)
        XCTAssertNotEqual(insertedTab, parentTab)

        XCTAssertEqual(insertedTab.content, .url(.duckDuckGoEmail, credential: nil, source: .ui))
        XCTAssertEqual(insertedTab.burnerMode, burnerMode)
        XCTAssertEqual(insertedTab.parentTab, nil)

        XCTAssertEqual(windowControllersManager.openTabCalls, [
            .init(tab: insertedTab, parentTab: parentTab, selected: true)
        ])
        XCTAssertEqual(windowControllersManager.openWindowCalls, [])
    }

    @MainActor
    func testPopupVM_WhenInsertingTabAtIndex_OpensInCorrectLocation() {
        // Given: A popup window with a tab that has a parent
        let parentTab = Tab(content: .url(.duckDuckGo, credential: nil, source: .ui))
        let initialTab = Tab(content: .newtab, parentTab: parentTab)
        let tabCollection = TabCollection(tabs: [initialTab], isPopup: true)
        let windowControllersManager = WindowControllersManagerMock()
        let vm = TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManagerProvider: nil, windowControllersManager: windowControllersManager)

        // When: Trying to insert a tab at index
        let newTab = Tab(content: .url(.duckDuckGoEmail, credential: nil, source: .ui), parentTab: parentTab)
        vm.insert(newTab, at: .unpinned(1), selected: true)

        // Then: The tab should be opened in the correct location and not added to popup
        XCTAssertEqual(vm.tabCollection.tabs, [initialTab], "Original tab should remain unchanged")

        // Verify window manager calls
        XCTAssertEqual(windowControllersManager.showTabCalls, [])
        XCTAssertEqual(windowControllersManager.openCalls, [])
        XCTAssertEqual(windowControllersManager.openTabCalls, [
            .init(tab: newTab, parentTab: parentTab, selected: true)
        ])
        XCTAssertEqual(windowControllersManager.openWindowCalls, [])
    }

    @MainActor
    func testPopupVM_WhenInsertingTabAfterParentTab_OpensInCorrectLocation() {
        // Given: A popup window with a tab that has a parent
        let parentTab = Tab(content: .url(.duckDuckGo, credential: nil, source: .ui))
        let initialTab = Tab(content: .newtab, parentTab: parentTab)
        let tabCollection = TabCollection(tabs: [initialTab], isPopup: true)
        let windowControllersManager = WindowControllersManagerMock()
        let vm = TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManagerProvider: nil, windowControllersManager: windowControllersManager)

        // When: Trying to insert a tab after parent
        let newTab = Tab(content: .url(.duckDuckGoEmail, credential: nil, source: .ui))
        vm.insert(newTab, after: parentTab, selected: true)

        // Then: The tab should be opened in the correct location and not added to popup
        XCTAssertEqual(vm.tabCollection.tabs, [initialTab], "Original tab should remain unchanged")

        // Verify window manager calls
        XCTAssertEqual(windowControllersManager.showTabCalls, [])
        XCTAssertEqual(windowControllersManager.openCalls, [])
        XCTAssertEqual(windowControllersManager.openTabCalls, [
            .init(tab: newTab, parentTab: parentTab, selected: true)
        ])
        XCTAssertEqual(windowControllersManager.openWindowCalls, [])
    }

    @MainActor
    func testPopupVM_WhenInsertingTabWithoutParent_OpensInNewWindowWithRegularBurnerMode() {
        // Given: A popup window with a tab that has no parent, in burner mode
        let burnerMode = BurnerMode(isBurner: true)
        let initialTab = Tab(content: .newtab, burnerMode: burnerMode)
        let tabCollection = TabCollection(tabs: [initialTab], isPopup: true)
        let windowControllersManager = WindowControllersManagerMock()
        let vm = TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManagerProvider: nil, burnerMode: burnerMode, windowControllersManager: windowControllersManager)

        // When: Trying to insert a tab without parent
        let newTab = Tab(content: .url(.duckDuckGoEmail, credential: nil, source: .ui))
        vm.insert(newTab, selected: true)

        // Then: The tab should be opened in a new window and not added to popup
        XCTAssertEqual(vm.tabCollection.tabs, [initialTab], "Original tab should remain unchanged")

        // Verify window manager calls
        XCTAssertEqual(windowControllersManager.showTabCalls, [])
        XCTAssertEqual(windowControllersManager.openCalls, [])
        XCTAssertEqual(windowControllersManager.openTabCalls, [])
        XCTAssertEqual(windowControllersManager.openWindowCalls, [
            .init(
                contents: [newTab.content],
                burnerMode: .regular,
                droppingPoint: nil,
                contentSize: nil,
                showWindow: true,
                popUp: false,
                lazyLoadTabs: false,
                isMiniaturized: false,
                isMaximized: false,
                isFullscreen: false
            )
        ])
    }

    @MainActor
    func testPopupVM_WhenInsertingBurnerTabWithoutParent_OpensInNewWindowWithCorrectBurnerMode() {
        // Given: A popup window with a tab that has no parent, in burner mode
        let burnerMode = BurnerMode(isBurner: true)
        let initialTab = Tab(content: .newtab, burnerMode: burnerMode)
        let tabCollection = TabCollection(tabs: [initialTab], isPopup: true)
        let windowControllersManager = WindowControllersManagerMock()
        let vm = TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManagerProvider: nil, burnerMode: burnerMode, windowControllersManager: windowControllersManager)

        // When: Trying to insert a tab without parent
        let newTab = Tab(content: .url(.duckDuckGoEmail, credential: nil, source: .ui), burnerMode: burnerMode)
        vm.insert(newTab, selected: true)

        // Then: The tab should be opened in a new window and not added to popup
        XCTAssertEqual(vm.tabCollection.tabs, [initialTab], "Original tab should remain unchanged")

        // Verify window manager calls
        XCTAssertEqual(windowControllersManager.showTabCalls, [])
        XCTAssertEqual(windowControllersManager.openCalls, [])
        XCTAssertEqual(windowControllersManager.openTabCalls, [])
        XCTAssertEqual(windowControllersManager.openWindowCalls, [
            .init(
                contents: [newTab.content],
                burnerMode: burnerMode,
                droppingPoint: nil,
                contentSize: nil,
                showWindow: true,
                popUp: false,
                lazyLoadTabs: false,
                isMiniaturized: false,
                isMaximized: false,
                isFullscreen: false
            )
        ])
    }

    @MainActor
    func testPopupVM_WhenInsertOrAppendNewTab_OpensInCorrectLocationInheritingBurnerMode() throws {
        // Given: A popup window with a tab that has a parent in burner mode
        let burnerMode = BurnerMode(isBurner: true)
        let parentTab = Tab(content: .url(.duckDuckGo, credential: nil, source: .ui), burnerMode: burnerMode)
        let initialTab = Tab(content: .newtab, parentTab: parentTab, burnerMode: burnerMode)
        let tabCollection = TabCollection(tabs: [initialTab], isPopup: true)
        let windowControllersManager = WindowControllersManagerMock()
        let vm = TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManagerProvider: nil, burnerMode: burnerMode, windowControllersManager: windowControllersManager)

        // When: Trying to insert or append a new tab
        vm.insertOrAppendNewTab()

        // Then: The tab should be opened in the correct location and not added to popup
        XCTAssertEqual(vm.tabCollection.tabs, [initialTab], "Original tab should remain unchanged")

        // Verify window manager calls
        XCTAssertEqual(windowControllersManager.showTabCalls, [])
        XCTAssertEqual(windowControllersManager.openCalls, [])

        let insertedTab = try XCTUnwrap(windowControllersManager.openTabCalls.first?.tab)
        XCTAssertNotEqual(insertedTab, initialTab)
        XCTAssertNotEqual(insertedTab, parentTab)

        XCTAssertEqual(insertedTab.content, .newtab)
        XCTAssertEqual(insertedTab.burnerMode, burnerMode)
        XCTAssertEqual(insertedTab.parentTab, nil)

        XCTAssertEqual(windowControllersManager.openTabCalls, [
            .init(tab: insertedTab, parentTab: parentTab, selected: true)
        ])
        XCTAssertEqual(windowControllersManager.openWindowCalls, [])
    }

    @MainActor
    func testPopupVM_WhenAppendingTabsWithDifferentBurnerModes_OpensInCorrectLocations() {
        // Given: A popup window with a tab that has a parent in burner mode
        let burnerMode1 = BurnerMode(isBurner: true)
        let burnerMode2 = BurnerMode(isBurner: true)
        let burnerMode3 = BurnerMode(isBurner: true)
        let parentTab1 = Tab(content: .url(.duckDuckGo, credential: nil, source: .ui), burnerMode: burnerMode1)
        let parentTab2 = Tab(content: .url(.aboutDuckDuckGo, credential: nil, source: .ui), burnerMode: burnerMode2)
        let initialTab = Tab(content: .newtab, parentTab: parentTab1, burnerMode: burnerMode1)
        let tabCollection = TabCollection(tabs: [initialTab], isPopup: true)
        let windowControllersManager = WindowControllersManagerMock()
        let vm = TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManagerProvider: nil, burnerMode: burnerMode1, windowControllersManager: windowControllersManager)

        // When: Trying to add tabs with different parents and burner modes
        let tabs = [
            Tab(content: .url(.duckDuckGoEmail, credential: nil, source: .ui), parentTab: parentTab1, burnerMode: burnerMode1),
            Tab(content: .url(.aboutDuckDuckGo, credential: nil, source: .ui), parentTab: parentTab2, burnerMode: burnerMode2),
            Tab(content: .url(.duckDuckGoAutocomplete, credential: nil, source: .ui), parentTab: parentTab2, burnerMode: burnerMode3),
            Tab(content: .url(.duckDuckGoEmailLogin, credential: nil, source: .ui), parentTab: parentTab2, burnerMode: .regular),
        ]
        vm.append(tabs: tabs, andSelect: true)

        // Then: The tabs should be opened in appropriate locations and not added to popup
        XCTAssertEqual(vm.tabCollection.tabs, [initialTab], "Original tab should remain unchanged")

        // Verify window manager calls
        XCTAssertEqual(windowControllersManager.showTabCalls, [])
        XCTAssertEqual(windowControllersManager.openCalls, [])
        XCTAssertEqual(windowControllersManager.openTabCalls, [
            .init(tab: tabs[0], parentTab: parentTab1, selected: false),
            .init(tab: tabs[1], parentTab: parentTab2, selected: false),
        ])
        XCTAssertEqual(windowControllersManager.openWindowCalls, [
            .init(
                contents: [.url(.duckDuckGoAutocomplete, credential: nil, source: .ui)],
                burnerMode: burnerMode3,
                droppingPoint: nil,
                contentSize: nil,
                showWindow: true,
                popUp: false,
                lazyLoadTabs: false,
                isMiniaturized: false,
                isMaximized: false,
                isFullscreen: false
            ),
            .init(
                contents: [.url(.duckDuckGoEmailLogin, credential: nil, source: .ui)],
                burnerMode: .regular,
                droppingPoint: nil,
                contentSize: nil,
                showWindow: true,
                popUp: false,
                lazyLoadTabs: false,
                isMiniaturized: false,
                isMaximized: false,
                isFullscreen: false
            ),
        ])
    }

    @MainActor
    func testPopupVM_WhenInsertOrAppendingTabWithParent_OpensInCorrectLocationInheritingBurnerMode() {
        // Given: A popup window with a tab that has a parent in burner mode
        let burnerMode = BurnerMode(isBurner: true)
        let parentTab = Tab(content: .url(.duckDuckGo, credential: nil, source: .ui), burnerMode: burnerMode)
        let initialTab = Tab(content: .newtab, parentTab: parentTab, burnerMode: burnerMode)
        let tabCollection = TabCollection(tabs: [initialTab], isPopup: true)
        let windowControllersManager = WindowControllersManagerMock()
        let vm = TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManagerProvider: nil, burnerMode: burnerMode, windowControllersManager: windowControllersManager)

        // When: Trying to insert or append a tab with parent
        let newTab = Tab(content: .url(.duckDuckGoEmail, credential: nil, source: .ui), parentTab: parentTab, burnerMode: burnerMode)
        vm.insertOrAppend(tab: newTab, selected: true)

        // Then: The tab should be opened in the correct location and not added to popup
        XCTAssertEqual(vm.tabCollection.tabs, [initialTab], "Original tab should remain unchanged")

        // Verify window manager calls
        XCTAssertEqual(windowControllersManager.showTabCalls, [])
        XCTAssertEqual(windowControllersManager.openCalls, [])
        XCTAssertEqual(windowControllersManager.openTabCalls, [
            .init(tab: newTab, parentTab: parentTab, selected: true)
        ])
        XCTAssertEqual(windowControllersManager.openWindowCalls, [])
    }
}

fileprivate extension TabCollectionViewModel {

    static func aTabCollectionViewModel() -> TabCollectionViewModel {
        let tabCollection = TabCollection()
        let provider = PinnedTabsManagerProvidingMock()
        return TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManagerProvider: provider)
    }
}

private extension Tab {
    @MainActor
    convenience init(parentTab: Tab? = nil) {
        self.init(content: .none, parentTab: parentTab)
    }
}
