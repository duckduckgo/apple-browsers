//
//  TabsModelTests.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

@testable import DuckDuckGo
@testable import Core

class TabsModelTests: XCTestCase {

    private let exampleLink = Link(title: nil, url: URL(string: "https://example.com")!)

    private var emptyModel: TabsModel {
        return TabsModel(desktop: false)
    }

    private var singleModel: TabsModel {
        let model = TabsModel(tabs: [
            Tab(link: exampleLink)
        ], desktop: false)
        return model
    }

    private var filledModel: TabsModel {
        let model = TabsModel(tabs: [
            Tab(link: Link(title: "url1", url: URL(string: "https://ur1l.com")!)),
            Tab(link: Link(title: "url2", url: URL(string: "https://ur12.com")!)),
            Tab(link: Link(title: "url3", url: URL(string: "https://ur13.com")!))
        ], desktop: false)
        return model
    }

    func testWhenBulkRemovingAllThenAllTabsAreRemoved() {
        let model = filledModel
        model.removeTabs(model.tabs)
        XCTAssertEqual(model.tabs, [])
    }

    func testWhenBulkRemovingSubsetThenSetTabsAreRemovedAndIndexUpdated() {
        let model = filledModel
        model.select(tab: model.tabs[1])
        let tabToRemove = model.tabs[0]
        model.removeTabs([tabToRemove])
        XCTAssertEqual(model.tabs.count, 2)
        XCTAssertEqual(model.currentIndex, 0)
    }

    func testWhenAtLeastOneTabIsNotViewedThenHasUnreadIsTrue() {
        let tab = Tab(link: exampleLink, viewed: false)
        
        let model = filledModel
        model.insert(tab: tab, placement: .afterCurrentTab, selectNewTab: false)

        XCTAssertTrue(model.hasUnread)
    }
    
    func testWhenTabInsertedAfterCurrentThenInsertedAtCorrectLocation() {

        let model = filledModel
        model.insert(tab: Tab(link: exampleLink), placement: .afterCurrentTab, selectNewTab: false)

        XCTAssertNotNil(model.tabs[0].link)
        XCTAssertEqual("https://example.com", model.tabs[1].link?.url.absoluteString)
        XCTAssertNotNil(model.tabs[2].link)
        XCTAssertNotNil(model.tabs[3].link)

    }

    func testWhenTabsAddedViewedIsFalse() {
        XCTAssertFalse(filledModel.tabs[0].viewed)
    }

    func testWhenModelIsNewThenContainsHomeTab() {
        XCTAssertEqual(TabsModel(desktop: false).count, 1)
        XCTAssertNil(TabsModel(desktop: false).get(tabAt: 0)?.link)
        XCTAssertEqual(TabsModel(desktop: false).currentIndex, 0)
    }

    func testWhenTabMovedToInvalidPositionNoChangeMadeToCurrentIndex() {
        let testee = filledModel
        let tab = testee.tabs[1]
        testee.select(tab: tab)
        testee.move(tab: tab, to: 3)
        XCTAssertEqual(1, testee.currentIndex)
        testee.move(tab: tab, to: -1)
        XCTAssertEqual(1, testee.currentIndex)
    }
    
    func testWhenTabMovedToStartOfListThenCurrentIndexUpdatedCorrectly() {
        let testee = filledModel
        let tab = testee.tabs[1]
        testee.select(tab: tab)
        
        testee.move(tab: tab, to: 0)
        XCTAssertEqual(0, testee.currentIndex)
    }

    func testWhenTabMovedToEndOfListThenCurrentIndexUpdatedCorrectly() {
        let testee = filledModel
        let tab = testee.tabs[1]
        testee.select(tab: tab)
        
        testee.move(tab: tab, to: 2)
        XCTAssertEqual(2, testee.currentIndex)
    }

    func testWhenTabExistsThenIndexReturned() {
        let tab = Tab(link: Link(title: nil, url: URL(string: "https://www.example.com")!))
        let testee = filledModel
        testee.insert(tab: tab, placement: .atEnd, selectNewTab: true)
        XCTAssertEqual(testee.indexOf(tab: tab), 3)
    }

