//
//  TextZoomTests.swift
//  DuckDuckGo
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

import Foundation
@testable import DuckDuckGo
import BrowserServicesKit
import Core
import XCTest
import WebKit

final class TextZoomTests: XCTestCase {

    let viewScaleKey = "viewScale"

    func testZoomLevelAppliedToWebView() {
        let storage = TextZoomStorage()
        storage.textZoomLevels = [:]

        let coordinator: TextZoomCoordinating = makeTextZoomCoordinator(storage: storage)
        let webView = URLFixedWebView(frame: .zero, configuration: .nonPersistent())

        webView.setValue(0.1, forKey: viewScaleKey)
        coordinator.onNavigationCommitted(applyToWebView: webView)
        XCTAssertEqual(1.0, webView.value(forKey: viewScaleKey) as? Double)

        webView.setValue(0.1, forKey: viewScaleKey)
        coordinator.onTextZoomChange(applyToWebView: webView)
        XCTAssertEqual(1.0, webView.value(forKey: viewScaleKey) as? Double)

        webView.setValue(0.1, forKey: viewScaleKey)
        coordinator.onWebViewCreated(applyToWebView: webView)
        XCTAssertEqual(1.0, webView.value(forKey: viewScaleKey) as? Double)

        let host = "example.com"
        webView.fixed = URL(string: "https://\(host)")
        coordinator.set(textZoomLevel: .percent120, forHost: host)

        webView.setValue(0.1, forKey: viewScaleKey)
        coordinator.onNavigationCommitted(applyToWebView: webView)
        XCTAssertEqual(1.2, webView.value(forKey: viewScaleKey) as? Double)

        webView.setValue(0.1, forKey: viewScaleKey)
        coordinator.onTextZoomChange(applyToWebView: webView)
        XCTAssertEqual(1.2, webView.value(forKey: viewScaleKey) as? Double)

        webView.setValue(0.1, forKey: viewScaleKey)
        coordinator.onWebViewCreated(applyToWebView: webView)
        XCTAssertEqual(1.2, webView.value(forKey: viewScaleKey) as? Double)

        // When reset to the default then "forget"
        coordinator.set(textZoomLevel: .percent100, forHost: host)
        XCTAssertEqual(storage.textZoomLevels, [:])
    }

    func testMenuItemCreation() {
        let host = "example.com"

        let storage = TextZoomStorage()
        storage.textZoomLevels = [:]

        let coordinator: TextZoomCoordinating = makeTextZoomCoordinator(storage: storage)
        coordinator.set(textZoomLevel: .percent120, forHost: host)

        let controller = UIViewController()
        let webView = WKWebView(frame: .zero, configuration: .nonPersistent())

        let item1 = coordinator.makeBrowsingMenuEntry(
            forLink: makeLink(url: URL(string: "https://other.org")!),
            inController: controller,
            forWebView: webView,
            useSmallIcon: true,
            percentageInDetail: false)

        // Expecting the 'default' value
        if case .regular(let name, _, _, _, _, _, _) = item1 {
            XCTAssertEqual(UserText.textZoomMenuItem, name)
        } else {
            XCTFail("Unexpected menu item type")
        }

        let item2 = coordinator.makeBrowsingMenuEntry(
            forLink: makeLink(url: URL(string: "https://\(host)")!),
            inController: controller,
            forWebView: webView,
            useSmallIcon: true,
            percentageInDetail: false)

        // Expecting the menu item to include the percent
        if case .regular(let name, _, _, _, _, _, _) = item2 {
            XCTAssertEqual(UserText.textZoomWithPercentForMenuItem(120), name)
        } else {
            XCTFail("Unexpected menu item type")
        }

    }

