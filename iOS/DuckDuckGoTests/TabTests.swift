//
//  TabTests.swift
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
import AIChat

@testable import Core
@testable import DuckDuckGo

class TabTests: XCTestCase {

    struct Constants {
        static let title = "A title"
        static let url = URL(string: "https://example.com")!
        static let differentUrl = URL(string: "https://aDifferentUrl.com")!
    }

    func testWhenDesktopPropertyChangesThenObserversNotified() {
        let observer = MockTabObserver()

        let tab = Tab(link: link())
        tab.addObserver(observer)
        tab.isDesktop = true

        XCTAssertNotNil(observer.didChangeTab)

    }

    func testWhenDesktopModeToggledThenPropertyIsUpdated() {
        _ = AppWidthObserver.shared.willResize(toWidth: UIScreen.main.bounds.width)

        let tab = Tab(link: link())

        if AppWidthObserver.shared.isLargeWidth {
            XCTAssertTrue(tab.isDesktop)
            tab.toggleDesktopMode()
            XCTAssertFalse(tab.isDesktop)
            tab.toggleDesktopMode()
            XCTAssertTrue(tab.isDesktop)
        } else {
            XCTAssertFalse(tab.isDesktop)
            tab.toggleDesktopMode()
            XCTAssertTrue(tab.isDesktop)
            tab.toggleDesktopMode()
            XCTAssertFalse(tab.isDesktop)
        }
    }

    func testWhenEncodedWithDesktopPropertyThenDecodesSuccessfully() {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: Tab(link: link(), viewed: false, desktop: true),
                                                           requiringSecureCoding: false) else {
            XCTFail("Data is nil")
            return
        }
        XCTAssertFalse(data.isEmpty)

        let tab = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? Tab
        