    func testWhenTabDoesNotExistThenIndexIsNil() {
        let tab = Tab(link: nil)
        let testee = filledModel
        XCTAssertNil(testee.indexOf(tab: tab))
    }

    func testWhenFirstItemAddedThenCountIsOneAndCurrentIndexIsZero() {
        let testee = emptyModel
        testee.insert(tab: Tab(link: exampleLink), placement: .atEnd, selectNewTab: true)
        XCTAssertEqual(testee.count, 2)
        XCTAssertEqual(testee.currentIndex, 1)
    }

    func testWhenAdditionalItemAddedThenCountIsIncrementedAndCurrentIsSetToNewIndex() {
        let testee = filledModel
        XCTAssertEqual(testee.count, 3)
        XCTAssertEqual(testee.currentIndex, 0)
        testee.insert(tab: Tab(link: exampleLink), placement: .atEnd, selectNewTab: true)
        XCTAssertEqual(testee.count, 4)
        XCTAssertEqual(testee.currentIndex, 3)
    }

    func testWhenItemRemovedThenCountDecrements() {
        let testee = filledModel
        XCTAssertEqual(testee.count, 3)
        let tab = testee.tabs[0]
        testee.remove(tab: tab)
        XCTAssertEqual(testee.count, 2)
    }

    func testWhenFinalItemRemovedThenHomeTabRemains() {
        let testee = singleModel
        let tab = testee.tabs[0]
        testee.remove(tab: tab)
        XCTAssertEqual(testee.count, 1)
        XCTAssertNil(testee.get(tabAt: 0)?.link)
    }

    func testWhenOnlyHomeTabThenNoActiveTabs() {
        let testee = emptyModel
        XCTAssertFalse(testee.hasActiveTabs)
    }

    func testWhenOneOrMoreActiveTabsThenHasActiveTabs() {
        let testee = singleModel
        XCTAssertTrue(testee.hasActiveTabs)
    }

    func testWhenPreviousItemRemovedThenCurrentIndexDecrements() {
        let testee = filledModel
        testee.select(tab: testee.tabs[2])
        let tabToRemove = testee.tabs[0]
        testee.remove(tab: tabToRemove)
        XCTAssertEqual(testee.currentIndex, 1)
    }

    func testWhenLaterItemRemovedThenCurrentIndexStaysTheSame() {
        let testee = filledModel
        testee.select(tab: testee.tabs[0])
        let tabToRemove = testee.tabs[2]
        testee.remove(tab: tabToRemove)
        XCTAssertEqual(testee.currentIndex, 0)
    }

    func testWhenCurrentIsFirstItemAndItIsRemovedThenCurrentIsZero() {
        let testee = filledModel
        testee.select(tab: testee.tabs[0])
        let tabToRemove = testee.tabs[0]
        testee.remove(tab: tabToRemove)
        XCTAssertEqual(testee.currentIndex, 0)
    }

    func testWhenLastIsRemovedThenHomeTabCreated() {
        let testee = singleModel
        let tab = testee.tabs[0]
        testee.remove(tab: tab)
        XCTAssertEqual(1, testee.count)
        XCTAssertEqual(0, testee.currentIndex)
    }
    
    func testWhenTabExistsThenReturnTrue() throws {
        let currentHost = try XCTUnwrap(filledModel.tabs[1].link?.url.host)
        XCTAssertTrue(filledModel.tabExists(withHost: currentHost))
        XCTAssertFalse(filledModel.tabExists(withHost: "domaindoesnotexist"))
    }

    func testWhenNormalModeClearAllThenHomeTabRemains() {
        let model = filledModel
        model.clearAll()
        XCTAssertEqual(model.count, 1)
        XCTAssertNil(model.get(tabAt: 0)?.link)
    }

    // MARK: - Insert afterCurrentTab