    func testSettingAndResetingDomainTextZoomLevels() {
        let host1 = "example.com"
        let host2 = "another.org"

        let storage = TextZoomStorage()
        storage.textZoomLevels = [:]

        let coordinator: TextZoomCoordinating = makeTextZoomCoordinator(storage: storage)
        coordinator.set(textZoomLevel: .percent120, forHost: host1)
        XCTAssertEqual(coordinator.textZoomLevel(forHost: host1), .percent120)

        coordinator.set(textZoomLevel: .percent140, forHost: host2)
        XCTAssertEqual(coordinator.textZoomLevel(forHost: host2), .percent140)

        coordinator.resetTextZoomLevels(excludingDomains: [host1])
        XCTAssertEqual(coordinator.textZoomLevel(forHost: host1), .percent120)
        XCTAssertEqual(coordinator.textZoomLevel(forHost: host2), AppSettingsMock().defaultTextZoomLevel)
    }

    func testResetTextZoomLevelsForVisitedDomains_ClearsSpecifiedDomains() {
        let host1 = "example.com"
        let host2 = "another.org"

        let storage = TextZoomStorage()
        storage.textZoomLevels = [:]

        let coordinator: TextZoomCoordinating = makeTextZoomCoordinator(storage: storage)
        coordinator.set(textZoomLevel: .percent120, forHost: host1)
        coordinator.set(textZoomLevel: .percent140, forHost: host2)

        coordinator.resetTextZoomLevels(forVisitedDomains: [host1], excludingDomains: [])

        XCTAssertEqual(coordinator.textZoomLevel(forHost: host1), AppSettingsMock().defaultTextZoomLevel)
        XCTAssertEqual(coordinator.textZoomLevel(forHost: host2), .percent140)
    }

    func testResetTextZoomLevelsForVisitedDomains_SubdomainClearsETLDplus1() {
        let storage = TextZoomStorage()
        storage.textZoomLevels = [:]

        let coordinator: TextZoomCoordinating = makeTextZoomCoordinator(storage: storage)
        coordinator.set(textZoomLevel: .percent120, forHost: "example.com")

        // Passing a subdomain should clear the eTLD+1 stored value
        coordinator.resetTextZoomLevels(forVisitedDomains: ["www.example.com"], excludingDomains: [])

        XCTAssertEqual(coordinator.textZoomLevel(forHost: "example.com"), AppSettingsMock().defaultTextZoomLevel)
    }

    func testResetTextZoomLevelsForVisitedDomains_WhenSubdomainVisitedAndRootExcluded_ThenNotCleared() {
        // Given - amazon.com is excluded (fireproofed), stored text zoom for amazon.com
        let storage = TextZoomStorage()
        storage.textZoomLevels = ["amazon.com": TextZoomLevel.percent120.rawValue]

        // When - Visit mail.amazon.com (subdomain), exclude amazon.com
        storage.resetTextZoomLevels(forVisitedDomains: ["mail.amazon.com"], excludingDomains: ["amazon.com"])

        // Then - amazon.com text zoom should be preserved (excluded)
        XCTAssertEqual(storage.textZoomLevelForDomain("amazon.com"), .percent120)
    }

    private func makeTextZoomCoordinator(
        appSettings: AppSettings = AppSettingsMock(),
        storage: TextZoomStoring = MockTextZoomStorage()
    ) -> TextZoomCoordinating {
        return TextZoomCoordinator(appSettings: appSettings,
                                   storage: storage)
    }

    private func makeLink(title: String? = "title", url: URL = .ddg, localPath: URL? = nil) -> Link {
        return Link(title: title, url: url, localPath: localPath)
    }

}

/// Nothing else should be using storage directly so just keeping it here out of the way.
private class MockTextZoomStorage: TextZoomStoring {

    func textZoomLevelForDomain(_ domain: String) -> DuckDuckGo.TextZoomLevel? {
        return nil
    }
    
    func set(textZoomLevel: DuckDuckGo.TextZoomLevel, forDomain domain: String) {
    }
    
    func removeTextZoomLevel(forDomain domain: String) {
    }
    
    func resetTextZoomLevels(excludingDomains: [String]) {
    }

    func resetTextZoomLevels(forVisitedDomains visitedDomains: [String], excludingDomains: [String]) {
    }

}

private class URLFixedWebView: WKWebView {

    var fixed: URL?

    override var url: URL? {
        fixed
    }

}