        XCTAssertNotNil(tab?.link)
        XCTAssertFalse(tab?.viewed ?? true)
        XCTAssertTrue(tab?.isDesktop ?? false)
    }

    /// This test supports the migration scenario where desktop was not a property of tab
    func testWhenEncodedWithoutDesktopPropertyThenDecodesSuccessfully() {
        let tab = Tab(coder: CoderStub(properties: ["link": link(), "viewed": false]))
        XCTAssertNotNil(tab?.link)
        XCTAssertFalse(tab?.viewed ?? true)
        XCTAssertFalse(tab?.isDesktop ?? true)
    }
    
    func testWhenTabObserverIsOutOfScopeThenUpdatesAreSuccessful() {
        var observer: MockTabObserver? = MockTabObserver()
        let tab = Tab(link: link())
        tab.addObserver(observer!)
        observer = nil
        tab.viewed = true
        XCTAssertTrue(tab.viewed)
    }
    
    func testWhenTabLinkChangesThenObserversAreNotified() {
        let observer = MockTabObserver()
        
        let tab = Tab(link: link())
        tab.addObserver(observer)
        tab.link = Link(title: nil, url: Constants.url)

        XCTAssertNotNil(observer.didChangeTab)
    }

    func testWhenTabViewedChangesThenObserversAreNotified() {
        let observer = MockTabObserver()
        
        let tab = Tab(link: link())
        tab.addObserver(observer)
        tab.viewed = true
        
        XCTAssertNotNil(observer.didChangeTab)
    }

    func testWhenTabWithViewedDecodedThenItDecodesSuccessfully() {

        let tab = Tab(coder: CoderStub(properties: ["link": link(), "viewed": false]))
        XCTAssertNotNil(tab?.link)
        XCTAssertFalse(tab?.viewed ?? true)
    }

    func testWhenTabEncodedBeforeViewedPropertyAddedIsDecodedThenItDecodesSuccessfully() {

        let tab = Tab(coder: CoderStub(properties: ["link": link()]))
        XCTAssertNotNil(tab?.link)
        XCTAssertTrue(tab?.viewed ?? false)
    }

    func testWhenTabHasRegularURLThenIsAITabReturnsFalse() {
        // Given
        let tab = Tab(link: link())

        // Then
        XCTAssertFalse(tab.isAITab)
    }

    func testWhenTabHasDuckAIURLThenIsAITabReturnsTrue() {
        // Given - URL with duck.ai host
        let aiURL = URL(string: "https://duck.ai/chat")!
        let tab = Tab(link: Link(title: "AI Chat", url: aiURL))

        // Then
        XCTAssertTrue(tab.isAITab)
    }

    func testWhenTabHasDuckDuckGoAIChatQueryThenIsAITabReturnsTrue() {
        // Given - duckduckgo.com URL with ia=chat
        let aiURL = URL(string: "https://duckduckgo.com/?ia=chat")!
        let tab = Tab(link: Link(title: "AI Chat", url: aiURL))

        // Then
        XCTAssertTrue(tab.isAITab)
    }

    func testWhenTabHasNoLinkThenIsAITabReturnsFalse() {
        // Given
        let tab = Tab()

        // Then
        XCTAssertFalse(tab.isAITab)
    }

    func testWhenAIChatTabEncodedThenDecodesWithCorrectType() {
        // Given - Tab with Duck AI URL
        let aiURL = URL(string: "https://duck.ai/chat")!
        let tabToEncode = Tab(link: Link(title: "AI Chat", url: aiURL))

        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: tabToEncode,
                                                           requiringSecureCoding: false) else {
            XCTFail("Data is nil")
            return
        }

        // When
        let decodedTab = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? Tab

        // Then
        XCTAssertNotNil(decodedTab)
        XCTAssertTrue(decodedTab?.isAITab ?? false)
    }

    func testWhenWebTabEncodedThenDecodesWithCorrectType() {
        // Given - Tab with regular URL
        let tabToEncode = Tab(link: link())

        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: tabToEncode,
                                                           requiringSecureCoding: false) else {
            XCTFail("Data is nil")
            return
        }

        // When
        let decodedTab = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? Tab

        // Then
        XCTAssertNotNil(decodedTab)
        XCTAssertFalse(decodedTab?.isAITab ?? true)
    }

    func testWhenTabEncodedBeforeTypePropertyAddedIsDecodedThenDefaultsToWebType() {
        // Given
        let tab = Tab(coder: CoderStub(properties: ["link": link(), "viewed": false]))

        // Then
        XCTAssertNotNil(tab?.link)
        XCTAssertFalse(tab?.isAITab ?? true)
    }

    func testWhenTabLinkChangesToAIURLThenIsAITabReturnsTrue() {
        // Given
        let tab = Tab(link: link())
        XCTAssertFalse(tab.isAITab)

        // When - Change to Duck AI URL
        let aiURL = URL(string: "https://duck.ai/chat")!
        tab.link = Link(title: "AI Chat", url: aiURL)

        // Then
        XCTAssertTrue(tab.isAITab)
    }

    func testWhenTabLinkChangesFromAIURLToRegularURLThenIsAITabReturnsFalse() {
        // Given - Tab with Duck AI URL
        let aiURL = URL(string: "https://duck.ai/chat")!
        let tab = Tab(link: Link(title: "AI Chat", url: aiURL))
        XCTAssertTrue(tab.isAITab)

        // When - Change to regular URL
        tab.link = link()

        // Then
        XCTAssertFalse(tab.isAITab)
    }

    func testWhenSameObjectThenEqualsPasses() {
        let link = Link(title: Constants.title, url: Constants.url)
        let tab = Tab(link: link)
        XCTAssertEqual(tab, tab)
    }

    func testWhenSameDataThenEqualsPasses() {
        let lhs = Tab(link: Link(title: Constants.title, url: Constants.url))
        let rhs = Tab(link: Link(title: Constants.title, url: Constants.url))
        XCTAssertEqual(lhs, rhs)
    }

    func testWhenLinksDifferentThenEqualsFails() {
        let lhs = Tab(link: Link(title: Constants.title, url: Constants.url))
        let rhs = Tab(link: Link(title: Constants.title, url: Constants.differentUrl))
        XCTAssertNotEqual(lhs, rhs)
    }

    // MARK: - Custom Debug URL Tests

    func testWhenTabHasCustomDebugURLThenIsAITabReturnsTrue() {
        // Given
        let debugSettings = MockAIChatDebugSettings()
        debugSettings.customURL = "https://dev.duck.ai"
        let customURL = URL(string: "https://dev.duck.ai/chat")!
        let tab = Tab(link: Link(title: "Dev AI", url: customURL), aichatDebugSettings: debugSettings)

        // Then
        XCTAssertTrue(tab.isAITab)
    }

    func testWhenTabHostMatchesCustomDebugHostThenIsAITabReturnsTrue() {
        // Given
        let debugSettings = MockAIChatDebugSettings()
        debugSettings.customURL = "https://staging.example.com/some/path"
        let url = URL(string: "https://staging.example.com/different/path")!
        let tab = Tab(link: Link(title: "Staging", url: url), aichatDebugSettings: debugSettings)

        // Then - Should match based on host, not full URL
        XCTAssertTrue(tab.isAITab)
    }

    func testWhenTabHostMatchesCustomDebugHostWithDifferentCaseThenIsAITabReturnsTrue() {
        // Given
        let debugSettings = MockAIChatDebugSettings()
        debugSettings.customURL = "https://Dev.Duck.AI"
        let url = URL(string: "https://dev.duck.ai/chat")!
        let tab = Tab(link: Link(title: "Dev AI", url: url), aichatDebugSettings: debugSettings)

        // Then
        XCTAssertTrue(tab.isAITab)
    }

    func testWhenCustomDebugURLIsNilThenFallsBackToStandardCheck() {
        // Given
        let debugSettings = MockAIChatDebugSettings()
        debugSettings.customURL = nil
        let regularURL = URL(string: "https://example.com")!
        let tab = Tab(link: Link(title: "Regular", url: regularURL), aichatDebugSettings: debugSettings)

        // Then
        XCTAssertFalse(tab.isAITab)
    }

    func testWhenCustomDebugURLIsEmptyThenFallsBackToStandardCheck() {
        // Given
        let debugSettings = MockAIChatDebugSettings()
        debugSettings.customURL = ""
        let regularURL = URL(string: "https://example.com")!
        let tab = Tab(link: Link(title: "Regular", url: regularURL), aichatDebugSettings: debugSettings)

        // Then
        XCTAssertFalse(tab.isAITab)
    }

    func testWhenCustomDebugURLIsMalformedThenIsAITabReturnsFalse() {
        // Given - Malformed URL without scheme results in nil host
        let debugSettings = MockAIChatDebugSettings()
        debugSettings.customURL = "mydevserver"
        let aboutBlankURL = URL(string: "about:blank")!
        let tab = Tab(link: Link(title: "Blank", url: aboutBlankURL), aichatDebugSettings: debugSettings)

        // Then - Should not match even though both hosts are nil
        XCTAssertFalse(tab.isAITab)
    }

    func testWhenURLIsDuckAIThenIsAITabReturnsTrueRegardlessOfDebugSettings() {
        // Given - Standard duck.ai URL should work even with different debug settings
        let debugSettings = MockAIChatDebugSettings()
        debugSettings.customURL = "https://other.domain.com"
        let duckAIURL = URL(string: "https://duck.ai/chat")!
        let tab = Tab(link: Link(title: "AI", url: duckAIURL), aichatDebugSettings: debugSettings)

        // Then
        XCTAssertTrue(tab.isAITab)
    }

    func testWhenTabWithCustomDebugURLEncodedThenDecodesSuccessfully() {
        // Given - Tab with custom debug URL
        let debugSettings = MockAIChatDebugSettings()
        debugSettings.customURL = "https://dev.duck.ai"
        let customURL = URL(string: "https://dev.duck.ai/chat")!
        let tabToEncode = Tab(link: Link(title: "Dev AI", url: customURL), aichatDebugSettings: debugSettings)

        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: tabToEncode,
                                                           requiringSecureCoding: false) else {
            XCTFail("Data is nil")
            return
        }

        // When
        let decodedTab = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? Tab

        // Then - Tab restores successfully with correct link
        XCTAssertNotNil(decodedTab)
        XCTAssertEqual(decodedTab?.link?.url.absoluteString, "https://dev.duck.ai/chat")
    }


    // MARK: - Contextual Chat URL Tests

    func testWhenTabWithContextualChatURLEncodedThenDecodesSuccessfully() {
        let contextualURL = "https://duck.ai/?chatId=abc123&placement=sidebar"
        let tabToEncode = Tab(link: link(), contextualChatURL: contextualURL)

        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: tabToEncode,
                                                           requiringSecureCoding: false) else {
            XCTFail("Data is nil")
            return
        }

        let decodedTab = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? Tab

        XCTAssertNotNil(decodedTab)
        XCTAssertEqual(decodedTab?.contextualChatURL, contextualURL)
    }

    func testWhenTabEncodedWithoutContextualChatURLThenDecodesWithNil() {
        let tab = Tab(coder: CoderStub(properties: ["link": link(), "viewed": false]))

        XCTAssertNotNil(tab)
        XCTAssertNil(tab?.contextualChatURL)
    }

    func testWhenTabWithNilContextualChatURLEncodedThenDecodesWithNil() {
        let tabToEncode = Tab(link: link(), contextualChatURL: nil)

        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: tabToEncode,
                                                           requiringSecureCoding: false) else {
            XCTFail("Data is nil")
            return
        }

        let decodedTab = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? Tab

        XCTAssertNotNil(decodedTab)
        XCTAssertNil(decodedTab?.contextualChatURL)
    }

    private func link() -> Link {
        return Link(title: "title", url: URL(string: "http://example.com")!)
    }

}

private class CoderStub: NSCoder {

    private let properties: [String: Any]

    init(properties: [String: Any]) {
        self.properties = properties
    }

    override func containsValue(forKey key: String) -> Bool {
        return properties.keys.contains(key)
    }

    override func decodeObject(forKey key: String) -> Any? {
        return properties[key]
    }

    override func decodeBool(forKey key: String) -> Bool {
        return (properties[key] as? Bool)!
    }

    override func decodeInteger(forKey key: String) -> Int {
        return (properties[key] as? Int) ?? 0
    }

}

private class MockTabObserver: NSObject, TabObserver {
    
    var didChangeTab: Tab?
    
    func didChange(tab: Tab) {
        didChangeTab = tab
    }
}
