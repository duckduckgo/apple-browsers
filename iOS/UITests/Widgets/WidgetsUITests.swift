//
//  WidgetsUITests.swift
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

import XCTest
import UITestingSupport

final class WidgetsUITests: UITestCase {

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let timeout = UITestTimeouts.navigation

    private let customShortcuts = "Custom Shortcuts"
    private let galleryPages = ["Custom Shortcuts", "Custom Shortcuts", "Search and Favorites", "Search and Favorites",
                                "Search Passwords", "VPN", "Search"]

    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_DISABLE_ANIMATIONS": "1"]
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        app.resetBookmarks()
    }

    func testWhenWidgetGalleryIsOpenedThenEveryDuckDuckGoWidgetIsListed() {
        openWidgetGallery()
        for (index, title) in galleryPages.enumerated() {
            XCTAssertTrue(springboard.staticTexts[title].waitForExistence(timeout: timeout),
                          "Widget gallery page \(index + 1) is not \(title).")
            if index < galleryPages.count - 1 {
                springboard.swipeLeft()
            }
        }
        closeWidgetGallery()
    }

    func testWhenSearchWidgetIsTappedThenAppOpensReadyToSearch() throws {
        let site = try localWebsite()
        site.open(.first, in: app)

        addWidget(onGalleryPage: 0)
        tapSearchBar(ofWidgetNamed: customShortcuts)

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout), "The widget did not open the app.")
        site.open(.second, in: app)
        app.openTabSwitcher()
        app.assertTabCount(2)
    }

    func testWhenFavoriteIsSavedThenFavoritesWidgetShowsIt() throws {
        let site = try localWebsite()

        addWidget(onGalleryPage: 2)
        XCTAssertTrue(springboard.staticTexts["Add Favorites"].waitForExistence(timeout: timeout),
                      "The empty favorites widget does not prompt to add favorites.")

        app.activate()
        site.open(.first, in: app)
        app.openBrowsingMenuItem("Browser.Menu.AddFavorite")

        goToFirstHomeScreenPage()
        let favorite = springboard.descendants(matching: .any)[LocalUITestWebsite.Page.first.title]
        XCTAssertTrue(favorite.waitForExistence(timeout: timeout), "The favorites widget does not show the new favorite.")
        XCTAssertFalse(springboard.staticTexts["Add Favorites"].exists)
    }

    private var duckDuckGoWidget: XCUIElement {
        let predicate = NSPredicate(format: "label == %@ AND elementType != %d", "DuckDuckGo", XCUIElement.ElementType.icon.rawValue)
        return springboard.descendants(matching: .any).matching(predicate).firstMatch
    }

    private func goToFirstHomeScreenPage() {
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: timeout))
        XCUIDevice.shared.press(.home)
    }

    private func openWidgetGallery() {
        goToFirstHomeScreenPage()
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.5)
        let editHomeScreen = springboard.buttons["Edit Home Screen"]
        if editHomeScreen.waitForExistence(timeout: UITestTimeouts.elementExistence) {
            editHomeScreen.tap()
        }
        springboard.buttons["Edit"].tapWhenHittable(in: springboard)
        springboard.buttons["Add Widget"].tapWhenHittable(in: springboard)
        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: timeout))
        search.tap()
        search.typeText("DuckDuckGo")
        let result = springboard.cells.containing(.staticText, identifier: "DuckDuckGo").firstMatch
        result.tapWhenHittable(in: springboard)
    }

    private func closeWidgetGallery() {
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.press(.home)
    }

    private func addWidget(onGalleryPage page: Int) {
        openWidgetGallery()
        XCTAssertTrue(springboard.staticTexts[galleryPages[0]].waitForExistence(timeout: timeout))
        for index in stride(from: 1, through: page, by: 1) {
            springboard.swipeLeft()
            XCTAssertTrue(springboard.staticTexts[galleryPages[index]].waitForExistence(timeout: timeout),
                          "Widget gallery page \(index + 1) is not \(galleryPages[index]).")
        }
        let add = springboard.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Add Widget")).firstMatch
        add.tapWhenHittable(in: springboard)
        springboard.buttons["Done"].tapWhenHittable(in: springboard)
    }

    private func tapSearchBar(ofWidgetNamed name: String) {
        let widget = duckDuckGoWidget
        XCTAssertTrue(widget.waitForExistence(timeout: timeout), "The \(name) widget is not on the home screen.")
        widget.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
    }
}