    func testWhenCurrentIsLastThenAfterCurrentTabInsertsAtEnd() {
        let testee = filledModel
        testee.select(tab: testee.tabs[2])
        let newTab = Tab(link: exampleLink)
        testee.insert(tab: newTab, placement: .afterCurrentTab, selectNewTab: false)
        XCTAssertTrue(testee.tabs[3] === newTab)
        XCTAssertEqual(testee.count, 4)
    }

    func testWhenInsertAfterCurrentWithSelectThenCurrentIndexMovesToNewTab() {
        let testee = filledModel
        testee.select(tab: testee.tabs[0])
        let newTab = Tab(link: exampleLink)
        testee.insert(tab: newTab, placement: .afterCurrentTab, selectNewTab: true)
        XCTAssertEqual(testee.currentIndex, 1)
        XCTAssertTrue(testee.currentTab === newTab)
    }

    // MARK: - Insert replacing

    func testWhenReplacingThenNewTabTakesOldTabIndex() {
        let testee = filledModel
        let oldTab = testee.tabs[1]
        let newTab = Tab(link: exampleLink)
        testee.insert(tab: newTab, placement: .replacing(oldTab), selectNewTab: false)
        XCTAssertTrue(testee.tabs[1] === newTab)
        XCTAssertEqual(testee.count, 3)
        XCTAssertNil(testee.indexOf(tab: oldTab))
    }

    func testWhenReplacingNonCurrentTabThenSelectionIsPreserved() {
        let testee = filledModel
        let selectedTab = testee.tabs[0]
        testee.select(tab: selectedTab)
        let oldTab = testee.tabs[2]
        let newTab = Tab(link: exampleLink)
        testee.insert(tab: newTab, placement: .replacing(oldTab), selectNewTab: false)
        XCTAssertTrue(testee.currentTab === selectedTab)
        XCTAssertEqual(testee.currentIndex, 0)
    }

    func testWhenReplacingNonExistentTabThenNoChange() {
        let testee = filledModel
        let orphanTab = Tab(link: exampleLink)
        let newTab = Tab(link: exampleLink)
        let originalCount = testee.count
        testee.insert(tab: newTab, placement: .replacing(orphanTab), selectNewTab: true)
        XCTAssertEqual(testee.count, originalCount)
        XCTAssertNil(testee.indexOf(tab: newTab))
    }

    // MARK: - nextTab / previousTab / tabBefore

    func testWhenCurrentIsLastThenNextTabWrapsToFirst() {
        let testee = filledModel
        testee.select(tab: testee.tabs[2])
        XCTAssertTrue(testee.nextTab === testee.tabs[0])
    }

    func testWhenCurrentIsFirstThenPreviousTabWrapsToLast() {
        let testee = filledModel
        testee.select(tab: testee.tabs[0])
        XCTAssertTrue(testee.previousTab === testee.tabs[2])
    }

    func testWhenCurrentIsNotFirstThenTabBeforeReturnsPrevious() {
        let testee = filledModel
        let expectedTab = testee.tabs[1]
        testee.select(tab: testee.tabs[2])
        XCTAssertTrue(testee.tabBefore === expectedTab)
    }

    func testWhenCurrentIsFirstThenTabBeforeReturnsNil() {
        let testee = filledModel
        testee.select(tab: testee.tabs[0])
        XCTAssertNil(testee.tabBefore)
    }

    // MARK: - select / tabExists

    func testWhenSelectingNonExistentTabThenCurrentIndexUnchanged() {
        let testee = filledModel
        testee.select(tab: testee.tabs[1])
        let orphanTab = Tab(link: exampleLink)
        testee.select(tab: orphanTab)
        XCTAssertEqual(testee.currentIndex, 1)
    }

    func testWhenTabExistsInModelThenTabExistsReturnsTrue() {
        let testee = filledModel
        let tab = testee.tabs[1]
        XCTAssertTrue(testee.tabExists(tab: tab))
        XCTAssertFalse(testee.tabExists(tab: Tab(link: exampleLink)))
    }

}
